`include "TB_Tagged_update_control_other_components.sv"
`include "TB_Tagged_update_control_sequences.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"
import tagged_update_cntrl_params_pkg::*;


class tagged_update_cntrl_test extends uvm_test;

		tagged_update_cntrl_env            env;
		tagged_update_cntrl_smoke_sequence basic_seq;
		tagged_update_cntrl_disabled_sequence control_disabled;
		tagged_update_cntrl_allocation_sequence allocation_seq;
		tagged_update_cntrl_reward_sequence reward_seq;
		tagged_update_cntrl_penalize_sequence penalize_seq;
		tagged_update_cntrl_zero_confidence_penalize_sequence zero_conf_penalize;
		tagged_update_cntrl_decay_sequence decay_seq;
		tagged_update_cntrl_counter_sweep_sequence sweep_seq;
		tagged_update_cntrl_data_boundary_sequence boundry_seq;
		tagged_update_cntrl_repeated_reward_sequence repeat_reward_seq;
		tagged_update_cntrl_repeated_penalize_n_allocate_sequence penalize_allocate;
		tagged_update_cntrl_allocate_reward_penalize_sequence allocate_reward_penalize;
		tagged_update_cntrl_random_valid_sequence random_valid_seq;
		tagged_update_cntrl_invalid_protocol_sequence invalid_seq;

		`uvm_component_utils(tagged_update_cntrl_test)

		function new(string name = "tagged_update_cntrl_test",uvm_component parent = null);
			super.new(name,parent);
		endfunction

		virtual function void build_phase(uvm_phase phase);

			super.build_phase(phase);

			uvm_config_db #(uvm_active_passive_enum)::set(this,"env.agent","is_active",UVM_ACTIVE);
			env = tagged_update_cntrl_env::type_id::create("env",this);

		endfunction

		virtual task run_phase(uvm_phase phase);

			phase.raise_objection(this,"Starting tagged-update-controller test");

				// basic_seq = tagged_update_cntrl_smoke_sequence::type_id::create("basic_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller smoke test",UVM_LOW)
				// basic_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller smoke test completed",UVM_LOW)

				// control_disabled = tagged_update_cntrl_disabled_sequence::type_id::create("control_disabled");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller CONTROL DISABLED test",UVM_LOW)
				// control_disabled.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller CONTROL DISABLED test completed",UVM_LOW)

				// allocation_seq = tagged_update_cntrl_allocation_sequence::type_id::create("allocation_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller ALLOCATION SEQUENCE test",UVM_LOW)
				// allocation_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller ALLOCATION SEQUENCE test completed",UVM_LOW)

				// reward_seq = tagged_update_cntrl_reward_sequence::type_id::create("reward_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller REWARD SEQUENCE test",UVM_LOW)
				// reward_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller REWARD SEQUENCE test completed",UVM_LOW)

				// penalize_seq = tagged_update_cntrl_penalize_sequence::type_id::create("penalize_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller PENALIZE SEQUENCE test",UVM_LOW)
				// penalize_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller PENALIZE SEQUENCE test completed",UVM_LOW)

				// zero_conf_penalize = tagged_update_cntrl_zero_confidence_penalize_sequence::type_id::create("zero_conf_penalize");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller ZERO CONF PENALIZE SEQUENCE test",UVM_LOW)
				// zero_conf_penalize.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller ZERO CONF PENALIZE SEQUENCE test completed",UVM_LOW)

				// decay_seq = tagged_update_cntrl_decay_sequence::type_id::create("decay_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller DECAY SEQUENCE test",UVM_LOW)
				// decay_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller DECAY SEQUENCE test completed",UVM_LOW)

				// sweep_seq = tagged_update_cntrl_counter_sweep_sequence::type_id::create("sweep_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller SWEEP SEQUENCE test",UVM_LOW)
				// sweep_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller SWEEP SEQUENCE test completed",UVM_LOW)

				// boundry_seq = tagged_update_cntrl_data_boundary_sequence::type_id::create("boundry_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller BOUNDARY SEQUENCE test",UVM_LOW)
				// boundry_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller BOUNDARY SEQUENCE test completed",UVM_LOW)

				// repeat_reward_seq = tagged_update_cntrl_repeated_reward_sequence::type_id::create("repeat_reward_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller REPEAT REWARD SEQUENCE test",UVM_LOW)
				// repeat_reward_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller REPEAT REWARD SEQUENCE test completed",UVM_LOW)

				// penalize_allocate = tagged_update_cntrl_repeated_penalize_n_allocate_sequence::type_id::create("penalize_allocate");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller PEANLIZE ALLOCATE SEQUENCE test",UVM_LOW)
				// penalize_allocate.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller REPEAT PENALIZE ALLOCATE SEQUENCE test completed",UVM_LOW)

				// allocate_reward_penalize = tagged_update_cntrl_allocate_reward_penalize_sequence::type_id::create("allocate_reward_penalize");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller ALLOCATE REWARD PENALIZE SEQUENCE test",UVM_LOW)
				// allocate_reward_penalize.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller ALLOCATE REWARD PENALIZE SEQUENCE test completed",UVM_LOW)

				// random_valid_seq = tagged_update_cntrl_random_valid_sequence::type_id::create("random_valid_seq");
				// `uvm_info(get_type_name(),"Starting tagged-update-controller RANDOM VALID SEQUENCE test",UVM_LOW)
				// random_valid_seq.start(env.agent.sequencer);
				// `uvm_info(get_type_name(),"Tagged-update-controller RANDOM VALID SEQUENCE test completed",UVM_LOW)

				invalid_seq = tagged_update_cntrl_invalid_protocol_sequence::type_id::create("invalid_seq");
				`uvm_info(get_type_name(),"Starting tagged-update-controller INVALID SEQUENCE test",UVM_LOW)
				invalid_seq.start(env.agent.sequencer);
				`uvm_info(get_type_name(),"Tagged-update-controller INVALID SEQUENCE test completed",UVM_LOW)

			phase.drop_objection(this,"Tagged-update-controller test completed");

		endtask

endclass


module tb_top;

		timeunit 1ns;
		timeprecision 1ps;

		tagged_update_cntrl_if tagged_if();

		tagged_update_cntrl #(
			.DISTANCE_WIDTH   (DISTANCE_WIDTH),
			.TAG_WIDTH        (TAG_WIDTH),
			.CONFIDENCE_WIDTH (CONFIDENCE_WIDTH),
			.USEFUL_WIDTH     (USEFUL_WIDTH)
		) dut (
			.en_i               (tagged_if.en_i),
			.cmd_i              (tagged_if.cmd_i),
			.current_conf_i     (tagged_if.current_conf_i),
			.current_useful_i   (tagged_if.current_useful_i),
			.current_tag_i      (tagged_if.current_tag_i),
			.current_distance_i (tagged_if.current_distance_i),
			.new_tag_i          (tagged_if.new_tag_i),
			.true_distance_i    (tagged_if.true_distance_i),

			.sram_we_o          (tagged_if.sram_we_o),
			.next_confidence_o  (tagged_if.next_confidence_o),
			.next_useful_o      (tagged_if.next_useful_o),
			.next_tag_o         (tagged_if.next_tag_o),
			.next_distance_o    (tagged_if.next_distance_o)
		);

		initial begin

			uvm_config_db #(virtual tagged_update_cntrl_if)::set(null,"uvm_test_top.env.agent*","vif",tagged_if);
			run_test("tagged_update_cntrl_test");

		end

endmodule