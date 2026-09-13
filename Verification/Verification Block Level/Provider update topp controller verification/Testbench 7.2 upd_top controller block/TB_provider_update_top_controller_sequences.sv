`include "TB_provider_update_top_controller_components.sv"

import uvm_pkg::*;
import provider_update_params_pkg::*;

/// base sequence
class provider_update_base_sequence extends uvm_sequence #(provider_update_seq_item);

	`uvm_object_utils(provider_update_base_sequence)

	function new(string name = "provider_update_base_sequence");
		super.new(name);
	endfunction

	virtual task body();
		`uvm_info("BASE_SEQ","Starting provider update base sequence",UVM_MEDIUM)
	endtask

	virtual task send_idle();
		provider_update_seq_item req;
		req = provider_update_seq_item::type_id::create("idle_req");
		start_item(req);
		req.clear_inputs();
		finish_item(req);
	endtask

	// Three tasks to define the design 
	// 1. idle cycles
	// 2. some configured request
	// 3. some randomized valid case

	// sending multiple IDLE cycles
	virtual task send_idle_cycles(int unsigned number_of_cycles);
		for (int i = 0; i < number_of_cycles; i++) begin
			send_idle();
		end
	endtask

	/// sending a some structuraly configured request 
	virtual task send_configured_request(provider_update_seq_item req);
		if (req == null) begin
			`uvm_fatal("NULL_REQ","send_configured_request received a null request")
		end
		start_item(req);
		finish_item(req);
	endtask

	//// creating and sending a fully randomize valid commit request
	virtual task send_random_valid_commit();
		provider_update_seq_item req;
		req = provider_update_seq_item::type_id::create("random_valid_req");
		start_item(req);
		if (!req.randomize() with {commit_valid_i == 1'b1;}) begin
			`uvm_fatal("RANDOMIZE_FAILED","Failed to randomize a valid provider update request")
		end
		finish_item(req);
	endtask

endclass

///  basic smoke sequence
class provider_update_base_table_smoke_correct_prediction_sequence extends provider_update_base_sequence;

`uvm_object_utils(provider_update_base_table_smoke_correct_prediction_sequence)

function new(string name = "provider_update_base_table_smoke_correct_prediction_sequence");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;
	// Four different base-table indices.
	base_index_t prediction_indices [0:3];
	bit unique_index;

	`uvm_info("BASE_CORRECT_SEQ","Starting base-table correct-prediction sequence",UVM_LOW)

	// fixed index for fixed commit (correct prediction)
	prediction_indices[0] = base_index_t'(10'h155);

	// randomize indices for other commits
	for (int prediction_number = 1; prediction_number < 4; prediction_number++) begin
		do begin
			unique_index = 1'b1;
			prediction_indices[prediction_number] = base_index_t'($urandom());
			for (int previous_prediction = 0; previous_prediction < prediction_number; previous_prediction++) begin
				if (prediction_indices[prediction_number] == prediction_indices[previous_prediction]) begin
					unique_index = 1'b0;
				end
			end
		end
		while (!unique_index);
	end

	/// correct commits for the design
	for (int prediction_number = 0; prediction_number < 4; prediction_number++) begin
		req = provider_update_seq_item::type_id::create($sformatf("base_correct_req_%0d",prediction_number));
		start_item(req);
		req.clear_inputs();
		req.commit_valid_i        = 1'b1;
		req.commit_mispredicted_i = 1'b0;
		req.provider_id_i         = BASE_PROVIDER_ID;
		req.commit_base_idx_i = prediction_indices[prediction_number];
		finish_item(req);

		`uvm_info("BASE_CORRECT_SEQ",
			$sformatf(
				{
					"Sent base-table prediction %0d of 4: ",
					"provider_id=%0d base_idx=0x%0h"
				},
				prediction_number + 1,
				req.provider_id_i,
				req.commit_base_idx_i
			),
			UVM_LOW
		)

		// sending three idle cycles after every prediction.
		send_idle_cycles(3);

		`uvm_info("BASE_CORRECT_SEQ",
			$sformatf(
				{
					"Completed three idle cycles after prediction %0d; ",
					"expected held base index=0x%0h"
				},
				prediction_number + 1,
				prediction_indices[prediction_number]
			),
			UVM_LOW
		)
	end
	`uvm_info(
		"BASE_CORRECT_SEQ",
		"Completed four base-table correct-prediction repetitions",
		UVM_LOW
	)
endtask
endclass

//// 
class provider_update_tagged_tables_correct_prediction_smoke_sequence extends provider_update_base_sequence;

`uvm_object_utils(provider_update_tagged_tables_correct_prediction_smoke_sequence)

function new(string name = "provider_update_tagged_tables_correct_prediction_smoke_sequence");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;
	// Randomized order of providers T1 through T7.
	provider_id_t provider_order [0:NUM_TAGGED_TABLES-1];
	provider_id_t temporary_provider;
	int selected_table_index;
	int random_position;
	int idle_gap;

	`uvm_info("TAGGED_CORRECT_SEQ","Starting tagged-table correct-prediction sequence",UVM_LOW)

	// initilizing the provider order as T1,T2,....T7
	for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
		provider_order[i] = provider_id_t'(i + 1);
	end

	/// MAKING sure that each table appears exactly once. Some algorithm from CHatgpt
	for (int i = NUM_TAGGED_TABLES - 1; i > 0; i--) begin
		random_position = $urandom_range(i, 0);
		temporary_provider          = provider_order[i];
		provider_order[i]           = provider_order[random_position];
		provider_order[random_position] = temporary_provider;
	end

	// Send correct prediction for every tagged provider
	for (int selection_number = 0; selection_number < NUM_TAGGED_TABLES; selection_number++) begin
		selected_table_index = int'(provider_order[selection_number]) - 1;
		req = provider_update_seq_item::type_id::create($sformatf("tagged_correct_T%0d_req", provider_order[selection_number]));
		start_item(req);
		
		// Clear unrelated fields
		req.clear_inputs();
		req.commit_valid_i        = 1'b1;
		req.commit_mispredicted_i = 1'b0;
		req.provider_id_i = provider_order[selection_number];
		// Base table not updated on every valid commit
		req.commit_base_idx_i = '0;
		// Meaningful input for selected tagged table only
		req.commit_tagged_indices_i[selected_table_index] = tagged_index_t'($urandom());
		req.commit_tagged_tags_i[selected_table_index] = tagged_tag_t'($urandom());
		finish_item(req);

		`uvm_info(
			"TAGGED_CORRECT_SEQ",
			$sformatf(
				{
					"Sent correct prediction %0d of %0d: ",
					"provider=T%0d base_idx=0x%0h ",
					"tagged_idx=0x%0h tagged_tag=0x%0h"
				},
				selection_number + 1,
				NUM_TAGGED_TABLES,
				req.provider_id_i,
				req.commit_base_idx_i,
				req.commit_tagged_indices_i[selected_table_index],
				req.commit_tagged_tags_i[selected_table_index]
			),
			UVM_LOW
		)

		// 2-3 random idle cycles gap
		idle_gap = $urandom_range(3, 2);
		send_idle_cycles(idle_gap);

		`uvm_info(
			"TAGGED_CORRECT_SEQ",
			$sformatf(
				{
					"Completed %0d idle cycles after provider T%0d"
				},
				idle_gap,
				req.provider_id_i
			),
			UVM_LOW
		)
	end
	`uvm_info(
		"TAGGED_CORRECT_SEQ",
		"Completed tagged-table correct-prediction sequence; T1-T7 covered",
		UVM_LOW
	)
endtask
endclass

/// idle clock gating sequence
class provider_update_idle_clock_gating_sequence extends provider_update_base_sequence;

`uvm_object_utils(provider_update_idle_clock_gating_sequence)

function new(string name = "provider_update_idle_clock_gating_sequence");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;

	`uvm_info(
		"IDLE_GATING_SEQ",
		"Starting ten-cycle idle and clock-gating sequence",
		UVM_LOW
	)

	// Keep valid low, toggle others to verify gating
	for (int idle_cycle = 0; idle_cycle < 10; idle_cycle++) begin
		req = provider_update_seq_item::type_id::create($sformatf("idle_gating_req_%0d", idle_cycle));
		start_item(req);
		req.clear_inputs();

		// Transaction remains invalid
		req.commit_valid_i = 1'b0;
		// Toggle misprediction on invalid request
		req.commit_mispredicted_i = idle_cycle % 2;
		// Cycle T0 to T7
		req.provider_id_i = provider_id_t'(idle_cycle % NUM_PROVIDERS);
		// Rotate LFSR
		req.current_LFSR_value_input = tagged_table_mask_t'(1 << (idle_cycle % NUM_TAGGED_TABLES));
		// Change candidate mask per cycle
		req.table_empty_mask_i = tagged_table_mask_t'(~(1 << (idle_cycle % NUM_TAGGED_TABLES)));
		// Change base index per cycle
		req.commit_base_idx_i = base_index_t'(10'h080 + (idle_cycle * 10'h031));
		
		// Change all tagged indices and tags
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			req.commit_tagged_indices_i[i] = tagged_index_t'((idle_cycle * NUM_TAGGED_TABLES) + i + 1);
			req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hA000 + (idle_cycle * 16'h0010) + i);
		end
		finish_item(req);

		`uvm_info(
			"IDLE_GATING_SEQ",
			$sformatf(
				{
					"Sent idle cycle %0d of 10: ",
					"valid=%0b mispredicted=%0b provider=%0d ",
					"LFSR=0b%0b candidate_mask=0b%0b ",
					"base_idx=0x%0h"
				},
				idle_cycle + 1,
				req.commit_valid_i,
				req.commit_mispredicted_i,
				req.provider_id_i,
				req.current_LFSR_value_input,
				req.table_empty_mask_i,
				req.commit_base_idx_i
			),
			UVM_LOW
		)
	end
	`uvm_info(
		"IDLE_GATING_SEQ",
		"Completed ten-cycle idle and clock-gating sequence",
		UVM_LOW
	)
endtask
endclass

/// base misprediction but no allocation
class provider_update_base_misprediction_no_allocation_sequence extends provider_update_base_sequence;

`uvm_object_utils(provider_update_base_misprediction_no_allocation_sequence)

function new(string name = "provider_update_base_misprediction_no_allocation_sequence");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;
	int idle_gap;

	`uvm_info(
		"BASE_MISPRED_NO_ALLOC_SEQ",
		{
			"Starting base-table misprediction sequence ",
			"with no tagged-table allocation"
		},
		UVM_LOW
	)

	// Send 4 base mispredictions
	for (int transaction_number = 0; transaction_number < 4; transaction_number++) begin
		req = provider_update_seq_item::type_id::create($sformatf("base_mispredict_no_alloc_req_%0d", transaction_number));
		start_item(req);
		req.clear_inputs();
		
		// Valid committed prediction
		req.commit_valid_i = 1'b1;
		// Incorrect prediction
		req.commit_mispredicted_i = 1'b1;
		// Base table provider
		req.provider_id_i = BASE_PROVIDER_ID;
		// No vacant positions; expect DECAY
		req.table_empty_mask_i = '0;
		// Vary LFSR (ignored when mask is 0)
		req.current_LFSR_value_input = tagged_table_mask_t'(1 << (transaction_number % NUM_TAGGED_TABLES));
		// Different base index per transaction
		req.commit_base_idx_i = base_index_t'(10'h100 + (transaction_number * 10'h055));
		
		// Valid index/tag for DECAY
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			req.commit_tagged_indices_i[i] = tagged_index_t'((transaction_number * NUM_TAGGED_TABLES) + i + 1);
			req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hC000 + (transaction_number * 16'h0100) + i);
		end
		finish_item(req);

		`uvm_info(
			"BASE_MISPRED_NO_ALLOC_SEQ",
			$sformatf(
				{
					"Sent transaction %0d of 4: ",
					"valid=%0b mispredicted=%0b provider=T%0d ",
					"base_idx=0x%0h candidate_mask=0b%0b ",
					"LFSR=0b%0b"
				},
				transaction_number + 1,
				req.commit_valid_i,
				req.commit_mispredicted_i,
				req.provider_id_i,
				req.commit_base_idx_i,
				req.table_empty_mask_i,
				req.current_LFSR_value_input
			),
			UVM_LOW
		)

		// 2-3 random idle cycles gap
		idle_gap = $urandom_range(3, 2);
		send_idle_cycles(idle_gap);

		`uvm_info(
			"BASE_MISPRED_NO_ALLOC_SEQ",
			$sformatf(
				"Completed %0d idle cycles after transaction %0d",
				idle_gap,
				transaction_number + 1
			),
			UVM_LOW
		)
	end
	`uvm_info(
		"BASE_MISPRED_NO_ALLOC_SEQ",
		{
			"Completed base-table misprediction sequence ",
			"with no tagged-table allocation"
		},
		UVM_LOW
	)
endtask
endclass

/// tagged table (T0) with the misprediction and no vacant place in the respective indexes. 
// Hence, PENALIZE the table (T0)
class provider_update_T0_mispredictiton_no_allocation_sequence_with_idle_cycle extends provider_update_base_sequence;

`uvm_object_utils(provider_update_T0_mispredictiton_no_allocation_sequence_with_idle_cycle)

function new(string name = "provider_update_T0_mispredictiton_no_allocation_sequence_with_idle_cycle");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;
	int idle_gap;

	`uvm_info(
		"T0_MISPRED_NO_ALLOC_SEQ",
		{
			"Starting tagged-table T0 misprediction sequence ",
			"with no higher-table allocation"
		},
		UVM_LOW
	)

	// Send 4 T0 mispredictions
	for (int transaction_number = 0; transaction_number < 4; transaction_number++) begin
		req = provider_update_seq_item::type_id::create($sformatf("T0_mispredict_no_alloc_req_%0d", transaction_number));
		start_item(req);
		req.clear_inputs();
		
		// Valid commit
		req.commit_valid_i = 1'b1;
		// Misprediction
		req.commit_mispredicted_i = 1'b1;
		// T0 is the provider
		req.provider_id_i = provider_id_t'(BASE_PROVIDER_ID + 1);
		// No allocation; expect T0 PENALIZE, higher tables DECAY
		req.table_empty_mask_i = '0;
		// LFSR ignored
		req.current_LFSR_value_input = tagged_table_mask_t'(1 << (transaction_number % NUM_TAGGED_TABLES));
		// Valid base index
		req.commit_base_idx_i = base_index_t'(10'h180 + (transaction_number * 10'h055));
		
		// Valid data for PENALIZE and DECAY
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
			req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hA100 + (transaction_number * 16'h0100) + i + 1);
		end

		// Ensure T0 valid data
		if ((req.commit_tagged_indices_i[0] == '0) || (req.commit_tagged_tags_i[0] == '0)) begin
			`uvm_fatal(
				"T0_MISPRED_NO_ALLOC_SEQ",
				{
					"Tagged table T0 must have a nonzero ",
					"index and tag"
				}
			)
		end
		finish_item(req);

		`uvm_info(
			"T0_MISPRED_NO_ALLOC_SEQ",
			$sformatf(
				{
					"Sent transaction %0d of 4: ",
					"valid=%0b mispredicted=%0b ",
					"provider=tagged-T0 provider_id=%0d ",
					"T0_idx=0x%0h T0_tag=0x%0h ",
					"base_idx=0x%0h candidate_mask=0b%0b ",
					"LFSR=0b%0b"
				},
				transaction_number + 1,
				req.commit_valid_i,
				req.commit_mispredicted_i,
				req.provider_id_i,
				req.commit_tagged_indices_i[0],
				req.commit_tagged_tags_i[0],
				req.commit_base_idx_i,
				req.table_empty_mask_i,
				req.current_LFSR_value_input
			),
			UVM_LOW
		)

		// 2-3 idle gap
		idle_gap = $urandom_range(3, 2);
		send_idle_cycles(idle_gap);

		`uvm_info(
			"T0_MISPRED_NO_ALLOC_SEQ",
			$sformatf(
				"Completed %0d idle cycles after transaction %0d",
				idle_gap,
				transaction_number + 1
			),
			UVM_LOW
		)
	end
	`uvm_info(
		"T0_MISPRED_NO_ALLOC_SEQ",
		{
			"Completed tagged-table T0 misprediction sequence ",
			"with no higher-table allocation"
		},
		UVM_LOW
	)
endtask
endclass

///// T0 misprediction no allocation with NO IDLE CYCLE REST in between
class provider_update_T0_mispredictiton_no_allocation_no_idle_cycle_in_middle_sequence extends provider_update_base_sequence;

`uvm_object_utils(provider_update_T0_mispredictiton_no_allocation_no_idle_cycle_in_middle_sequence)

function new(string name = "provider_update_T0_mispredictiton_no_allocation_no_idle_cycle_in_middle_sequence");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;

	`uvm_info(
		"T0_MISPRED_NO_ALLOC_NO_IDLE_SEQ",
		{
			"Starting back-to-back tagged-table T0 misprediction ",
			"sequence with no allocation"
		},
		UVM_LOW
	)

	// Send 4 back-to-back T0 mispredictions
	for (int transaction_number = 0; transaction_number < 4; transaction_number++) begin
		req = provider_update_seq_item::type_id::create($sformatf("T0_mispredict_no_alloc_no_idle_req_%0d", transaction_number));
		start_item(req);
		req.clear_inputs();
		
		// Valid commit
		req.commit_valid_i = 1'b1;
		// Misprediction
		req.commit_mispredicted_i = 1'b1;
		// T0 is provider
		req.provider_id_i = provider_id_t'(BASE_PROVIDER_ID + 1);
		// No allocation
		req.table_empty_mask_i = '0;

		// Vary LFSR
		case (transaction_number)
			0: req.current_LFSR_value_input = tagged_table_mask_t'('0);
			1: req.current_LFSR_value_input = tagged_table_mask_t'('1);
			2: req.current_LFSR_value_input = tagged_table_mask_t'('h55);
			default: req.current_LFSR_value_input = tagged_table_mask_t'(1 << (NUM_TAGGED_TABLES - 1));
		endcase

		// Valid base index
		req.commit_base_idx_i = base_index_t'(10'h100 + (transaction_number * 10'h080));
		
		// Valid indices/tags
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
			req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hB100 + (transaction_number * 16'h0100) + i);
		end

		// Boundary values for T0
		case (transaction_number)
			0: begin
				req.commit_tagged_indices_i[0] = tagged_index_t'(1);
				req.commit_tagged_tags_i[0] = tagged_tag_t'(1);
			end
			1: begin
				req.commit_tagged_indices_i[0] = tagged_index_t'('1);
				req.commit_tagged_tags_i[0] = tagged_tag_t'('1);
			end
			2: begin
				req.commit_tagged_indices_i[0] = tagged_index_t'('h55);
				req.commit_tagged_tags_i[0] = tagged_tag_t'('hAAAA);
			end
			default: begin
				req.commit_tagged_indices_i[0] = tagged_index_t'(1 << (S_WIDTH - 1));
				req.commit_tagged_tags_i[0] = tagged_tag_t'(1 << (T_WIDTH - 1));
			end
		endcase

		// Check T0 validity
		if ((req.commit_tagged_indices_i[0] == '0) || (req.commit_tagged_tags_i[0] == '0)) begin
			`uvm_fatal(
				"T0_MISPRED_NO_ALLOC_NO_IDLE_SEQ",
				{
					"Tagged table T0 must have a valid nonzero ",
					"index and tag"
				}
			)
		end
		finish_item(req);

		`uvm_info(
			"T0_MISPRED_NO_ALLOC_NO_IDLE_SEQ",
			$sformatf(
				{
					"Sent back-to-back transaction %0d of 4: ",
					"valid=%0b mispredicted=%0b ",
					"provider=tagged-T0 provider_id=%0d ",
					"T0_idx=0x%0h T0_tag=0x%0h ",
					"candidate_mask=0b%0b LFSR=0b%0b"
				},
				transaction_number + 1,
				req.commit_valid_i,
				req.commit_mispredicted_i,
				req.provider_id_i,
				req.commit_tagged_indices_i[0],
				req.commit_tagged_tags_i[0],
				req.table_empty_mask_i,
				req.current_LFSR_value_input
			),
			UVM_LOW
		)
	end
	`uvm_info(
		"T0_MISPRED_NO_ALLOC_NO_IDLE_SEQ",
		{
			"Completed back-to-back tagged-table T0 misprediction ",
			"sequence with no allocation"
		},
		UVM_LOW
	)
endtask
endclass

//// misprediction from Tagged table (T2) - Tagged table (T6). Keeoping T7 out of the opicture now
// No allocation happedning in this as well. Only penalize the provider
class provider_update_random_middle_tagged_misprediction_no_allocation_sequence extends provider_update_base_sequence;

`uvm_object_utils(provider_update_random_middle_tagged_misprediction_no_allocation_sequence)
localparam int NUM_TRANSACTIONS = 13;

