import uvm_pkg::*;
import predictor_history_tb_params_pkg::*;
`include "uvm_macros.svh"


/// sequence item
class predictor_history_sequence_item extends uvm_sequence_item;

		// Inputs driven toward the wrapper.
		rand logic en_i;
		rand logic br_valid_i;
		rand branch_packet_t br_packet_i;
		rand program_counter_t load_pc_i;
		rand logic branch_commit_i;
		rand logic misprediction_i;
		rand misprediction_depth_t mispredicted_table_depth_i;

		// Outputs sampled from the wrapper.
		logic rst_n;
		tagged_index_t tagged_index_o;
		tagged_tag_t tagged_tag_o;
		logic fifo_full_o;
		logic fifo_empty_o;
		logic recovery_active_o;
		branch_packet_t ghr_incoming_packet_o;
		ghr_packet_array_t ghr_expiring_packets_o;
		branch_packet_t selected_expiring_packet_o;
		folded_history_t folded_history_state_o;
		folded_history_t recovery_folded_history_o;

		// Testbench bookkeeping.
		int unsigned cycle_number;
		time sample_time;
		string transaction_name;

		constraint legal_misprediction_depth_c {
			if (misprediction_i) mispredicted_table_depth_i inside {[1:GHR_MAX_PTR-1]};
			else mispredicted_table_depth_i == '0;
		}

		constraint disabled_control_c {
			if (!en_i) br_valid_i == 1'b0;
			if (!en_i) branch_commit_i == 1'b0;
			if (!en_i) misprediction_i == 1'b0;
		}

		constraint aligned_pc_c {
			load_pc_i[1:0] == 2'b00;
		}

		`uvm_object_utils_begin(predictor_history_sequence_item)
			`uvm_field_int(en_i, UVM_DEFAULT)
			`uvm_field_int(br_valid_i, UVM_DEFAULT)
			`uvm_field_int(br_packet_i, UVM_HEX)
			`uvm_field_int(load_pc_i, UVM_HEX)
			`uvm_field_int(branch_commit_i, UVM_DEFAULT)
			`uvm_field_int(misprediction_i, UVM_DEFAULT)
			`uvm_field_int(mispredicted_table_depth_i, UVM_DEC)
			`uvm_field_int(rst_n, UVM_DEFAULT)
			`uvm_field_int(tagged_index_o, UVM_HEX)
			`uvm_field_int(tagged_tag_o, UVM_HEX)
			`uvm_field_int(fifo_full_o, UVM_DEFAULT)
			`uvm_field_int(fifo_empty_o, UVM_DEFAULT)
			`uvm_field_int(recovery_active_o, UVM_DEFAULT)
			`uvm_field_int(ghr_incoming_packet_o, UVM_HEX)
			`uvm_field_sarray_int(ghr_expiring_packets_o, UVM_HEX)
			`uvm_field_int(selected_expiring_packet_o, UVM_HEX)
			`uvm_field_int(folded_history_state_o, UVM_HEX)
			`uvm_field_int(recovery_folded_history_o, UVM_HEX)
			`uvm_field_int(cycle_number, UVM_DEC)
			`uvm_field_int(sample_time, UVM_TIME)
			`uvm_field_string(transaction_name, UVM_DEFAULT)
		`uvm_object_utils_end

		function new(string name = "predictor_history_sequence_item");
			super.new(name);
			transaction_name = "unnamed_cycle";
		endfunction

		function logic get_chckpt_wr_en();
			return en_i && br_valid_i;
		endfunction

		function logic get_chckpt_rd_en();
			return branch_commit_i || misprediction_i;
		endfunction

		function string convert2string();
			return $sformatf("name=%s cycle=%0d en=%b br_valid=%b packet=0x%0h pc=0x%08h commit=%b misprediction=%b depth=%0d fifo_full=%b fifo_empty=%b recovery=%b folded_history=0x%0h index=0x%0h tag=0x%0h", transaction_name, cycle_number, en_i, br_valid_i, br_packet_i, load_pc_i, branch_commit_i, misprediction_i, mispredicted_table_depth_i, fifo_full_o, fifo_empty_o, recovery_active_o, folded_history_state_o, tagged_index_o, tagged_tag_o);
		endfunction

endclass

