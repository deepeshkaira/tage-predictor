module tagged_way_comparator #(
    parameter int NUM_WAYS  = 4,
    parameter int TAG_WIDTH = 16
)(

	input  logic fetch_en_i,            // this fetch enable is the one clock cycle delayed fetch enable in the SRAM blocked upstream
    input  logic [TAG_WIDTH-1:0] hashed_tag_i,
    input  logic [TAG_WIDTH-1:0] read_tags_i [NUM_WAYS],

	output logic way_hit_flag,
    output logic [NUM_WAYS-1:0]  way_hit_vector_o
);

    logic [TAG_WIDTH-1:0] hashed_tag_gated;
    logic [TAG_WIDTH-1:0] read_tags_gated [NUM_WAYS];
    
    assign hashed_tag_gated = fetch_en_i ? hashed_tag_gated : '0;
    always_comb
        begin
            for(int i=0; i < NUM_WAYS; i++) begin
                read_tags_gated = '0;
            end        
        end

    // generate blocks
    generate
        for (genvar w = 0; w < NUM_WAYS; w++) begin : gen_comparators

            assign way_hit_vector_o[w] = (hashed_tag_gated == read_tags_gated[w]);
        end
    endgenerate

	assign way_hit_flag = |way_hit_vector_o;

    // assertions to make sure that the way hit vector is one-hot (only when fetch_en_i is HIGH)
    always_comb begin
        if(fetch_en_i) begin
            assert($onehot0(way_hit_vector_o)) else $error("Mulitple tagged ways matched during a valid fetch")
        end
    end

endmodule