function new(string name = "provider_update_random_middle_tagged_misprediction_no_allocation_sequence");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;
	int idle_gap;
	int tagged_provider_index;
	int provider_table_order[$];
	int shuffled_middle_tables[$];
	int provider_hit_count[NUM_TAGGED_TABLES];

	`uvm_info(
		"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
		{
			"Starting random middle-tagged-table misprediction ",
			"sequence with no allocation"
		},
		UVM_LOW
	)

	// Require >= 3 tagged tables
	if (NUM_TAGGED_TABLES < 3) begin
		`uvm_fatal("RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ","At least three tagged tables are required")
	end
	
	// Ensure enough transactions
	if ((2 * (NUM_TAGGED_TABLES - 2)) > NUM_TRANSACTIONS) begin
		`uvm_fatal(
			"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
			$sformatf(
				{
					"%0d transactions are insufficient to cover all ",
					"%0d middle tagged tables twice"
				},
				NUM_TRANSACTIONS,
				NUM_TAGGED_TABLES - 2
			)
		)
	end

	// Init counters
	for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
		provider_hit_count[i] = 0;
	end

	// Create 2 shuffled passes
	for (int coverage_pass = 0; coverage_pass < 2; coverage_pass++) begin
		shuffled_middle_tables.delete();
		for (int table_index = 1; table_index < (NUM_TAGGED_TABLES - 1); table_index++) begin
			shuffled_middle_tables.push_back(table_index);
		end
		shuffled_middle_tables.shuffle();
		foreach (shuffled_middle_tables[i]) begin
			provider_table_order.push_back(shuffled_middle_tables[i]);
		end
	end

	// Fill rest
	while (provider_table_order.size() < NUM_TRANSACTIONS) begin
		provider_table_order.push_back($urandom_range(NUM_TAGGED_TABLES - 2, 1));
	end
	provider_table_order.shuffle();

	// Send 13 transactions
	for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
		tagged_provider_index = provider_table_order[transaction_number];
		req = provider_update_seq_item::type_id::create($sformatf("random_middle_mispredict_no_alloc_req_%0d", transaction_number));
		start_item(req);
		req.clear_inputs();
		
		// Valid commit
		req.commit_valid_i = 1'b1;
		// Misprediction
		req.commit_mispredicted_i = 1'b1;
		// Select middle provider
		req.provider_id_i = provider_id_t'(BASE_PROVIDER_ID + tagged_provider_index + 1);
		// No allocation
		req.table_empty_mask_i = '0;
		// Random LFSR
		req.current_LFSR_value_input = tagged_table_mask_t'($urandom());
		// Valid base index
		req.commit_base_idx_i = base_index_t'(10'h200 + (transaction_number * 10'h021));

		// Valid indices/tags
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			req.commit_tagged_indices_i[i] = tagged_index_t'((transaction_number * NUM_TAGGED_TABLES) + i + 1);
			req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hC100 + (transaction_number * 16'h0100) + i + 1);
		end

		// Ensure provider valid
		if ((req.commit_tagged_indices_i[tagged_provider_index] == '0) || (req.commit_tagged_tags_i[tagged_provider_index] == '0)) begin
			`uvm_fatal(
				"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
				$sformatf(
					{
						"Tagged table T%0d has an invalid zero ",
						"index or tag"
					},
					tagged_provider_index
				)
			)
		end
		finish_item(req);
		
		// Record hit
		provider_hit_count[tagged_provider_index]++;

		`uvm_info(
			"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
			$sformatf(
				{
					"Sent transaction %0d of %0d: ",
					"provider=T%0d provider_id=%0d ",
					"provider_idx=0x%0h provider_tag=0x%0h ",
					"candidate_mask=0b%0b LFSR=0b%0b"
				},
				transaction_number + 1,
				NUM_TRANSACTIONS,
				tagged_provider_index,
				req.provider_id_i,
				req.commit_tagged_indices_i[tagged_provider_index],
				req.commit_tagged_tags_i[tagged_provider_index],
				req.table_empty_mask_i,
				req.current_LFSR_value_input
			),
			UVM_LOW
		)

		// 1-4 random idle gap
		if (transaction_number < (NUM_TRANSACTIONS - 1)) begin
			idle_gap = $urandom_range(4, 1);
			send_idle_cycles(idle_gap);
			`uvm_info(
				"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
				$sformatf(
					{
						"Completed %0d idle cycles after ",
						"transaction %0d"
					},
					idle_gap,
					transaction_number + 1
				),
				UVM_LOW
			)
		end
	end

	// Verify all middle tables hit >= 2 times
	for (int table_index = 1; table_index < (NUM_TAGGED_TABLES - 1); table_index++) begin
		if (provider_hit_count[table_index] < 2) begin
			`uvm_fatal(
				"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
				$sformatf(
					{
						"Coverage failure: tagged table T%0d was ",
						"selected only %0d time(s)"
					},
					table_index,
					provider_hit_count[table_index]
				)
			)
		end
		else begin
			`uvm_info(
				"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
				$sformatf(
					"Tagged table T%0d was selected %0d time(s)",
					table_index,
					provider_hit_count[table_index]
				),
				UVM_LOW
			)
		end
	end
	`uvm_info(
		"RANDOM_MIDDLE_MISPRED_NO_ALLOC_SEQ",
		{
			"Completed thirteen random middle-tagged-table ",
			"mispredictions with no allocation"
		},
		UVM_LOW
	)
endtask
endclass

////////// misprediction from Tagged table (T2) - Tagged table (T6). Keeoping T7 out of the opicture now
// No allocation happedning in this as well. Only penalize the provider. NO-IDLE CYCLES IN MIDDLE
class provider_update_random_middle_tagged_misprediction_no_allocation_no_idle_CYCLES_in_middle_sequence extends provider_update_base_sequence;

`uvm_object_utils(provider_update_random_middle_tagged_misprediction_no_allocation_no_idle_CYCLES_in_middle_sequence)
localparam int NUM_TRANSACTIONS = 13;

function new(string name = "provider_update_random_middle_tagged_misprediction_no_allocation_no_idle_CYCLES_in_middle_sequence");
	super.new(name);
endfunction

virtual task body();
	provider_update_seq_item req;
	int tagged_provider_index;
	int provider_table_order[$];
	int shuffled_middle_tables[$];
	int provider_hit_count[NUM_TAGGED_TABLES];

	`uvm_info(
		"RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ",
		{
			"Starting back-to-back random middle-tagged-table ",
			"misprediction sequence with no allocation"
		},
		UVM_LOW
	)

	// Require >= 3 tables
	if (NUM_TAGGED_TABLES < 3) begin
		`uvm_fatal("RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ", "At least three tagged tables are required")
	end
	// Validate transactions count
	if ((2 * (NUM_TAGGED_TABLES - 2)) > NUM_TRANSACTIONS) begin
		`uvm_fatal(
			"RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ",
			$sformatf(
				{
					"%0d transactions are insufficient to cover all ",
					"%0d middle tagged tables twice"
				},
				NUM_TRANSACTIONS,
				NUM_TAGGED_TABLES - 2
			)
		)
	end

	// Init counters
	for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
		provider_hit_count[i] = 0;
	end

	// 2 shuffled passes
	for (int coverage_pass = 0; coverage_pass < 2; coverage_pass++) begin
		shuffled_middle_tables.delete();
		for (int table_index = 1; table_index < (NUM_TAGGED_TABLES - 1); table_index++) begin
			shuffled_middle_tables.push_back(table_index);
		end
		shuffled_middle_tables.shuffle();
		foreach (shuffled_middle_tables[i]) begin
			provider_table_order.push_back(shuffled_middle_tables[i]);
		end
	end
	// Fill rest
	while (provider_table_order.size() < NUM_TRANSACTIONS) begin
		provider_table_order.push_back($urandom_range(NUM_TAGGED_TABLES - 2, 1));
	end
	provider_table_order.shuffle();

	// Send back-to-back
	for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
		tagged_provider_index = provider_table_order[transaction_number];
		req = provider_update_seq_item::type_id::create($sformatf("random_middle_no_alloc_no_idle_req_%0d", transaction_number));
		start_item(req);
		req.clear_inputs();
		
		// Valid commit
		req.commit_valid_i = 1'b1;
		// Misprediction
		req.commit_mispredicted_i = 1'b1;
		// Target provider
		req.provider_id_i = provider_id_t'(BASE_PROVIDER_ID + tagged_provider_index + 1);
		// No alloc
		req.table_empty_mask_i = '0;
		// Random LFSR
		req.current_LFSR_value_input = tagged_table_mask_t'($urandom());
		// Valid base index
		req.commit_base_idx_i = base_index_t'(10'h200 + (transaction_number * 10'h021));

		// Valid indices/tags
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			req.commit_tagged_indices_i[i] = tagged_index_t'((transaction_number * NUM_TAGGED_TABLES) + i + 1);
			req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hD100 + (transaction_number * 16'h0100) + i + 1);
		end

		// Check valid target
		if ((req.commit_tagged_indices_i[tagged_provider_index] == '0) || (req.commit_tagged_tags_i[tagged_provider_index] == '0)) begin
			`uvm_fatal(
				"RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ",
				$sformatf(
					{
						"Tagged table T%0d has an invalid zero ",
						"index or tag"
					},
					tagged_provider_index
				)
			)
		end
		finish_item(req);
		
		// Record hit
		provider_hit_count[tagged_provider_index]++;

		`uvm_info(
			"RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ",
			$sformatf(
				{
					"Sent back-to-back transaction %0d of %0d: ",
					"provider=T%0d provider_id=%0d ",
					"provider_idx=0x%0h provider_tag=0x%0h ",
					"candidate_mask=0b%0b LFSR=0b%0b"
				},
				transaction_number + 1,
				NUM_TRANSACTIONS,
				tagged_provider_index,
				req.provider_id_i,
				req.commit_tagged_indices_i[tagged_provider_index],
				req.commit_tagged_tags_i[tagged_provider_index],
				req.table_empty_mask_i,
				req.current_LFSR_value_input
			),
			UVM_LOW
		)
	end

	// Coverage checks
	for (int table_index = 1; table_index < (NUM_TAGGED_TABLES - 1); table_index++) begin
		if (provider_hit_count[table_index] < 2) begin
			`uvm_fatal(
				"RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ",
				$sformatf(
					{
						"Coverage failure: tagged table T%0d was ",
						"selected only %0d time(s)"
					},
					table_index,
					provider_hit_count[table_index]
				)
			)
		end
		else begin
			`uvm_info(
				"RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ",
				$sformatf(
					"Tagged table T%0d was selected %0d time(s)",
					table_index,
					provider_hit_count[table_index]
				),
				UVM_LOW
			)
		end
	end
	`uvm_info(
		"RANDOM_MIDDLE_NO_ALLOC_NO_IDLE_SEQ",
		{
			"Completed thirteen back-to-back random middle-tagged-table ",
			"mispredictions with no allocation"
		},
		UVM_LOW
	)
endtask
endclass

