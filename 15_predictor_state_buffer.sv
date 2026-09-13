module phast_predictor_state_buffer #(
    parameter int LQ_DEPTH_BITS  = 4,     // 4 bits = 16 Load Queue entries
    parameter int NUM_TAGGED     = 7,
    parameter int BASE_S_WIDTH   = 10,
    parameter int S_WIDTH        = 7,
    parameter int T_WIDTH        = 16
)(
    input  logic clk,
    input  logic rst_n,
	
	// write ports
    input  logic we_i,		// write only when hash block genreates the output tags and addresses
    input  logic [LQ_DEPTH_BITS-1:0] fetch_lq_id_i,		// index of load queue where the LOAD instruction has been stored
    
    // addresses from base and tagged table & tags from tagged tables
	// these needs to be handled synchronously - so that all the data can be captured by considering clock edge as a gate
    input  logic [BASE_S_WIDTH-1:0]  fetch_base_idx_i,
    input  logic [S_WIDTH-1:0]       fetch_tagged_indices_i [0:NUM_TAGGED-1],
    input  logic [T_WIDTH-1:0]       fetch_tagged_tags_i    [0:NUM_TAGGED-1],

	// read port - when instruction is committed to predictor like ALLOCATE, PENALIZE, DECAY or REWARD
    // <<--- this does not mean commmit from ROB. This means that there is some prediction that needs to be logged in the device.
    // Highly likely an incorrect prediction log.
    // COMMIT - Means something needs to be logged in predictor tables for which we need indexes.
    
    input  logic commit_valid_i, 
    input  logic [LQ_DEPTH_BITS-1:0] commit_lq_id_i,
    
    // payload used for identifying the row and tags. will be used with LFSR things to AND these with table enable vector 
    // this will be purely asynchronous - need to push the ddata instantly
	output logic [BASE_S_WIDTH-1:0]  commit_base_idx_o,
    output logic [S_WIDTH-1:0]       commit_tagged_indices_o [0:NUM_TAGGED-1],
    output logic [T_WIDTH-1:0]       commit_tagged_tags_o    [0:NUM_TAGGED-1]
);

	localparam int NUM_ENTRIES = 1 << LQ_DEPTH_BITS;

	typedef struct packed {
			logic [BASE_S_WIDTH-1:0]            base_idx;
			logic [NUM_TAGGED-1:0][S_WIDTH-1:0] tagged_indices;
			logic [NUM_TAGGED-1:0][T_WIDTH-1:0] tagged_tags;
		} prb_payload_t;

	(* ramstyle = "logic" *) prb_payload_t prb_memory [0:(1<<LQ_DEPTH_BITS)-1];

	prb_payload_t write_data;
	prb_payload_t read_data;

	// for data clamps
	logic [LQ_DEPTH_BITS-1:0] fetch_lq_id_gated;
    logic [BASE_S_WIDTH-1:0]  fetch_base_idx_gated;
    logic [S_WIDTH-1:0] fetch_tagged_indices_gated [0:NUM_TAGGED-1];
    logic [T_WIDTH-1:0] fetch_tagged_tags_gated [0:NUM_TAGGED-1];
	logic [LQ_DEPTH_BITS-1:0] commit_lq_id_gated;

	assign fetch_lq_id_gated = we_i ? fetch_lq_id_i    : '0;
    assign fetch_base_idx_gated = we_i ? fetch_base_idx_i : '0;

	always_comb begin
        for (int i = 0; i < NUM_TAGGED; i++) begin
            fetch_tagged_indices_gated[i] = we_i ? fetch_tagged_indices_i[i] : '0;
            fetch_tagged_tags_gated[i]    = we_i ? fetch_tagged_tags_i[i]    : '0;
        end
    end

	assign commit_lq_id_gated = commit_valid_i ? commit_lq_id_i : '0;

	
	// storing the index for base table WITH index and tags for tagged tables
	always_comb begin
        write_data.base_idx = fetch_base_idx_gated;
        for (int i = 0; i < NUM_TAGGED; i++) begin
            write_data.tagged_indices[i] = fetch_tagged_indices_gated[i];
            write_data.tagged_tags[i]    = fetch_tagged_tags_gated[i];
        end
    end

	// for ICG
	logic [NUM_ENTRIES-1:0] row_we;
    logic [NUM_ENTRIES-1:0] clk_gated_prb;

	generate
        for (genvar i = 0; i < NUM_ENTRIES; i++) begin : gen_prb_rows
            
            assign row_we[i] = we_i && (fetch_lq_id_gated == i);

            // Independent ICG cell for each row
            gated_clk u_icg (
                .clk_i       (clk),
                .en_i        (row_we[i]),
                .clk_gated_o (clk_gated_prb[i])
            );

            // Flip-flops driven strictly by the gated clock
            always_ff @(posedge clk_gated_prb[i] or negedge rst_n) begin
                if (!rst_n) begin
                    prb_memory[i] <= '0;
                end else begin
                    // Pure flop update, no 'if(we_i)' check needed inside
                    prb_memory[i] <= write_data;
                end
            end
        end
    endgenerate

	// read logic 
	assign read_data = prb_memory[commit_lq_id_gated];

	always_comb begin
        // drive the outputs only when there is a valid commit.
        if (commit_valid_i) begin
            commit_base_idx_o = read_data.base_idx;
            for (int i = 0; i < NUM_TAGGED; i++) begin
                commit_tagged_indices_o[i] = read_data.tagged_indices[i];
                commit_tagged_tags_o[i]    = read_data.tagged_tags[i];
            end
        end else begin
            commit_base_idx_o = '0;
            for (int i = 0; i < NUM_TAGGED; i++) begin
                commit_tagged_indices_o[i] = '0;
                commit_tagged_tags_o[i]    = '0;
            end
        end
	end
		
endmodule