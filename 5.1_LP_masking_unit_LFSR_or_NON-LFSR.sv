module masking_unit_LFSR_or_NON_LFSR #(
    parameter int NUM_TABLES = 7
)(
    input  logic en_i,
    input  logic [NUM_TABLES-1:0] candidate_vector_i,
    input  logic [NUM_TABLES-1:0] eligibility_mask_i,
    input  logic [NUM_TABLES-1:0] LFSR_i,

    output logic [NUM_TABLES-1:0] final_candidate_mask_o,
    output logic allocate_cmd_o,
    output logic provider_update_only_cmd_o
);

    // localparam logic [NUM_TABLES-1:0] CEILING_MASK =(1 << (NUM_TABLES-1));

    // Operand-isolated inputs
    logic [NUM_TABLES-1:0] candidate_vector_gated;
    logic [NUM_TABLES-1:0] eligibility_mask_gated;
    logic [NUM_TABLES-1:0] LFSR_gated;

    logic [NUM_TABLES-1:0] base_candidates;     // candidates without LFSR vector ANDed with the candidate_vector ane eligibility mask
    logic [NUM_TABLES-1:0] LFSR_based_candidates;
    logic  LFSR_killed_all;
    // logic  is_ceiling;

    assign candidate_vector_gated = en_i ? candidate_vector_i : '0;
    assign eligibility_mask_gated = en_i ? eligibility_mask_i : '0;
    assign LFSR_gated = en_i ? LFSR_i : '0;

    // assign is_ceiling = (eligibility_mask_gated == CEILING_MASK);
    assign base_candidates = candidate_vector_gated & eligibility_mask_gated;
    assign LFSR_based_candidates = base_candidates & LFSR_gated;
    assign LFSR_killed_all = ~(|LFSR_based_candidates);

    always_comb begin
        final_candidate_mask_o       = '0;
        allocate_cmd_o               = 1'b0;
        provider_update_only_cmd_o   = 1'b0;

        if (en_i) begin
            if (!(|base_candidates)) begin      // if space is not there in higher tables, then we need to update the current/provider table only
                provider_update_only_cmd_o = 1'b1;
            end
            else begin
                allocate_cmd_o = 1'b1;

                if (LFSR_killed_all)
                    final_candidate_mask_o = base_candidates;
                else
                    final_candidate_mask_o = LFSR_based_candidates;
            end
        end
    end

endmodule