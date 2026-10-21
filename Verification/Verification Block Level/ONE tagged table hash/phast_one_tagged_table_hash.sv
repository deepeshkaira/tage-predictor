`timescale 1ns/1ps
// phast tagged table hash with single value of depth

module phast_tagged_table_hash #(
    parameter int PKT_WIDTH  = 7,
    parameter int S_WIDTH    = 7,
    parameter int T_WIDTH    = 16,
    // parameter int DEPTHS [0:NUM_TAGGED-1] = '{2, 4, 6, 8, 12, 16, 32}
	parameter int HISTORY_DEPTH = 2
)(

    input  logic clk,
    input  logic rst_n,
    input  logic en_i,
    
    input  logic br_valid_i,
    input  logic [PKT_WIDTH-1:0] incoming_pkt_i,                 
    input  logic [PKT_WIDTH-1:0] expiring_pkts_i, 
    input  logic [31:0] load_pc_i,                      
    
	// input for the signal to decide whether to take the calculated value of next_folded_history or recovery_history value
	input logic recovery_valid_i,
	input logic [S_WIDTH+T_WIDTH-1:0] recovery_folded_history_i,

    output logic [S_WIDTH-1:0] tagged_indices_o,
    output logic [T_WIDTH-1:0] tagged_tags_o ,

	output logic valid_o,		// need to tell the next block that the signals are valid at this specific time

	//output to send out the folded history output to the checkpoint FIFO buffer to think about
	output logic [S_WIDTH+T_WIDTH-1:0] folded_history_o
);

	localparam int CSR_WIDTH = S_WIDTH + T_WIDTH;
	logic recovery_valid_i_gated;		// recovery valid signals
	logic folded_history_clock_en;		/// signal for gating the clock on both conditions:-  VALID BRANCH   &	 ACTIVE RECOVERY

	// variables for gating the incoming signals
	logic br_valid_i_gated;
	logic [PKT_WIDTH-1:0] incoming_pkt_i_gated;                 
    logic [PKT_WIDTH-1:0] expiring_pkts_i_gated;
    logic [S_WIDTH+T_WIDTH-1:0] recovery_folded_history_i_gated;		// for recovery addresses
    logic [31:0] load_pc_i_gated;
	
	logic [S_WIDTH-1:0] tagged_indices_next;
    logic [T_WIDTH-1:0] tagged_tags_next;

	assign recovery_valid_i_gated = en_i && recovery_valid_i;
	assign br_valid_i_gated = en_i && br_valid_i && !recovery_valid_i_gated;
	assign incoming_pkt_i_gated = br_valid_i_gated ? incoming_pkt_i : '0;		// no need to gate these large bit sized packets. as they will lead to power use in each flips
	
	/// clock gating for the design
	assign folded_history_clock_en = br_valid_i_gated || recovery_valid_i_gated;

	// program counter value is required for both the cases: VALID BRANCH and ACTIVE RECOVERY
	assign load_pc_i_gated = folded_history_clock_en ? load_pc_i : '0;
	
	assign expiring_pkts_i_gated = br_valid_i_gated ? expiring_pkts_i : '0;
	assign recovery_folded_history_i_gated = recovery_valid_i_gated ? recovery_folded_history_i : '0;	

	logic [29:0] pc_word;
	assign pc_word = load_pc_i_gated [31:2];		// ignored 2 LSB bits, word aligned PC

	logic [29:0] hash_pc_idx_full;
	logic [29:0] hash_pc_tag_full;

	// bitwirse XOR of PC for tag and index
	assign hash_pc_idx_full = pc_word ^ (pc_word >> 2) ^ (pc_word >> 5);
	assign hash_pc_tag_full = pc_word ^ (pc_word >> 3) ^ (pc_word >> 7);

	// just for one block of timing the design
	localparam int EVICT_SHIFT = HISTORY_DEPTH % CSR_WIDTH;

	logic [CSR_WIDTH-1:0] folded_history;
	logic [CSR_WIDTH-1:0] next_folded_history;

	logic [CSR_WIDTH-1:0] shifted_fold;
	logic [CSR_WIDTH-1:0] padded_incoming;
	logic [CSR_WIDTH-1:0] padded_expiring;
	logic [CSR_WIDTH-1:0] aligned_expiring;

	assign shifted_fold = {folded_history[CSR_WIDTH-2:0],folded_history[CSR_WIDTH-1]};
	assign padded_incoming = {{(CSR_WIDTH-PKT_WIDTH){1'b0}},incoming_pkt_i_gated};
	assign padded_expiring = {{(CSR_WIDTH-PKT_WIDTH){1'b0}},expiring_pkts_i_gated};
	assign aligned_expiring = (padded_expiring << EVICT_SHIFT) | (padded_expiring >> (CSR_WIDTH - EVICT_SHIFT));

	always_comb begin
		next_folded_history = folded_history;
		if (recovery_valid_i_gated) begin
			next_folded_history = recovery_folded_history_i_gated;
		end
		else if (br_valid_i_gated) begin
			next_folded_history = shifted_fold ^ padded_incoming ^ aligned_expiring;
		end
	end

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			valid_o <= '0;
			folded_history <= '0;
			tagged_indices_next <= '0;
			tagged_tags_next <= '0; 
		end
		else begin 
			valid_o <= folded_history_clock_en;

			if (folded_history_clock_en) begin
				valid_o <= 1'b1;
				folded_history <= next_folded_history;
				tagged_indices_next <= next_folded_history[CSR_WIDTH-1:T_WIDTH] ^ hash_pc_idx_full[S_WIDTH-1:0];
				tagged_tags_next <= next_folded_history[T_WIDTH-1:0] ^ hash_pc_tag_full[T_WIDTH-1:0];
			end
		end
	end

	assign tagged_indices_o = tagged_indices_next;
	assign tagged_tags_o = tagged_tags_next;

	// Registered folded-history state sent to the checkpoint FIFO.
	assign folded_history_o = folded_history;

endmodule
