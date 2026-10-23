`timescale 1ns/1ps


// this block defines the global history buffer which stores the value for the history along with TAGS.
module LP_ghr_block_2reg #(
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
	output logic output_valid_o,

	// but there will be a cycle latency from the checkpoint FIFO when it supplies the data (clean folded history) to the Hash generators.
	// and to stop the data movement into the design during that time we need a RECOVERY ACTIVE signal.
	input logic recovery_active_i

	// ******** ------  *******  PROBABLE HISTORY RECOVERY PORTS. CAN BE USED LATER.
	// output logic recovery_valid_o,	// recovery packet outputs are valid
	// output logic [PKT_WIDTH-1:0] recovery_incoming_packet_o,	// next_old GHR packet being replayed
	// output logic [PKT_WIDTH-1:0] recovery_expiring_packet_o [0:NUM_HASH_TABLES-1],	// packet going out from history window during replay
	// output logic recovery_last_o	// last recovey packet 
	);

	//registered inputs declaration
	logic                         br_valid_i_reg;
	logic [PKT_WIDTH-1:0]         br_packet_i_reg;
	logic                         misprediction_i_reg;
	logic [5:0]                   mispredicted_table_depth_i_reg;
	logic                         recovery_active_i_reg;
	logic 						  input_stage_valid_reg;

	// registered outputs declaration
	logic [PKT_WIDTH-1:0]         incoming_packet_o_reg;
	logic [PKT_WIDTH-1:0]         expiring_packet_o_reg [0:NUM_HASH_TABLES-1];
	logic                         output_valid_o_reg;

	logic br_valid_and_recovery_not_active;		// this wire is just to say that the branch is valid and recovery is not active
	logic ptr_update_en;

	/// banked memory
	logic [PKT_WIDTH-1:0] bank_mem [0:ENTRIES_PER_BANK-1][0:NUM_BANKS-1];
	logic [5:0] write_ptr;
	logic [3:0] write_bank;
	logic [1:0] write_row;

	logic bank_we [0:NUM_BANKS-1];
	logic gated_bank_clk [0:NUM_BANKS-1];

	localparam int TOTAL_CAPACITY = (NUM_BANKS * ENTRIES_PER_BANK);
	localparam logic [5:0] DEPTHS [0:NUM_HASH_TABLES-1] = '{6'd2, 6'd4, 6'd6, 6'd8, 6'd12, 6'd16, 6'd32};

	//registers input
	always_ff @(posedge clk or negedge rst_n)
		begin
			if(!rst_n) begin
				br_valid_i_reg                  <= 1'b0;
				br_packet_i_reg                 <= '0;
				misprediction_i_reg             <= 1'b0;
				mispredicted_table_depth_i_reg  <= '0;
				recovery_active_i_reg           <= 1'b0;
				input_stage_valid_reg			<= 1'b0;
			end else begin
				// input_stage_valid_reg			<= en_i;
				if (en_i) begin
					br_valid_i_reg                  <= br_valid_i;
					br_packet_i_reg                 <= br_packet_i;
					misprediction_i_reg             <= misprediction_i;
					mispredicted_table_depth_i_reg  <= mispredicted_table_depth_i;
					recovery_active_i_reg           <= recovery_active_i;	
					input_stage_valid_reg			<= br_valid_i || misprediction_i;
				end
			end
		end

	assign br_valid_and_recovery_not_active = input_stage_valid_reg && br_valid_i_reg && (!recovery_active_i_reg);
	
	/// pointers for the memory banks
	logic [5:0] head_ptr;
	logic [5:0] next_head_ptr;
	logic [5:0] incremented_ptr;
	logic [5:0] rollback_ptr;
	logic [5:0] rollback_incremented_ptr;

	/// calculation of normal increment , rollback and rollback_increment_case
	always_comb begin

		if (head_ptr == MAX_PTR - 1)		// Normal increment
			incremented_ptr = '0;
		else
			incremented_ptr = head_ptr + 1'b1;
	
		if (head_ptr >= mispredicted_table_depth_i_reg)		// rollback only, no incoming writes
			rollback_ptr = head_ptr - mispredicted_table_depth_i_reg;
		else
			rollback_ptr =	head_ptr + MAX_PTR - mispredicted_table_depth_i_reg;
	
		if (rollback_ptr == MAX_PTR - 1)		// rollback with incoming writes
			rollback_incremented_ptr = '0;
		else
			rollback_incremented_ptr = rollback_ptr + 1'b1;
	end

	// next head ptr calculation	
	always_comb begin
		// next_head_ptr = head_ptr;

		case ({input_stage_valid_reg && misprediction_i_reg,br_valid_and_recovery_not_active})
			2'b00: next_head_ptr = head_ptr;
			2'b01: next_head_ptr = incremented_ptr;
			2'b10: next_head_ptr = rollback_ptr;
			2'b11: next_head_ptr = rollback_incremented_ptr;
			default: next_head_ptr = head_ptr;
		endcase
	end
	

	// enable logic for intermediate ptr_update_en
	assign ptr_update_en = en_i && (!recovery_active_i) && (br_valid_i || misprediction_i);
	// assign ptr_update_en = input_stage_valid_reg && (!recovery_active_i_reg) && (br_valid_i_reg || misprediction_i_reg);

	//register for the head pointer	
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			head_ptr <= '0;
		//	next_head_ptr <= '0;
		end
		// else if (ptr_update_en)
		else if (ptr_update_en) begin
			head_ptr <= next_head_ptr;
/*
			case ({misprediction_i_reg,br_valid_i})
				2'b00: next_head_ptr <= head_ptr;
				2'b01: next_head_ptr <= incremented_ptr;
				2'b10: next_head_ptr <= rollback_ptr;
				2'b11: next_head_ptr <= rollback_incremented_ptr;
				default: next_head_ptr <= head_ptr;
			endcase
*/
		end
	end

	// selection of write pointer
	always_comb begin
		write_ptr = head_ptr;		// Normal write occurs at the current free location.
	
		if (input_stage_valid_reg && misprediction_i_reg)	// After rollback, the recovered head becomes the write location.
			write_ptr = rollback_ptr;
	end

	// get bank and row for writing
	get_bank u_get_write_bank (
		.pointer_i (write_ptr),
		.bank_o    (write_bank)
	);

	get_row u_get_write_row (
		.pointer_i (write_ptr),
		.row_o     (write_row)
	);


	always_comb begin
		for (int b = 0; b < NUM_BANKS; b++)
			//bank_we[b] = br_valid_and_recovery_not_active && (write_bank == b);
			bank_we[b] = ptr_update_en && (write_bank == b);
	end


	generate
		for (genvar b = 0; b < NUM_BANKS; b++) begin : gen_memory_banks
	
			gated_clk u_icg (
				.clk_i       (clk),
				.en_i        (bank_we[b]),
				.clk_gated_o (gated_bank_clk[b])
			);
	
//			always @(posedge gated_bank_clk[b] or negedge rst_n) begin
			always @(posedge clk or negedge rst_n) begin
				if (!rst_n) begin
					for (int r = 0; r < ENTRIES_PER_BANK; r++)
						bank_mem[r][b] <= '0;
				end
//				else if (en_i && br_valid_i) begin
				else if (bank_we[b]) begin
					bank_mem[write_row][b] <= br_packet_i_reg;
				end
			end
	
		end
	endgenerate


	/// variables
	logic [5:0] target_index [0:NUM_HASH_TABLES-1];
	logic [3:0] read_bank [0:NUM_HASH_TABLES-1];
	logic [1:0] read_row [0:NUM_HASH_TABLES-1];

	logic [PKT_WIDTH-1:0] incoming_packet_next;
	logic [PKT_WIDTH-1:0] expiring_packet_next [0:NUM_HASH_TABLES-1];
	logic output_valid_next;


	/// generating read address
	generate
		for (genvar i = 0; i < NUM_HASH_TABLES; i++) begin : gen_history_reads
	
			assign target_index[i] = (next_head_ptr >= DEPTHS[i]) ? next_head_ptr - DEPTHS[i] : TOTAL_CAPACITY - (DEPTHS[i] - next_head_ptr);
	
			get_bank u_get_read_bank (
				.pointer_i (target_index[i]),
				.bank_o    (read_bank[i])
			);
	
			get_row u_get_read_row (
				.pointer_i (target_index[i]),
				.row_o     (read_row[i])
			);
	
			assign expiring_packet_next[i] = bank_mem[read_row[i]][read_bank[i]];
/*
			always @(posedge clk or negedge rst_n) begin
				if (!rst_n) begin
					for (int i = 0; i < NUM_HASH_TABLES; i++) begin
						expiring_packet_o_reg[i] <= '0;
					end
				end else if(en_i) begin
					for (int i = 0; i < NUM_HASH_TABLES; i++) begin
						expiring_packet_o_reg[i] <= expiring_packet_next[i];
					end
				end
			end
*/
			assign expiring_packet_o[i] = expiring_packet_o_reg[i];

		end
	endgenerate

	assign incoming_packet_next = br_packet_i_reg;
	assign output_valid_next = br_valid_and_recovery_not_active;

	// output registers
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			incoming_packet_o_reg <= '0;
			output_valid_o_reg    <= 1'b0;
			for (int i = 0; i < NUM_HASH_TABLES; i++) begin
				expiring_packet_o_reg[i] <= '0;
			end
		end
		else if (en_i) begin
			output_valid_o_reg <= output_valid_next;
			// if (output_valid_o_reg) begin
			if (output_valid_next) begin
				incoming_packet_o_reg <= incoming_packet_next;
				for (int i = 0; i < NUM_HASH_TABLES; i++) begin
					expiring_packet_o_reg[i] <= expiring_packet_next[i];
				end
			end
		end
		else begin
			output_valid_o_reg <= 1'b0;			
		end
	end

	// assigning values to the output ports
	assign incoming_packet_o = incoming_packet_o_reg;
	assign output_valid_o = output_valid_o_reg;

	
endmodule