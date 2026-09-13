module tagged_table_wrapper #(
    parameter int INDEX_WIDTH      = 7,
    parameter int NUM_WAYS         = 4,
    parameter int TAG_WIDTH        = 16,
    parameter int DISTANCE_WIDTH   = 7,
    parameter int CONFIDENCE_WIDTH = 4,
    parameter int USEFUL_WIDTH     = 2
)(
    input  logic                        clk,

    input  logic                        fetch_en_i,
    input  logic [INDEX_WIDTH-1:0]      fetch_idx_i,
    
    output logic [TAG_WIDTH-1:0]        read_tags_o   [NUM_WAYS],
    output logic [DISTANCE_WIDTH-1:0]   read_dists_o  [NUM_WAYS],
    output logic [CONFIDENCE_WIDTH-1:0] read_confs_o  [NUM_WAYS],
    output logic [USEFUL_WIDTH-1:0]     read_useful_o [NUM_WAYS],

    
    // COMMIT CONTROL
    input  logic                        update_en_i,	/// it will be bit of the 7 bits wide "tagged_updated_en_o" from the provider_top_controller
    input  logic [1:0]                  update_cmd_i,	/// it will be 2 bits of the 2 bits wide, 7 bits deep  "table_cmd" from the provider_top_controller
    input  logic [INDEX_WIDTH-1:0]      commit_idx_i,
    
    // Encoder signal inputs
    input  logic [3:0]                  commit_empty_ways_i,
    input  logic [1:0]                  commit_hit_way_id_i,
 
    // Old Metadata being carried
    input  logic [TAG_WIDTH-1:0]        commit_old_tag_i,
    input  logic [DISTANCE_WIDTH-1:0]   commit_old_dist_i,
    input  logic [CONFIDENCE_WIDTH-1:0] commit_old_conf_i,
    input  logic [USEFUL_WIDTH-1:0]     commit_old_useful_i, 
    
    // New Target Payload (For Allocations/Misses)
    input  logic [TAG_WIDTH-1:0]        commit_new_tag_i,
    input  logic [DISTANCE_WIDTH-1:0]   commit_new_dist_i
);

    // LOCAL WAY ENCODER (The Target Selector) 
    logic [3:0] encoder_way_mask;

    local_way_encoder u_encoder (
        .en_i                (update_en_i),
        .cmd_i               (update_cmd_i),
        .commit_empty_ways_i (commit_empty_ways_i),
        .commit_hit_way_id_i (commit_hit_way_id_i),
        .way_write_mask_o    (encoder_way_mask)
    );

    // TAGGED UPDATE CONTROL ALUs
	logic predictor_we;
    logic [TAG_WIDTH-1:0] alu_next_tag;
    logic [DISTANCE_WIDTH-1:0] alu_next_dist;
    logic [CONFIDENCE_WIDTH-1:0] alu_next_conf;
    logic [USEFUL_WIDTH-1:0] alu_next_useful;


	tagged_update_cntrl #(
		.DISTANCE_WIDTH   (DISTANCE_WIDTH),
		.TAG_WIDTH        (TAG_WIDTH),
		.CONFIDENCE_WIDTH (CONFIDENCE_WIDTH),
		.USEFUL_WIDTH     (USEFUL_WIDTH)
	) u_alu (
		// Wakes up ONLY when the respective table is supposed to get updated/allocated based on the rpvoider_top_controller
		.en_i               (update_en_i), 
		.cmd_i              (update_cmd_i),
		
		// takes in commited values 
		.current_conf_i     (commit_old_conf_i),
		.current_useful_i   (commit_old_useful_i), 
		.current_tag_i      (commit_old_tag_i),
		.current_distance_i (commit_old_dist_i),
		
		// incase of misprediction, new values
		.new_tag_i          (commit_new_tag_i),
		.true_distance_i    (commit_new_dist_i),
		
		.sram_we_o          (predictor_we), 
		.next_confidence_o  (alu_next_conf),
		.next_useful_o      (alu_next_useful),
		.next_tag_o         (alu_next_tag),
		.next_distance_o    (alu_next_dist)
	);


	// TAGGED_PREDICTOR_SRAM_TABLE
    tagged_predictor_sram #(
        .INDEX_WIDTH      (INDEX_WIDTH),
        .NUM_WAYS         (NUM_WAYS),
        .TAG_WIDTH        (TAG_WIDTH),
        .DISTANCE_WIDTH   (DISTANCE_WIDTH),
        .CONFIDENCE_WIDTH (CONFIDENCE_WIDTH),
        .USEFUL_WIDTH     (USEFUL_WIDTH)
    ) u_sram (
        .clk                (clk),
        
        .fetch_en_i         (fetch_en_i),
        .fetch_idx_i        (fetch_idx_i),
        
        .tagged_update_en_i (predictor_we),
        .commit_way_id_i    (encoder_way_mask), 
        .commit_idx_i       (commit_idx_i),
        
        // directly taking in the values from the tagged update control
        .wdata_tag_i        (alu_next_tag),
        .wdata_dist_i       (alu_next_dist),
        .wdata_conf_i       (alu_next_conf),
        .wdata_useful_i     (alu_next_useful),

		.read_tags_o        (read_tags_o),
        .read_dists_o       (read_dists_o),
        .read_confs_o       (read_confs_o),
        .read_useful_o      (read_useful_o)
    );

endmodule