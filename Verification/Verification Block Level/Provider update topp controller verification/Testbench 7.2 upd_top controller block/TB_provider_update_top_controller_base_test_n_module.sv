`timescale 1ns/1ps

`include "TB_provider_update_top_controller_sequences.sv"
import uvm_pkg::*;
import provider_update_params_pkg::*;


//// test class
class provider_update_base_test extends uvm_test;

`uvm_component_utils(provider_update_base_test)

provider_update_env env;
provider_update_base_table_smoke_correct_prediction_sequence base_smoke_seq;
provider_update_tagged_tables_correct_prediction_smoke_sequence tagged_smoke_seq;
provider_update_idle_clock_gating_sequence idle_seq;
provider_update_base_misprediction_no_allocation_sequence base_misp_no_allocate;
provider_update_T0_mispredictiton_no_allocation_sequence_with_idle_cycle T0_misp_no_allocate;
provider_update_T0_mispredictiton_no_allocation_no_idle_cycle_in_middle_sequence T0_misp_no_allocate_NO_IDLE_CYCLES_IN_btwn;
provider_update_random_middle_tagged_misprediction_no_allocation_sequence misp_no_allocate_middle_tables;
provider_update_random_middle_tagged_misprediction_no_allocation_no_idle_CYCLES_in_middle_sequence misp_no_allocate_middle_tables_NO_IDLE_CYCLES_IN_btwn;
provider_update_last_tagged_table_misprediction_no_allocation_sequence misp_T7_no_allocation;
provider_update_last_tagged_table_misprediction_no_allocation_no_idle_cycles_in_between_sequence misp_T7_no_allocation_no_IDLE_CYCLES;
provider_update_tagged_misprediction_lower_depth_candidates_vector_no_allocation_sequence lower_depth_candidates_available_mask;
provider_update_base_misprediction_single_higher_table_allocation_sequence base_misp_single_higher_allocate;
provider_update_base_misprediction_multiple_higher_tables_allocation_sequence base_misp_multiple_higher_allocate;
provider_update_base_misprediction_multiple_candidates_variable_lfsr_sequence base_misp_multiple_tables_variable_LFSR;
provider_update_tagged_misprediction_single_higher_table_allocation_sequence  tagged_misp_one_higher_table;
provider_update_tagged_misprediction_multiple_higher_tables_zero_lfsr_sequence tagged_misp_multiple_higher_tables;
provider_update_tagged_misprediction_multiple_higher_tables_variable_lfsr_sequence tagged_misp_multiple_higher_tables_var_lfsr;
provider_update_T7_misprediction_variable_lfsr_and_empty_mask_sequence tagged_T7_misp_var_LFSR_n_empty_mask;
provider_update_constrained_random_back_to_back_allocation_sequence constrained_random_seq;
provider_update_constrained_random_alternating_allocation_no_allocation_sequence constrained_allocation_non_allocate_seq;
provider_update_constrained_random_alternating_correct_misprediction_sequence constrained_random_correct_mispredicted_seq;
provider_update_reset_interruption_during_back_to_back_traffic_sequence  reset_seq;


function new(string name = "provider_update_base_test",uvm_component parent = null);
	super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
	super.build_phase(phase);
	uvm_config_db#(uvm_active_passive_enum)::set(this,"env.agent","is_active",UVM_ACTIVE);
	env = provider_update_env::type_id::create("env",this);
endfunction

virtual function void end_of_elaboration_phase(uvm_phase phase);
	super.end_of_elaboration_phase(phase);
	uvm_root::get().print_topology();
endfunction

virtual task run_phase(uvm_phase phase);

	phase.raise_objection(this);
	
	// base_smoke_seq = provider_update_base_table_smoke_correct_prediction_sequence::type_id::create("base_smoke_seq");
	// base_smoke_seq.start(env.agent.sequencer);
	
	// tagged_smoke_seq = provider_update_tagged_tables_correct_prediction_smoke_sequence::type_id::create("tagged_smoke_seq");
	// tagged_smoke_seq.start(env.agent.sequencer);

	// idle_seq = provider_update_idle_clock_gating_sequence::type_id::create("idle_seq");
	// idle_seq.start(env.agent.sequencer);

	// base_misp_no_allocate = provider_update_base_misprediction_no_allocation_sequence::type_id::create("base_misp_no_allocate");
	// base_misp_no_allocate.start(env.agent.sequencer);

	// T0_misp_no_allocate = provider_update_T0_mispredictiton_no_allocation_sequence_with_idle_cycle::type_id::create("T0_misp_no_allocate");
	// T0_misp_no_allocate.start(env.agent.sequencer);

	// T0_misp_no_allocate_NO_IDLE_CYCLES_IN_btwn = provider_update_T0_mispredictiton_no_allocation_no_idle_cycle_in_middle_sequence::type_id::create("T0_misp_no_allocate_NO_IDLE_CYCLES_IN_btwn");
	// T0_misp_no_allocate_NO_IDLE_CYCLES_IN_btwn.start(env.agent.sequencer);

	// misp_no_allocate_middle_tables = provider_update_random_middle_tagged_misprediction_no_allocation_sequence::type_id::create("misp_no_allocate_middle_tables");
	// misp_no_allocate_middle_tables.start(env.agent.sequencer);

	// misp_no_allocate_middle_tables_NO_IDLE_CYCLES_IN_btwn = provider_update_random_middle_tagged_misprediction_no_allocation_no_idle_CYCLES_in_middle_sequence::type_id::create("misp_no_allocate_middle_tables_NO_IDLE_CYCLES_IN_btwn");
	// misp_no_allocate_middle_tables_NO_IDLE_CYCLES_IN_btwn.start(env.agent.sequencer);

	// misp_T7_no_allocation = provider_update_last_tagged_table_misprediction_no_allocation_sequence::type_id::create("misp_T7_no_allocation");
	// misp_T7_no_allocation.start(env.agent.sequencer);

	// misp_T7_no_allocation_no_IDLE_CYCLES = provider_update_last_tagged_table_misprediction_no_allocation_no_idle_cycles_in_between_sequence::type_id::create("misp_T7_no_allocation_no_IDLE_CYCLES");
	// misp_T7_no_allocation_no_IDLE_CYCLES.start(env.agent.sequencer);

	// lower_depth_candidates_available_mask = provider_update_tagged_misprediction_lower_depth_candidates_vector_no_allocation_sequence::type_id::create("lower_depth_candidates_available_mask");
	// lower_depth_candidates_available_mask.start(env.agent.sequencer);

	// base_misp_single_higher_allocate = provider_update_base_misprediction_single_higher_table_allocation_sequence::type_id::create("base_misp_single_higher_allocate");
	// base_misp_single_higher_allocate.start(env.agent.sequencer);

	// base_misp_multiple_higher_allocate = provider_update_base_misprediction_multiple_higher_tables_allocation_sequence::type_id::create("base_misp_multiple_higher_allocate");
	// base_misp_multiple_higher_allocate.start(env.agent.sequencer);

	// base_misp_multiple_tables_variable_LFSR = provider_update_base_misprediction_multiple_candidates_variable_lfsr_sequence::type_id::create("base_misp_multiple_tables_variable_LFSR");
	// base_misp_multiple_tables_variable_LFSR.start(env.agent.sequencer);

	// tagged_misp_one_higher_table = provider_update_tagged_misprediction_single_higher_table_allocation_sequence::type_id::create("tagged_misp_one_higher_table");
	// tagged_misp_one_higher_table.start(env.agent.sequencer);

	// tagged_misp_multiple_higher_tables = provider_update_tagged_misprediction_multiple_higher_tables_zero_lfsr_sequence::type_id::create("tagged_misp_multiple_higher_tables");
	// tagged_misp_multiple_higher_tables.start(env.agent.sequencer);

	// tagged_misp_multiple_higher_tables_var_lfsr = provider_update_tagged_misprediction_multiple_higher_tables_variable_lfsr_sequence::type_id::create("tagged_misp_multiple_higher_tables_var_lfsr");
	// tagged_misp_multiple_higher_tables_var_lfsr.start(env.agent.sequencer);

	// tagged_T7_misp_var_LFSR_n_empty_mask = provider_update_T7_misprediction_variable_lfsr_and_empty_mask_sequence::type_id::create("tagged_T7_misp_var_LFSR_n_empty_mask");
	// tagged_T7_misp_var_LFSR_n_empty_mask.start(env.agent.sequencer);

	// constrained_random_seq = provider_update_constrained_random_back_to_back_allocation_sequence::type_id::create("constrained_random_seq");
	// constrained_random_seq.start(env.agent.sequencer);

	// constrained_allocation_non_allocate_seq = provider_update_constrained_random_alternating_allocation_no_allocation_sequence::type_id::create("constrained_allocation_non_allocate_seq");
	// constrained_allocation_non_allocate_seq.start(env.agent.sequencer);

	// constrained_random_correct_mispredicted_seq = provider_update_constrained_random_alternating_correct_misprediction_sequence::type_id::create("constrained_random_correct_mispredicted_seq");
	// constrained_random_correct_mispredicted_seq.start(env.agent.sequencer);

	reset_seq = provider_update_reset_interruption_during_back_to_back_traffic_sequence::type_id::create("reset_seq");
	reset_seq.start(env.agent.sequencer);

	phase.phase_done.set_drain_time(this,20ns);
	
	phase.drop_objection(this);
endtask

endclass



// tb top
module provider_update_tb_top;

timeunit      1ns;
timeprecision 1ps;

import uvm_pkg::*;

import provider_update_params_pkg::*;
// import provider_update_tb_pkg::*;

logic clk;
logic rst_n;

provider_update_if provider_vif (
	.clk   (clk),
	.rst_n (rst_n)
);

// FOR CHECKING THE RESET SEQUENCE IN THE DESIGN
// provider_update_if provider_vif (
//     .clk (clk)
// );

LP_provider_update_top_control #(
	.NUM_TAGGED_TABLES (provider_update_params_pkg::NUM_TAGGED_TABLES),
	.PROVIDER_ID_WIDTH (provider_update_params_pkg::PROVIDER_ID_WIDTH),
	.BASE_S_WIDTH (provider_update_params_pkg::BASE_S_WIDTH),
	.S_WIDTH (provider_update_params_pkg::S_WIDTH),
	.T_WIDTH (provider_update_params_pkg::T_WIDTH)
) dut (
	.clk (clk),
	.rst_n (rst_n),
	// .rst_n (provider_vif.rst_n),		// ONLY FOR CHECKING THE RESET SEQUENCE IN THE DESIGN
	.commit_valid_i (provider_vif.commit_valid_i),
	.commit_mispredicted_i (provider_vif.commit_mispredicted_i),
	.provider_id_i (provider_vif.provider_id_i),
	.current_LFSR_value_input (provider_vif.current_LFSR_value_input),
	.table_empty_mask_i (provider_vif.table_empty_mask_i),
	.commit_base_idx_i (provider_vif.commit_base_idx_i),
	.commit_tagged_indices_i (provider_vif.commit_tagged_indices_i),
	.commit_tagged_tags_i (provider_vif.commit_tagged_tags_i),
	.base_update_en_o (provider_vif.base_update_en_o),
	.base_update_idx_o (provider_vif.base_update_idx_o),
	.tagged_table_update_en_o (provider_vif.tagged_table_update_en_o),
	.table_cmd_o (provider_vif.table_cmd_o),
	.update_tagged_indices_o (provider_vif.update_tagged_indices_o),
	.update_tagged_tags_o (provider_vif.update_tagged_tags_o)
);


initial begin

	clk = 1'b0;
	forever begin
		#(CLK_HALF_PERIOD);
		clk = ~clk;
	end
end

// Reset generation
initial begin

	rst_n = 1'b0;
	repeat (RESET_CYCLES) begin
		@(negedge clk);
	end
	rst_n = 1'b1;
end

// FOR TESTING THE RESET SEQUENCE IN THE DESIGN
// initial begin
//     provider_vif.apply_reset(RESET_CYCLES);
// end

initial begin
	provider_vif.initialize_inputs();
	uvm_config_db#(virtual provider_update_if)::set(null,"uvm_test_top.env.agent.*","vif",provider_vif);
	// uvm_config_db#(virtual provider_update_if)::set(null,"*","vif",provider_vif);
	run_test("provider_update_base_test");
end

endmodule