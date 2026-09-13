module hash_table_top#(
	parameter int PKT_WIDTH = 7,
	parameter int BASE_S_WIDTH = 10,
	parameter int NUM_TAGGED = 7,
	parameter int S_WIDTH = 7,
	parameter int T_WIDTH = 16,
	parameter int DEPTHS [0:NUM_TAGGED-1] = '{2,4,6,8,12,16,32}
)(
	input logic clk,
	input logic rst_n,
	input logic en_i,

	input logic br_valid_i,
	input logic [PKT_WIDTH-1:0] incoming_pkt_i,
	input logic [PKT_WIDTH-1:0] expiring_pkts_i [0:NUM_TAGGED-1], 	// for T1 - T7 only
	input logic [31:0] load_pc_i,

	// outputs for all SRAM addresses

	output logic  [BASE_S_WIDTH-1:0] base_index_o,		// output for base table indexes
	output logic [S_WIDTH-1:0] tagged_indices_o [0:NUM_TAGGED-1],		// output for tagged table indexes
	output logic [T_WIDTH-1:0] tagged_tags_o [0:NUM_TAGGED-1]			// output for tagged table tags
);

/// Base table predictor
phast_base_table_hash#(
	.BASE_S_WIDTH(BASE_S_WIDTH)
)u_base_hash(
	.clk(clk),
	.rst_n(rst_n),
	.en_i(en_i),
	.load_pc_i(load_pc_i),
	.base_index_o(base_index_o)
);


//// tagged predictors hash calculation
phast_tagged_table_hash#(
	.PKT_WIDTH  (PKT_WIDTH),
	.NUM_TAGGED (NUM_TAGGED),
	.S_WIDTH    (S_WIDTH),
	.T_WIDTH    (T_WIDTH),
	.DEPTHS     (DEPTHS)
)u_tagged_hash(
	.clk(clk),
	.rst_n(rst_n),
	.en_i(en_i),
	.br_valid_i(br_valid_i),
	.incoming_pkt_i(incoming_pkt_i),
	.expiring_pkts_i(expiring_pkts_i),
	.load_pc_i(load_pc_i),
	.tagged_indices_o(tagged_indices_o),
	.tagged_tags_o(tagged_tags_o)
);

endmodule


// PHAST Base Table hash block with no Tags, direct mapped table.
module phast_base_table_hash #(
	parameter int BASE_S_WIDTH = 10		// S = 10 for untagged table
)(
	input logic clk,
	input logic rst_n,
	input logic en_i,
	input logic [31:0] load_pc_i,

	output logic [BASE_S_WIDTH-1:0] base_index_o
);

	logic [31:0] load_pc_i_gated;

	assign load_pc_i_gated = en_i ? load_pc_i : '0;

	always_ff@(posedge clk or negedge rst_n)
		begin
			if(!rst_n)
			begin
				base_index_o <= '0;
			end
			else if(en_i) begin
				base_index_o <= load_pc_i_gated[BASE_S_WIDTH + 1 : 2];		// use the 10 bits of the PC after omitting the first 2 LSB bits (word addressing)				
			end
			
		end

endmodule



//// PHAST Hash module for Tagged Tables with variable depths

module phast_tagged_table_hash #(
    parameter int PKT_WIDTH  = 7,
    parameter int NUM_TAGGED = 7,
    parameter int S_WIDTH    = 7,
    parameter int T_WIDTH    = 16,
    
    parameter int DEPTHS [0:NUM_TAGGED-1] = '{2, 4, 6, 8, 12, 16, 32}
)(

    input  logic clk,
    input  logic rst_n,
    input  logic en_i,
    
    input  logic br_valid_i,
    input  logic [PKT_WIDTH-1:0] incoming_pkt_i,                 
    input  logic [PKT_WIDTH-1:0] expiring_pkts_i [0:NUM_TAGGED-1], 
    input  logic [31:0] load_pc_i,                      
    
    output logic [S_WIDTH-1:0] tagged_indices_o [0:NUM_TAGGED-1],
    output logic [T_WIDTH-1:0] tagged_tags_o    [0:NUM_TAGGED-1]
);

	// variables for gating the incoming signals
	logic br_valid_i_gated;
	logic [PKT_WIDTH-1:0] incoming_pkt_i_gated;                 
    logic [PKT_WIDTH-1:0] expiring_pkts_i_gated [0:NUM_TAGGED-1];
    logic [31:0] load_pc_i_gated;

	assign br_valid_i_gated = en_i ? br_valid_i : '0;
	assign incoming_pkt_i_gated = en_i ? incoming_pkt_i : '0;
	assign expiring_pkts_i_gated = en_i ? expiring_pkts_i : '0;
	assign load_pc_i_gated = en_i ? load_pc_i : '0;

	localparam int CSR_WIDTH = S_WIDTH + T_WIDTH;

	logic [29:0] pc_word;
	assign pc_word = load_pc_i_gated [31:2];		// ignored 2 LSB bits, word aligned PC

	logic [29:0] hash_pc_indx_full;
	logic [29:0] hash_pc_tag_full;

	// bitwirse XOR of PC for tag and index
	assign hash_pc_idx_full = pc_word ^ (pc_word >> 2) ^ (pc_word >> 5);
	assign hash_pc_tag_full = pc_word ^ (pc_word >> 3) ^ (pc_word >> 7);

	generate

		for(genvar i = 0; i < NUM_TAGGED; i++) begin : gen_csr_engines
			
			localparam int EVICT_SHIFT = DEPTHS[i] % CSR_WIDTH;		// calculate the eviction shift based on the parameterized depth for this specific table
			
			logic [CSR_WIDTH-1:0] folded_history, next_folded_history, shifted_fold, padded_incoming, padded_expiring, aligned_expiring;

			always_ff@(posedge clk or negedge rst_n) 
				begin
					if(!rst_n) begin
						folded_history <= '0;
					end else if(en_i) begin
						folded_history <= next_folded_history;
					end
				end

			
			// CSR fold logic
			always_comb

				begin
					next_folded_history = folded_history;
					shifted_fold = '0;
					padded_incoming = '0;
					padded_expiring = '0; 
					aligned_expiring = '0;

					if(br_valid_i_gated) begin
						
						shifted_fold    = {folded_history[CSR_WIDTH-2:0], folded_history[CSR_WIDTH-1]};		// left circular shift of the current history/CSR bits in the hash table by 1 place
						padded_incoming = { {(CSR_WIDTH-PKT_WIDTH){1'b0}}, incoming_pkt_i };				// padded the incoming GHR packet

						padded_expiring = { {(CSR_WIDTH-PKT_WIDTH){1'b0}}, expiring_pkts_i[i] };			// padded the expiring GHR packet

						if(EVICT_SHIFT == 0)  begin
							aligned_expiring = padded_expiring;
						end else begin
							aligned_expiring = {padded_expiring[CSR_WIDTH-EVICT_SHIFT-1 : 0], padded_expiring[CSR_WIDTH-1 : CSR_WIDTH-EVICT_SHIFT]};
						end

						next_folded_history = shifted_fold ^ padded_incoming ^ aligned_expiring;
					end
				end

				// Final Output Mix (Sliced CSR ^ Left shifted PC)
				assign tagged_indices_o[i] = next_folded_history[CSR_WIDTH-1 : T_WIDTH]   ^ hash_pc_idx_full[S_WIDTH-1 : 0];
				assign tagged_tags_o[i]    = next_folded_history[T_WIDTH-1 : 0] ^ hash_pc_tag_full[T_WIDTH-1 : 0];

		end
	endgenerate

endmodule