/// taged table 7 providing the misprediction with table_empty_mask_i = 0
class provider_update_last_tagged_table_misprediction_no_allocation_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_last_tagged_table_misprediction_no_allocation_sequence)

	function new(string name = "provider_update_last_tagged_table_misprediction_no_allocation_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		int last_table_index;
		int idle_gap;

		// Select last table
		last_table_index = NUM_TAGGED_TABLES - 1;

		`uvm_info(
			"LAST_TABLE_MISPRED_NO_ALLOC_SEQ",
			{
				"Starting last-tagged-table misprediction sequence ",
				"with table_empty_mask_i equal to zero"
			},
			UVM_LOW
		)

		// 4 mispredictions
		for (int transaction_number = 0; transaction_number < 4; transaction_number++) begin
			req = provider_update_seq_item::type_id::create($sformatf("last_table_mispredict_no_alloc_req_%0d", transaction_number));
			start_item(req);
			req.clear_inputs();
			
			// Valid commit
			req.commit_valid_i = 1'b1;
			// Misprediction
			req.commit_mispredicted_i = 1'b1;
			// T7 provider
			req.provider_id_i = LAST_TAGGED_PROVIDER_ID;
			// No alloc
			req.table_empty_mask_i = '0;

			// Vary LFSR
			case (transaction_number)
				0: req.current_LFSR_value_input = tagged_table_mask_t'('0);
				1: req.current_LFSR_value_input = tagged_table_mask_t'('1);
				2: req.current_LFSR_value_input = tagged_table_mask_t'('h55);
				default: req.current_LFSR_value_input = tagged_table_mask_t'(1 << last_table_index);
			endcase

			// Base not provider
			req.commit_base_idx_i = '0;
			
			// Valid data
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hE100 + (transaction_number * 16'h0100) + i);
			end

			// Boundary values
			case (transaction_number)
				0: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'(1);
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'(1);
				end
				1: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'('1);
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'('1);
				end
				2: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'('h55);
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'('hAAAA);
				end
				default: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'(1 << (S_WIDTH - 1));
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'(1 << (T_WIDTH - 1));
				end
			endcase

			// Confirm T7 valid
			if ((req.commit_tagged_indices_i[last_table_index] == '0) || (req.commit_tagged_tags_i[last_table_index] == '0)) begin
				`uvm_fatal(
					"LAST_TABLE_MISPRED_NO_ALLOC_SEQ",
					{
						"The last tagged-table provider must have a ",
						"valid nonzero index and tag"
					}
				)
			end
			finish_item(req);

			`uvm_info(
				"LAST_TABLE_MISPRED_NO_ALLOC_SEQ",
				$sformatf(
					{
						"Sent transaction %0d of 4: ",
						"provider=T%0d provider_id=%0d ",
						"provider_idx=0x%0h provider_tag=0x%0h ",
						"empty_mask=0b%0b LFSR=0b%0b"
					},
					transaction_number + 1,
					last_table_index + 1,
					req.provider_id_i,
					req.commit_tagged_indices_i[last_table_index],
					req.commit_tagged_tags_i[last_table_index],
					req.table_empty_mask_i,
					req.current_LFSR_value_input
				),
				UVM_LOW
			)

			// Random idle gap
			if (transaction_number < 3) begin
				idle_gap = $urandom_range(3, 2);
				send_idle_cycles(idle_gap);
				`uvm_info(
					"LAST_TABLE_MISPRED_NO_ALLOC_SEQ",
					$sformatf(
						{
							"Completed %0d idle cycles after ",
							"transaction %0d"
						},
						idle_gap,
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end
		`uvm_info(
			"LAST_TABLE_MISPRED_NO_ALLOC_SEQ",
			{
				"Completed last-tagged-table misprediction sequence ",
				"with no allocation"
			},
			UVM_LOW
		)
	endtask
endclass

//// misprediction from tagged table 7 with misprediction and without IDLE cycles
class provider_update_last_tagged_table_misprediction_no_allocation_no_idle_cycles_in_between_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_last_tagged_table_misprediction_no_allocation_no_idle_cycles_in_between_sequence)

	function new(string name = "provider_update_last_tagged_table_misprediction_no_allocation_no_idle_cycles_in_between_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		int last_table_index;

		// Select T7
		last_table_index = NUM_TAGGED_TABLES - 1;

		`uvm_info(
			"LAST_TABLE_NO_ALLOC_NO_IDLE_SEQ",
			{
				"Starting back-to-back T7 misprediction sequence ",
				"with no allocation"
			},
			UVM_LOW
		)

		// 4 back-to-back
		for (int transaction_number = 0; transaction_number < 4; transaction_number++) begin
			req = provider_update_seq_item::type_id::create($sformatf("T7_mispredict_no_alloc_no_idle_req_%0d", transaction_number));
			start_item(req);
			req.clear_inputs();
			
			// Valid commit
			req.commit_valid_i = 1'b1;
			// Misprediction
			req.commit_mispredicted_i = 1'b1;
			// T7 provider
			req.provider_id_i = LAST_TAGGED_PROVIDER_ID;
			// No alloc
			req.table_empty_mask_i = '0;

			// Vary LFSR
			case (transaction_number)
				0: req.current_LFSR_value_input = tagged_table_mask_t'('0);
				1: req.current_LFSR_value_input = tagged_table_mask_t'('1);
				2: req.current_LFSR_value_input = tagged_table_mask_t'('h55);
				default: req.current_LFSR_value_input = tagged_table_mask_t'(1 << last_table_index);
			endcase

			// Base not provider
			req.commit_base_idx_i = '0;
			
			// Valid data
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h20 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hF100 + (transaction_number * 16'h0100) + i);
			end

			// Specific boundary values
			case (transaction_number)
				0: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'(1);
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'(1);
				end
				1: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'('1);
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'('1);
				end
				2: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'('h55);
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'('hAAAA);
				end
				default: begin
					req.commit_tagged_indices_i[last_table_index] = tagged_index_t'(1 << (S_WIDTH - 1));
					req.commit_tagged_tags_i[last_table_index] = tagged_tag_t'(1 << (T_WIDTH - 1));
				end
			endcase

			// Confirm T7 valid
			if ((req.commit_tagged_indices_i[last_table_index] == '0) || (req.commit_tagged_tags_i[last_table_index] == '0)) begin
				`uvm_fatal(
					"LAST_TABLE_NO_ALLOC_NO_IDLE_SEQ",
					{
						"T7 must have a valid nonzero ",
						"index and tag"
					}
				)
			end
			finish_item(req);

			`uvm_info(
				"LAST_TABLE_NO_ALLOC_NO_IDLE_SEQ",
				$sformatf(
					{
						"Sent back-to-back transaction %0d of 4: ",
						"provider=T%0d provider_id=%0d ",
						"provider_idx=0x%0h provider_tag=0x%0h ",
						"empty_mask=0b%0b LFSR=0b%0b"
					},
					transaction_number + 1,
					last_table_index + 1,
					req.provider_id_i,
					req.commit_tagged_indices_i[last_table_index],
					req.commit_tagged_tags_i[last_table_index],
					req.table_empty_mask_i,
					req.current_LFSR_value_input
				),
				UVM_LOW
			)
		end
		`uvm_info(
			"LAST_TABLE_NO_ALLOC_NO_IDLE_SEQ",
			{
				"Completed four back-to-back T7 mispredictions ",
				"with no allocation"
			},
			UVM_LOW
		)
	endtask
endclass

/// table empty mask is high for table with depth lower than the table providing the misprediction
// tablw with lower depth is available but the design should not pick it up as per the eligibility criteria
class provider_update_tagged_misprediction_lower_depth_candidates_vector_no_allocation_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_tagged_misprediction_lower_depth_candidates_vector_no_allocation_sequence)
	localparam int NUM_TRANSACTIONS = 4;

	function new(string name = "provider_update_tagged_misprediction_lower_depth_candidates_vector_no_allocation_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		provider_id_t provider_order [0:NUM_TAGGED_TABLES-1];
		provider_id_t temporary_provider;
		provider_id_t selected_provider_id;
		tagged_table_mask_t allowed_lower_mask;
		tagged_table_mask_t forbidden_higher_mask;
		int selected_provider_index;
		int forced_available_index;
		int random_position;
		int idle_gap;

		`uvm_info(
			"LOWER_CANDIDATES_NO_ALLOC_SEQ",
			{
				"Starting tagged-table misprediction sequence with ",
				"available entries only at or below the provider depth"
			},
			UVM_LOW
		)

		if (NUM_TAGGED_TABLES < NUM_TRANSACTIONS) begin
			`uvm_fatal(
				"LOWER_CANDIDATES_NO_ALLOC_SEQ",
				$sformatf(
					{
						"This sequence requires at least %0d ",
						"tagged tables"
					},
					NUM_TRANSACTIONS
				)
			)
		end

		// Init providers
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			provider_order[i] = provider_id_t'(i + 1);
		end
		
		// Shuffle
		for (int i = NUM_TAGGED_TABLES - 1; i > 0; i--) begin
			random_position = $urandom_range(i, 0);
			temporary_provider = provider_order[i];
			provider_order[i] = provider_order[random_position];
			provider_order[random_position] = temporary_provider;
		end

		// 4 mispredictions
		for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
			selected_provider_id = provider_order[transaction_number];
			selected_provider_index = int'(selected_provider_id) - 1;
			req = provider_update_seq_item::type_id::create($sformatf("lower_candidates_no_alloc_T%0d_req_%0d", selected_provider_id, transaction_number));
			start_item(req);
			req.clear_inputs();
			
			// Valid misprediction
			req.commit_valid_i = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			// Randomly ordered provider
			req.provider_id_i = selected_provider_id;

			// Mask of provider and lower tables
			allowed_lower_mask = '0;
			for (int i = 0; i <= selected_provider_index; i++) begin
				allowed_lower_mask[i] = 1'b1;
			end

			// Randomize and trim upper tables
			req.table_empty_mask_i = tagged_table_mask_t'($urandom()) & allowed_lower_mask;
			
			// Force nonzero if needed
			if (req.table_empty_mask_i == '0) begin
				forced_available_index = $urandom_range(selected_provider_index, 0);
				req.table_empty_mask_i[forced_available_index] = 1'b1;
			end

			// Ensure no higher tables marked
			forbidden_higher_mask = ~allowed_lower_mask;
			if (req.table_empty_mask_i == '0) begin
				`uvm_fatal("LOWER_CANDIDATES_NO_ALLOC_SEQ", "table_empty_mask_i must be nonzero")
			end
			if ((req.table_empty_mask_i & forbidden_higher_mask) != '0) begin
				`uvm_fatal(
					"LOWER_CANDIDATES_NO_ALLOC_SEQ",
					$sformatf(
						{
							"Provider T%0d has an illegal higher-table ",
							"candidate: empty_mask=0b%0b"
						},
						selected_provider_id,
						req.table_empty_mask_i
					)
				)
			end

			// Random LFSR
			req.current_LFSR_value_input = tagged_table_mask_t'($urandom());
			// Base not provider
			req.commit_base_idx_i = '0;
			
			// Valid indices/tags
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hA100 + (transaction_number * 16'h0100) + i);
			end

			// Confirm provider valid data
			if ((req.commit_tagged_indices_i[selected_provider_index] == '0) || (req.commit_tagged_tags_i[selected_provider_index] == '0)) begin
				`uvm_fatal(
					"LOWER_CANDIDATES_NO_ALLOC_SEQ",
					$sformatf(
						{
							"Provider T%0d must have a valid nonzero ",
							"index and tag"
						},
						selected_provider_id
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"LOWER_CANDIDATES_NO_ALLOC_SEQ",
				$sformatf(
					{
						"Sent transaction %0d of %0d: ",
						"provider=T%0d provider_index=%0d ",
						"allowed_lower_mask=0b%0b ",
						"table_empty_mask=0b%0b ",
						"provider_idx=0x%0h provider_tag=0x%0h ",
						"LFSR=0b%0b"
					},
					transaction_number + 1,
					NUM_TRANSACTIONS,
					selected_provider_id,
					selected_provider_index,
					allowed_lower_mask,
					req.table_empty_mask_i,
					req.commit_tagged_indices_i[selected_provider_index],
					req.commit_tagged_tags_i[selected_provider_index],
					req.current_LFSR_value_input
				),
				UVM_LOW
			)

			// 1-3 idle gap
			if (transaction_number < (NUM_TRANSACTIONS - 1)) begin
				idle_gap = $urandom_range(3, 1);
				send_idle_cycles(idle_gap);
				`uvm_info(
					"LOWER_CANDIDATES_NO_ALLOC_SEQ",
					$sformatf(
						{
							"Completed %0d idle cycles after ",
							"transaction %0d"
						},
						idle_gap,
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end
		`uvm_info(
			"LOWER_CANDIDATES_NO_ALLOC_SEQ",
			{
				"Completed four tagged-table mispredictions with ",
				"nonzero lower/equal-depth candidate masks and no allocation"
			},
			UVM_LOW
		)
	endtask
endclass

//////////
// BASE Misprediction and Single higher table allocation only
class provider_update_base_misprediction_single_higher_table_allocation_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_base_misprediction_single_higher_table_allocation_sequence)
	localparam int NUM_IDLE_TRANSACTIONS         = 4;
	localparam int NUM_BACK_TO_BACK_TRANSACTIONS = 4;

	function new(string name = "provider_update_base_misprediction_single_higher_table_allocation_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		int allocation_target_index;
		int idle_gap;
		int idle_target_order [0:NUM_IDLE_TRANSACTIONS-1];
		int back_to_back_target_order [0:NUM_BACK_TO_BACK_TRANSACTIONS-1];

		`uvm_info(
			"BASE_MISPRED_SINGLE_ALLOC_SEQ",
			{
				"Starting base-table misprediction sequence with ",
				"single tagged-table allocation candidates"
			},
			UVM_LOW
		)

		if (NUM_TAGGED_TABLES != 7) begin
			`uvm_fatal(
				"BASE_MISPRED_SINGLE_ALLOC_SEQ",
				$sformatf(
					{
						"This sequence expects NUM_TAGGED_TABLES=7, ",
						"but the configured value is %0d"
					},
					NUM_TAGGED_TABLES
				)
			)
		end

		// Phase 1 alloc targets
		idle_target_order[0] = 0;
		idle_target_order[1] = 2;
		idle_target_order[2] = 4;
		idle_target_order[3] = 6;
		
		// Phase 2 alloc targets
		back_to_back_target_order[0] = 1;
		back_to_back_target_order[1] = 3;
		back_to_back_target_order[2] = 5;
		back_to_back_target_order[3] = 0;

		`uvm_info(
			"BASE_MISPRED_SINGLE_ALLOC_SEQ",
			{
				"Starting phase 1: single-candidate allocations ",
				"with idle cycles"
			},
			UVM_LOW
		)

		// 4 single-alloc transactions
		for (int transaction_number = 0; transaction_number < NUM_IDLE_TRANSACTIONS; transaction_number++) begin
			allocation_target_index = idle_target_order[transaction_number];
			req = provider_update_seq_item::type_id::create($sformatf("base_mispredict_single_alloc_idle_T%0d_req_%0d", allocation_target_index + 1, transaction_number));
			start_item(req);
			req.clear_inputs();
			
			// Valid base misprediction
			req.commit_valid_i        = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			req.provider_id_i         = BASE_PROVIDER_ID;
			// All 1s LFSR preserves alloc
			req.current_LFSR_value_input = tagged_table_mask_t'(7'b111_1111);
			// One table available
			req.table_empty_mask_i = tagged_table_mask_t'(1 << allocation_target_index);

			// Retain boundary values
			case (transaction_number)
				0: req.commit_base_idx_i = base_index_t'(1);
				1: req.commit_base_idx_i = base_index_t'(10'h155);
				2: req.commit_base_idx_i = base_index_t'(10'h2AA);
				default: req.commit_base_idx_i = base_index_t'('1);
			endcase

			// Supply valid indices/tags
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hA100 + (transaction_number * 16'h0100) + i);
			end

			// Verify stimulus
			if (!$onehot(req.table_empty_mask_i)) begin
				`uvm_fatal(
					"BASE_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Phase 1 expected a one-hot empty mask, ",
							"received 0b%0b"
						},
						req.table_empty_mask_i
					)
				)
			end
			if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin
				`uvm_fatal(
					"BASE_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Phase 1 allocation target T%0d has a ",
							"zero index or tag"
						},
						allocation_target_index + 1
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"BASE_MISPRED_SINGLE_ALLOC_SEQ",
				$sformatf(
					{
						"Phase 1 transaction %0d of %0d: ",
						"provider=T0 base_idx=0x%0h ",
						"allocation_target=T%0d ",
						"target_idx=0x%0h target_tag=0x%0h ",
						"empty_mask=0b%0b LFSR=0b%0b"
					},
					transaction_number + 1,
					NUM_IDLE_TRANSACTIONS,
					req.commit_base_idx_i,
					allocation_target_index + 1,
					req.commit_tagged_indices_i[allocation_target_index],
					req.commit_tagged_tags_i[allocation_target_index],
					req.table_empty_mask_i,
					req.current_LFSR_value_input
				),
				UVM_LOW
			)

			// 2-3 idle gap
			if (transaction_number < (NUM_IDLE_TRANSACTIONS - 1)) begin
				idle_gap = $urandom_range(3, 2);
				send_idle_cycles(idle_gap);
				`uvm_info(
					"BASE_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Completed %0d idle cycles after ",
							"phase 1 transaction %0d"
						},
						idle_gap,
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end

		`uvm_info(
			"BASE_MISPRED_SINGLE_ALLOC_SEQ",
			{
				"Starting phase 2: back-to-back single-candidate ",
				"allocation transactions"
			},
			UVM_LOW
		)

		// 4 back-to-back
		for (int transaction_number = 0; transaction_number < NUM_BACK_TO_BACK_TRANSACTIONS; transaction_number++) begin
			allocation_target_index = back_to_back_target_order[transaction_number];
			req = provider_update_seq_item::type_id::create($sformatf("base_mispredict_single_alloc_back_to_back_T%0d_req_%0d", allocation_target_index + 1, transaction_number));
			start_item(req);
			req.clear_inputs();
			
			// Valid misprediction
			req.commit_valid_i        = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			req.provider_id_i         = BASE_PROVIDER_ID;
			// Enable all LFSR
			req.current_LFSR_value_input = tagged_table_mask_t'(7'b111_1111);
			// One table available
			req.table_empty_mask_i = tagged_table_mask_t'(1 << allocation_target_index);
			// Differing nonzero base indices
			req.commit_base_idx_i = base_index_t'(10'h300 + (transaction_number * 10'h040));

			// Valid tag/indices
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h40 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hB100 + (transaction_number * 16'h0100) + i);
			end

			// Verify stimulus
			if (!$onehot(req.table_empty_mask_i)) begin
				`uvm_fatal(
					"BASE_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Phase 2 expected a one-hot empty mask, ",
							"received 0b%0b"
						},
						req.table_empty_mask_i
					)
				)
			end
			if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin
				`uvm_fatal(
					"BASE_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Phase 2 allocation target T%0d has a ",
							"zero index or tag"
						},
						allocation_target_index + 1
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"BASE_MISPRED_SINGLE_ALLOC_SEQ",
				$sformatf(
					{
						"Phase 2 back-to-back transaction %0d of %0d: ",
						"provider=T0 base_idx=0x%0h ",
						"allocation_target=T%0d ",
						"target_idx=0x%0h target_tag=0x%0h ",
						"empty_mask=0b%0b LFSR=0b%0b"
					},
					transaction_number + 1,
					NUM_BACK_TO_BACK_TRANSACTIONS,
					req.commit_base_idx_i,
					allocation_target_index + 1,
					req.commit_tagged_indices_i[allocation_target_index],
					req.commit_tagged_tags_i[allocation_target_index],
					req.table_empty_mask_i,
					req.current_LFSR_value_input
				),
				UVM_LOW
			)
		end
		`uvm_info(
			"BASE_MISPRED_SINGLE_ALLOC_SEQ",
			{
				"Completed base-table single-candidate allocation sequence: ",
				"four transactions with idle cycles followed by four ",
				"back-to-back transactions"
			},
			UVM_LOW
		)
	endtask
