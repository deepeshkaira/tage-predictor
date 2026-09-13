module base_table_wrapper #(
    parameter int INDEX_WIDTH      = 10,
    parameter int DISTANCE_WIDTH   = 7,
    parameter int CONFIDENCE_WIDTH = 3
)(
    input  logic clk,

    input  logic fetch_en_i,
    input  logic [INDEX_WIDTH-1:0] fetch_idx_i,
    
    output logic [DISTANCE_WIDTH-1:0] read_dist_o,
    output logic [CONFIDENCE_WIDTH-1:0] read_conf_o,

    input  logic update_en_i,		// input from the provider_update_top_controller's pin "base_update_en"
    input  logic commit_mispredicted_i,
    input  logic [INDEX_WIDTH-1:0] commit_idx_i,

    input  logic [DISTANCE_WIDTH-1:0] commit_old_dist_i,
    input  logic [CONFIDENCE_WIDTH-1:0] commit_old_conf_i,
    input  logic [DISTANCE_WIDTH-1:0] commit_new_dist_i
);

    logic base_sram_we;
    logic [INDEX_WIDTH-1:0] base_sram_addr;
    logic [DISTANCE_WIDTH-1:0] base_sram_next_dist;
    logic [CONFIDENCE_WIDTH-1:0] base_sram_next_conf;

    
    // Base Update Block
    base_update_cntrl #(
        .INDEX_WIDTH (INDEX_WIDTH),
        .DISTANCE_WIDTH (DISTANCE_WIDTH),
        .CONFIDENCE_WIDTH (CONFIDENCE_WIDTH)
    ) u_base_cntrl (
        .en_i                  (update_en_i),		// enable signal from top controller that tells we need to update the base table
        
		// consider that we need these from ROB for our table update
		.commit_mispredicted_i (commit_mispredicted_i),		// prediction result from ROB
        .base_index_i (commit_idx_i),				// commit index from ROB
        .true_distance_i (commit_new_dist_i),			// commit index from PRB - incase confidence is ZERO. This will be used.
        .commit_old_dist_i (commit_old_dist_i),			
        .commit_old_conf_i (commit_old_conf_i),

        .base_we_o (base_sram_we),
        .base_addr_o (base_sram_addr),
        .base_wdata_dist_o (base_sram_next_dist),
        .base_wdata_conf_o (base_sram_next_conf)
    );

    // Base Predictor SRAM
    base_predictor_sram #(
        .INDEX_WIDTH (INDEX_WIDTH),
        .DISTANCE_WIDTH (DISTANCE_WIDTH),
        .CONFIDENCE_WIDTH (CONFIDENCE_WIDTH)
    ) u_base_sram (
        .clk (clk),

        .fetch_en_i (fetch_en_i),
        .fetch_idx_i (fetch_idx_i),

        .base_dist_o (read_dist_o),
        .base_conf_o (read_conf_o),

        .update_en_i (base_sram_we),
        .commit_index_i (base_sram_addr),
        .commit_distance_i (base_sram_next_dist),
        .commit_confidence_i (base_sram_next_conf)
    );

endmodule