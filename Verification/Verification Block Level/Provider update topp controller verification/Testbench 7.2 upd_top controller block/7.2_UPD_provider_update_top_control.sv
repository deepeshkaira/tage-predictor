/// this block contains the control for the update tables of Base table (T0) and the tagged tables (T1 - T7)

module LP_provider_update_top_control#(
	parameter int NUM_TAGGED_TABLES = 7,
	parameter int PROVIDER_ID_WIDTH = $clog2(NUM_TAGGED_TABLES+1),
	parameter int BASE_S_WIDTH = 10,
	parameter int S_WIDTH = 7,
	parameter int T_WIDTH = 16
)(
	input logic clk,
	input logic rst_n,
	input logic commit_valid_i,
	input logic commit_mispredicted_i,
	input logic [PROVIDER_ID_WIDTH-1:0] provider_id_i,		// the table that gave prediction

	input logic [NUM_TAGGED_TABLES-1:0] current_LFSR_value_input,	// need to take LFSR as input to feed the block instantiated inside

	// input to tell which all tables have a particular address available for use for a new prediction.
	input logic [NUM_TAGGED_TABLES-1:0] table_empty_mask_i,

	// Incoming from Predictor State Buffer (PRB)
	input logic [BASE_S_WIDTH-1:0] commit_base_idx_i,		// base index
	input logic [S_WIDTH-1:0]  commit_tagged_indices_i [0:NUM_TAGGED_TABLES-1],			// tagged indices
	input logic [T_WIDTH-1:0]  commit_tagged_tags_i    [0:NUM_TAGGED_TABLES-1],			// tagged table tags

	//dedicated for BAST TABLE update
	output logic base_update_en_o,
	output logic [BASE_S_WIDTH-1:0] base_update_idx_o, // goes to base table and gives the index

	// for tagged tables
	output logic [NUM_TAGGED_TABLES-1:0] tagged_table_update_en_o,
	output logic [1:0] table_cmd_o [0:NUM_TAGGED_TABLES-1],

	// Outputs to the Tagged Table SRAM Wrappers
	output logic [S_WIDTH-1:0] update_tagged_indices_o [0:NUM_TAGGED_TABLES-1],
	output logic [T_WIDTH-1:0] update_tagged_tags_o    [0:NUM_TAGGED_TABLES-1]
);

	typedef enum logic [1:0] {
		CMD_ALLOCATE, CMD_REWARD, CMD_PENALIZE, CMD_DECAY
	} phast_cmd_t;

	// for registering the inputs to the block
    logic commit_valid_reg;
    logic commit_mispredicted_reg;
    logic [PROVIDER_ID_WIDTH-1:0] provider_id_reg;
    logic [NUM_TAGGED_TABLES-1:0] table_empty_mask_reg;
    logic [NUM_TAGGED_TABLES-1:0] current_LFSR_reg;
    logic [BASE_S_WIDTH-1:0] commit_base_idx_reg;       
    logic [S_WIDTH-1:0] commit_tagged_indices_reg [0:NUM_TAGGED_TABLES-1];        
    logic [T_WIDTH-1:0] commit_tagged_tags_reg [0:NUM_TAGGED_TABLES-1];  

	logic clk_gated_inputs;
	// logic clk_gated_outputs;

    // ICG for the input side og the block
    gated_clk u_icg_inputs (
        .clk_i (clk),
        .en_i (commit_valid_i),
        .clk_gated_o (clk_gated_inputs)
    );

	// ICG for the output data
    //  the reason why I have given the commit_valid_reg as input to the output ICG is that there will be a clock cycle delay in the 
    // calculation of the data and we would want to give some time to the blocks to run the logic inside.
    // IF WE DON'T DO THAT - the outputs will capture the data ONE CYCLE EARLY IN the design AND CAN GIVE ERRONEOUS DATA as OUTPUT
    // gated_clk u_icg_outputs (
    //     .clk_i       (clk),
    //     .en_i        (commit_valid_reg),
    //     .clk_gated_o (clk_gated_outputs)
    // );

    // normal clock required for registering the inputs to the block
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            commit_valid_reg <= 1'b0;
        end else begin
            commit_valid_reg <= commit_valid_i;
        end
    end

    // input registers for the design 
    always_ff @(posedge clk_gated_inputs or negedge rst_n) begin
		if (!rst_n) begin
            commit_mispredicted_reg <= '0;
            provider_id_reg <= '0;
            table_empty_mask_reg <= '0;
            current_LFSR_reg <= '0;
            commit_base_idx_reg <= '0;
            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
                commit_tagged_indices_reg[i] <= '0;
                commit_tagged_tags_reg[i] <= '0;
            end
		end else begin
			commit_mispredicted_reg <= commit_mispredicted_i;
			provider_id_reg <= provider_id_i;
			table_empty_mask_reg <= table_empty_mask_i;
			current_LFSR_reg <= current_LFSR_value_input;
			commit_base_idx_reg <= commit_base_idx_i;
			
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				commit_tagged_indices_reg[i] <= commit_tagged_indices_i[i];
				commit_tagged_tags_reg[i] <= commit_tagged_tags_i[i];
			end
		end
    end

	// internal routing
	logic [NUM_TAGGED_TABLES-1:0] eligible_allocation_mask;

	// eligibility mask
	always_comb
		begin
			eligible_allocation_mask = '0;

			if (commit_valid_reg && commit_mispredicted_reg) begin
				// Generate the Eligibility Vector. Sweep from T1 upto T7 and mark while one are eligiblie for change
				for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
					if ((i+1) > provider_id_reg) begin
						eligible_allocation_mask[i] = 1'b1;
					end
				end
			end
		end

	logic [NUM_TAGGED_TABLES-1:0] final_LFSR_target_mask;
	logic allocate_cmd_flag;
	logic provider_update_only_cmd_flag;
	logic [NUM_TAGGED_TABLES-1:0] available_eligible_mask;
	logic [NUM_TAGGED_TABLES-1:0] decay_target_mask;

	
	masking_unit_LFSR_or_NON_LFSR#(
		.NUM_TABLES(NUM_TAGGED_TABLES)
	) u_allocation_module (
		.en_i(commit_valid_reg & commit_mispredicted_reg),	// only active during mispredict evaluation
		.candidate_vector_i(table_empty_mask_reg),		// this is cming as input from  PHAST candidate generator block
		.eligibility_mask_i(eligible_allocation_mask),	// this has been generated few code lines back in here
		.LFSR_i(current_LFSR_reg),				// input from LFSR block

		// Outputs
		.final_candidate_mask_o(final_LFSR_target_mask),
		.allocate_cmd_o(allocate_cmd_flag),
		.provider_update_only_cmd_o(provider_update_only_cmd_flag)
	);


	// bit smearing for lower circuit requirement for priority encoder
	logic [NUM_TAGGED_TABLES-1:0] smear_1, smear_2, smear_4;
	logic [NUM_TAGGED_TABLES-1:0] isolated_allocation_target;

	assign smear_1 = final_LFSR_target_mask | (final_LFSR_target_mask >> 1);
	assign smear_2 = smear_1 | (smear_1 >> 2);
	assign smear_4 = smear_2 | (smear_2 >> 4);
	assign isolated_allocation_target = smear_4 & ~(smear_4 >> 1);

	/// to make sure that the  ABOVE "isolation_allocation_target" in never multihot signal
	assert property (@(posedge clk) disable iff (!rst_n) $onehot0(isolated_allocation_target));


	// for outputs - need to reg the outputs for the block
	logic next_base_update_en;
    logic [BASE_S_WIDTH-1:0] next_base_update_idx;
    logic [NUM_TAGGED_TABLES-1:0] next_tagged_table_update_en;
    logic [1:0] next_table_cmd [NUM_TAGGED_TABLES-1:0];
    logic [S_WIDTH-1:0] next_update_tagged_indices [0:NUM_TAGGED_TABLES-1];
    logic [T_WIDTH-1:0] next_update_tagged_tags [0:NUM_TAGGED_TABLES-1];

	// OUTPUT LOGIC Drive
	always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_update_en_o <= '0;
            tagged_table_update_en_o <= '0;
        end else begin
            base_update_en_o <= next_base_update_en;
            tagged_table_update_en_o <= next_tagged_table_update_en;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_update_idx_o <= '0;
            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
                table_cmd_o[i]             <= CMD_ALLOCATE;
                update_tagged_indices_o[i] <= '0;
                update_tagged_tags_o[i]    <= '0;
            end
        end else begin
            base_update_idx_o <= next_base_update_idx;
            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
                table_cmd_o[i]             <= next_table_cmd[i];
                update_tagged_indices_o[i] <= next_update_tagged_indices[i];
                update_tagged_tags_o[i]    <= next_update_tagged_tags[i];
            end
        end
    end


	assign available_eligible_mask = table_empty_mask_reg & eligible_allocation_mask;
	assign decay_target_mask = allocate_cmd_flag ? (final_LFSR_target_mask & ~isolated_allocation_target) : '0;

	// during the allocation, decay target must be a subset of the final LFSR selected candidate mask
	assert property (@(posedge clk)	disable iff (!rst_n) allocate_cmd_flag |-> ((decay_target_mask & ~final_LFSR_target_mask) == '0));

	/// the table selected for allocation must NEVER also recive decay in the same cycle
	assert property (@(posedge clk)	disable iff (!rst_n) allocate_cmd_flag |-> ((decay_target_mask & isolated_allocation_target) == '0));

	// A one-hot final LFSR mask requires allocation only, with no DECAY
	assert property (@(posedge clk) disable iff (!rst_n) (allocate_cmd_flag && $onehot(final_LFSR_target_mask)) |-> (decay_target_mask == '0));

	// Multiple final candidates produce one allocation ,,, DECAY for all remaining final candidates.
	assert property (@(posedge clk) disable iff (!rst_n) (allocate_cmd_flag && !$onehot(final_LFSR_target_mask)) |-> (decay_target_mask == (final_LFSR_target_mask & ~isolated_allocation_target)));

	
	always_comb
		begin
			
			// currently considering the commit for only LOAD instructions that were dependent on certain stores. 
			// because there can be commit for other instructions too  - not only LOAD.
			// base table updates for new commit only when it provides the correct prediction. If the provider is higher/Tagged table - then it is not going to happen
			next_base_update_en = commit_valid_reg && (provider_id_reg == '0);	
			next_base_update_idx = commit_base_idx_reg;
			next_tagged_table_update_en = '0;

			for(int i = 0; i < NUM_TAGGED_TABLES; i++)	/// kind of a reset situtaion to bring the "cmd_o" command to 00 for all the tables
				begin
					next_table_cmd[i] = CMD_ALLOCATE;  		// default for all tables at the start
					next_update_tagged_indices[i] = '0;                
            		next_update_tagged_tags[i] = '0;                  
				end

			/// THIS IS WHERE I KEEP AL THE FUNCTIOANLITY.
			
			if (commit_valid_reg) begin
		
				if (!commit_mispredicted_reg) begin	// CORRECT PREDICTION course of action
					
					if (provider_id_reg != '0) begin
						// if provider ID is not BASE TABLE, REWARD the PROVIDER
						next_tagged_table_update_en[provider_id_reg-1] = 1'b1;
						next_table_cmd[provider_id_reg-1] = CMD_REWARD;
						next_update_tagged_indices[provider_id_reg-1]  = commit_tagged_indices_reg[provider_id_reg-1];
						next_update_tagged_tags[provider_id_reg-1]  = commit_tagged_tags_reg[provider_id_reg-1];
					end
	
				end else begin
					// MISPREDICTION course of action
					// first peanlize the tagged table which provided the prediction
					if (provider_id_reg != '0) begin
						// PENALIZE the table with reduction in Confidence bits
						next_tagged_table_update_en[provider_id_reg-1] = 1'b1;
						next_table_cmd[provider_id_reg-1] = CMD_PENALIZE;
						next_update_tagged_indices[provider_id_reg-1] = commit_tagged_indices_reg[provider_id_reg-1];
						next_update_tagged_tags[provider_id_reg-1] = commit_tagged_tags_reg[provider_id_reg-1];
					end


					//// ADD AN ASSERTION HERE THAT  - provider_id_reg is always non-zero in here.

					/// Only update the provider and DECAY other tables
					if (provider_update_only_cmd_flag && !(allocate_cmd_flag)) begin

					//  DECAY all the Higher tables because our value for (candidate vector & eligibility_mask) was ZERO.

						for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
							if (eligible_allocation_mask[i]) begin
								next_tagged_table_update_en[i] = 1'b1;
								next_table_cmd[i] = CMD_DECAY;
								next_update_tagged_indices[i] = commit_tagged_indices_reg[i];
								next_update_tagged_tags[i] = commit_tagged_tags_reg[i];
							end
						end
					end


					else if(allocate_cmd_flag && !provider_update_only_cmd_flag) begin
						// THE ALLOCATION PATH: Low-Power One-Hot Cascade
						for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
							if (isolated_allocation_target[i]) begin
								next_tagged_table_update_en[i] = 1'b1;
								next_table_cmd[i] = CMD_ALLOCATE;
								next_update_tagged_indices[i] = commit_tagged_indices_reg[i];
								next_update_tagged_tags[i] = commit_tagged_tags_reg[i];   	
							end
							else if (decay_target_mask[i]) begin
								// Other available candidates receive decay.
								next_tagged_table_update_en[i] = 1'b1;
								next_table_cmd[i] = CMD_DECAY;
								next_update_tagged_indices[i] = commit_tagged_indices_reg[i];
								next_update_tagged_tags[i] = commit_tagged_tags_reg[i];
							end
						end
					end
				end
			end
		end

		// to check whether the provider id reg is not out of bounds
		assert property (@(posedge clk) disable iff (!rst_n) commit_valid_reg |-> (provider_id_reg <= NUM_TAGGED_TABLES));

		//mutual exclusion assertion
		assert property (@(posedge clk) disable iff (!rst_n) !(allocate_cmd_flag && provider_update_only_cmd_flag));
endmodule