endclass

//// Base misprediction with multiple bits high for table empty mask and check the action on the tables with
/// LFSR = 7'b111_1111 and LFSR = 7'b000_0000
class provider_update_base_misprediction_multiple_higher_tables_allocation_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_base_misprediction_multiple_higher_tables_allocation_sequence)
	localparam int NUM_TRANSACTIONS = 4;

	function new(string name = "provider_update_base_misprediction_multiple_higher_tables_allocation_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		tagged_table_mask_t candidate_masks [0:NUM_TRANSACTIONS-1];
		int expected_allocation_target [0:NUM_TRANSACTIONS-1];
		int allocation_candidate_count;
		int idle_gap;

		`uvm_info(
			"BASE_MISPRED_MULTI_ALLOC_SEQ",
			{
				"Starting base-table misprediction sequence with ",
				"multiple higher-table allocation candidates"
			},
			UVM_LOW
		)

		if (NUM_TAGGED_TABLES != 7) begin
			`uvm_fatal(
				"BASE_MISPRED_MULTI_ALLOC_SEQ",
				$sformatf(
					{
						"This sequence expects NUM_TAGGED_TABLES=7, ",
						"but the configured value is %0d"
					},
					NUM_TAGGED_TABLES
				)
			)
		end

		candidate_masks[0]             = 7'b000_0011;
		expected_allocation_target[0]  = 1;
		candidate_masks[1]             = 7'b001_1010;
		expected_allocation_target[1]  = 4;
		candidate_masks[2]             = 7'b010_0100;
		expected_allocation_target[2]  = 5;
		candidate_masks[3]             = 7'b100_1001;
		expected_allocation_target[3]  = 6;

		// Send 4 transactions with idle cycles
		for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
			req = provider_update_seq_item::type_id::create($sformatf("base_mispredict_multiple_alloc_req_%0d", transaction_number));
			start_item(req);
			req.clear_inputs();
			
			// Valid base misprediction
			req.commit_valid_i        = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			req.provider_id_i         = BASE_PROVIDER_ID;
			// Preserve candidates via LFSR
			req.current_LFSR_value_input = tagged_table_mask_t'(7'b111_1111);
			// Supply 2-3 alloc candidates
			req.table_empty_mask_i = candidate_masks[transaction_number];
			// Valid base index
			req.commit_base_idx_i = base_index_t'(10'h100 + (transaction_number * 10'h080));

			// Valid indices/tags
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hC100 + (transaction_number * 16'h0100) + i);
			end

			// Verify mask contains 2 or 3 candidates
			allocation_candidate_count = $countones(req.table_empty_mask_i);
			if ((allocation_candidate_count < 2) || (allocation_candidate_count > 3)) begin
				`uvm_fatal(
					"BASE_MISPRED_MULTI_ALLOC_SEQ",
					$sformatf(
						{
							"Transaction %0d expected two or three ",
							"allocation candidates, but mask 0b%0b ",
							"contains %0d candidates"
						},
						transaction_number,
						req.table_empty_mask_i,
						allocation_candidate_count
					)
				)
			end
			
			// Verify target included
			if (req.table_empty_mask_i[expected_allocation_target[transaction_number]] !== 1'b1) begin
				`uvm_fatal(
					"BASE_MISPRED_MULTI_ALLOC_SEQ",
					$sformatf(
						{
							"Expected allocation target T%0d is not ",
							"present in candidate mask 0b%0b"
						},
						expected_allocation_target[transaction_number] + 1,
						req.table_empty_mask_i
					)
				)
			end
			// Verify target valid data
			if ((req.commit_tagged_indices_i[expected_allocation_target[transaction_number]] == '0) || (req.commit_tagged_tags_i[expected_allocation_target[transaction_number]] == '0)) begin
				`uvm_fatal(
					"BASE_MISPRED_MULTI_ALLOC_SEQ",
					$sformatf(
						{
							"Expected allocation target T%0d has a ",
							"zero index or tag"
						},
						expected_allocation_target[transaction_number] + 1
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"BASE_MISPRED_MULTI_ALLOC_SEQ",
				$sformatf(
					{
						"Sent transaction %0d of %0d: ",
						"provider=T0 base_idx=0x%0h ",
						"candidate_mask=0b%0b candidate_count=%0d ",
						"expected_allocation_target=T%0d ",
						"target_idx=0x%0h target_tag=0x%0h ",
						"LFSR=0b%0b"
					},
					transaction_number + 1,
					NUM_TRANSACTIONS,
					req.commit_base_idx_i,
					req.table_empty_mask_i,
					allocation_candidate_count,
					expected_allocation_target[transaction_number] + 1,
					req.commit_tagged_indices_i[expected_allocation_target[transaction_number]],
					req.commit_tagged_tags_i[expected_allocation_target[transaction_number]],
					req.current_LFSR_value_input
				),
				UVM_LOW
			)

			// 2-3 idle gap
			if (transaction_number < (NUM_TRANSACTIONS - 1)) begin
				idle_gap = $urandom_range(3, 2);
				send_idle_cycles(idle_gap);
				`uvm_info(
					"BASE_MISPRED_MULTI_ALLOC_SEQ",
					$sformatf(
						{
							"Completed %0d idle cycles after ",
							"transaction %0d"
						},
						idle_gap,
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end
		`uvm_info(
			"BASE_MISPRED_MULTI_ALLOC_SEQ",
			{
				"Completed base-table misprediction sequence with ",
				"multiple higher-table allocation candidates and ",
				"an all-one LFSR"
			},
			UVM_LOW
		)
	endtask
endclass

// in this we have base table as the misprediction provider
// 2-3 tagged tables available per transaction for update/write
// variable LFSR values between '0 to '1
// some handfuiul of cases with base_candidates 
class provider_update_base_misprediction_multiple_candidates_variable_lfsr_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_base_misprediction_multiple_candidates_variable_lfsr_sequence)
	localparam int NUM_TRANSACTIONS = 17;

	function new(string name = "provider_update_base_misprediction_multiple_candidates_variable_lfsr_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		tagged_table_mask_t candidate_masks [0:NUM_TRANSACTIONS-1];
		tagged_table_mask_t lfsr_values [0:NUM_TRANSACTIONS-1];
		tagged_table_mask_t lfsr_filtered_candidates;
		tagged_table_mask_t final_selection_pool;
		int expected_allocation_target;
		int allocation_candidate_count;

		`uvm_info(
			"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
			{
				"Starting seventeen base-table mispredictions with ",
				"multiple candidates and variable LFSR values"
			},
			UVM_LOW
		)

		if (NUM_TAGGED_TABLES != 7) begin
			`uvm_fatal(
				"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
				$sformatf(
					{
						"This sequence expects NUM_TAGGED_TABLES=7, ",
						"but the configured value is %0d"
					},
					NUM_TAGGED_TABLES
				)
			)
		end

		candidate_masks[0]  = 7'b000_0011;
		candidate_masks[1]  = 7'b000_1101;
		candidate_masks[2]  = 7'b001_1010;
		candidate_masks[3]  = 7'b010_0100;
		candidate_masks[4]  = 7'b100_1001;
		candidate_masks[5]  = 7'b110_0000;
		candidate_masks[6]  = 7'b101_0100;
		candidate_masks[7]  = 7'b011_0001;
		candidate_masks[8]  = 7'b000_1010;
		candidate_masks[9]  = 7'b001_0110;
		candidate_masks[10] = 7'b010_1001;
		candidate_masks[11] = 7'b100_0100;
		candidate_masks[12] = 7'b100_0011;
		candidate_masks[13] = 7'b011_1000;
		candidate_masks[14] = 7'b101_0100;
		candidate_masks[15] = 7'b010_0010;
		candidate_masks[16] = 7'b110_1000;

		// Final transaction uses all-one LFSR
		lfsr_values[0]  = 7'b000_0000;
		lfsr_values[1]  = 7'b000_0001;
		lfsr_values[2]  = 7'b000_0010;
		lfsr_values[3]  = 7'b000_0100;
		lfsr_values[4]  = 7'b000_0000;
		lfsr_values[5]  = 7'b000_1000;
		lfsr_values[6]  = 7'b001_0000;
		lfsr_values[7]  = 7'b010_0000;
		lfsr_values[8]  = 7'b100_0000;
		lfsr_values[9]  = 7'b000_0000;
		lfsr_values[10] = 7'b101_0101;
		lfsr_values[11] = 7'b010_1010;
		lfsr_values[12] = 7'b001_1110;
		lfsr_values[13] = 7'b110_0001;
		lfsr_values[14] = 7'b000_0000;
		lfsr_values[15] = 7'b011_1111;
		lfsr_values[16] = 7'b111_1111;

		// Send 17 transactions
		for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
			req = provider_update_seq_item::type_id::create($sformatf("base_multi_candidate_variable_lfsr_req_%0d", transaction_number));
			start_item(req);
			req.clear_inputs();

			// Valid base-table misprediction
			req.commit_valid_i        = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			req.provider_id_i         = BASE_PROVIDER_ID;

			// Apply multi-candidate mask and variable LFSR
			req.table_empty_mask_i = candidate_masks[transaction_number];
			req.current_LFSR_value_input = lfsr_values[transaction_number];

			// Valid base index
			req.commit_base_idx_i = base_index_t'(10'h080 + (transaction_number * 10'h025));

			// Valid tagged-table indices/tags
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'((transaction_number * NUM_TAGGED_TABLES) + i + 1);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hD000 + (transaction_number * 16'h0100) + i + 1);
			end

			// Verify candidate counts
			allocation_candidate_count = $countones(req.table_empty_mask_i);
			if ((allocation_candidate_count < 2) || (allocation_candidate_count > 3)) begin
				`uvm_fatal(
					"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Transaction %0d expected two or three ",
							"candidates, but mask 0b%0b has %0d"
						},
						transaction_number,
						req.table_empty_mask_i,
						allocation_candidate_count
					)
				)
			end

			// Reproduce expected LFSR filtering behavior
			lfsr_filtered_candidates = req.table_empty_mask_i & req.current_LFSR_value_input;
			if (lfsr_filtered_candidates != '0) begin
				final_selection_pool = lfsr_filtered_candidates;
			end
			else begin
				final_selection_pool = req.table_empty_mask_i;
			end

			// Find deepest candidate in final pool
			expected_allocation_target = -1;
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				if (final_selection_pool[i] === 1'b1) begin
					expected_allocation_target = i;
				end
			end

			if (expected_allocation_target < 0) begin
				`uvm_fatal(
					"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Transaction %0d produced no expected ",
							"allocation target"
						},
						transaction_number
					)
				)
			end

			if ((req.commit_tagged_indices_i[expected_allocation_target] == '0) || (req.commit_tagged_tags_i[expected_allocation_target] == '0)) begin
				`uvm_fatal(
					"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Expected target T%0d has a zero ",
							"index or tag"
						},
						expected_allocation_target + 1
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
				$sformatf(
					{
						"Transaction %0d of %0d: ",
						"provider=T0 base_idx=0x%0h ",
						"candidate_mask=0b%0b LFSR=0b%0b ",
						"filtered_candidates=0b%0b ",
						"selection_pool=0b%0b ",
						"expected_target=T%0d ",
						"fallback_used=%0b"
					},
					transaction_number + 1,
					NUM_TRANSACTIONS,
					req.commit_base_idx_i,
					req.table_empty_mask_i,
					req.current_LFSR_value_input,
					lfsr_filtered_candidates,
					final_selection_pool,
					expected_allocation_target + 1,
					(lfsr_filtered_candidates == '0)
				),
				UVM_LOW
			)

			// Insert 1 idle cycle occasionally
			if ((transaction_number == 3) || (transaction_number == 7) || (transaction_number == 11)) begin
				send_idle_cycles(1);
				`uvm_info(
					"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Inserted one idle cycle after ",
							"transaction %0d"
						},
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end
		`uvm_info(
			"BASE_MULTI_CANDIDATE_VARIABLE_LFSR_SEQ",
			{
				"Completed seventeen variable-LFSR transactions, ",
				"including four all-zero LFSR fallback cases"
			},
			UVM_LOW
		)
	endtask
endclass

/// tagged table provides the misprediction with just one higher table for allocation
class provider_update_tagged_misprediction_single_higher_table_allocation_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_tagged_misprediction_single_higher_table_allocation_sequence)
	localparam int NUM_TRANSACTIONS = 6;

	function new(string name = "provider_update_tagged_misprediction_single_higher_table_allocation_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		provider_id_t provider_order [0:NUM_TRANSACTIONS-1];
		int allocation_target_order [0:NUM_TRANSACTIONS-1];
		int provider_index;
		int allocation_target_index;
		int idle_gap;

		`uvm_info(
			"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
			{
				"Starting tagged-provider misprediction sequence with ",
				"exactly one higher-table allocation candidate"
			},
			UVM_LOW
		)

		if (NUM_TAGGED_TABLES != 7) begin
			`uvm_fatal(
				"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
				$sformatf(
					{
						"This sequence expects NUM_TAGGED_TABLES=7, ",
						"but the configured value is %0d"
					},
					NUM_TAGGED_TABLES
				)
			)
		end

		// Provider and allocation-target combinations (T7 not provider)
		provider_order[0]          = provider_id_t'(1);
		allocation_target_order[0] = 1; // T2
		provider_order[1]          = provider_id_t'(2);
		allocation_target_order[1] = 3; // T4
		provider_order[2]          = provider_id_t'(3);
		allocation_target_order[2] = 6; // T7
		provider_order[3]          = provider_id_t'(4);
		allocation_target_order[3] = 4; // T5
		provider_order[4]          = provider_id_t'(5);
		allocation_target_order[4] = 6; // T7
		provider_order[5]          = provider_id_t'(6);
		allocation_target_order[5] = 6; // T7

		// Send 6 tagged mispredictions
		for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
			provider_index = int'(provider_order[transaction_number]) - 1;
			allocation_target_index = allocation_target_order[transaction_number];
			req = provider_update_seq_item::type_id::create($sformatf("tagged_T%0d_mispredict_single_alloc_T%0d_req_%0d", provider_order[transaction_number], allocation_target_index + 1, transaction_number));
			start_item(req);
			req.clear_inputs();

			// Valid tagged misprediction
			req.commit_valid_i        = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			// Select provider
			req.provider_id_i = provider_order[transaction_number];
			// All 1s LFSR preserves candidate
			req.current_LFSR_value_input = tagged_table_mask_t'(7'b111_1111);
			// One higher table available
			req.table_empty_mask_i = tagged_table_mask_t'(1 << allocation_target_index);
			// Base not provider
			req.commit_base_idx_i = '0;

			// Supply valid indices/tags
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hA100 + (transaction_number * 16'h0100) + i);
			end

			// Verify target table above provider
			if ((allocation_target_index + 1) <= int'(req.provider_id_i)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Illegal allocation target: provider=T%0d, ",
							"target=T%0d. Target must be above provider."
						},
						req.provider_id_i,
						allocation_target_index + 1
					)
				)
			end

			// Confirm one-hot candidate mask
			if (!$onehot(req.table_empty_mask_i)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Expected a one-hot table_empty_mask_i, ",
							"received 0b%0b"
						},
						req.table_empty_mask_i
					)
				)
			end

			// Confirm provider valid data
			if ((req.commit_tagged_indices_i[provider_index] == '0) || (req.commit_tagged_tags_i[provider_index] == '0)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Provider T%0d must have a valid nonzero ",
							"index and tag"
						},
						req.provider_id_i
					)
				)
			end

			// Confirm target valid data
			if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Allocation target T%0d must have a valid ",
							"nonzero index and tag"
						},
						allocation_target_index + 1
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
				$sformatf(
					{
						"Transaction %0d of %0d: ",
						"provider=T%0d provider_idx=0x%0h ",
						"provider_tag=0x%0h ",
						"allocation_target=T%0d target_idx=0x%0h ",
						"target_tag=0x%0h empty_mask=0b%0b ",
						"LFSR=0b%0b"
					},
					transaction_number + 1,
					NUM_TRANSACTIONS,
					req.provider_id_i,
					req.commit_tagged_indices_i[provider_index],
					req.commit_tagged_tags_i[provider_index],
					allocation_target_index + 1,
					req.commit_tagged_indices_i[allocation_target_index],
					req.commit_tagged_tags_i[allocation_target_index],
					req.table_empty_mask_i,
					req.current_LFSR_value_input
				),
				UVM_LOW
			)

			// 2-3 idle cycles gap
			if (transaction_number < (NUM_TRANSACTIONS - 1)) begin
				idle_gap = $urandom_range(3, 2);
				send_idle_cycles(idle_gap);
				`uvm_info(
					"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
					$sformatf(
						{
							"Completed %0d idle cycles after ",
							"transaction %0d"
						},
						idle_gap,
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end
		`uvm_info(
			"TAGGED_MISPRED_SINGLE_ALLOC_SEQ",
			{
				"Completed tagged-provider mispredictions with ",
				"exactly one higher allocation candidate"
			},
			UVM_LOW
		)
	endtask
