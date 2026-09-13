import uvm_pkg::*;
import predictor_history_tb_params_pkg::*;
`include "uvm_macros.svh"

`include "TB_Combine_wrapper_ghr_fifo_hash_sequences.sv"

// interface design
interface predictor_history_if (input logic clk);

	// Reset and global block enable.
	logic rst_n;
	logic en_i;

	// Branch stream entering the GHR and hash path.
	logic br_valid_i;
	branch_packet_t br_packet_i;
	program_counter_t load_pc_i;

	// Branch retirement and recovery information from the ROB.
	logic branch_commit_i;
	logic misprediction_i;
	misprediction_depth_t mispredicted_table_depth_i;

	// Single selected hash-address-generator outputs.
	tagged_index_t tagged_index_o;
	tagged_tag_t tagged_tag_o;

	// Checkpoint FIFO and recovery status.
	logic fifo_full_o;
	logic fifo_empty_o;
	logic recovery_active_o;

	// GHR and folded-history observability outputs.
	branch_packet_t ghr_incoming_packet_o;
	ghr_packet_array_t ghr_expiring_packets_o;
	branch_packet_t selected_expiring_packet_o;
	folded_history_t folded_history_state_o;
	folded_history_t recovery_folded_history_o;

	// The driver places the next request after the falling edge. Status inputs
	// let it avoid illegal traffic when the FIFO is full or recovery is active.
	clocking drv_cb @(negedge clk);
		default input #1step output #0;
		input rst_n;
		input fifo_full_o;
		input fifo_empty_o;
		input recovery_active_o;
		output en_i;
		output br_valid_i;
		output br_packet_i;
		output load_pc_i;
		output branch_commit_i;
		output misprediction_i;
		output mispredicted_table_depth_i;
	endclocking

	// Sampling at the falling edge observes values that settled after the
	// preceding rising edge. The driver output update occurs after this sample.
	clocking mon_cb @(negedge clk);
		default input #1step;
		input rst_n;
		input en_i;
		input br_valid_i;
		input br_packet_i;
		input load_pc_i;
		input branch_commit_i;
		input misprediction_i;
		input mispredicted_table_depth_i;
		input tagged_index_o;
		input tagged_tag_o;
		input fifo_full_o;
		input fifo_empty_o;
		input recovery_active_o;
		input ghr_incoming_packet_o;
		input ghr_expiring_packets_o;
		input selected_expiring_packet_o;
		input folded_history_state_o;
		input recovery_folded_history_o;
	endclocking

	modport DUT (
		input clk,
		input rst_n,
		input en_i,
		input br_valid_i,
		input br_packet_i,
		input load_pc_i,
		input branch_commit_i,
		input misprediction_i,
		input mispredicted_table_depth_i,
		output tagged_index_o,
		output tagged_tag_o,
		output fifo_full_o,
		output fifo_empty_o,
		output recovery_active_o,
		output ghr_incoming_packet_o,
		output ghr_expiring_packets_o,
		output selected_expiring_packet_o,
		output folded_history_state_o,
		output recovery_folded_history_o
	);

	modport DRIVER (clocking drv_cb, input clk, input rst_n);
	modport MONITOR (clocking mon_cb, input clk, input rst_n);

endinterface

