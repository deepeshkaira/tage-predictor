// this block defines the global history buffer which stores the value for the history along with TAGS.
module LP_ghr_block #(
	// give width parameters here
	parameter PKT_WIDTH = 7,	//{type[1],taken[1],target[5]}  /// THE target is the lowest 5 bits of the target addreess.
	parameter NUM_BANKS = 9,
	parameter ENTRIES_PER_BANK = 4,
	parameter MAX_PTR = 36,		/// 36 total entries (0 to 35)
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
	output logic [PKT_WIDTH-1:0] expiring_packet_o [0:NUM_HASH_TABLES-1],	// 2D array containing the 7 specific historical packets each 7 bits wide required for geometric foldingn

	// recovery for folded history in the hash blocks downstream
	// I dont think that we need the recovery valid outputs in here. Because once we are back with our head read pointers --
	// the GHR is going to handle the incoming packets same way as it is suppossed to and we will have the Porgram counter fetching up the instructions from the rolled back PC
	// and hence i think the incmoing packet will be re-fetched. We dont need to restore the incmoing packet in GHR.
	// ONly thing that I need to restore in the design of GHR is HEAD POINTER which will be used to fetch value from checkpoint buffer.
	// and use that Head pointer to pickup the folded_history packet from checkpoint buffer and push it to hash address generator blocks.
	// that is how it is going to work in recovery of pointer and folded history. 
	
	// ******** ------  *******  PROBABLE HISTORY RECOVERY PORTS. CAN BE USED LATER.
	// output logic recovery_valid_o,	// recovery packet outputs are valid
	// output logic [PKT_WIDTH-1:0] recovery_incoming_packet_o,	// next_old GHR packet being replayed
	// output logic [PKT_WIDTH-1:0] recovery_expiring_packet_o [0:NUM_HASH_TABLES-1],	// packet going out from history window during replay
	// output logic recovery_last_o	// last recovey packet 
);


	// STORAGE - We need to define 9 memory banks in here so that we can use them for placing in the 
	// incoming instructions information and do not create Collision. When we calculate modulo using 7 Banks then it creates collision
	// after 5th bank. But if we use 9 banks , then it will not create any collision and will wrap around only after 7th bank.
	// Hence, we have 7 totally different banks to use for entries. (BADGR architecture)
	// ALSO, we will be able to select the row number (address) for each bank like that so that we don't need an 
	// additional counter/pointer for each memory
	logic [PKT_WIDTH-1:0] bank_mem [0:ENTRIES_PER_BANK-1][0:NUM_BANKS-1];

	logic [5:0] head_ptr, next_head_ptr;	// pointers for count
	// logic [5:0] valid_history_count, next_valid_history_count;		// counters for telling recovery wich positions represent genuine history
	logic br_valid_i_gated;
	logic misprediction_i_gated;
	logic [5:0] mispredicted_table_depth_i_gated;
	logic [PKT_WIDTH-1:0] br_packet_i_gated;

	// input operand isolation. AND with "recovery" i.e. stop taking in new instructions for GHR if misprediction recovery of Hash tables is going on
	// assign br_valid_i_gated = (en_i && !recovery_active) ? br_valid_i : 1'b0;
	// assign misprediction_i_gated = (en_i && !recovery_active) ? misprediction_i : 1'b0;
	// assign mispredicted_table_depth_i_gated = (en_i && !recovery_active) ? mispredicted_table_depth_i : '0;
	// assign br_packet_i_gated = (en_i && !recovery_active) ? br_packet_i : '0;

	assign br_valid_i_gated = en_i ? br_valid_i : 1'b0;
	assign misprediction_i_gated = en_i ? misprediction_i : 1'b0;
	assign mispredicted_table_depth_i_gated = en_i ? mispredicted_table_depth_i : '0;
	assign br_packet_i_gated = en_i ? br_packet_i : '0;

	logic ptr_update_en;
	
	assign ptr_update_en = br_valid_i_gated || misprediction_i_gated;	//gate for enabling the pointer only when there is either a "valid_branch" or "misprediction"
	logic clk_gated_ptr;

    gated_clk u_icg (
        .clk_i       (clk),
        .en_i        (ptr_update_en),	// gated clocks to head pointer only when there is br_valid or misprediction
        .clk_gated_o (clk_gated_ptr)
    );

	// pointer varibales for conditions
	logic [5:0] incremented_ptr;
	logic [5:0] rollback_ptr;
	logic [5:0] rollback_incremented_ptr;

	// pointer increment
	always_ff @(posedge clk_gated_ptr or negedge rst_n)
		begin
			if(!rst_n) begin
				head_ptr <= '0;
				// valid_history_count <= '0;		// commenting them as of now because we are not defining the valid histroy depth and depend on ROB to provide the valid depth
			end else begin
				head_ptr <= next_head_ptr;
				// valid_history_count <= next_valid_history_count;
			end
		end
		
	// calculation of normal increment, rollback and rollback_increment case
	always_comb begin

		// Normal increment
		if (head_ptr == MAX_PTR - 1)
			incremented_ptr = '0;
		else
			incremented_ptr = head_ptr + 1'b1;
	
		// rollback only, no incoming writes
		if (head_ptr >= mispredicted_table_depth_i_gated)
			rollback_ptr = head_ptr - mispredicted_table_depth_i_gated;
		else
			rollback_ptr =	head_ptr + MAX_PTR - mispredicted_table_depth_i_gated;
	
		// rollback with incoming writes
		if (rollback_ptr == MAX_PTR - 1)
			rollback_incremented_ptr = '0;
		else
			rollback_incremented_ptr = rollback_ptr + 1'b1;
	end

	
	// assigning the value to head pointer
	always_comb begin
		next_head_ptr = head_ptr;

		// priority to misprediction to determine the "next_head_ptr"
		case ({misprediction_i_gated, br_valid_i_gated})
        	2'b00: begin
				next_head_ptr = head_ptr;
			end

			2'b01: begin				// normal increment
				next_head_ptr = incremented_ptr;
			end

			2'b10: begin	// incase there is a squash/misprediction, so we need to bring back the pointer. No incoming packets at this time
				next_head_ptr = rollback_ptr;
			end

			2'b11: begin	/// incase there is a squash/misprediction, so we need to bring back the pointer. priority given to MISPREDICTION 
							/// to decide the head pointer so that next head pointer can point to next location for incoming write
				next_head_ptr = rollback_incremented_ptr;
			end

			default: begin
				next_head_ptr = head_ptr;
			end
    endcase
	end


	/// combinational block for recovery of history to be pushed into hash block downstream
	// NOT NEED THIS == ROB should provide a valid depth of misprediction
	// always_comb begin
	// 	next_valid_history_count = valid_history_count;
	
	// 	case ({misprediction_i_gated, br_valid_i_gated})
	
	// 		2'b00: begin	// idle position
	// 			next_valid_history_count = valid_history_count;
	// 		end
	
	// 		2'b01: begin	// normal incoming branch, no misprediction
	// 			// Normal branch insertion - max 36
	// 			if (valid_history_count < MAX_PTR)
	// 				next_valid_history_count =	valid_history_count + 1'b1;
	// 		end
	
	// 		2'b10: begin	// no incoming branch , with MISPREDICTION
	// 			// Remove squashed entries
	// 			next_valid_history_count = valid_history_count - mispredicted_table_depth_i_gated;
	// 		end
	
	// 		2'b11: begin	// MISPREDICTION with INCOMING BRANCH
	// 			// Remove squashed entries, and insert recovery branch
	// 			next_valid_history_count = valid_history_count - mispredicted_table_depth_i_gated + 1'b1;
	// 		end
	
	// 		default: begin
	// 			next_valid_history_count = valid_history_count;
	// 		end
	
	// 	endcase
	// end


	// module and SRAM block address generator function
	// function for generating the modulo to get the bank to write on
	// will synthesize with case logic
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

	// circular subtract function. Moves backwards through circular 36 GHR entry
	function automatic logic [5:0] circular_subtract(
		input logic [5:0] pointer,
		input logic [5:0] distance
	);
		if (pointer >= distance)
			return pointer - distance;
		else
			return pointer + MAX_PTR - distance;
	endfunction

	///WRITE LOGIC
	// here we need to use the generated bank and address to get and write to the physical target

	logic [3:0] write_bank;	// select the bank to write to
	logic [1:0] write_row;	// select the row to write on that bank

	// physical target to write to Bank number and row number
	// correction here for the reset condition where the head pointer will look at table_0_loc_0 and 
	// next_hd_ptr will look at table_1_loc_0. So, inserting the logic to differentiate between rollback and normal writes

	logic [5:0] write_ptr;

	always_comb begin
		write_ptr = head_ptr;		// Normal write occurs at the current free location.

		// After rollback, the recovered head becomes the write location.
		if (misprediction_i_gated)	write_ptr = rollback_ptr;
	end

	assign write_bank = get_bank(write_ptr);
	assign write_row  = get_row(write_ptr);

	// send the write to a specific bank. we don't need to use a reset logic here as it is memory
	// ******Power Gating ****** the banks - select only that bank which is going to take incoming value
	//		FIRSTLY, make a WRITE_ENABLE for that particular bank.
	logic bank_we [0:NUM_BANKS-1];
	
	always_comb begin
		for (int b = 0; b < NUM_BANKS; b++) begin
			bank_we[b] = br_valid_i_gated && (write_bank == b);
		end
    end

	// to keep a check that the bank_we is one hot only when br_valid_i_gated is high
	// assert property (@(posedge clk) br_valid_i_gated |-> $onehot(bank_we));

	// ICGs for each of the 9 banks.
	logic gated_bank_clk [0:NUM_BANKS-1];
	
	generate 
			for (genvar b = 0; b < NUM_BANKS; b++) begin 
				
				gated_clk u_icg (
                    .clk_i       (clk),
                    .en_i        (bank_we[b]),
                    .clk_gated_o (gated_bank_clk[b])
                );


				always_ff @(posedge gated_bank_clk[b] or negedge rst_n) begin
					if (!rst_n) begin
						for (int r = 0; r < ENTRIES_PER_BANK; r++) begin
							bank_mem[r][b] <= '0;
						end
					end	else begin
						bank_mem[write_row][b] <= br_packet_i_gated;
					end
				end
			end
	endgenerate


	// gate the output
	assign incoming_packet_o = (br_valid_i_gated) ? br_packet_i_gated : '0;		// this is the packet that will directly go to the hash table

	/// READ LOGIC
	localparam int TOTAL_CAPACITY = NUM_BANKS * ENTRIES_PER_BANK;
	localparam logic [5:0] DEPTHS [0:NUM_HASH_TABLES-1] = '{6'd2, 6'd4, 6'd6, 6'd8, 6'd12, 6'd16, 6'd32};

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

				// we dont need operand isolation here because we want the output to hold certain value and not toggle to ZERO mindlessly when ENABLE == 0
				assign expiring_packet_o[i] = bank_mem[read_row[i]][read_bank[i]];

			end
	endgenerate

	// assertion added so that the pointer does not rollback into history that never existed
	assert property (@(posedge clk)
		misprediction_i_gated |-> (mispredicted_table_depth_i_gated > 0) && (mispredicted_table_depth_i_gated < MAX_PTR)
	);

endmodule