endclass

/// tagged table misprediction with multiple higher tables available for allocation
class provider_update_tagged_misprediction_multiple_higher_tables_zero_lfsr_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_tagged_misprediction_multiple_higher_tables_zero_lfsr_sequence)
	localparam int NUM_TRANSACTIONS = 6;

	function new(string name = "provider_update_tagged_misprediction_multiple_higher_tables_zero_lfsr_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		provider_id_t provider_order [0:NUM_TRANSACTIONS-1];
		tagged_table_mask_t candidate_masks [0:NUM_TRANSACTIONS-1];
		tagged_table_mask_t eligible_higher_mask;
		tagged_table_mask_t final_lfsr_target_mask;
		tagged_table_mask_t expected_decay_mask;
		int provider_index;
		int allocation_target_index;
		int candidate_count;
		int idle_gap;

		`uvm_info(
			"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
			{
				"Starting tagged-provider misprediction sequence with ",
				"multiple higher candidates and an all-zero LFSR"
			},
			UVM_LOW
		)

		if (NUM_TAGGED_TABLES != 7) begin
			`uvm_fatal(
				"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
				$sformatf(
					{
						"This sequence expects NUM_TAGGED_TABLES=7, ",
						"but the configured value is %0d"
					},
					NUM_TAGGED_TABLES
				)
			)
		end

		// Candidates strictly above provider
		provider_order[0]  = provider_id_t'(1);
		candidate_masks[0] = 7'b100_1010; // T2, T4, T7
		provider_order[1]  = provider_id_t'(2);
		candidate_masks[1] = 7'b011_0100; // T3, T5, T6
		provider_order[2]  = provider_id_t'(3);
		candidate_masks[2] = 7'b110_1000; // T4, T6, T7
		provider_order[3]  = provider_id_t'(4);
		candidate_masks[3] = 7'b101_0000; // T5, T7
		provider_order[4]  = provider_id_t'(5);
		candidate_masks[4] = 7'b110_0000; // T6, T7
		provider_order[5]  = provider_id_t'(6);
		candidate_masks[5] = 7'b100_0000; // T7 only

		// Send 6 transactions
		for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
			provider_index = int'(provider_order[transaction_number]) - 1;
			req = provider_update_seq_item::type_id::create($sformatf("tagged_T%0d_mispredict_multi_alloc_zero_lfsr_req_%0d", provider_order[transaction_number], transaction_number));
			start_item(req);
			req.clear_inputs();

			// Valid tagged misprediction
			req.commit_valid_i        = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			// Select provider
			req.provider_id_i = provider_order[transaction_number];
			// All-zero LFSR forces fallback to complete candidate mask
			req.current_LFSR_value_input = '0;
			// Configure higher tables available
			req.table_empty_mask_i = candidate_masks[transaction_number];
			// Base not provider
			req.commit_base_idx_i = '0;

			// Valid indices/tags
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hB100 + (transaction_number * 16'h0100) + i);
			end

			// Construct higher-table eligibility mask
			eligible_higher_mask = '0;
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				if ((i + 1) > int'(req.provider_id_i)) begin
					eligible_higher_mask[i] = 1'b1;
				end
			end

			// Confirm no candidate below provider
			if ((req.table_empty_mask_i & ~eligible_higher_mask) != '0) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
					$sformatf(
						{
							"Provider T%0d has an illegal candidate ",
							"at or below its depth: candidate mask=0b%0b, ",
							"eligible mask=0b%0b"
						},
						req.provider_id_i,
						req.table_empty_mask_i,
						eligible_higher_mask
					)
				)
			end

			// Verify candidate counts
			candidate_count = $countones(req.table_empty_mask_i);
			if ((req.provider_id_i <= provider_id_t'(5)) && (candidate_count < 2)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
					$sformatf(
						{
							"Provider T%0d expected multiple higher ",
							"candidates, but mask 0b%0b contains %0d"
						},
						req.provider_id_i,
						req.table_empty_mask_i,
						candidate_count
					)
				)
			end
			if ((req.provider_id_i == provider_id_t'(6)) && (candidate_count != 1)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
					$sformatf(
						{
							"Provider T6 expected exactly one higher ",
							"candidate, but mask 0b%0b contains %0d"
						},
						req.table_empty_mask_i,
						candidate_count
					)
				)
			end

			// LFSR filtered mask will be zero, fallback to table_empty_mask_i
			final_lfsr_target_mask = req.table_empty_mask_i & eligible_higher_mask;

			// Locate deepest candidate
			allocation_target_index = -1;
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				if (final_lfsr_target_mask[i] === 1'b1) begin
					allocation_target_index = i;
				end
			end

			if (allocation_target_index < 0) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
					$sformatf(
						{
							"Provider T%0d produced no allocation target"
						},
						req.provider_id_i
					)
				)
			end

			// Remaining candidates decay
			expected_decay_mask = final_lfsr_target_mask;
			expected_decay_mask[allocation_target_index] = 1'b0;

			// Verify valid data for provider and target
			if ((req.commit_tagged_indices_i[provider_index] == '0) || (req.commit_tagged_tags_i[provider_index] == '0)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
					$sformatf(
						{
							"Provider T%0d has a zero index or tag"
						},
						req.provider_id_i
					)
				)
			end
			if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
					$sformatf(
						{
							"Allocation target T%0d has a zero index or tag"
						},
						allocation_target_index + 1
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
				$sformatf(
					{
						"Transaction %0d of %0d: ",
						"provider=T%0d provider_idx=0x%0h ",
						"provider_tag=0x%0h ",
						"candidate_mask=0b%0b candidate_count=%0d ",
						"LFSR=0b%0b fallback_mask=0b%0b ",
						"allocation_target=T%0d decay_mask=0b%0b"
					},
					transaction_number + 1,
					NUM_TRANSACTIONS,
					req.provider_id_i,
					req.commit_tagged_indices_i[provider_index],
					req.commit_tagged_tags_i[provider_index],
					req.table_empty_mask_i,
					candidate_count,
					req.current_LFSR_value_input,
					final_lfsr_target_mask,
					allocation_target_index + 1,
					expected_decay_mask
				),
				UVM_LOW
			)

			// 2-3 idle gap
			if (transaction_number < (NUM_TRANSACTIONS - 1)) begin
				idle_gap = $urandom_range(3, 2);
				send_idle_cycles(idle_gap);
				`uvm_info(
					"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
					$sformatf(
						{
							"Completed %0d idle cycles after ",
							"transaction %0d"
						},
						idle_gap,
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end
		`uvm_info(
			"TAGGED_MISPRED_MULTI_ZERO_LFSR_SEQ",
			{
				"Completed T1-through-T6 mispredictions with higher ",
				"allocation candidates and an all-zero LFSR"
			},
			UVM_LOW
		)
	endtask
endclass

/// tagged table misprediction - multiple higher table for allocation - non zero lfsr.
class provider_update_tagged_misprediction_multiple_higher_tables_variable_lfsr_sequence extends provider_update_base_sequence;

	`uvm_object_utils(provider_update_tagged_misprediction_multiple_higher_tables_variable_lfsr_sequence)
	localparam int NUM_TRANSACTIONS = 17;

	function new(string name = "provider_update_tagged_misprediction_multiple_higher_tables_variable_lfsr_sequence");
		super.new(name);
	endfunction

	virtual task body();
		provider_update_seq_item req;
		provider_id_t provider_order [0:NUM_TRANSACTIONS-1];
		tagged_table_mask_t candidate_masks [0:NUM_TRANSACTIONS-1];
		tagged_table_mask_t lfsr_values [0:NUM_TRANSACTIONS-1];
		tagged_table_mask_t eligible_higher_mask;
		tagged_table_mask_t available_eligible_mask;
		tagged_table_mask_t lfsr_candidate_mask;
		tagged_table_mask_t final_lfsr_target_mask;
		tagged_table_mask_t expected_decay_mask;
		int provider_index;
		int allocation_target_index;
		int candidate_count;

		`uvm_info(
			"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
			{
				"Starting tagged-provider misprediction sequence with ",
				"multiple higher candidates and variable LFSR values"
			},
			UVM_LOW
		)

		if (NUM_TAGGED_TABLES != 7) begin
			`uvm_fatal(
				"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
				$sformatf(
					{
						"This sequence expects NUM_TAGGED_TABLES=7, ",
						"but the configured value is %0d"
					},
					NUM_TAGGED_TABLES
				)
			)
		end

		// Exercise T1-T6 repeatedly
		provider_order[0]  = provider_id_t'(1);
		provider_order[1]  = provider_id_t'(2);
		provider_order[2]  = provider_id_t'(3);
		provider_order[3]  = provider_id_t'(4);
		provider_order[4]  = provider_id_t'(5);
		provider_order[5]  = provider_id_t'(6);
		provider_order[6]  = provider_id_t'(1);
		provider_order[7]  = provider_id_t'(2);
		provider_order[8]  = provider_id_t'(3);
		provider_order[9]  = provider_id_t'(4);
		provider_order[10] = provider_id_t'(5);
		provider_order[11] = provider_id_t'(6);
		provider_order[12] = provider_id_t'(1);
		provider_order[13] = provider_id_t'(4);
		provider_order[14] = provider_id_t'(2);
		provider_order[15] = provider_id_t'(5);
		provider_order[16] = provider_id_t'(3);

		// Higher candidate masks
		candidate_masks[0]  = 7'b100_1010;
		candidate_masks[1]  = 7'b011_0100;
		candidate_masks[2]  = 7'b110_1000;
		candidate_masks[3]  = 7'b101_0000;
		candidate_masks[4]  = 7'b110_0000;
		candidate_masks[5]  = 7'b100_0000;
		candidate_masks[6]  = 7'b011_0100;
		candidate_masks[7]  = 7'b100_1000;
		candidate_masks[8]  = 7'b011_0000;
		candidate_masks[9]  = 7'b111_0000;
		candidate_masks[10] = 7'b110_0000;
		candidate_masks[11] = 7'b100_0000;
		candidate_masks[12] = 7'b001_0110;
		candidate_masks[13] = 7'b101_0000;
		candidate_masks[14] = 7'b110_0100;
		candidate_masks[15] = 7'b110_0000;
		candidate_masks[16] = 7'b101_1000;

		// Test various LFSR patterns including all-zero and all-one
		lfsr_values[0]  = 7'b000_0000;
		lfsr_values[1]  = 7'b111_1111;
		lfsr_values[2]  = 7'b010_0000;
		lfsr_values[3]  = 7'b001_0000;
		lfsr_values[4]  = 7'b000_0000;
		lfsr_values[5]  = 7'b100_0000;
		lfsr_values[6]  = 7'b010_1010;
		lfsr_values[7]  = 7'b101_0101;
		lfsr_values[8]  = 7'b000_1000;
		lfsr_values[9]  = 7'b111_0000;
		lfsr_values[10] = 7'b010_0000;
		lfsr_values[11] = 7'b000_0000;
		lfsr_values[12] = 7'b001_1111;
		lfsr_values[13] = 7'b100_0000;
		lfsr_values[14] = 7'b000_0000;
		lfsr_values[15] = 7'b110_0000;
		lfsr_values[16] = 7'b111_1111;

		// Send 17 transactions
		for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin
			provider_index = int'(provider_order[transaction_number]) - 1;
			req = provider_update_seq_item::type_id::create($sformatf("tagged_T%0d_multi_candidate_variable_lfsr_req_%0d", provider_order[transaction_number], transaction_number));
			start_item(req);
			req.clear_inputs();

			// Valid tagged misprediction
			req.commit_valid_i        = 1'b1;
			req.commit_mispredicted_i = 1'b1;
			// Select provider
			req.provider_id_i = provider_order[transaction_number];
			// Apply candidate/LFSR masks
			req.table_empty_mask_i = candidate_masks[transaction_number];
			req.current_LFSR_value_input = lfsr_values[transaction_number];
			// Base not provider
			req.commit_base_idx_i = '0;

			// Valid indices/tags
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
				req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hC000 + (transaction_number * 16'h0100) + i + 1);
			end

			// Construct higher eligibility mask
			eligible_higher_mask = '0;
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				if ((i + 1) > int'(req.provider_id_i)) begin
					eligible_higher_mask[i] = 1'b1;
				end
			end

			// Ensure no candidate at/below provider
			if ((req.table_empty_mask_i & ~eligible_higher_mask) != '0) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Provider T%0d has an illegal candidate ",
							"at or below its depth: empty mask=0b%0b, ",
							"eligible mask=0b%0b"
						},
						req.provider_id_i,
						req.table_empty_mask_i,
						eligible_higher_mask
					)
				)
			end

			// Calculate available & eligible candidates
			available_eligible_mask = req.table_empty_mask_i & eligible_higher_mask;
			candidate_count = $countones(available_eligible_mask);

			// T1-T5 expect multiple candidates
			if ((req.provider_id_i <= provider_id_t'(5)) && (candidate_count < 2)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Provider T%0d expected multiple higher ",
							"candidates, but mask 0b%0b contains %0d"
						},
						req.provider_id_i,
						available_eligible_mask,
						candidate_count
					)
				)
			end

			// T6 expects only T7
			if ((req.provider_id_i == provider_id_t'(6)) && (available_eligible_mask != 7'b100_0000)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Provider T6 expected T7 as its only ",
							"candidate, received mask 0b%0b"
						},
						available_eligible_mask
					)
				)
			end

			// Apply LFSR to candidates
			lfsr_candidate_mask = available_eligible_mask & req.current_LFSR_value_input;
			if (lfsr_candidate_mask != '0) begin
				final_lfsr_target_mask = lfsr_candidate_mask;
			end
			else begin
				final_lfsr_target_mask = available_eligible_mask;
			end

			// Find deepest candidate in final LFSR target mask
			allocation_target_index = -1;
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
				if (final_lfsr_target_mask[i] === 1'b1) begin
					allocation_target_index = i;
				end
			end

			if (allocation_target_index < 0) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Transaction %0d produced no allocation target"
						},
						transaction_number
					)
				)
			end

			// Remaining final candidates decay
			expected_decay_mask = final_lfsr_target_mask;
			expected_decay_mask[allocation_target_index] = 1'b0;

			// Confirm provider valid data
			if ((req.commit_tagged_indices_i[provider_index] == '0) || (req.commit_tagged_tags_i[provider_index] == '0)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Provider T%0d has a zero index or tag"
						},
						req.provider_id_i
					)
				)
			end

			// Confirm target valid data
			if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin
				`uvm_fatal(
					"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Allocation target T%0d has a zero index or tag"
						},
						allocation_target_index + 1
					)
				)
			end
			finish_item(req);

			`uvm_info(
				"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
				$sformatf(
					{
						"Transaction %0d of %0d: ",
						"provider=T%0d candidate_mask=0b%0b ",
						"LFSR=0b%0b filtered_mask=0b%0b ",
						"fallback_used=%0b final_mask=0b%0b ",
						"allocation_target=T%0d decay_mask=0b%0b"
					},
					transaction_number + 1,
					NUM_TRANSACTIONS,
					req.provider_id_i,
					available_eligible_mask,
					req.current_LFSR_value_input,
					lfsr_candidate_mask,
					(lfsr_candidate_mask == '0),
					final_lfsr_target_mask,
					allocation_target_index + 1,
					expected_decay_mask
				),
				UVM_LOW
			)

			// Back-to-back bursts with 1 idle cycle in between
			if ((transaction_number == 4) || (transaction_number == 9) || (transaction_number == 13)) begin
				send_idle_cycles(1);
				`uvm_info(
					"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
					$sformatf(
						{
							"Inserted one idle cycle after ",
							"transaction %0d"
						},
						transaction_number + 1
					),
					UVM_LOW
				)
			end
		end
		`uvm_info(
			"TAGGED_MISPRED_MULTI_VARIABLE_LFSR_SEQ",
			{
				"Completed seventeen T1-through-T6 mispredictions with ",
				"multiple higher candidates and variable LFSR values"
			},
			UVM_LOW
		)
	endtask
endclass


/// tagged table T7 provides the misprediction so checking with variable LFSRs and table_empty_mask_i
class provider_update_T7_misprediction_variable_lfsr_and_empty_mask_sequence  extends provider_update_base_sequence;

    `uvm_object_utils(provider_update_T7_misprediction_variable_lfsr_and_empty_mask_sequence)

    localparam int NUM_TRANSACTIONS = 12;

    function new(string name = "provider_update_T7_misprediction_variable_lfsr_and_empty_mask_sequence");
        super.new(name);
    endfunction

    virtual task body();

        provider_update_seq_item req;
        tagged_table_mask_t table_empty_masks [0:NUM_TRANSACTIONS-1];
        tagged_table_mask_t lfsr_values [0:NUM_TRANSACTIONS-1];

        int T7_table_index;

        // T7 is array index 6 when NUM_TAGGED_TABLES is seven.
        T7_table_index = NUM_TAGGED_TABLES - 1;

        `uvm_info("T7_MISPRED_VARIABLE_MASK_SEQ",
            {
                "Starting T7-provider misprediction sequence with ",
                "variable LFSR and table-empty-mask values"
            },
            UVM_LOW
        )

        if (NUM_TAGGED_TABLES != 7) begin

            `uvm_fatal("T7_MISPRED_VARIABLE_MASK_SEQ",
                $sformatf(
                    {
                        "This sequence expects NUM_TAGGED_TABLES=7, ",
                        "but the configured value is %0d"
                    },
                    NUM_TAGGED_TABLES
                )
            )
        end


        // Variable table-empty masks covering following cases:
        //   - All zeros
        //   - All ones
        //   - Every one-hot table position
        //   - Alternating patterns
        //   - Multibit patterns
        table_empty_masks[0]  = 7'b000_0000;
        table_empty_masks[1]  = 7'b111_1111;

        table_empty_masks[2]  = 7'b000_0001; 		// T1 available
        table_empty_masks[3]  = 7'b000_0010; 		// T2 available
        table_empty_masks[4]  = 7'b000_0100; 		// T3 available
        table_empty_masks[5]  = 7'b000_1000; 		// T4 available
        table_empty_masks[6]  = 7'b001_0000; 		// T5 available
        table_empty_masks[7]  = 7'b010_0000; 		// T6 available
        table_empty_masks[8]  = 7'b100_0000; 		// T7 available

        table_empty_masks[9]  = 7'b101_0101;
        table_empty_masks[10] = 7'b010_1010;
        table_empty_masks[11] = 7'b110_1001;


        // Variable LFSR values -I am expecting that the LFSR must not affect this sequence because the T7 provider has no eligible higher allocation table.

        lfsr_values[0]  = 7'b000_0000;
        lfsr_values[1]  = 7'b111_1111;

        lfsr_values[2]  = 7'b111_1111;
        lfsr_values[3]  = 7'b000_0000;
        lfsr_values[4]  = 7'b000_0001;
        lfsr_values[5]  = 7'b000_1000;
        lfsr_values[6]  = 7'b001_0000;
        lfsr_values[7]  = 7'b010_0000;
        lfsr_values[8]  = 7'b000_0000;

        lfsr_values[9]  = 7'b010_1010;
        lfsr_values[10] = 7'b101_0101;
        lfsr_values[11] = 7'b110_0110;


        // Send twelve T7-provider misprediction transactions.
        for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin

            req = provider_update_seq_item::type_id::create($sformatf("T7_mispredict_variable_mask_req_%0d",transaction_number));

            start_item(req);
				req.clear_inputs();
				// Valid T7 misprediction.

				req.commit_valid_i        = 1'b1;
				req.commit_mispredicted_i = 1'b1;
				// T7 is the prediction provider.

				req.provider_id_i = LAST_TAGGED_PROVIDER_ID;

				// Apply variable LFSR and table-empty-mask values.
				req.current_LFSR_value_input = lfsr_values[transaction_number];
				req.table_empty_mask_i = table_empty_masks[transaction_number];

				// The base table is not the provider.
				req.commit_base_idx_i = '0;

				// Supply valid nonzero indices and tags for every tagged table.Only T7's index and tag should be forwarded for PENALIZE.

				for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

					req.commit_tagged_indices_i[i] = tagged_index_t'(7'h10 + (transaction_number * NUM_TAGGED_TABLES) + i);
					req.commit_tagged_tags_i[i] = tagged_tag_t'(16'hE000 + (transaction_number * 16'h0100) + i + 1);

				end

				// Verify the provider is the last tagged table.
				if (req.provider_id_i != LAST_TAGGED_PROVIDER_ID) begin

					`uvm_fatal("T7_MISPRED_VARIABLE_MASK_SEQ",
						$sformatf(
							{
								"Expected T7 provider ID=%0d, received %0d"
							},
							LAST_TAGGED_PROVIDER_ID,
							req.provider_id_i
						)
					)
				end

				// Verify that T7 has valid nonzero data.
				if ((req.commit_tagged_indices_i[T7_table_index] == '0) || (req.commit_tagged_tags_i[T7_table_index] == '0)) begin

					`uvm_fatal("T7_MISPRED_VARIABLE_MASK_SEQ","T7 must have a valid nonzero index and tag")

				end

            finish_item(req);


            `uvm_info(
                "T7_MISPRED_VARIABLE_MASK_SEQ",
                $sformatf(
                    {
                        "Transaction %0d of %0d: ",
                        "provider=T7 T7_idx=0x%0h T7_tag=0x%0h ",
                        "table_empty_mask=0b%0b LFSR=0b%0b"
                    },
                    transaction_number + 1,
                    NUM_TRANSACTIONS,
                    req.commit_tagged_indices_i[T7_table_index],
                    req.commit_tagged_tags_i[T7_table_index],
                    req.table_empty_mask_i,
                    req.current_LFSR_value_input
                ),
                UVM_LOW
            )

            if ((transaction_number == 3) || (transaction_number == 7)) begin

                send_idle_cycles(1);

                `uvm_info("T7_MISPRED_VARIABLE_MASK_SEQ",
                    $sformatf(
                        {
                            "Inserted one idle cycle after ",
                            "transaction %0d"
                        },
                        transaction_number + 1
                    ),
                    UVM_LOW
                )
            end
        end

        `uvm_info("T7_MISPRED_VARIABLE_MASK_SEQ",
            {
                "Completed twelve T7-provider mispredictions with ",
                "variable LFSR and table-empty-mask values"
            },
            UVM_LOW
        )

    endtask

endclass


//// constrianed random sequnence for back 2 back transaction, inthis we are covering the following
// Sends 20 back-to-back transactions with no idle cycles.
// Randomly selects Base/T0 or tagged providers T1–T6.
// Excludes T7 because it cannot allocate to a higher table.
// Guarantees every provider from Base/T0 through T6 appears at least once.
// Uses a nonzero LFSR.
// Guarantees at least one LFSR-selected higher allocation candidate.
// Allows one or multiple final LFSR candidates.
// Checks allocation and decay behavior through the scoreboard.
class provider_update_constrained_random_back_to_back_allocation_sequence extends provider_update_base_sequence;

    `uvm_object_utils(provider_update_constrained_random_back_to_back_allocation_sequence)

    localparam int NUM_TRANSACTIONS = 20;

    function new(string name = "provider_update_constrained_random_back_to_back_allocation_sequence");
        super.new(name);
    endfunction

    virtual task body();

        provider_update_seq_item req;

        provider_id_t guaranteed_provider_order [0:NUM_TAGGED_TABLES-1];

        provider_id_t temporary_provider;
        provider_id_t selected_provider;

        tagged_table_mask_t eligibility_mask;
        tagged_table_mask_t available_eligible_mask;
        tagged_table_mask_t lfsr_candidate_mask;
        tagged_table_mask_t final_lfsr_target_mask;
        tagged_table_mask_t expected_decay_mask;

        int provider_index;
        int allocation_target_index;
        int random_position;
        int candidate_count;
        int final_candidate_count;

        int provider_hit_count [0:NUM_TAGGED_TABLES-1];

        `uvm_info("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
            {
                "Starting constrained-random back-to-back allocation ",
                "sequence with Base/T0 through T6 providers"
            },
            UVM_LOW
        )

        if (NUM_TAGGED_TABLES != 7) begin

            `uvm_fatal("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                $sformatf(
                    {
                        "This sequence expects NUM_TAGGED_TABLES=7, ",
                        "but the configured value is %0d"
                    },
                    NUM_TAGGED_TABLES
                )
            )
        end


        // Initialize the guaranteed provider order.
        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            guaranteed_provider_order[i] = provider_id_t'(i);
            provider_hit_count[i] = 0;
        end


        // Randomize the order of the guaranteed providers.
        for (int i = NUM_TAGGED_TABLES - 1; i > 0; i--) begin
            random_position = $urandom_range(i, 0);
            temporary_provider = guaranteed_provider_order[i];
            guaranteed_provider_order[i] = guaranteed_provider_order[random_position];
            guaranteed_provider_order[random_position] = temporary_provider;
        end


        // Sending back-to-back allocation transactions.
        for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin

            if (transaction_number < NUM_TAGGED_TABLES) begin
                selected_provider = guaranteed_provider_order[transaction_number];
            end
            else begin
                selected_provider = provider_id_t'($urandom_range(NUM_TAGGED_TABLES - 1,BASE_PROVIDER_ID));
            end

            req = provider_update_seq_item::type_id::create($sformatf("constrained_random_b2b_alloc_req_%0d",transaction_number));

            start_item(req);
            req.clear_inputs();


            // Constrained-random allocation transaction.
            if (!req.randomize() with {

                commit_valid_i        == 1'b1;
                commit_mispredicted_i == 1'b1;
                provider_id_i == selected_provider;
                current_LFSR_value_input != '0;

                table_empty_mask_i != '0;

                (table_empty_mask_i & current_LFSR_value_input) != '0;

                foreach (table_empty_mask_i[i]) {

                    if ((i + 1) <= provider_id_i) {
                        table_empty_mask_i[i] == 1'b0;
                    }
                }

                commit_base_idx_i != '0;

                foreach (commit_tagged_indices_i[i]) {
                    commit_tagged_indices_i[i] != '0;
                }

                foreach (commit_tagged_tags_i[i]) {
                    commit_tagged_tags_i[i] != '0;
                }

            }) begin

                `uvm_fatal("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Failed to randomize transaction %0d ",
                            "for provider ID %0d"
                        },
                        transaction_number,
                        selected_provider
                    )
                )
            end


            // Construct the expected eligibility mask.
            eligibility_mask = '0;

            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
                if ((i + 1) > int'(req.provider_id_i)) begin
                    eligibility_mask[i] = 1'b1;
                end
            end

            // Calculate the available and eligible allocation candidates.
            available_eligible_mask = req.table_empty_mask_i & eligibility_mask;

            // Apply the nonzero LFSR. This sequence guarantees that the intersection is nonzero,
            // so the fallback path is not expected.
            lfsr_candidate_mask = available_eligible_mask & req.current_LFSR_value_input;

            if (lfsr_candidate_mask == '0) begin

                `uvm_fatal("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d unexpectedly produced a ",
                            "zero LFSR candidate mask: available=0b%0b, ",
                            "LFSR=0b%0b"
                        },
                        transaction_number,
                        available_eligible_mask,
                        req.current_LFSR_value_input
                    )
                )
            end

            final_lfsr_target_mask = lfsr_candidate_mask;

            // Find the deepest final LFSR target.
            allocation_target_index = -1;

            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                if (final_lfsr_target_mask[i] === 1'b1) begin
                    allocation_target_index = i;
                end

            end

            if (allocation_target_index < 0) begin

                `uvm_fatal("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d produced no allocation target"
                        },
                        transaction_number
                    )
                )
            end

            // Every remaining final candidate recieves a DECAY.
            expected_decay_mask = final_lfsr_target_mask;

            expected_decay_mask[allocation_target_index] = 1'b0;

            // info for logging.
            candidate_count = $countones(available_eligible_mask);
            final_candidate_count = $countones(final_lfsr_target_mask);

            if (req.provider_id_i == BASE_PROVIDER_ID) begin
                provider_index = -1;
            end
            else begin
                provider_index = int'(req.provider_id_i) - 1;
            end


            // Confirm valid provider data for a tagged provider.
            if (provider_index >= 0) begin

                if ((req.commit_tagged_indices_i[provider_index] == '0) || (req.commit_tagged_tags_i[provider_index] == '0)) begin

                    `uvm_fatal("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Provider T%0d has a zero index or tag"
                            },
                            req.provider_id_i
                        )
                    )

                end

            end

            // Confirm valid data for the allocation target.
            if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin

                `uvm_fatal("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Allocation target T%0d has a zero ",
                            "index or tag"
                        },
                        allocation_target_index + 1
                    )
                )
            end

            finish_item(req);

            provider_hit_count[int'(req.provider_id_i)]++;

            `uvm_info("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                $sformatf(
                    {
                        "Transaction %0d of %0d: ",
                        "provider=%s%0d ",
                        "available_mask=0b%0b candidate_count=%0d ",
                        "LFSR=0b%0b final_mask=0b%0b ",
                        "final_count=%0d allocation_target=T%0d ",
                        "decay_mask=0b%0b"
                    },
                    transaction_number + 1,
                    NUM_TRANSACTIONS,
                    (req.provider_id_i == BASE_PROVIDER_ID) ? "Base/T" : "T",
                    req.provider_id_i,
                    available_eligible_mask,
                    candidate_count,
                    req.current_LFSR_value_input,
                    final_lfsr_target_mask,
                    final_candidate_count,
                    allocation_target_index + 1,
                    expected_decay_mask
                ),
                UVM_LOW
            )

        end


        // Confirm that Base/T0 through T6 were each selected at least once.
        for (int provider_number = 0; provider_number < NUM_TAGGED_TABLES; provider_number++) begin

            if (provider_hit_count[provider_number] == 0) begin

                `uvm_fatal("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Provider ID %0d was not covered"
                        },
                        provider_number
                    )
                )
            end
            else begin

                `uvm_info("CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Provider ID %0d was selected %0d time(s)"
                        },
                        provider_number,
                        provider_hit_count[provider_number]
                    ),
                    UVM_LOW
                )

            end

        end


        `uvm_info(
            "CONSTRAINED_RANDOM_B2B_ALLOC_SEQ",
            {
                "Completed twenty constrained-random back-to-back ",
                "allocation transactions"
            },
            UVM_LOW
        )

    endtask

endclass


///// alternation sequence for back to back allocate and non-allocate type of transactions
class provider_update_constrained_random_alternating_allocation_no_allocation_sequence extends provider_update_base_sequence;

    `uvm_object_utils(provider_update_constrained_random_alternating_allocation_no_allocation_sequence)

    localparam int NUM_TRANSACTIONS = 20;

    function new(string name = "provider_update_constrained_random_alternating_allocation_no_allocation_sequence");
        super.new(name);
    endfunction

    virtual task body();

        provider_update_seq_item req;

        provider_id_t selected_provider;

        tagged_table_mask_t eligibility_mask;
        tagged_table_mask_t available_eligible_mask;
        tagged_table_mask_t lfsr_candidate_mask;
        tagged_table_mask_t final_lfsr_target_mask;
        tagged_table_mask_t expected_decay_mask;

        bit allocation_transaction;

        int provider_index;
        int allocation_target_index;
        int allocation_transaction_count;
        int no_allocation_transaction_count;

        allocation_transaction_count = 0;
        no_allocation_transaction_count = 0;

        `uvm_info("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
            {
                "Starting constrained-random back-to-back sequence ",
                "alternating allocation and no-allocation transactions"
            },
            UVM_LOW
        )

        if (NUM_TAGGED_TABLES != 7) begin

            `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                $sformatf(
                    {
                        "This sequence expects NUM_TAGGED_TABLES=7, ",
                        "but the configured value is %0d"
                    },
                    NUM_TAGGED_TABLES
                )
            )
        end


        // Send back-to-back transactions alternating between the allocation
        // and no-allocation paths.
        for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin

            allocation_transaction = ((transaction_number % 2) == 0);

            // Allocation requires a provider from Base/T0 through T6.
            // T7 is excluded because it has no higher allocation table.
            if (allocation_transaction) begin
                selected_provider = provider_id_t'($urandom_range(NUM_TAGGED_TABLES - 1,BASE_PROVIDER_ID));
            end
            else begin
                selected_provider = provider_id_t'($urandom_range(LAST_TAGGED_PROVIDER_ID,BASE_PROVIDER_ID));
            end

            req = provider_update_seq_item::type_id::create($sformatf("alternating_alloc_no_alloc_req_%0d",transaction_number));

            start_item(req);
            req.clear_inputs();

            if (allocation_transaction) begin

                // Allocation transaction:
                //
                //   - Valid misprediction
                //   - Provider is Base/T0 through T6
                //   - At least one higher table is available
                //   - Nonzero LFSR
                //   - At least one candidate survives the LFSR
                if (!req.randomize() with {

                    commit_valid_i        == 1'b1;
                    commit_mispredicted_i == 1'b1;
                    provider_id_i         == selected_provider;

                    current_LFSR_value_input != '0;
                    table_empty_mask_i != '0;

                    (table_empty_mask_i & current_LFSR_value_input) != '0;

                    foreach (table_empty_mask_i[i]) {

                        if ((i + 1) <= provider_id_i) {
                            table_empty_mask_i[i] == 1'b0;
                        }
                    }

                    commit_base_idx_i != '0;

                    foreach (commit_tagged_indices_i[i]) {
                        commit_tagged_indices_i[i] != '0;
                    }

                    foreach (commit_tagged_tags_i[i]) {
                        commit_tagged_tags_i[i] != '0;
                    }

                }) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Failed to randomize allocation ",
                                "transaction %0d for provider ID %0d"
                            },
                            transaction_number,
                            selected_provider
                        )
                    )
                end

            end
            else begin

                // No-allocation transaction:
                //
                //   - Base provider uses an all-zero empty mask.
                //   - A tagged provider may have available tables only at or
                //     below its own depth.
                //   - No higher eligible table may be available.
                if (!req.randomize() with {

                    commit_valid_i        == 1'b1;
                    commit_mispredicted_i == 1'b1;
                    provider_id_i         == selected_provider;

                    commit_base_idx_i != '0;

                    if (provider_id_i == BASE_PROVIDER_ID) {
                        table_empty_mask_i == '0;
                    }
                    else {
                        table_empty_mask_i != '0;

                        foreach (table_empty_mask_i[i]) {
                            if ((i + 1) > provider_id_i) {
                                table_empty_mask_i[i] == 1'b0;
                            }
                        }
                    }

                    foreach (commit_tagged_indices_i[i]) {
                        commit_tagged_indices_i[i] != '0;
                    }

                    foreach (commit_tagged_tags_i[i]) {
                        commit_tagged_tags_i[i] != '0;
                    }

                }) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Failed to randomize no-allocation ",
                                "transaction %0d for provider ID %0d"
                            },
                            transaction_number,
                            selected_provider
                        )
                    )
                end
            end


            // Construct the eligibility mask.
            eligibility_mask = '0;

            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
                if ((i + 1) > int'(req.provider_id_i)) begin
                    eligibility_mask[i] = 1'b1;
                end
            end

            available_eligible_mask = req.table_empty_mask_i & eligibility_mask;

            provider_index = -1;

            if (req.provider_id_i != BASE_PROVIDER_ID) begin
                provider_index = int'(req.provider_id_i) - 1;
            end

            if (allocation_transaction) begin

                allocation_transaction_count++;

                // An allocation transaction must have a nonzero eligible mask.
                if (available_eligible_mask == '0) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Allocation transaction %0d produced no ",
                                "available eligible table"
                            },
                            transaction_number
                        )
                    )
                end

                lfsr_candidate_mask = available_eligible_mask & req.current_LFSR_value_input;

                // This sequence constrains at least one candidate to survive.
                if (lfsr_candidate_mask == '0) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Allocation transaction %0d produced a ",
                                "zero LFSR candidate mask"
                            },
                            transaction_number
                        )
                    )
                end

                final_lfsr_target_mask = lfsr_candidate_mask;

                // Select the deepest surviving table.
                allocation_target_index = -1;

                for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                    if (final_lfsr_target_mask[i] === 1'b1) begin
                        allocation_target_index = i;
                    end

                end

                if (allocation_target_index < 0) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Allocation transaction %0d produced no ",
                                "allocation target"
                            },
                            transaction_number
                        )
                    )
                end

                expected_decay_mask = final_lfsr_target_mask;
                expected_decay_mask[allocation_target_index] = 1'b0;

            end
            else begin

                no_allocation_transaction_count++;

                // A no-allocation transaction must not have any available
                // eligible higher table.
                if (available_eligible_mask != '0) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "No-allocation transaction %0d unexpectedly ",
                                "has available eligible mask=0b%0b"
                            },
                            transaction_number,
                            available_eligible_mask
                        )
                    )
                end

                lfsr_candidate_mask = '0;
                final_lfsr_target_mask = '0;
                allocation_target_index = -1;

                // During the no-allocation path, every higher eligible table
                // receives DECAY. The tagged provider separately receives
                // PENALIZE.
                expected_decay_mask = eligibility_mask;
            end


            // Confirm valid data for a tagged provider.
            if (provider_index >= 0) begin

                if ((req.commit_tagged_indices_i[provider_index] == '0) || (req.commit_tagged_tags_i[provider_index] == '0)) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Provider T%0d has a zero index or tag"
                            },
                            req.provider_id_i
                        )
                    )
                end
            end


            // Confirm valid data for an allocation target.
            if (allocation_transaction) begin

                if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin

                    `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                        $sformatf(
                            {
                                "Allocation target T%0d has a zero ",
                                "index or tag"
                            },
                            allocation_target_index + 1
                        )
                    )
                end
            end

            finish_item(req);


            if (allocation_transaction) begin

                `uvm_info("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d of %0d: ALLOCATION ",
                            "provider=%s%0d available_mask=0b%0b ",
                            "LFSR=0b%0b final_mask=0b%0b ",
                            "allocation_target=T%0d decay_mask=0b%0b"
                        },
                        transaction_number + 1,
                        NUM_TRANSACTIONS,
                        (req.provider_id_i == BASE_PROVIDER_ID) ? "Base/T" : "T",
                        req.provider_id_i,
                        available_eligible_mask,
                        req.current_LFSR_value_input,
                        final_lfsr_target_mask,
                        allocation_target_index + 1,
                        expected_decay_mask
                    ),
                    UVM_LOW
                )

            end
            else begin

                `uvm_info("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d of %0d: NO ALLOCATION ",
                            "provider=%s%0d table_empty_mask=0b%0b ",
                            "eligibility_mask=0b%0b ",
                            "expected_decay_mask=0b%0b"
                        },
                        transaction_number + 1,
                        NUM_TRANSACTIONS,
                        (req.provider_id_i == BASE_PROVIDER_ID) ? "Base/T" : "T",
                        req.provider_id_i,
                        req.table_empty_mask_i,
                        eligibility_mask,
                        expected_decay_mask
                    ),
                    UVM_LOW
                )

            end

            // Intentionally no idle cycles between transactions.

        end


        if (allocation_transaction_count != (NUM_TRANSACTIONS / 2)) begin

            `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                $sformatf(
                    {
                        "Expected %0d allocation transactions, observed %0d"
                    },
                    NUM_TRANSACTIONS / 2,
                    allocation_transaction_count
                )
            )
        end

        if (no_allocation_transaction_count != (NUM_TRANSACTIONS / 2)) begin

            `uvm_fatal("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
                $sformatf(
                    {
                        "Expected %0d no-allocation transactions, observed %0d"
                    },
                    NUM_TRANSACTIONS / 2,
                    no_allocation_transaction_count
                )
            )
        end


        `uvm_info("ALTERNATING_ALLOC_NO_ALLOC_SEQ",
            {
                "Completed twenty back-to-back transactions alternating ",
                "between allocation and no-allocation paths"
            },
            UVM_LOW
        )

    endtask

