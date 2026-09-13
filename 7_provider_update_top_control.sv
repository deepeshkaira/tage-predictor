/// this block contains the control for the update tables of Base table (T0) and the tagged tables (T1 - T7)

module provider_update_top_control#(
	parameter int NUM_TAGGED_TABLES = 7,
	parameter int PROVIDER_ID_WIDTH = $clog2(NUM_TAGGED_TABLES+1)
)(
	input logic commit_valid_i,
	input logic commit_mispredicted_i,
	input logic [PROVIDER_ID_WIDTH-1:0] provider_id_i,		// the table that gave prediction

	input logic [NUM_TAGGED_TABLES-1:0] current_LFSR_value_input,	// need to take LFSR as input to feed the block instantiated inside

	// input to tell which all tables have a particular address available for use for a new prediction.
	input logic [NUM_TAGGED_TABLES-1:0] table_empty_mask_i,

	//dedicated for BAST TABLE update
	output logic base_update_en_o,

	// for tagged tables
	output logic [NUM_TAGGED_TABLES-1:0] tagged_table_update_en_o,
	output logic [1:0] table_cmd_o [NUM_TAGGED_TABLES-1:0]
);

	// simple enums to explicity tell what mode is going out fr the tagged tables
	localparam logic [1:0] CMD_ALLOCATE = 2'b00;
	localparam logic [1:0] CMD_REWARD   = 2'b01;
	localparam logic [1:0] CMD_PENALIZE = 2'b10;
	localparam logic [1:0] CMD_DECAY    = 2'b11;


	// operand isolation
	logic commit_mispredicted_gated;
    logic [PROVIDER_ID_WIDTH-1:0] provider_id_gated;
    logic [NUM_TAGGED_TABLES-1:0] table_empty_mask_gated;
    logic [NUM_TAGGED_TABLES-1:0] current_LFSR_gated;

	assign commit_mispredicted_gated = commit_valid_i ? commit_mispredicted_i : 1'b0;
    assign provider_id_gated = commit_valid_i ? provider_id_i : '0;
    assign table_empty_mask_gated = commit_valid_i ? table_empty_mask_i : '0;
    assign current_LFSR_gated = commit_valid_i ? current_LFSR_value_input : '0;

	// internal rotuing
	logic [NUM_TAGGED_TABLES-1:0] eligible_allocation_mask;
	// logic [NUM_TAGGED_TABLES-1:0] target_allocation_mask;
	// logic allocation_failed;

	// eligibility mask
	always_comb
		begin

			eligible_allocation_mask = '0;

			// Generate the Eligibility Vector. Sweep from T1 upto T7 and mark while one are eligiblie for change
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				if (i > provider_id_i) begin
					eligible_allocation_mask[i] = 1'b1;
				end
			end
		end

	// NOW , we use our "masking_unit_LFSR_or_NON_LFSR" to generate the final LFSR target mask and enable command to decide if it is PROVIDER UPDATE or ALLOCATION UPDATE
	logic [NUM_TAGGED_TABLES-1:0] final_lfsr_target_mask;
	logic allocate_cmd_flag;
	logic provider_update_only_cmd_flag;

	masking_unit_LFSR_or_NON_LFSR#(
		.NUM_TABLES(NUM_TAGGED_TABLES)
	)u_allocation_module(
		.en_i(commit_valid_i & commit_mispredicted_gated),	// only active during mispredict evaluation
		.candidate_vector_i(table_empty_mask_gated),	// this is cming as input from  PHAST candidate generator block
		.eligibility_mask_i(eligible_allocation_mask),	// this has been generated few code lines back in here
		.LFSR_i(current_LFSR_gated),		// input from LFSR block

		// Outputs
		.final_candidate_mask_o(final_lfsr_target_mask),
		.allocate_cmd_o(allocate_cmd_flag),
		.provider_update_only_cmd_o(provider_update_only_cmd_flag)
	)

	always_comb
		begin
			
			// currently considering the commit for only LOAD instructions that were dependent on certain stores. 
			// because there can be commit for other instructions too  - not only LOAD.
			base_update_en_o = commit_valid_i;	// base table updates for every new commit in the LOAD INSTRUCTIONS. Default state can also be maintained like this
			
			tagged_table_update_en_o = '0;
			for(int i = 0; i < NUM_TAGGED_TABLES; i++)	/// kind of a reset situtaion to bring the "cmd_o" command to 00 for all the tables
				begin
					table_cmd_o[i] = CMD_ALLOCATE;		// default for all tables at the start
				end

			/// *******************  ///
			/// THIS IS WHERE I KEEP AL THE FUNCTIOANLITY.
			/// Things above are just put to avoid the LATCH - there is a default state for each OUTPUT and INTERNAL WIRES

			if (commit_valid_i) begin
		
				if (!commit_mispredicted_i) begin	// CORRECT PREDICTION course of action
					
					if (provider_id_i != '0) begin
						// if provider ID is not BASE TABLE, REWARD the PROVIDER WITH Confidence bits increment n LRU incremnt
						tagged_table_update_en_o[provider_id_i-1] = 1'b1;
						table_cmd_o[provider_id_i-1]       = CMD_REWARD;
					end
	
				end else begin
					// MISPREDICTION course of action
					// 1. peanalize the provider table
					// 2. generate an eligibility mask here - later to be used for ANDing with Candidate vector and LFSR.
					// 3. check if there are any tables after ANDing the Table empty mask and Eligiblty_mask
					// 4. Check if the allocation is failed becuase of - (eligible_mask && table_empty_mask)
					// That means 2 conditions ->
					// ONE is that provider table is T7 and we dont have tables with depth greater than T7
					// TWO is that there are no tables with empty spaces available
					// 5. That means we need to decay the CONFIDENCE BITS and LRU BITS in provider table only.

					if (provider_id_i != '0) begin
						// if provider ID is not BASE TABLE, then PENALIZE the table with reduction in Confidence bits
						// and if LRU == 0, overwrite the predicted distance. THough that functionality is covered well in provider update pipeline block
						tagged_table_update_en_o[provider_id_i-1] = 1'b1;
						table_cmd_o[provider_id_i-1] = CMD_PENALIZE;	// this will take care of replacing distance or reducing confidence value
					end
	

					if (provider_update_only_cmd_flag && !(allocate_cmd_flag)) begin
						// DECAY all eligible tables because either ceiling hit 
						for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
							if (eligible_allocation_mask[i]) begin
								tagged_table_update_en_o[i] = 1'b1;
								table_cmd_o[i]       = CMD_DECAY;
							end
						end
					end else if(allocate_cmd_flag && !(provider_update_only_cmd_flag)) begin
						// THE ALLOCATION PATH: Priority Encoder Cascade
						for (int i = NUM_TAGGED_TABLES-1; i >= 0; i--) begin
							if (final_lfsr_target_mask[i]) begin
								tagged_table_update_en_o[i] = 1'b1;
								table_cmd_o[i]       = CMD_ALLOCATE;
								break;		// used this so that the loop execution stops as soon as first time this if block executes.
							end
						end
					end
				end
			end
			end

endmodule
