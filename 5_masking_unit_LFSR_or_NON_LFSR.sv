// allocation masking unit
// this unit will be used to decide which table to go with for updation or for new entry in the prediction tables.
// this will simply give the allocation masking to the blocks. Nothing more than that
// updation or giveing a new entry will be handled in the provider block.

module masking_unit_LFSR_or_NON_LFSR#(
	parameter int NUM_TABLES = 7
)(
	input logic en_i,				/// commit mispredicted / commit valid
	input logic [NUM_TABLES-1:0] candidate_vector_i,
	input logic [NUM_TABLES-1:0] eligibility_mask_i,

	input logic [NUM_TABLES-1:0] LFSR_i,

	output logic [NUM_TABLES-1:0] final_candidate_mask_o,

	// so, technically we need 2 flags to explicitly mention what we want to do.
	// ALLOCATE_CMD_O = 1 <- Performing standard allocation  ||    0 <- Do nothing
	// PROVIDER_UPDATE_ONLY_CMD_O  = 1 <- we 
	output logic	allocate_cmd_o,      // 1 = perform standard allocation in different table, 0 = DO nothing
    output logic    provider_update_only_cmd_o      // 1 = ceiling hit - can be because of 2 reasons
													// a. Misprediction was from TABLE 7
													// b. The tables with History Depths greater than the Mispredicted tables don't have
													//	  a location to put in. Hence, we need to update current location only 
													//	  with heavy penalty to confidence bits. 

);

	localparam logic [NUM_TABLES-1:0] CEILING_MASK = (1 << (NUM_TABLES-1));

	/// operand isolation  								<<---- NO NEED OF OPERAND ISOLATION HERE because it will consue more power
	// wires for internal use

	logic [NUM_TABLES-1:0] base_candidates;
    logic [NUM_TABLES-1:0] LFSR_based_candidates;
    logic LFSR_killed_all;
	logic is_ceiling;
	
	assign is_ceiling = (eligibility_mask_i == CEILING_MASK);

	// getting temporary 7 bit vector which can be later ANDED with LFSR or not
	assign base_candidates = (candidate_vector_i & eligibility_mask_i);
	assign LFSR_based_candidates = (base_candidates & LFSR_i);	// with LFSR , candidate_vec and eligibility_mask
	assign LFSR_killed_all = ~(|LFSR_based_candidates);		// to  check if the LFSR generated values are ZEROED

	always_comb
	begin
		final_candidate_mask_o = '0;
		allocate_cmd_o = '0;
		provider_update_only_cmd_o = '0;

		if(en_i)  begin
			if(is_ceiling || (~(|base_candidates))) begin
				// update the highest configured table becuase no more tbales available with greater depths
				// T7 provided misprediction OR 
				// Some other Table (T0 - T6) provided the misprediction but there is NO AVAILABLE SPACE in the TABLES WITH GREATER DEPTHs
				// penalize the respective indexes of eligible tables with greater depths
				provider_update_only_cmd_o = 1'b1;
				// final_candidate_mask_o = CEILING_MASK;	// sedning this final candidate mask down incase update is being done to the  same tabe that provided the misprediction
				// it will remain ZERO as it is in the starting of the block
			end
			else begin
				// standard allocation - allocate misprediction to a table with greater history depth
				allocate_cmd_o = 1'b1;	// <- This 1 bit FLAG tells normal allocation

				if(LFSR_killed_all) begin
					final_candidate_mask_o = base_candidates;
				end else begin
					final_candidate_mask_o = LFSR_based_candidates;
				end
			end
		end
	end
endmodule
