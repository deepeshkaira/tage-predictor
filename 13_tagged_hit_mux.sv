module tagged_hit_mux #(
    parameter int NUM_WAYS         = 4,
    parameter int DISTANCE_WIDTH   = 7,
    parameter int CONFIDENCE_WIDTH = 4,
    parameter int USEFUL_WIDTH     = 2,
    parameter int WAY_ID_WIDTH     = $clog2(NUM_WAYS)
)(
    // 1-hot hit vector from the Comparator
    input  logic [NUM_WAYS-1:0]         way_hit_vector_i,
    
    // 4-Way Payloads straight from the SRAM
    input  logic [DISTANCE_WIDTH-1:0]   read_dists_i  [NUM_WAYS],
    input  logic [CONFIDENCE_WIDTH-1:0] read_confs_i  [NUM_WAYS],
    input  logic [USEFUL_WIDTH-1:0]     read_useful_i [NUM_WAYS],

    // Single Extracted Payload

    output logic [DISTANCE_WIDTH-1:0]   hit_dist_o,
    output logic [CONFIDENCE_WIDTH-1:0] hit_conf_o,
    output logic [USEFUL_WIDTH-1:0]     hit_useful_o,
    output logic [WAY_ID_WIDTH-1:0]     hit_way_id_o
);

    logic hit_mux_active = |way_hit_vector_i;
    
    // assertion to check that the design gives some output other than zero if the the input for way_hit_vector_i is one-hot
    always_comb begin
        assert ($onehot0(way_hit_vector_i)) else $error("Tagged hit mux received a multi-hot way vector");
    end

    always_comb begin

        hit_dist_o   = '0;
        hit_conf_o   = '0;
        hit_useful_o = '0;
        hit_way_id_o = '0;

        if(hit_mux_active) begin
                    //  One hot selection logic for the design to select one of the way which generates a TAG-HIT
                for (int w = 0; w < NUM_WAYS; w++) begin
                
                    // THIS IS A GOOD WAY TO DO IT. But, in this we will have to look into each bit with loop unrolled for all ways
                    // Next would be - if the MSB is HIGH , then it would make a mux heavy logic (will need a NOT Gate as well)
                    // AND , OR and NOT Gates

                    // if (way_hit_vector_i[w]) begin
                    //     hit_dist_o   = read_dists_i[w];
                    //     hit_conf_o   = read_confs_i[w];
                    //     hit_useful_o = read_useful_i[w];
                    // end

                    /// instead - we can make it like this. Parallel AND OR block. (only 2 layers AND and  OR)
                    hit_dist_o   |= read_dists_i[w]  & {DISTANCE_WIDTH{way_hit_vector_i[w]}};
                    hit_conf_o   |= read_confs_i[w]  & {CONFIDENCE_WIDTH{way_hit_vector_i[w]}};
                    hit_useful_o |= read_useful_i[w] & {USEFUL_WIDTH{way_hit_vector_i[w]}};
                    hit_way_id_o |= w[WAY_ID_WIDTH-1:0] & {WAY_ID_WIDTH{way_hit_vector_i[w]}};
                end
            end            
        end


endmodule