/// Base SRAM Predictor table

module base_predictor_sram #(
    parameter int INDEX_WIDTH = 10,     // 1024 rows
    parameter int DISTANCE_WIDTH = 7,   // 7-bit target payload
    parameter int CONFIDENCE_WIDTH = 3  // OPTIMIZED: 3-bit hysteresis counter
)(
    input  logic clk,

    // read path to feed the prediction distance
	input  logic fetch_en_i,	// read enable pin for reading the distances at certain index
    input  logic [INDEX_WIDTH-1:0] fetch_idx_i,		// index to read the distance from 
    output logic [DISTANCE_WIDTH-1:0] base_dist_o,
    output logic [CONFIDENCE_WIDTH-1:0] base_conf_o,

    // just for sending a fetch valid signal downstream for the encoder as enable flag to and with tagged tables as well.
    output logic fetch_valid_o,

	// write path to feed the values to be written on the predictor table
	input  logic update_en_i,
	input  logic [INDEX_WIDTH-1:0] commit_index_i,
	input  logic [DISTANCE_WIDTH-1:0] commit_distance_i,
	input  logic [CONFIDENCE_WIDTH-1:0] commit_confidence_i
);

	localparam int TABLE_DEPTH = 1 << INDEX_WIDTH;
		
	// SRAM memory array
	typedef struct packed {
        logic [DISTANCE_WIDTH-1:0] distn;
        logic [CONFIDENCE_WIDTH-1:0] conf;
    } base_sram_word_t;

    base_sram_word_t sram_array [0 : TABLE_DEPTH-1];

	// can also do the SRAM memory declaration like this
	// localparam int WORD_WIDTH = DISTANCE_WIDTH + CONFIDENCE_WIDTH; 
    // logic [WORD_WIDTH-1:0] sram_array [0 : TABLE_DEPTH-1];


   	// this is just for the encoder block downstream in the design. handled the X propagation here.
    always_ff @(posedge clk) begin
        case (fetch_en_i)
            1'b1:    fetch_valid_o <= 1'b1;
            default: fetch_valid_o <= 1'b0; // Handles 0, X and Z
        endcase
    end

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
        .en_i        (update_en_i),
        .clk_gated_o (clk_gated_write)
    );

	always_ff @(posedge clk_gated_read) begin
		// block to do the read operation and give out the distance and confidence
		// if(fetch_en_i)
			// begin
				base_dist_o <= sram_array[fetch_idx_i].distn;
				base_conf_o <= sram_array[fetch_idx_i].conf;
			// end
	end

	always_ff @(posedge clk_gated_write) begin
		// block to do the write/update operation
		// if (update_en_i) begin		// this is kind of power gating that we have to stop togling of sram cells when not enabled
			sram_array[commit_index_i].distn <= commit_distance_i;
            sram_array[commit_index_i].conf <= commit_confidence_i;
		// end
	end


    // Added an assertion to make sure that in case of simultaneous read-write.
    // Read returns old value at the memory while write overwrites the location in the next clock cycle as they are clock bound.
    property p_simultaneous_rw_returns_old_data;
        base_sram_word_t old_word;

        @(posedge clk)
        (fetch_en_i && update_en_i && (fetch_idx_i == commit_index_i) && !$isunknown(sram_array[fetch_idx_i]),old_word = sram_array[fetch_idx_i])
        |=> ( base_dist_o == old_word.distn && base_conf_o == old_word.conf);
    endproperty

    assert property (p_simultaneous_rw_returns_old_data)
    else $error("Base SRAM read/write collision did not return old data");


endmodule