endclass


/// misprediction and correct prediction on back 2 back consecutive cycles
class provider_update_constrained_random_alternating_correct_misprediction_sequence extends provider_update_base_sequence;

    `uvm_object_utils(provider_update_constrained_random_alternating_correct_misprediction_sequence)

    localparam int NUM_TRANSACTIONS = 20;

    function new(string name = "provider_update_constrained_random_alternating_correct_misprediction_sequence");
        super.new(name);
    endfunction

    virtual task body();

        provider_update_seq_item req;

        provider_id_t guaranteed_correct_provider_order [0:NUM_PROVIDERS-1];

        provider_id_t temporary_provider;
        provider_id_t selected_provider;

        tagged_table_mask_t eligibility_mask;
        tagged_table_mask_t available_eligible_mask;
        tagged_table_mask_t lfsr_candidate_mask;
        tagged_table_mask_t final_lfsr_target_mask;
        tagged_table_mask_t expected_decay_mask;

        bit correct_prediction_transaction;
        bit allocation_misprediction;

        int provider_index;
        int allocation_target_index;
        int random_position;
        int correct_transaction_number;
        int misprediction_number;

        int correct_prediction_count;
        int misprediction_count;
        int allocation_misprediction_count;
        int no_allocation_misprediction_count;

        correct_prediction_count = 0;
        misprediction_count = 0;
        allocation_misprediction_count = 0;
        no_allocation_misprediction_count = 0;

        `uvm_info("ALTERNATING_CORRECT_MISPRED_SEQ",
            {
                "Starting constrained-random back-to-back sequence ",
                "alternating correct predictions and mispredictions"
            },
            UVM_LOW
        )

        if (NUM_TAGGED_TABLES != 7) begin

            `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                $sformatf(
                    {
                        "This sequence expects NUM_TAGGED_TABLES=7, ",
                        "but the configured value is %0d"
                    },
                    NUM_TAGGED_TABLES
                )
            )
        end


        // Initialize and randomize the guaranteed correct-prediction provider order.
        for (int i = 0; i < NUM_PROVIDERS; i++) begin
            guaranteed_correct_provider_order[i] = provider_id_t'(i);
        end

        for (int i = NUM_PROVIDERS - 1; i > 0; i--) begin
            random_position = $urandom_range(i,0);
            temporary_provider = guaranteed_correct_provider_order[i];
            guaranteed_correct_provider_order[i] = guaranteed_correct_provider_order[random_position];
            guaranteed_correct_provider_order[random_position] = temporary_provider;
        end


        // Send alternating correct-prediction and misprediction transactions.
        for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin

            correct_prediction_transaction = ((transaction_number % 2) == 0);

            eligibility_mask = '0;
            available_eligible_mask = '0;
            lfsr_candidate_mask = '0;
            final_lfsr_target_mask = '0;
            expected_decay_mask = '0;
            allocation_target_index = -1;
            provider_index = -1;

            if (correct_prediction_transaction) begin

                correct_transaction_number = transaction_number / 2;

                // Guarantee that Base/T0 through T7 are each used for a correct
                // prediction before selecting additional random providers.
                if (correct_transaction_number < NUM_PROVIDERS) begin
                    selected_provider = guaranteed_correct_provider_order[correct_transaction_number];
                end
                else begin
                    selected_provider = provider_id_t'($urandom_range(LAST_TAGGED_PROVIDER_ID,BASE_PROVIDER_ID));
                end

            end
            else begin

                misprediction_number = transaction_number / 2;

                // Alternate the misprediction path between allocation and
                // no allocation.
                allocation_misprediction = ((misprediction_number % 2) == 0);

                if (allocation_misprediction) begin
                    selected_provider = provider_id_t'($urandom_range(NUM_TAGGED_TABLES - 1,BASE_PROVIDER_ID));
                end
                else begin
                    selected_provider = provider_id_t'($urandom_range(LAST_TAGGED_PROVIDER_ID,BASE_PROVIDER_ID));
                end

            end


            req = provider_update_seq_item::type_id::create($sformatf("alternating_correct_mispredict_req_%0d",transaction_number));

            start_item(req);
            req.clear_inputs();


            if (correct_prediction_transaction) begin

                // Correct-prediction transaction:
                //
                //   - Base/T0 provider updates through the base interface.
                //   - Tagged provider receives CMD_REWARD.
                if (!req.randomize() with {

                    commit_valid_i        == 1'b1;
                    commit_mispredicted_i == 1'b0;
                    provider_id_i         == selected_provider;

                    current_LFSR_value_input == '0;
                    table_empty_mask_i == '0;

                    commit_base_idx_i != '0;

                    foreach (commit_tagged_indices_i[i]) {
                        commit_tagged_indices_i[i] != '0;
                    }

                    foreach (commit_tagged_tags_i[i]) {
                        commit_tagged_tags_i[i] != '0;
                    }

                }) begin

                    `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                        $sformatf(
                            {
                                "Failed to randomize correct-prediction ",
                                "transaction %0d for provider ID %0d"
                            },
                            transaction_number,
                            selected_provider
                        )
                    )
                end

                correct_prediction_count++;

            end
            else if (allocation_misprediction) begin

                // Allocation misprediction:
                //
                //   - Provider is Base/T0 through T6.
                //   - At least one higher candidate survives the LFSR.
                if (!req.randomize() with {

                    commit_valid_i        == 1'b1;
                    commit_mispredicted_i == 1'b1;
                    provider_id_i         == selected_provider;

                    current_LFSR_value_input != '0;
                    table_empty_mask_i != '0;

                    (table_empty_mask_i & current_LFSR_value_input) != '0;

                    foreach (table_empty_mask_i[i]) {

                        if ((i + 1) <= provider_id_i) {
                            table_empty_mask_i[i] == 1'b0;
                        }
                    }

                    commit_base_idx_i != '0;

                    foreach (commit_tagged_indices_i[i]) {
                        commit_tagged_indices_i[i] != '0;
                    }

                    foreach (commit_tagged_tags_i[i]) {
                        commit_tagged_tags_i[i] != '0;
                    }

                }) begin

                    `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                        $sformatf(
                            {
                                "Failed to randomize allocation ",
                                "misprediction %0d for provider ID %0d"
                            },
                            transaction_number,
                            selected_provider
                        )
                    )
                end

                misprediction_count++;
                allocation_misprediction_count++;

            end
            else begin

                // No-allocation misprediction:
                //
                //   - Base provider uses an all-zero empty mask.
                //   - Tagged providers may have available tables only at or
                //     below their provider depth.
                if (!req.randomize() with {

                    commit_valid_i        == 1'b1;
                    commit_mispredicted_i == 1'b1;
                    provider_id_i         == selected_provider;

                    commit_base_idx_i != '0;

                    if (provider_id_i == BASE_PROVIDER_ID) {
                        table_empty_mask_i == '0;
                    }
                    else {
                        table_empty_mask_i != '0;

                        foreach (table_empty_mask_i[i]) {

                            if ((i + 1) > provider_id_i) {
                                table_empty_mask_i[i] == 1'b0;
                            }
                        }
                    }

                    foreach (commit_tagged_indices_i[i]) {
                        commit_tagged_indices_i[i] != '0;
                    }

                    foreach (commit_tagged_tags_i[i]) {
                        commit_tagged_tags_i[i] != '0;
                    }

                }) begin

                    `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                        $sformatf(
                            {
                                "Failed to randomize no-allocation ",
                                "misprediction %0d for provider ID %0d"
                            },
                            transaction_number,
                            selected_provider
                        )
                    )
                end

                misprediction_count++;
                no_allocation_misprediction_count++;

            end


            if (req.provider_id_i != BASE_PROVIDER_ID) begin
                provider_index = int'(req.provider_id_i) - 1;
            end


            // Confirm valid data for a tagged provider.
            if (provider_index >= 0) begin

                if ((req.commit_tagged_indices_i[provider_index] == '0) || (req.commit_tagged_tags_i[provider_index] == '0)) begin

                    `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                        $sformatf(
                            {
                                "Provider T%0d has a zero index or tag"
                            },
                            req.provider_id_i
                        )
                    )
                end

            end


            if (!correct_prediction_transaction) begin

                // Construct the expected eligibility and available masks.
                for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                    if ((i + 1) > int'(req.provider_id_i)) begin
                        eligibility_mask[i] = 1'b1;
                    end

                end

                available_eligible_mask = req.table_empty_mask_i & eligibility_mask;


                if (allocation_misprediction) begin

                    if (available_eligible_mask == '0) begin

                        `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                            $sformatf(
                                {
                                    "Allocation misprediction %0d produced ",
                                    "no available eligible candidate"
                                },
                                transaction_number
                            )
                        )
                    end

                    lfsr_candidate_mask = available_eligible_mask & req.current_LFSR_value_input;

                    if (lfsr_candidate_mask == '0) begin

                        `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                            $sformatf(
                                {
                                    "Allocation misprediction %0d produced ",
                                    "a zero LFSR candidate mask"
                                },
                                transaction_number
                            )
                        )
                    end

                    final_lfsr_target_mask = lfsr_candidate_mask;

                    for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                        if (final_lfsr_target_mask[i] === 1'b1) begin
                            allocation_target_index = i;
                        end

                    end

                    if (allocation_target_index < 0) begin

                        `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                            $sformatf(
                                {
                                    "Allocation misprediction %0d produced ",
                                    "no allocation target"
                                },
                                transaction_number
                            )
                        )
                    end

                    expected_decay_mask = final_lfsr_target_mask;
                    expected_decay_mask[allocation_target_index] = 1'b0;


                    if ((req.commit_tagged_indices_i[allocation_target_index] == '0) || (req.commit_tagged_tags_i[allocation_target_index] == '0)) begin

                        `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                            $sformatf(
                                {
                                    "Allocation target T%0d has a zero ",
                                    "index or tag"
                                },
                                allocation_target_index + 1
                            )
                        )
                    end

                end
                else begin

                    if (available_eligible_mask != '0) begin

                        `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                            $sformatf(
                                {
                                    "No-allocation misprediction %0d has ",
                                    "available eligible mask=0b%0b"
                                },
                                transaction_number,
                                available_eligible_mask
                            )
                        )
                    end

                    expected_decay_mask = eligibility_mask;

                end

            end

            finish_item(req);


            if (correct_prediction_transaction) begin

                `uvm_info("ALTERNATING_CORRECT_MISPRED_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d of %0d: CORRECT PREDICTION ",
                            "provider=%s%0d expected_action=%s"
                        },
                        transaction_number + 1,
                        NUM_TRANSACTIONS,
                        (req.provider_id_i == BASE_PROVIDER_ID) ? "Base/T" : "T",
                        req.provider_id_i,
                        (req.provider_id_i == BASE_PROVIDER_ID) ? "BASE_UPDATE" : "CMD_REWARD"
                    ),
                    UVM_LOW
                )

            end
            else if (allocation_misprediction) begin

                `uvm_info("ALTERNATING_CORRECT_MISPRED_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d of %0d: MISPREDICTION/ALLOCATION ",
                            "provider=%s%0d available_mask=0b%0b ",
                            "LFSR=0b%0b final_mask=0b%0b ",
                            "allocation_target=T%0d decay_mask=0b%0b"
                        },
                        transaction_number + 1,
                        NUM_TRANSACTIONS,
                        (req.provider_id_i == BASE_PROVIDER_ID) ? "Base/T" : "T",
                        req.provider_id_i,
                        available_eligible_mask,
                        req.current_LFSR_value_input,
                        final_lfsr_target_mask,
                        allocation_target_index + 1,
                        expected_decay_mask
                    ),
                    UVM_LOW
                )

            end
            else begin

                `uvm_info("ALTERNATING_CORRECT_MISPRED_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d of %0d: MISPREDICTION/NO-ALLOCATION ",
                            "provider=%s%0d empty_mask=0b%0b ",
                            "eligibility_mask=0b%0b decay_mask=0b%0b"
                        },
                        transaction_number + 1,
                        NUM_TRANSACTIONS,
                        (req.provider_id_i == BASE_PROVIDER_ID) ? "Base/T" : "T",
                        req.provider_id_i,
                        req.table_empty_mask_i,
                        eligibility_mask,
                        expected_decay_mask
                    ),
                    UVM_LOW
                )

            end

            // Intentionally no idle cycles between transactions.

        end


        if (correct_prediction_count != (NUM_TRANSACTIONS / 2)) begin

            `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                $sformatf(
                    {
                        "Expected %0d correct predictions, observed %0d"
                    },
                    NUM_TRANSACTIONS / 2,
                    correct_prediction_count
                )
            )
        end

        if (misprediction_count != (NUM_TRANSACTIONS / 2)) begin

            `uvm_fatal("ALTERNATING_CORRECT_MISPRED_SEQ",
                $sformatf(
                    {
                        "Expected %0d mispredictions, observed %0d"
                    },
                    NUM_TRANSACTIONS / 2,
                    misprediction_count
                )
            )
        end


        `uvm_info("ALTERNATING_CORRECT_MISPRED_SEQ",
            $sformatf(
                {
                    "Completed %0d back-to-back transactions: ",
                    "correct=%0d mispredictions=%0d ",
                    "allocation_mispredictions=%0d ",
                    "no_allocation_mispredictions=%0d"
                },
                NUM_TRANSACTIONS,
                correct_prediction_count,
                misprediction_count,
                allocation_misprediction_count,
                no_allocation_misprediction_count
            ),
            UVM_LOW
        )

    endtask

