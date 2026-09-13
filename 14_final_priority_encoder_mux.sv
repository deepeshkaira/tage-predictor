// NEED NOT DO POWER GATING HERE BECAUSE IT WILL BE QUIET/ HOLDING STATE BECAUSE OF CLAMPINGS IN THE UPSTREAM OF LOGIC

module final_priority_encoder_mux #(
    parameter int NUM_TAGGED_TABLES = 7,
    parameter int DISTANCE_WIDTH    = 7,
    parameter int CONFIDENCE_WIDTH  = 4,
    parameter int USEFUL_WIDTH      = 2,
    parameter int WAY_ID_WIDTH      = 2,
    parameter int PROVIDER_ID_WIDTH = $clog2(NUM_TAGGED_TABLES + 1)
)(

    // signals for power gating the design
    input logic base_fetch_valid_i,

	// tagged tables input
    input  logic [NUM_TAGGED_TABLES-1:0] table_hit_vector_i,
    input  logic [DISTANCE_WIDTH-1:0] tagged_dists_i [NUM_TAGGED_TABLES],
    input  logic [USEFUL_WIDTH-1:0] useful_bits_i [NUM_TAGGED_TABLES],
    input  logic [CONFIDENCE_WIDTH-1:0] confidence_bits_i [NUM_TAGGED_TABLES],
    input  logic [WAY_ID_WIDTH-1:0] way_id_i [NUM_TAGGED_TABLES],

	// base table input. Since, there is not flag in BASE TABLE, so we simply output the distance.
    input  logic [DISTANCE_WIDTH-1:0] base_dist_i,
    input  logic [CONFIDENCE_WIDTH-1:0] base_confidence_i,

	// output
    output logic [DISTANCE_WIDTH-1:0] final_dist_o,
    output logic [PROVIDER_ID_WIDTH-1:0] provider_id_o,
    output logic [WAY_ID_WIDTH-1:0] way_hit_id_o,
    output logic [CONFIDENCE_WIDTH-1:0] confidence_bits_o,
    output logic [USEFUL_WIDTH-1:0] useful_bits_o
);

    /// variables for gating
    logic [NUM_TAGGED_TABLES-1:0] table_hit_vector_gated;
    logic [DISTANCE_WIDTH-1:0] tagged_dists_gated [0:NUM_TAGGED_TABLES-1];
    logic [USEFUL_WIDTH-1:0] useful_bits_gated [0:NUM_TAGGED_TABLES-1];
    logic [CONFIDENCE_WIDTH-1:0] confidence_bits_gated [0:NUM_TAGGED_TABLES-1];
    logic [WAY_ID_WIDTH-1:0] way_id_gated [0:NUM_TAGGED_TABLES-1];
    logic [DISTANCE_WIDTH-1:0] base_dist_gated;
    logic [CONFIDENCE_WIDTH-1:0] base_confidence_gated;

    logic [NUM_TAGGED_TABLES-1:0] smear;
    logic [NUM_TAGGED_TABLES-1:0] isolated_hit;
    
    logic [DISTANCE_WIDTH-1:0] hit_dist;
    logic [PROVIDER_ID_WIDTH-1:0] hit_id;
    logic [WAY_ID_WIDTH-1:0] way_hit;
    logic [CONFIDENCE_WIDTH-1:0] confidence_hit;
    logic [USEFUL_WIDTH-1:0] useful_hit;

    /// enable signal for encoder
    logic enable_for_power_gating_encoder;

    assign enable_for_power_gating_encoder = (((|table_hit_vector_i) || base_fetch_valid_i) == 1) ? 1'b1 : 1'b0;
    
    // gating block
    always_comb begin
        table_hit_vector_gated = '0;
        base_dist_gated        = '0;
        base_confidence_gated  = '0;
    
        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            tagged_dists_gated[i]    = '0;
            useful_bits_gated[i]     = '0;
            confidence_bits_gated[i] = '0;
            way_id_gated[i]          = '0;
        end
    
        if (enable_for_power_gating_encoder) begin
            table_hit_vector_gated = table_hit_vector_i;
            base_dist_gated        = base_dist_i;
            base_confidence_gated  = base_confidence_i;
    
            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
                tagged_dists_gated[i]    = tagged_dists_i[i];
                useful_bits_gated[i]     = useful_bits_i[i];
                confidence_bits_gated[i] = confidence_bits_i[i];
                way_id_gated[i]          = way_id_i[i];
            end
        end
    end


    always_comb begin

        smear = table_hit_vector_gated;
       
        for (int i = 0; (1 << i) < NUM_TAGGED_TABLES; i++) begin
            smear = smear | (smear >> (1 << i));
        end

        //isolated MSB
        isolated_hit = smear ^ (smear >> 1);

        hit_dist = '0;
        hit_id = '0;
        way_hit = '0;
        confidence_hit ='0;
        useful_hit = '0;


        // bit expanding the DISTANCE from a TABLE if its table has a hit.
        // if there is hit in table - > simply bit expand that "1" to AND with tagged_distance
        // if there is a miss in the table - > simply expand that '"0" to AND with tagged distance. will nullify the result from that table
        // same for table ID as well - AND and OR reduction tree.
        // and finally OR all the 7 results of hit_distance with themselves. will get the distance.

        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            hit_dist |= ({DISTANCE_WIDTH{isolated_hit[i]}} & tagged_dists_gated[i]);
            hit_id   |= ({PROVIDER_ID_WIDTH{isolated_hit[i]}} & (i[PROVIDER_ID_WIDTH-1:0] + 1'b1));
            way_hit |= way_id_gated[i] & {WAY_ID_WIDTH{isolated_hit[i]}};
            confidence_hit |= confidence_bits_gated[i] & {CONFIDENCE_WIDTH{isolated_hit[i]}};
            useful_hit |= useful_bits_gated[i] & {USEFUL_WIDTH{isolated_hit[i]}};    
        end

        // Default inactive outputs. if base is giving some result then it is there else it is going to be 0 all the wya.
        final_dist_o      = base_dist_gated;
        provider_id_o     = '0;
        way_hit_id_o      = '0;
        confidence_bits_o = base_confidence_gated;
        useful_bits_o     = '0;
        
        // Tagged-table hit overrides the base-table result.
        if (table_hit_vector_gated != '0) begin
            final_dist_o      = hit_dist;
            provider_id_o     = hit_id;
            way_hit_id_o      = way_hit;
            confidence_bits_o = confidence_hit;
            useful_bits_o     = useful_hit;
        end
        
    end

endmodule