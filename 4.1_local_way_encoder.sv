
//	Now once a table is selected. It is going to send a signal " selected"
//	and we can use that signal to enable the prioirity encoder (we can and it with the 
//	prioirty encoder's enable so that we have the power gating here as well)

module local_way_encoder(		// this is going to select the location where to exactly write on in the row

input logic en_i,				// valid branch commit or misprediction/squash (SRAM write enable from tagged update control block)
input logic [1:0] cmd_i,		// command for the course of action for the design

input logic [3:0] commit_empty_ways_i,	// will recieve an input that tells which of the ways are available
input logic [1:0] commit_hit_way_id_i,	// use this incase the provider tables needs to be updated

output logic [3:0] way_write_mask_o
); 

	// need to gate here so that DECAY is not triggered randomly
	logic [1:0] cmd_i_gated;
    logic [3:0] commit_empty_ways_gated;
    logic [1:0] commit_hit_way_id_gated;

	assign cmd_i_gated = en_i ? cmd_i : 2'b00; 
    assign commit_empty_ways_gated = en_i ? commit_empty_ways_i : 4'b0000;
    assign commit_hit_way_id_gated = en_i ? commit_hit_way_id_i : 2'b00;

	typedef enum logic [1:0] {
        CMD_ALLOCATE = 2'b00,
        CMD_REWARD   = 2'b01,
        CMD_PENALIZE = 2'b10,
        CMD_DECAY    = 2'b11
    } phast_cmd_t;

	phast_cmd_t command_wire;

	assign command_wire = phast_cmd_t'(cmd_i_gated);

	// smearing for LSB isolation (now in this the shifting is on the other direction)
	logic [3:0] smear_stage1;
    logic [3:0] smeared_vec;
    
    always_comb begin
        smear_stage1 = commit_empty_ways_gated | (commit_empty_ways_gated << 1);
        smeared_vec  = smear_stage1 | (smear_stage1 << 2);
    end

	always_comb begin
		way_write_mask_o = 4'b0000;

			case (command_wire)
				CMD_ALLOCATE: begin
					// if      (commit_empty_ways_i[0]) way_write_mask_o = 4'b0001;
					// else if (commit_empty_ways_i[1]) way_write_mask_o = 4'b0010;
					// else if (commit_empty_ways_i[2]) way_write_mask_o = 4'b0100;
					// else if (commit_empty_ways_i[3]) way_write_mask_o = 4'b1000;

					// we can write the above one as follows - for better hardware mapping
					way_write_mask_o = smeared_vec & ~(smeared_vec << 1);
				end

				CMD_REWARD,
				CMD_PENALIZE: begin
					way_write_mask_o = 4'b0001 << commit_hit_way_id_gated;		// shift the signal by 1 bit as per the commit hit id coming for current instruction from ROB/PRB
				end

				CMD_DECAY: begin		// Need to decay entire row beacuse none of the locations were useful
					way_write_mask_o = 4'b1111; 
				end
				
				default: way_write_mask_o = 4'b0000;
			endcase
		end

endmodule