/// base sequence/smoke sequence
class predictor_history_base_sequence extends uvm_sequence #(predictor_history_sequence_item);

		`uvm_object_utils(predictor_history_base_sequence)

		int unsigned generated_transaction_count;

		function new(string name = "predictor_history_base_sequence");
			super.new(name);
			generated_transaction_count = 0;
		endfunction

		virtual task body();
			`uvm_info(get_type_name(), "Base sequence body contains no direct stimulus", UVM_HIGH)
		endtask

		virtual task send_cycle(input string cycle_name, input logic en_value, input logic br_valid_value, input branch_packet_t packet_value, input program_counter_t pc_value, input logic branch_commit_value, input logic misprediction_value, input misprediction_depth_t misprediction_depth_value);
			predictor_history_sequence_item req;

			req = predictor_history_sequence_item::type_id::create($sformatf("req_%0d", generated_transaction_count));

			start_item(req);
			req.en_i = en_value;
			req.br_valid_i = br_valid_value;
			req.br_packet_i = packet_value;
			req.load_pc_i = pc_value;
			req.branch_commit_i = branch_commit_value;
			req.misprediction_i = misprediction_value;
			req.mispredicted_table_depth_i = misprediction_depth_value;
			req.transaction_name = cycle_name;
			finish_item(req);

			generated_transaction_count++;
		endtask

		virtual task idle_cycle(input string cycle_name = "idle_cycle");
			send_cycle(cycle_name, 1'b1, 1'b0, '0, '0, 1'b0, 1'b0, '0);
		endtask

		virtual task disabled_cycle(input string cycle_name = "disabled_cycle");
			send_cycle(cycle_name, 1'b0, 1'b0, '0, '0, 1'b0, 1'b0, '0);
		endtask

		virtual task branch_cycle(input branch_packet_t packet_value, input program_counter_t pc_value, input string cycle_name = "branch_cycle");
			send_cycle(cycle_name, 1'b1, 1'b1, packet_value, pc_value, 1'b0, 1'b0, '0);
		endtask

		virtual task branch_commit_cycle(input string cycle_name = "branch_commit_cycle");
			send_cycle(cycle_name, 1'b1, 1'b0, '0, '0, 1'b1, 1'b0, '0);
		endtask

		virtual task branch_and_commit_cycle(input branch_packet_t packet_value, input program_counter_t pc_value, input string cycle_name = "branch_and_commit_cycle");
			send_cycle(cycle_name, 1'b1, 1'b1, packet_value, pc_value, 1'b1, 1'b0, '0);
		endtask

		virtual task misprediction_cycle(input misprediction_depth_t depth_value, input program_counter_t restart_pc_value, input string cycle_name = "misprediction_cycle");
			if (!(depth_value inside {[1:GHR_MAX_PTR-1]})) begin
				`uvm_fatal(get_type_name(), $sformatf("Illegal misprediction depth %0d; expected 1 through %0d", depth_value, GHR_MAX_PTR-1))
			end

			send_cycle(cycle_name, 1'b1, 1'b0, '0, restart_pc_value, 1'b0, 1'b1, depth_value);
		endtask

		virtual task recovery_cycle(input program_counter_t restart_pc_value, input string cycle_name = "recovery_cycle");
			send_cycle(cycle_name, 1'b1, 1'b0, '0, restart_pc_value, 1'b0, 1'b0, '0);
		endtask

endclass


///// basic /smoke sequence
class predictor_history_smoke_sequence extends predictor_history_base_sequence;

    `uvm_object_utils(predictor_history_smoke_sequence)

    function new(string name = "predictor_history_smoke_sequence");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_type_name(), "Starting predictor-history smoke sequence", UVM_LOW)

        idle_cycle("initial_idle");
        branch_cycle(7'h11, 32'h0000_1000, "branch_write_1");
        branch_cycle(7'h22, 32'h0000_1004, "branch_write_2");
        branch_cycle(7'h35, 32'h0000_1008, "branch_write_3");
        branch_commit_cycle("commit_read_1");
        branch_and_commit_cycle(7'h4A, 32'h0000_100C, "simultaneous_branch_and_commit");
        disabled_cycle("global_enable_low");
        idle_cycle("post_disable_idle");
        misprediction_cycle(6'd2, 32'h0000_2000, "misprediction_read");
        recovery_cycle(32'h0000_2000, "apply_recovery");
        idle_cycle("recovery_settle_1");
        idle_cycle("recovery_settle_2");

        `uvm_info(get_type_name(), "Completed predictor-history smoke sequence", UVM_LOW)
    endtask

endclass