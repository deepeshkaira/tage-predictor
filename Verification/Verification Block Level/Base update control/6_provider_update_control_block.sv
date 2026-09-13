// we need to improve this and better separate into 3 different modules with 2 being 
// submodules and 3rd being the top for them serving as controller


// this BLOCK will provide the control and data for Table 0's WRITE OPERATION ONLY.

module base_update_cntrl#(
	parameter int INDEX_WIDTH = 10,		// SINCE base table has row index 10 bits wide
	parameter int DISTANCE_WIDTH = 7,	// 7 bit distance payload
	parameter int CONFIDENCE_WIDTH = 3  // 3-bit confidence hysteresis
)(
	input logic en_i,

	// inputs rom ROB and PRB
	input logic commit_mispredicted_i,						// ROB
	input logic [INDEX_WIDTH-1:0] base_index_i,				// input of PRB for committed packet - used to identify the location of the prediction. Will come from PRB
	input logic [DISTANCE_WIDTH-1:0] true_distance_i,		// input from commited packet to be written incase the confidence at location is ZERO (0)

	// coming from ROB
    input  logic [DISTANCE_WIDTH-1:0]   commit_old_dist_i,	/// will be written back incase the confidence is NOT ZERO
    input  logic [CONFIDENCE_WIDTH-1:0] commit_old_conf_i,	// the confidence when prediction was given

	output logic base_we_o,
	output logic [INDEX_WIDTH-1:0] base_addr_o,
	output logic [DISTANCE_WIDTH-1:0] base_wdata_dist_o,	// this is true distance for base table
	output logic [CONFIDENCE_WIDTH-1:0] base_wdata_conf_o
);

	localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};
	localparam logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE = '0;
	localparam logic [CONFIDENCE_WIDTH-1:0] WEAK_CONFIDENCE = 3'b100;

	// for operand isolation
	logic commit_mispredicted_gated;
    logic [INDEX_WIDTH-1:0] base_index_gated;
    logic [DISTANCE_WIDTH-1:0] true_distance_gated;
    logic [DISTANCE_WIDTH-1:0] commit_old_dist_gated;
    logic [CONFIDENCE_WIDTH-1:0] commit_old_conf_gated;

    assign commit_mispredicted_gated = en_i ? commit_mispredicted_i : 1'b0;
    assign base_index_gated = en_i ? base_index_i : '0;
    assign true_distance_gated = en_i ? true_distance_i : '0;
    assign commit_old_dist_gated = en_i ? commit_old_dist_i : '0;
    assign commit_old_conf_gated = en_i ? commit_old_conf_i : '0;

	always_comb
	begin

		/// assertion to protect the block incase the gating signal is itself is ZERO i.e. "en_i = 0"
		assert (!$isunknown(en_i))
        else $error("base_update_cntrl: en_i contains X or Z");

		base_we_o = 1'b0;
		base_addr_o = '0;
		base_wdata_dist_o = '0;
		base_wdata_conf_o = '0;

		if(en_i)
			begin
				base_we_o = 1'b1;
				base_addr_o = base_index_gated;
				
				if (commit_mispredicted_gated) begin
                
					// PENALIZE for misprediction

					if (commit_old_conf_gated == MIN_CONFIDENCE) begin
						// if zero distance, then need to replace the distance with the newly calculated true distance
						base_wdata_dist_o = true_distance_gated;
						base_wdata_conf_o = WEAK_CONFIDENCE;
					end else begin
						// decrement the confidence bits value
						base_wdata_dist_o = commit_old_dist_gated;
						base_wdata_conf_o = commit_old_conf_gated - 1'b1;
					end
					
				end else begin
					
					/// if correct then keep old distance and increment confidence
					base_wdata_dist_o = commit_old_dist_gated;
					base_wdata_conf_o = (commit_old_conf_gated == MAX_CONFIDENCE) ? MAX_CONFIDENCE : (commit_old_conf_gated + 1'b1);
			end
		end
	end

endmodule


// THIS BLOCK IS FOR giving CONTROL SIGNALS to UPDATE the Tagged Tables

module tagged_update_cntrl#(
	parameter int DISTANCE_WIDTH = 7,
	parameter int TAG_WIDTH = 16,
	parameter int CONFIDENCE_WIDTH = 4,
	parameter int USEFUL_WIDTH = 2
)(
	input logic en_i,
	input logic [1:0] cmd_i,		// this is some input that we will recieve from the top module controller 
									// that will tell us what action needs to be taken for this particular table
									// by default we can keep this at ZERO

	// current values at the selected location in the table
	input  logic [CONFIDENCE_WIDTH-1:0] current_conf_i,				// from ROB
    input  logic [USEFUL_WIDTH-1:0] current_useful_i,				// from ROB
    input  logic [TAG_WIDTH-1:0] current_tag_i,						// from PSB
    input  logic [DISTANCE_WIDTH-1:0] current_distance_i,			// from PSB

	// incoming new data packet after misprediction
	input logic [TAG_WIDTH-1:0] new_tag_i,
	input logic [DISTANCE_WIDTH-1:0] true_distance_i,

	/// data to be written/ update the location
	output logic sram_we_o,		// update the location 
	output logic [CONFIDENCE_WIDTH-1:0] next_confidence_o,
	output logic [USEFUL_WIDTH-1:0] next_useful_o,
	output logic [TAG_WIDTH-1:0] next_tag_o,
	output logic [DISTANCE_WIDTH-1:0] next_distance_o

);

	typedef enum logic [1:0] {
        CMD_ALLOCATE,CMD_REWARD,CMD_PENALIZE,CMD_DECAY
    } phast_cmd_t;
    
    phast_cmd_t tagged_cmd_i;
    assign tagged_cmd_i = en_i ? phast_cmd_t'(cmd_i) : '0;

	// definition o fthe boundaries of confidence bits
	localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};   // max confidence		
	localparam logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE = '0;			// lowest confidence
	localparam logic [CONFIDENCE_WIDTH-1:0] WEAK_CONFIDENCE = 4'b1000;		// threshold to flip the confidence

	localparam logic [USEFUL_WIDTH-1:0] MAX_USEFUL = {USEFUL_WIDTH{1'b1}};
	localparam logic [USEFUL_WIDTH-1:0]  MIN_USEFUL  = '0;

	// wires fr gating the inputs
	logic [CONFIDENCE_WIDTH-1:0] current_conf_gated;
    logic [USEFUL_WIDTH-1:0] current_useful_gated;
    logic [TAG_WIDTH-1:0] current_tag_gated;
    logic [DISTANCE_WIDTH-1:0] current_distance_gated;
    logic [TAG_WIDTH-1:0] new_tag_gated;
    logic [DISTANCE_WIDTH-1:0] true_distance_gated;

	assign current_conf_gated = en_i ? current_conf_i : '0;
    assign current_useful_gated = en_i ? current_useful_i  : '0;
    assign current_tag_gated = en_i ? current_tag_i : '0;
    assign current_distance_gated = en_i ? current_distance_i : '0;
    assign new_tag_gated = en_i ? new_tag_i : '0;
    assign true_distance_gated = en_i ? true_distance_i : '0;

	always_comb begin
		sram_we_o = 1'b0;
		next_confidence_o = '0;
        next_useful_o = '0;
        next_tag_o = '0;
        next_distance_o = '0;

		if(en_i) begin
			sram_we_o = 1'b1;

			case(tagged_cmd_i)
				CMD_ALLOCATE: begin		// allocating the place to a new mispredicted instruction in completely new location
					next_tag_o = new_tag_gated;
					// next_distance_o = true_distance_i_gated;		// no need of this as it is perfectly gated with "en_i"
					next_distance_o = true_distance_gated;
					next_confidence_o = WEAK_CONFIDENCE;
					next_useful_o = MIN_USEFUL;
				end

				CMD_REWARD: begin	
					// if correct prediction, then increment the confidence. Also, increment the LRU/USEFUL - of that particular way.
					// decrement the USEFUL of other unused ways inthat row but we can leave it here as it is and wait for DECAY action to decrement the USEFUL bits of a way.
					// If we decay the other 3 ways here and now, then we will have to update the encoder. 
					// ALSO, IT WILL INCREASE THE POWER USEAGE IN CIRCUIT.
					next_tag_o = current_tag_gated;
                    next_distance_o = current_distance_gated;
					next_confidence_o = (current_conf_gated == MAX_CONFIDENCE) ? MAX_CONFIDENCE : (current_conf_gated + 1'b1);
					next_useful_o = (current_useful_gated  == MAX_USEFUL)  ? MAX_USEFUL  : (current_useful_gated  + 1'b1);
				end

				CMD_PENALIZE: begin		// if wrong prediction, then reduce the confidence (by 1 or 2 or 3)
					
					next_tag_o = current_tag_gated;
                    next_useful_o = current_useful_gated;

					if (current_conf_i == MIN_CONFIDENCE) begin	 // Confidence is totally drained - overwrite the distance.
                        next_distance_o = true_distance_gated;
                        next_confidence_o  = WEAK_CONFIDENCE;			// new entry with a WEAK confidence. We cannot give full confidence to it.
                    end else begin
						next_distance_o   = current_distance_gated;
                        next_confidence_o = current_conf_gated - 1'b1;    /// I still have some confidence in this distance so no overwrite
                    end
				end

				CMD_DECAY: begin
					// we are not going to do DECAY here, because we have Single WAY decay in this logic , 
					// but for the case where we have to decay all the WAYS in a row, can;t be done as below one.
					// INstead we can move the decay calculation logic in the Tagged_predictor_sram block. BETTER
					// next_useful_o = (current_useful_i == ZERO_USEFUL) ? ZERO_USEFUL : (current_useful_i - 1'b1);

					// NOW, WE will simply pass the TAG, CONFIDENCE, USEFUL and DISTANCE bits. But they will not be used.
					// these are just for the sake of passing.
					next_confidence_o = current_conf_gated;
                    next_useful_o     = current_useful_gated; 
                    next_tag_o        = current_tag_gated;
                    next_distance_o   = current_distance_gated;
				end

				default: begin		// incase invlaid command comes in , simply disable the write to the SRAM
					sram_we_o = 1'b0;
				end
			endcase
		end

	end

endmodule