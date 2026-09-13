`timescale 1ns/1ps
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
    
	// input for the signal to decide whether to take the calculated value of next_folded_history or recovery_history value
	input logic recovery_valid_i,
	input logic [S_WIDTH+T_WIDTH-1:0] recovery_folded_history_i [0:NUM_TAGGED-1],

    output logic [S_WIDTH-1:0] tagged_indices_o [0:NUM_TAGGED-1],
    output logic [T_WIDTH-1:0] tagged_tags_o    [0:NUM_TAGGED-1],

	//output to send out the folded history output to the checkpoint FIFO buffer to think about
	output logic [S_WIDTH+T_WIDTH-1:0] folded_history_o [0:NUM_TAGGED-1]
);

	localparam int CSR_WIDTH = S_WIDTH + T_WIDTH;


	logic recovery_valid_i_gated;		// recovery valid signals
	logic folded_history_clock_en;		/// signal for gating the clock on both conditions:-  VALID BRANCH   &	 ACTIVE RECOVERY

	// variables for gating the incoming signals
	logic br_valid_i_gated;
	logic [PKT_WIDTH-1:0] incoming_pkt_i_gated;                 
    	logic [PKT_WIDTH-1:0] expiring_pkts_i_gated [0:NUM_TAGGED-1];
    	logic [S_WIDTH+T_WIDTH-1:0] recovery_folded_history_i_gated [0:NUM_TAGGED-1];		// for recovery addresses
    	logic [31:0] load_pc_i_gated;

	assign recovery_valid_i_gated = en_i && recovery_valid_i;
	assign br_valid_i_gated = en_i && br_valid_i && !recovery_valid_i_gated;
	assign incoming_pkt_i_gated = br_valid_i_gated ? incoming_pkt_i : '0;		// no need to gate these large bit sized packets. as they will lead to power use in each flips
	
	/// clock gating for the design
	assign folded_history_clock_en = br_valid_i_gated || recovery_valid_i_gated;

	// program counter value is required for both the cases: VALID BRANCH and ACTIVE RECOVERY
	assign load_pc_i_gated = folded_history_clock_en ? load_pc_i : '0;
	
	generate		// gating_input_expiring_packets and folded history incoming from checkpoint buffer
        for (genvar j = 0; j < NUM_TAGGED; j++) begin : gen_expire_clamp
            assign expiring_pkts_i_gated[j] = br_valid_i_gated ? expiring_pkts_i[j] : '0;
			assign recovery_folded_history_i_gated[j] = recovery_valid_i_gated ? recovery_folded_history_i[j] : '0;
        end
    endgenerate

	/// NEED TO THINK about the pulling the values down to ZERO on expiring packets because if I did it like this
	/// and the block gets disabled for just one clock cycle. Then i will have ZERO propagated to 
	/// - incoming_pkt_i_gated  and  expiring_pkts_i_gated   <------ these will be zero NOW, FOR just one clock cycle.
	/// because of this following signals will also go Zero in this clock cycle :-
	/// - padded_expiring     and    padded_incoming.
	/// But, **** NO ISSUES **** - because we will again get these signals next time when ""enable"" goes HIGH. Because we have folded history already protected with us using registered FF.
	/// So, it is alright.

	logic [29:0] pc_word;
	assign pc_word = load_pc_i_gated [31:2];		// ignored 2 LSB bits, word aligned PC

	logic [29:0] hash_pc_idx_full;
	logic [29:0] hash_pc_tag_full;

	// bitwirse XOR of PC for tag and index
	assign hash_pc_idx_full = pc_word ^ (pc_word >> 2) ^ (pc_word >> 5);
	assign hash_pc_tag_full = pc_word ^ (pc_word >> 3) ^ (pc_word >> 7);


	// ICG
	logic clk_gated_csr;

    // One ICG to gate the clock for all 7 CSR engines
    gated_clk u_icg (
        .clk_i       (clk),
        .en_i        (folded_history_clock_en),
        .clk_gated_o (clk_gated_csr)
    );


	//// ASSERTION FOR CHECKING X or Z in enable signals
	property hash_control_inputs_known_p;
        @(posedge clk) disable iff (!rst_n) !$isunknown({en_i, br_valid_i, recovery_valid_i});
    endproperty

    hash_control_inputs_known_a:
        assert property (hash_control_inputs_known_p)
        else $error("Hash control input en_i, br_valid_i, or recovery_valid_i contains X or Z");

    property hash_gated_controls_known_p;
        @(posedge clk) disable iff (!rst_n) !$isunknown({br_valid_i_gated, recovery_valid_i_gated, folded_history_clock_en});
    endproperty

    hash_gated_controls_known_a:
        assert property (hash_gated_controls_known_p)
        else $error("Hash gated control contains X or Z");

	generate

		for(genvar i = 0; i < NUM_TAGGED; i++) begin
			
			localparam int EVICT_SHIFT = DEPTHS[i] % CSR_WIDTH;		// calculate the eviction shift based on the parameterized depth for this specific table
			
			logic [CSR_WIDTH-1:0] folded_history, next_folded_history, shifted_fold, padded_incoming, padded_expiring, aligned_expiring;

			// aligned_expiring = '0;		// need not set this to ZERO because initially it can hold garbage data.
													// it will be assigned some value only when the gate signal "br_valid_i_gated" will be flipped to HIGH

			assign shifted_fold    = {folded_history[CSR_WIDTH-2:0], folded_history[CSR_WIDTH-1]};		// left circular shift of the current history/CSR bits in the hash table by 1 place
			assign padded_incoming = {{(CSR_WIDTH-PKT_WIDTH){1'b0}}, incoming_pkt_i_gated};				// padded the incoming GHR packet
			assign padded_expiring = {{(CSR_WIDTH-PKT_WIDTH){1'b0}}, expiring_pkts_i_gated[i] };			// padded the expiring GHR packet
			assign aligned_expiring = EVICT_SHIFT ? {padded_expiring[CSR_WIDTH - EVICT_SHIFT-1 : 0], padded_expiring[CSR_WIDTH-1 : CSR_WIDTH-EVICT_SHIFT]} : padded_expiring;

			always_ff@(posedge clk_gated_csr or negedge rst_n)
				begin
					if(!rst_n) begin
						folded_history <= '0;
					end else begin
						folded_history <= next_folded_history;
					end
				end
	
			// CSR fold logic
			always_comb
				begin
					next_folded_history = folded_history;
			
					if(br_valid_i_gated && (!recovery_valid_i_gated)) begin
						next_folded_history = shifted_fold ^ padded_incoming ^ aligned_expiring;
					end else if((!br_valid_i_gated) && recovery_valid_i_gated) begin
						next_folded_history = recovery_folded_history_i_gated[i];
					end
				end

			/// assertion to check if the folded history holds whenever  the enable abnd br_valid are down.
			property folded_history_holds_when_inactive_p;
				@(posedge clk) disable iff (!rst_n) !$past(folded_history_clock_en) |-> $stable(folded_history);
			endproperty
			
			folded_history_holds_when_inactive_a:
				assert property (folded_history_holds_when_inactive_p)
				else $error("TABLE %0d: folded_history changed while request was inactive",i);

			// Final Output Mix (Sliced CSR ^ Left shifted PC)
			assign tagged_indices_o[i] = next_folded_history[CSR_WIDTH-1 : T_WIDTH] ^ hash_pc_idx_full[S_WIDTH-1 : 0];
			assign tagged_tags_o[i] = next_folded_history[T_WIDTH-1 : 0] ^ hash_pc_tag_full[T_WIDTH-1 : 0];
			assign folded_history_o[i] = folded_history;

		end
	endgenerate

endmodule
