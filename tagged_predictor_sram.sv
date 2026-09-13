module tagged_predictor_sram #(
	parameter int NUM_TAGGED_TABLES = 7,	// 7 TAGGED tables
    parameter int INDEX_WIDTH      = 7,  // 128 rows ($clog2(128) = 7)
    parameter int NUM_WAYS         = 4,  // 4-way set associative
    parameter int TAG_WIDTH        = 16, // 16-bit Tag
    parameter int DISTANCE_WIDTH   = 7,  // 7-bit target payload
    parameter int CONFIDENCE_WIDTH = 4,  // 4-bit hysteresis
    parameter int USEFUL_WIDTH        = 2   // 2-bit replacement policy
)(
    input logic clk,

	input logic fetch_en_i,	// read enable pin
    input logic [INDEX_WIDTH-1:0] fetch_idx_i,	// index for reading the tags and other information
    
	// we need to output all the ways in here because we will be using comparator for tag comparison and then telling if there is a match or not.
	// incase of a match , we need to forward distance , confidence and LRUs. If CORRECT_PREDICTION or INCORRECT , then need to update LRU and CONFIDENCE bits
	// If INCORRECT_PREDICTION and we need to update the way - we need Tag and Distance value.
	// Basically, we need the packet that we are going to use to update row, it can be anything of the 4 va;ues.
	// these all will go to comparator and onyl one way will actually go out
    output logic [TAG_WIDTH-1:0] read_tags_o [NUM_WAYS],
    output logic [DISTANCE_WIDTH-1:0] read_dists_o [NUM_WAYS],
    output logic [CONFIDENCE_WIDTH-1:0] read_confs_o [NUM_WAYS],
    output logic [USEFUL_WIDTH-1:0] read_useful_o [NUM_WAYS],
 
    input  logic tagged_update_en_i,
    input  logic [NUM_WAYS-1:0] commit_way_id_i, // input from the control block. This is a MASK to select one way oout of the 4 - REWARD / PENALIZE / ALLOCATE / DECAY.
    input  logic [INDEX_WIDTH-1:0] commit_idx_i,
    
    input  logic [TAG_WIDTH-1:0] wdata_tag_i,
    input  logic [DISTANCE_WIDTH-1:0] wdata_dist_i,
    input  logic [CONFIDENCE_WIDTH-1:0] wdata_conf_i,
    input  logic [USEFUL_WIDTH-1:0] wdata_useful_i
);

	localparam int TABLE_DEPTH = 1 << INDEX_WIDTH; // 128
		
	// 128 deep SRAM tables
	// logic [TAG_WIDTH-1:0] tag_mem [NUM_TABLES][NUM_WAYS][TABLE_DEPTH];			// SRAM memory holding the TAG
	// logic [DISTANCE_WIDTH-1:0] dist_mem [NUM_TABLES][NUM_WAYS][TABLE_DEPTH];	// SRAM memory hlding the PREDICTED DISTANCE
	// logic [CONFIDENCE_WIDTH-1:0] conf_mem [NUM_TABLES][NUM_WAYS][TABLE_DEPTH];	// SRAM memory holding the CONFIDENCE BITS VALUE
	// logic [USEFUL_WIDTH-1:0] useful_mem  [NUM_TABLES][NUM_WAYS][TABLE_DEPTH];	// SRAM memory holding the USEFUL bits

	typedef struct packed {
        logic [TAG_WIDTH-1:0]        tag;
        logic [DISTANCE_WIDTH-1:0]   distn;
        logic [CONFIDENCE_WIDTH-1:0] conf;
        logic [USEFUL_WIDTH-1:0]     useful;
    } tagged_payload_t;

    tagged_payload_t sram_array [NUM_WAYS][TABLE_DEPTH];

	logic clk_gated_read;
    logic clk_gated_write;

    // ICG for the Read Port
    gated_clk u_icg_read (
        .clk_i       (clk),
        .en_i        (fetch_en_i),
        .clk_gated_o (clk_gated_read)
    );

    // ICG for the Write Port
    gated_clk u_icg_write (
        .clk_i       (clk),
        .en_i        (tagged_update_en_i),
        .clk_gated_o (clk_gated_write)
    );

	generate
			
			// this will read the TAG, DISTANCE , CONFIDENCE and USEFUL from a ROW location
			// since there are 4 ways, so these will output the all the 4 ways data packet
			for (genvar w = 0; w < NUM_WAYS; w++) begin
				always_ff @(posedge clk_gated_read) begin
					// if (fetch_en_i) begin				<-- not needed now, since clock is gated
						read_tags_o[w]   <= sram_array[w][fetch_idx_i].tag;
						read_dists_o[w]  <= sram_array[w][fetch_idx_i].distn;
						read_confs_o[w]  <= sram_array[w][fetch_idx_i].conf;
						read_useful_o[w] <= sram_array[w][fetch_idx_i].useful;
					// end
				end
			end


			logic is_decay;
			assign is_decay = (commit_way_id_i == 4'b1111);	// added this to differentiate between DECAY and OTHER OPERATIONS.
														// In decay , we will have all our WAY MASK = 4'b1111 . 
														// So, with bitwise AND ,we can easily identify if it is DECAY or OTHER OPERATIONS

			always_ff @(posedge clk_gated_write) begin
				
				// Only open the write latches if THIS specific table is enabled
				// if (tagged_update_en_i) begin		<-- not needed now, since clock is gated
					
					// Procedural loop to check the 4-bit 1-hot mask
					for (int way = 0; way < NUM_WAYS; way++) begin
						if (commit_way_id_i[way] & is_decay) begin

							// we are decaying the useful bits of all the ways in here like this.
							sram_array[way][commit_idx_i].useful <= (sram_array[way][commit_idx_i].useful == '0) ? '0 : (sram_array[way][commit_idx_i].useful - 1'b1);

						end else if(commit_way_id_i[way] & !(is_decay))begin
							// NORMAL UPDATE: Overwrite everything with the Skinny Payload
							sram_array[way][commit_idx_i].tag    <= wdata_tag_i;
							sram_array[way][commit_idx_i].distn  <= wdata_dist_i;
							sram_array[way][commit_idx_i].conf   <= wdata_conf_i;
							sram_array[way][commit_idx_i].useful <= wdata_useful_i; // Comes from ALU for all cases except DECAY
						end
					end					
				// end
			end

	endgenerate
endmodule