endclass


/// reset interuuption sequence
class provider_update_reset_interruption_during_back_to_back_traffic_sequence extends provider_update_base_sequence;

    `uvm_object_utils(provider_update_reset_interruption_during_back_to_back_traffic_sequence)

    localparam int NUM_TRANSACTIONS = 12;
    localparam int RESET_AFTER_TRANSACTION = 6;
    localparam int INTERRUPT_RESET_CYCLES = 3;

    function new(string name = "provider_update_reset_interruption_during_back_to_back_traffic_sequence");
        super.new(name);
    endfunction

    virtual task body();

        provider_update_seq_item req;

        virtual provider_update_if vif;

        provider_id_t selected_provider;

        tagged_table_mask_t eligibility_mask;
        tagged_table_mask_t available_eligible_mask;
        tagged_table_mask_t lfsr_candidate_mask;

        int allocation_target_index;
        int pre_reset_transaction_count;
        int post_reset_transaction_count;

        pre_reset_transaction_count = 0;
        post_reset_transaction_count = 0;

        `uvm_info("RESET_INTERRUPTION_SEQ",
            {
                "Starting back-to-back allocation traffic with ",
                "a reset interruption"
            },
            UVM_LOW
        )


        if (!uvm_config_db#(virtual provider_update_if)::get(null,"","vif",vif)) begin

            `uvm_fatal("RESET_INTERRUPTION_SEQ",
                "Failed to obtain provider_update_if from uvm_config_db"
            )
        end


        if (NUM_TAGGED_TABLES != 7) begin

            `uvm_fatal("RESET_INTERRUPTION_SEQ",
                $sformatf(
                    {
                        "This sequence expects NUM_TAGGED_TABLES=7, ",
                        "but the configured value is %0d"
                    },
                    NUM_TAGGED_TABLES
                )
            )
        end


        for (int transaction_number = 0; transaction_number < NUM_TRANSACTIONS; transaction_number++) begin


            // Apply reset immediately after the first six back-to-back
            // transactions.
            if (transaction_number == RESET_AFTER_TRANSACTION) begin

                `uvm_info("RESET_INTERRUPTION_SEQ",
                    $sformatf(
                        {
                            "Applying reset for %0d cycles after ",
                            "%0d back-to-back transactions"
                        },
                        INTERRUPT_RESET_CYCLES,
                        pre_reset_transaction_count
                    ),
                    UVM_LOW
                )

                vif.apply_reset(INTERRUPT_RESET_CYCLES);

                `uvm_info("RESET_INTERRUPTION_SEQ",
                    "Reset released; restarting back-to-back traffic",
                    UVM_LOW
                )

            end


            selected_provider = provider_id_t'($urandom_range(NUM_TAGGED_TABLES - 1,BASE_PROVIDER_ID));

            req = provider_update_seq_item::type_id::create($sformatf("reset_interruption_req_%0d",transaction_number));

            start_item(req);
            req.clear_inputs();


            // Generate a valid allocation-path misprediction.
            if (!req.randomize() with {

                commit_valid_i        == 1'b1;
                commit_mispredicted_i == 1'b1;
                provider_id_i         == selected_provider;

                current_LFSR_value_input != '0;
                table_empty_mask_i != '0;

                (table_empty_mask_i & current_LFSR_value_input) != '0;

                foreach (table_empty_mask_i[i]) {

                    if ((i + 1) <= provider_id_i) {
                        table_empty_mask_i[i] == 1'b0;
                    }
                }

                commit_base_idx_i != '0;

                foreach (commit_tagged_indices_i[i]) {
                    commit_tagged_indices_i[i] != '0;
                }

                foreach (commit_tagged_tags_i[i]) {
                    commit_tagged_tags_i[i] != '0;
                }

            }) begin

                `uvm_fatal("RESET_INTERRUPTION_SEQ",
                    $sformatf(
                        {
                            "Failed to randomize transaction %0d ",
                            "for provider ID %0d"
                        },
                        transaction_number,
                        selected_provider
                    )
                )
            end


            eligibility_mask = '0;

            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                if ((i + 1) > int'(req.provider_id_i)) begin
                    eligibility_mask[i] = 1'b1;
                end

            end

            available_eligible_mask = req.table_empty_mask_i & eligibility_mask;
            lfsr_candidate_mask = available_eligible_mask & req.current_LFSR_value_input;


            if (lfsr_candidate_mask == '0) begin

                `uvm_fatal("RESET_INTERRUPTION_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d produced a zero ",
                            "LFSR candidate mask"
                        },
                        transaction_number
                    )
                )
            end


            allocation_target_index = -1;

            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                if (lfsr_candidate_mask[i] === 1'b1) begin
                    allocation_target_index = i;
                end

            end


            if (allocation_target_index < 0) begin

                `uvm_fatal("RESET_INTERRUPTION_SEQ",
                    $sformatf(
                        {
                            "Transaction %0d produced no allocation target"
                        },
                        transaction_number
                    )
                )
            end

            finish_item(req);


            if (transaction_number < RESET_AFTER_TRANSACTION) begin
                pre_reset_transaction_count++;
            end
            else begin
                post_reset_transaction_count++;
            end


            `uvm_info("RESET_INTERRUPTION_SEQ",
                $sformatf(
                    {
                        "Transaction %0d of %0d: phase=%s ",
                        "provider=%s%0d available_mask=0b%0b ",
                        "LFSR=0b%0b allocation_target=T%0d"
                    },
                    transaction_number + 1,
                    NUM_TRANSACTIONS,
                    (transaction_number < RESET_AFTER_TRANSACTION) ? "PRE_RESET" : "POST_RESET",
                    (req.provider_id_i == BASE_PROVIDER_ID) ? "Base/T" : "T",
                    req.provider_id_i,
                    available_eligible_mask,
                    req.current_LFSR_value_input,
                    allocation_target_index + 1
                ),
                UVM_LOW
            )


            // No idle cycles are inserted between traffic transactions.

        end


        if (pre_reset_transaction_count != RESET_AFTER_TRANSACTION) begin

            `uvm_fatal("RESET_INTERRUPTION_SEQ",
                $sformatf(
                    {
                        "Expected %0d pre-reset transactions, observed %0d"
                    },
                    RESET_AFTER_TRANSACTION,
                    pre_reset_transaction_count
                )
            )
        end

        if (post_reset_transaction_count != (NUM_TRANSACTIONS - RESET_AFTER_TRANSACTION)) begin

            `uvm_fatal("RESET_INTERRUPTION_SEQ",
                $sformatf(
                    {
                        "Expected %0d post-reset transactions, observed %0d"
                    },
                    NUM_TRANSACTIONS - RESET_AFTER_TRANSACTION,
                    post_reset_transaction_count
                )
            )
        end


        `uvm_info("RESET_INTERRUPTION_SEQ",
            $sformatf(
                {
                    "Completed reset-interruption sequence: ",
                    "pre_reset=%0d post_reset=%0d reset_cycles=%0d"
                },
                pre_reset_transaction_count,
                post_reset_transaction_count,
                INTERRUPT_RESET_CYCLES
            ),
            UVM_LOW
        )

    endtask

endclass
