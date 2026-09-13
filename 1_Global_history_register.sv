// this block defines the global history buffer which stores the value for the history along with TAGS.
module ghr_block #(
	// give width parameters here
	parameter PKT_WIDTH = 7,	//{type[1],taken[1],target[5]}  /// THE target is the lowest 5 bits of the target addreess.
	parameter NUM_BANKS = 9,
	parameter ENTRIES_PER_BANK = 4,
	parameter MAX_PTR = 35,		/// 36 total entries (0 to 35)
	parameter NUM_HASH_TABLES = 7
)(
	input logic clk,
	input logic rst_n,				// asynchronous reset

	input logic en_i,					// need to include this to gate the D-flops
	
	// these two decodes the branch
	input logic br_valid_i,			// assert 1 when a valid divergent branch is decoded
	input logic [PKT_WIDTH-1:0] br_packet_i,	// incoming branch information {type[1],taken[1],target[5]}
	
	// commit /ROB interface
	input logic misprediction_i,		// assert 1 from ROB when a branch misprediction flush occurs
	input logic [5:0] mispredicted_table_depth_i,	// indicates how many branches deep the misprediction occurred

	/// check for the outputs
	output logic [PKT_WIDTH-1:0] incoming_packet_o,		// forwards the new packet to the folding logic to be XORed into all the tables
	output logic [PKT_WIDTH-1:0] expiring_packet_o [0:NUM_HASH_TABLES-1]	// 2D array containing the 7 specific historical packets each 7 bits wide required for geometric foldingn
);


	/// STORAGE - We need to define 9 sram banks in here so that we can use them for placing in the 
	// incoming instructions information and do not create Collision. When we calculate modulo using 7 Banks then it creates collision
	// after 5th bank. But if we use 9 banks , then it will not create any collision and will wrap around only after 7th bank.
	// Hence, we have 7 totally different banks to use for entries. (BADGR architecture)
	// ALSO, we will be able to select the row number (address) for each bank like that so that we don't need an 
	// additional counter/pointer for each SRAM
	logic [PKT_WIDTH-1:0] bank_mem [0:ENTRIES_PER_BANK-1][0:NUM_BANKS-1];

	logic [5:0] head_ptr, next_head_ptr;	// pointers for count
	logic br_valid_i_gated;
	logic [PKT_WIDTH-1:0] br_packet_i_gated;
	logic misprediction_i_gated;
	logic [5:0] mispredicted_table_depth_i_gated;

	// input operand isolation.
	assign br_valid_i_gated = en_i ? br_valid_i : 1'b0;
	assign br_packet_i_gated = en_i ? br_packet_i : '0;
	assign misprediction_i_gated = en_i ? misprediction_i : 1'b0;
	assign mispredicted_table_depth_i_gated = en_i ? mispredicted_table_depth_i_gated : '0;


	// pointer increment
	always_ff @(posedge clk or negedge rst_n)
		begin
			if(!rst_n) head_ptr <= '0;
			else if(en_i) head_ptr <= next_head_ptr;
		end
		
	always_comb begin
		next_head_ptr = head_ptr;

		if (misprediction_i_gated) begin		// incase there is a squash/misprediction, so we need to bring back the pointer
			
				if (head_ptr >= mispredicted_table_depth_i_gated) 
					next_head_ptr = head_ptr - mispredicted_table_depth_i_gated;
				else 
					next_head_ptr = (MAX_PTR + 1) - (mispredicted_table_depth_i_gated - head_ptr);	// this is for the case when our squash length is greater than the current head pointer value
		end else if (br_valid_i_gated) begin		// normal increment

				if (head_ptr == MAX_PTR)
					next_head_ptr = '0;
				else
					next_head_ptr = head_ptr + 1'b1;
		end
	end

	// module and SRAM block address generator function
	// function for generating the modulo to get the bank to write on
	function logic [3:0] get_bank(input logic [5:0] ptr); 
			case (ptr) inside
			[0:8]   : return ptr[3:0];
			[9:17]  : return (ptr - 6'd9);
			[18:26] : return (ptr - 6'd18);
			[27:35] : return (ptr - 6'd27);
			default : return '0;
		endcase
	endfunction

	// function to generate the row address of the respective bank
	function logic [1:0] get_row(input logic [5:0] ptr);        
		case (ptr) inside
			[0:8]   : return 2'b00;
			[9:17]  : return 2'b01;
			[18:26] : return 2'b10;
			[27:35] : return 2'b11;
			default : return 2'b00;
		endcase
	endfunction

	///WRITE LOGIC
	// here we need to use the generated bank and address to get and write to the physical target

	logic [3:0] write_bank;	// select the bank to write to
	logic [1:0] write_row;	// select the row to write on that bank

	// physical target to write to Bank number and row number
	assign write_bank = get_bank(next_head_ptr);
	assign write_row = get_row(next_head_ptr);

	// send the write to a specific bank. we don't need to use a reset logic here as it is memory
	always_ff @(posedge clk)
		begin
			if(br_valid_i_gated && !misprediction_i_gated)
				begin
					bank_mem[write_row][write_bank] <= br_packet_i_gated;
				end
		end
	//
	

	// gate the output
	assign incoming_packet_o = (br_valid_i_gated) ? br_packet_i_gated : '0;		// this is the packet that will directly go to the hash table

	/// READ LOGIC
	
	localparam int TOTAL_CAPACITY = NUM_BANKS * ENTRIES_PER_BANK;
	localparam logic [5:0] DEPTHS [0:NUM_TABLES-1] = '{6'd2, 6'd4, 6'd6, 6'd8, 6'd12, 6'd16, 6'd32};

	logic [5:0] target_index [0:NUM_HASH_TABLES-1];
	logic [3:0] read_bank	 [0:NUM_HASH_TABLES-1];
	logic [1:0] read_row	 [0:NUM_HASH_TABLES-1];


	generate
			for(genvar i = 0; i < NUM_HASH_TABLES; i++) begin
				
				// Absolute index calculation. for DEPTH less and greater than head pointer

				assign target_index[i] = (next_head_ptr >= DEPTHS[i]) ? (next_head_ptr - DEPTHS[i]) : ((TOTAL_CAPACITY) - (DEPTHS[i] - next_head_ptr));

				// 1D to 2D Hardware translation, getting the bank and the row
				assign read_bank[i] = get_bank(target_index[i]);
				assign read_row[i]  = get_row(target_index[i]);

				// operand isolation and giving out the packets for respective tables
				assign expiring_packet_o[i] = en_i ? bank_mem[read_bank[i]][read_row[i]] : '0;

			end
	endgenerate

endmodule