//// sequencer class
class predictor_history_sequencer extends uvm_sequencer #(predictor_history_sequence_item);

		`uvm_component_utils(predictor_history_sequencer)

		function new(string name = "predictor_history_sequencer", uvm_component parent = null);
			super.new(name, parent);
		endfunction

endclass



/// driver class
class predictor_history_driver extends uvm_driver #(predictor_history_sequence_item);

		`uvm_component_utils(predictor_history_driver)

		virtual predictor_history_if vif;
		int unsigned driven_transaction_count;

		function new(string name = "predictor_history_driver", uvm_component parent = null);
			super.new(name, parent);
			driven_transaction_count = 0;
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			if (!uvm_config_db #(virtual predictor_history_if)::get(this, "", "vif", vif)) begin
				`uvm_fatal(get_type_name(), "Unable to obtain predictor_history_if from uvm_config_db")
			end
		endfunction

		task drive_initial_values();
			vif.en_i <= 1'b0;
			vif.br_valid_i <= 1'b0;
			vif.br_packet_i <= '0;
			vif.load_pc_i <= '0;
			vif.branch_commit_i <= 1'b0;
			vif.misprediction_i <= 1'b0;
			vif.mispredicted_table_depth_i <= '0;
		endtask

		task drive_idle();
			vif.drv_cb.en_i <= 1'b1;
			vif.drv_cb.br_valid_i <= 1'b0;
			vif.drv_cb.br_packet_i <= '0;
			vif.drv_cb.load_pc_i <= '0;
			vif.drv_cb.branch_commit_i <= 1'b0;
			vif.drv_cb.misprediction_i <= 1'b0;
			vif.drv_cb.mispredicted_table_depth_i <= '0;
		endtask

		task drive_transaction(predictor_history_sequence_item req);
			vif.drv_cb.en_i <= req.en_i;
			vif.drv_cb.br_valid_i <= req.br_valid_i;
			vif.drv_cb.br_packet_i <= req.br_packet_i;
			vif.drv_cb.load_pc_i <= req.load_pc_i;
			vif.drv_cb.branch_commit_i <= req.branch_commit_i;
			vif.drv_cb.misprediction_i <= req.misprediction_i;
			vif.drv_cb.mispredicted_table_depth_i <= req.mispredicted_table_depth_i;
		endtask

		task run_phase(uvm_phase phase);
			predictor_history_sequence_item req;

			drive_initial_values();
			wait (vif.rst_n === 1'b1);

			forever begin
				@(vif.drv_cb);
				req = null;
				seq_item_port.try_next_item(req);

				if (req == null) begin
					drive_idle();
				end else begin
					drive_transaction(req);
					driven_transaction_count++;
					`uvm_info(get_type_name(), $sformatf("Driving transaction %0d: %s, chckpt_wr_en=%b, chckpt_rd_en=%b", driven_transaction_count, req.convert2string(), req.get_chckpt_wr_en(), req.get_chckpt_rd_en()), UVM_MEDIUM)
					seq_item_port.item_done();
				end
			end
		endtask

endclass


///monitor
class predictor_history_monitor extends uvm_monitor;

		`uvm_component_utils(predictor_history_monitor)

		virtual predictor_history_if vif;
		uvm_analysis_port #(predictor_history_sequence_item) analysis_port;
		int unsigned monitored_cycle_count;

		function new(string name = "predictor_history_monitor", uvm_component parent = null);
			super.new(name, parent);
			analysis_port = new("analysis_port", this);
			monitored_cycle_count = 0;
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			if (!uvm_config_db #(virtual predictor_history_if)::get(this, "", "vif", vif)) begin
				`uvm_fatal(get_type_name(), "Unable to obtain predictor_history_if from uvm_config_db")
			end
		endfunction

		task run_phase(uvm_phase phase);
			predictor_history_sequence_item observed_item;

			forever begin
				@(vif.mon_cb);

				observed_item = predictor_history_sequence_item::type_id::create($sformatf("observed_item_%0d", monitored_cycle_count));
				observed_item.rst_n = vif.mon_cb.rst_n;
				observed_item.en_i = vif.mon_cb.en_i;
				observed_item.br_valid_i = vif.mon_cb.br_valid_i;
				observed_item.br_packet_i = vif.mon_cb.br_packet_i;
				observed_item.load_pc_i = vif.mon_cb.load_pc_i;
				observed_item.branch_commit_i = vif.mon_cb.branch_commit_i;
				observed_item.misprediction_i = vif.mon_cb.misprediction_i;
				observed_item.mispredicted_table_depth_i = vif.mon_cb.mispredicted_table_depth_i;
				observed_item.tagged_index_o = vif.mon_cb.tagged_index_o;
				observed_item.tagged_tag_o = vif.mon_cb.tagged_tag_o;
				observed_item.fifo_full_o = vif.mon_cb.fifo_full_o;
				observed_item.fifo_empty_o = vif.mon_cb.fifo_empty_o;
				observed_item.recovery_active_o = vif.mon_cb.recovery_active_o;
				observed_item.ghr_incoming_packet_o = vif.mon_cb.ghr_incoming_packet_o;
				observed_item.selected_expiring_packet_o = vif.mon_cb.selected_expiring_packet_o;
				observed_item.folded_history_state_o = vif.mon_cb.folded_history_state_o;
				observed_item.recovery_folded_history_o = vif.mon_cb.recovery_folded_history_o;

				for (int i = 0; i < NUM_GHR_PACKETS; i++) begin
					observed_item.ghr_expiring_packets_o[i] = vif.mon_cb.ghr_expiring_packets_o[i];
				end

				observed_item.cycle_number = monitored_cycle_count;
				observed_item.sample_time = $time;
				observed_item.transaction_name = $sformatf("monitored_cycle_%0d", monitored_cycle_count);

				`uvm_info("CYCLE_MONITOR", observed_item.convert2string(), UVM_LOW)

				analysis_port.write(observed_item);
				monitored_cycle_count++;
			end
		endtask

endclass



//// scoreboard
class predictor_history_scoreboard extends uvm_scoreboard;

		`uvm_component_utils(predictor_history_scoreboard)

		uvm_analysis_imp #(predictor_history_sequence_item, predictor_history_scoreboard) analysis_export;

		branch_packet_t ghr_memory_model [0:GHR_MAX_PTR-1];
		folded_history_t fifo_memory_model [0:FIFO_DEPTH-1];
		folded_history_t folded_history_model;
		folded_history_t recovery_data_model;

		int unsigned ghr_head_model;
		int unsigned fifo_write_pointer_model;
		int unsigned fifo_read_pointer_model;
		int unsigned fifo_count_model;
		logic recovery_valid_model;

		int unsigned checked_cycle_count;
		int unsigned passed_check_count;
		int unsigned failed_check_count;

		function new(string name = "predictor_history_scoreboard", uvm_component parent = null);
			super.new(name, parent);
			analysis_export = new("analysis_export", this);
			checked_cycle_count = 0;
			passed_check_count = 0;
			failed_check_count = 0;
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			reset_model();
		endfunction

		function void reset_model();
			foreach (ghr_memory_model[i]) ghr_memory_model[i] = '0;
			foreach (fifo_memory_model[i]) fifo_memory_model[i] = '0;
			folded_history_model = '0;
			recovery_data_model = '0;
			ghr_head_model = 0;
			fifo_write_pointer_model = 0;
			fifo_read_pointer_model = 0;
			fifo_count_model = 0;
			recovery_valid_model = 1'b0;
		endfunction

		function automatic int unsigned circular_subtract(input int unsigned pointer_value, input int unsigned distance_value, input int unsigned modulus_value);
			return (pointer_value >= distance_value) ? pointer_value - distance_value : pointer_value + modulus_value - distance_value;
		endfunction

		function automatic folded_history_t rotate_left(input folded_history_t value, input int unsigned shift_amount);
			int unsigned effective_shift;
			effective_shift = shift_amount % FOLD_WIDTH;
			if (effective_shift == 0) return value;
			return (value << effective_shift) | (value >> (FOLD_WIDTH - effective_shift));
		endfunction

		function void record_pass(string check_name);
			passed_check_count++;
			`uvm_info("SCOREBOARD_PASS", $sformatf("cycle=%0d %s", checked_cycle_count, check_name), UVM_HIGH)
		endfunction

		function void record_failure(string check_name, string failure_detail);
			failed_check_count++;
			`uvm_error("SCOREBOARD_MISMATCH", $sformatf("cycle=%0d %s: %s", checked_cycle_count, check_name, failure_detail))
		endfunction

		function void write(predictor_history_sequence_item observed_item);
			logic previous_recovery_valid;
			logic expected_fifo_write_request;
			logic expected_fifo_read_request;
			logic expected_fifo_write_enable;
			logic expected_fifo_read_enable;
			logic expected_recovery_valid;
			logic expected_fifo_empty;
			logic expected_fifo_full;
			logic normal_ghr_branch_valid;
			logic normal_hash_branch_valid;
			int unsigned rollback_pointer;
			int unsigned next_ghr_head;
			int unsigned ghr_write_location;
			int unsigned selected_history_location;
			branch_packet_t selected_expiring_packet;
			folded_history_t folded_history_before_edge;
			folded_history_t popped_fifo_data;
			folded_history_t padded_incoming_packet;
			folded_history_t padded_expiring_packet;

			checked_cycle_count++;

			if (!observed_item.rst_n) begin
				reset_model();
				check_reset_outputs(observed_item);
				return;
			end

			previous_recovery_valid = recovery_valid_model;
			folded_history_before_edge = folded_history_model;
			expected_fifo_write_request = observed_item.en_i && observed_item.br_valid_i;
			expected_fifo_read_request = observed_item.branch_commit_i || observed_item.misprediction_i;
			expected_fifo_read_enable = observed_item.en_i && expected_fifo_read_request && (fifo_count_model != 0);
			expected_fifo_write_enable = observed_item.en_i && expected_fifo_write_request && ((fifo_count_model != FIFO_DEPTH) || expected_fifo_read_enable);

			normal_ghr_branch_valid = observed_item.en_i && observed_item.br_valid_i && !previous_recovery_valid;
			normal_hash_branch_valid = observed_item.en_i && observed_item.br_valid_i && !previous_recovery_valid;

			rollback_pointer = ghr_head_model;
			if (observed_item.en_i && observed_item.misprediction_i) 
				begin
					rollback_pointer = circular_subtract(ghr_head_model, observed_item.mispredicted_table_depth_i, GHR_MAX_PTR);
				end

			next_ghr_head = ghr_head_model;
			case ({observed_item.en_i && observed_item.misprediction_i, normal_ghr_branch_valid})
				2'b01: next_ghr_head = (ghr_head_model + 1) % GHR_MAX_PTR;
				2'b10: next_ghr_head = rollback_pointer;
				2'b11: next_ghr_head = (rollback_pointer + 1) % GHR_MAX_PTR;
				default: next_ghr_head = ghr_head_model;
			endcase

			selected_history_location = circular_subtract(next_ghr_head, SELECTED_HISTORY_DEPTH, GHR_MAX_PTR);
			selected_expiring_packet = ghr_memory_model[selected_history_location];

			popped_fifo_data = '0;
			if (expected_fifo_read_enable)
				begin
					popped_fifo_data = fifo_memory_model[fifo_read_pointer_model];					
				end

			if (observed_item.en_i && previous_recovery_valid) 
			begin
				folded_history_model = recovery_data_model;
			end else if (normal_hash_branch_valid) 
			begin
				padded_incoming_packet = {{(FOLD_WIDTH-PKT_WIDTH){1'b0}}, observed_item.br_packet_i};
				padded_expiring_packet = {{(FOLD_WIDTH-PKT_WIDTH){1'b0}}, selected_expiring_packet};
				folded_history_model = rotate_left(folded_history_before_edge, 1) ^ padded_incoming_packet ^ rotate_left(padded_expiring_packet, SELECTED_HISTORY_DEPTH);
			end

			if (expected_fifo_write_enable) 
			begin
				fifo_memory_model[fifo_write_pointer_model] = folded_history_before_edge;
				fifo_write_pointer_model = (fifo_write_pointer_model + 1) % FIFO_DEPTH;
			end

			if (expected_fifo_read_enable) 
				begin
					fifo_read_pointer_model = (fifo_read_pointer_model + 1) % FIFO_DEPTH;					
				end

			case ({expected_fifo_write_enable, expected_fifo_read_enable})
				2'b10: fifo_count_model++;
				2'b01: fifo_count_model--;
				default: fifo_count_model = fifo_count_model;
			endcase

			if (normal_ghr_branch_valid) 
			begin
				ghr_write_location = observed_item.misprediction_i ? rollback_pointer : ghr_head_model;
				ghr_memory_model[ghr_write_location] = observed_item.br_packet_i;
			end

			ghr_head_model = next_ghr_head;
			expected_recovery_valid = expected_fifo_read_enable && observed_item.misprediction_i;
			recovery_valid_model = expected_recovery_valid;
			if (expected_recovery_valid) 
			begin
				recovery_data_model = popped_fifo_data;				
			end

			expected_fifo_empty = (fifo_count_model == 0);
			expected_fifo_full = (fifo_count_model == FIFO_DEPTH);

			check_logic_value("fifo_empty_o", expected_fifo_empty, observed_item.fifo_empty_o);
			check_logic_value("fifo_full_o", expected_fifo_full, observed_item.fifo_full_o);
			check_logic_value("recovery_active_o", expected_recovery_valid, observed_item.recovery_active_o);
			check_vector_value("folded_history_state_o", folded_history_model, observed_item.folded_history_state_o);

			if (expected_recovery_valid) 
			begin
				check_vector_value("recovery_folded_history_o", popped_fifo_data, observed_item.recovery_folded_history_o);				
			end	else
			begin
				check_vector_value("recovery_folded_history_o", folded_history_t'('0), observed_item.recovery_folded_history_o);				
			end 

			`uvm_info("SCOREBOARD_MODEL", $sformatf("cycle=%0d wr_req=%b rd_req=%b wr_accept=%b rd_accept=%b fifo_count=%0d recovery=%b expected_fold=0x%0h", checked_cycle_count, expected_fifo_write_request, expected_fifo_read_request, expected_fifo_write_enable, expected_fifo_read_enable, fifo_count_model, expected_recovery_valid, folded_history_model), UVM_MEDIUM)
		endfunction

		function void check_reset_outputs(predictor_history_sequence_item observed_item);
			check_logic_value("reset fifo_empty_o", 1'b1, observed_item.fifo_empty_o);
			check_logic_value("reset fifo_full_o", 1'b0, observed_item.fifo_full_o);
			check_logic_value("reset recovery_active_o", 1'b0, observed_item.recovery_active_o);
			check_vector_value("reset folded_history_state_o", folded_history_t'('0), observed_item.folded_history_state_o);
			check_vector_value("reset recovery_folded_history_o", folded_history_t'('0), observed_item.recovery_folded_history_o);
		endfunction

		function void check_logic_value(string check_name, logic expected_value, logic observed_value);
			if (observed_value === expected_value) 
			begin
				record_pass(check_name);				
			end
			else begin
				record_failure(check_name, $sformatf("expected=%b observed=%b", expected_value, observed_value));
			end
		endfunction

		function void check_vector_value(string check_name, folded_history_t expected_value, folded_history_t observed_value);
			if (observed_value === expected_value) 
			begin
				record_pass(check_name);
			end	else
			begin
				record_failure(check_name, $sformatf("expected=0x%0h observed=0x%0h", expected_value, observed_value));
			end
		endfunction

		function void report_phase(uvm_phase phase);
			super.report_phase(phase);

			if (failed_check_count == 0) begin
				`uvm_info("SCOREBOARD_SUMMARY", $sformatf("PASS: cycles=%0d passed_checks=%0d failed_checks=%0d", checked_cycle_count, passed_check_count, failed_check_count), UVM_NONE)
			end else begin
				`uvm_error("SCOREBOARD_SUMMARY", $sformatf("FAIL: cycles=%0d passed_checks=%0d failed_checks=%0d", checked_cycle_count, passed_check_count, failed_check_count))
			end
		endfunction

endclass



///agent 
class predictor_history_agent extends uvm_agent;

		`uvm_component_utils(predictor_history_agent)

		predictor_history_sequencer sequencer;
		predictor_history_driver driver;
		predictor_history_monitor monitor;

		function new(string name = "predictor_history_agent", uvm_component parent = null);
			super.new(name, parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			monitor = predictor_history_monitor::type_id::create("monitor", this);

			if (get_is_active() == UVM_ACTIVE) begin
				sequencer = predictor_history_sequencer::type_id::create("sequencer", this);
				driver = predictor_history_driver::type_id::create("driver", this);
			end
		endfunction

		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);

			if (get_is_active() == UVM_ACTIVE) begin
				driver.seq_item_port.connect(sequencer.seq_item_export);
			end
		endfunction

endclass


		//// environment
class predictor_history_env extends uvm_env;

		`uvm_component_utils(predictor_history_env)

		predictor_history_agent agent;
		predictor_history_scoreboard scoreboard;

		function new(string name = "predictor_history_env", uvm_component parent = null);
			super.new(name, parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			agent = predictor_history_agent::type_id::create("agent", this);
			scoreboard = predictor_history_scoreboard::type_id::create("scoreboard", this);
		endfunction

		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);

			agent.monitor.analysis_port.connect(scoreboard.analysis_export);
		endfunction

endclass
