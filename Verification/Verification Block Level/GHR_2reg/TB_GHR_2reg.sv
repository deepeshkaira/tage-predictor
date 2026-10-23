`timescale 1ns/1ps


package ghr_params_pkg;

	parameter int unsigned PKT_WIDTH = 7;
	parameter int unsigned NUM_BANKS = 9;
	parameter int unsigned ENTRIES_PER_BANK = 4;
	parameter int unsigned NUM_HASH_TABLES = 7;
	parameter int unsigned MAX_PTR = 36;

	typedef logic [PKT_WIDTH-1:0] packet_t;
	typedef logic [5:0] history_depth_t;
	typedef packet_t expiring_packet_array_t [0:NUM_HASH_TABLES-1];

endpackage


import uvm_pkg::*;
import ghr_params_pkg::*;
`include "uvm_macros.svh"

/// interface
interface ghr_if #(
    parameter int PKT_WIDTH = 7,
    parameter int NUM_HASH_TABLES = 7
)(
    input logic clk
);

    logic rst_n;
    logic en_i;

    logic br_valid_i;
    logic [PKT_WIDTH-1:0] br_packet_i;

    logic misprediction_i;
    logic [5:0] mispredicted_table_depth_i;
    logic recovery_active_i;

    logic [PKT_WIDTH-1:0] incoming_packet_o;
    logic [PKT_WIDTH-1:0] expiring_packet_o [0:NUM_HASH_TABLES-1];
    logic output_valid_o;

    clocking driver_cb @(negedge clk);
        default input #1step output #0;

        output en_i;
        output br_valid_i;
        output br_packet_i;
        output misprediction_i;
        output mispredicted_table_depth_i;
        output recovery_active_i;

        input incoming_packet_o;
        input expiring_packet_o;
        input output_valid_o;
    endclocking

    clocking monitor_cb @(negedge clk);
        default input #1step;

        input rst_n;
        input en_i;
        input br_valid_i;
        input br_packet_i;
        input misprediction_i;
        input mispredicted_table_depth_i;
        input recovery_active_i;

        input incoming_packet_o;
        input expiring_packet_o;
        input output_valid_o;
    endclocking

    modport DRIVER (
        clocking driver_cb,
        input clk,
        input rst_n
    );

    modport MONITOR (
        clocking monitor_cb,
        input clk
    );

    modport DUT (
        input clk,
        input rst_n,
        input en_i,
        input br_valid_i,
        input br_packet_i,
        input misprediction_i,
        input mispredicted_table_depth_i,
        input recovery_active_i,

        output incoming_packet_o,
        output expiring_packet_o,
        output output_valid_o
    );

endinterface


class ghr_seq_item extends uvm_sequence_item;

    localparam int PKT_WIDTH = 7;
    localparam int NUM_HASH_TABLES = 7;

    rand bit en;
    rand bit br_valid;
    rand bit [PKT_WIDTH-1:0] br_packet;
    rand bit misprediction;
    rand bit [5:0] mispredicted_table_depth;
    rand bit recovery_active;

    logic rst_n;

    logic [PKT_WIDTH-1:0] observed_incoming_packet;
    logic [PKT_WIDTH-1:0] observed_expiring_packet [0:NUM_HASH_TABLES-1];
    logic observed_output_valid;

    longint unsigned sampled_cycle;
    time sample_time;

    `uvm_object_utils_begin(ghr_seq_item)
        `uvm_field_int(en, UVM_ALL_ON)
        `uvm_field_int(br_valid, UVM_ALL_ON)
        `uvm_field_int(br_packet, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(misprediction, UVM_ALL_ON)
        `uvm_field_int(mispredicted_table_depth, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(recovery_active, UVM_ALL_ON)

        `uvm_field_int(rst_n, UVM_ALL_ON)
        `uvm_field_int(observed_incoming_packet, UVM_ALL_ON | UVM_HEX)
        `uvm_field_sarray_int(observed_expiring_packet, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(observed_output_valid, UVM_ALL_ON)

        `uvm_field_int(sampled_cycle, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(sample_time, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "ghr_seq_item");
        super.new(name);
    endfunction

endclass


class ghr_base_sequence extends uvm_sequence #(ghr_seq_item);

    `uvm_object_utils(ghr_base_sequence)

    function new(string name = "ghr_base_sequence");
        super.new(name);
    endfunction

    task drive_cycle(
        input bit en,
        input bit br_valid,
        input bit [6:0] br_packet,
        input bit misprediction,
        input bit [5:0] mispredicted_depth,
        input bit recovery_active
    );

        ghr_seq_item tr;
        tr = ghr_seq_item::type_id::create("tr");

        start_item(tr);

        tr.en = en;
        tr.br_valid = br_valid;
        tr.br_packet = br_packet;
        tr.misprediction = misprediction;
        tr.mispredicted_table_depth = mispredicted_depth;
        tr.recovery_active = recovery_active;

        finish_item(tr);

    endtask

    task idle_cycle();
        drive_cycle(1'b1, 1'b0, '0, 1'b0, '0, 1'b0);
    endtask

    task branch_cycle(input bit [6:0] packet);
        drive_cycle(1'b1, 1'b1, packet, 1'b0, '0, 1'b0);
    endtask

    task misprediction_cycle(input bit [5:0] depth);
        drive_cycle(1'b1, 1'b0, '0, 1'b1, depth, 1'b0);
    endtask

    task misprediction_branch_cycle(input bit [5:0] depth, input bit [6:0] packet);
        drive_cycle(1'b1, 1'b1, packet, 1'b1, depth, 1'b0);
    endtask

    task recovery_cycle();
        drive_cycle(1'b1, 1'b0, '0, 1'b0, '0, 1'b1);
    endtask

    task disabled_cycle(
        input bit br_valid,
        input bit [6:0] packet,
        input bit misprediction,
        input bit [5:0] depth,
        input bit recovery_active
    );

        drive_cycle(1'b0, br_valid, packet, misprediction, depth, recovery_active);

    endtask

endclass

class ghr_pipeline_smoke_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_pipeline_smoke_sequence)

	function new(string name = "ghr_pipeline_smoke_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		int unsigned number_of_writes = 40;

		`uvm_info("GHR_PIPELINE_SMOKE", $sformatf("Starting pipeline smoke sequence with %0d randomized writes", number_of_writes), UVM_LOW)

		// Clear transactions remaining behind reset.
		repeat (3) idle_cycle();

		for (int write_number = 0; write_number < number_of_writes; write_number++) begin
			if (!std::randomize(packet) with {packet inside {[7'h01:7'h7F]};}) begin
				`uvm_fatal("GHR_PIPELINE_SMOKE", $sformatf("Packet randomization failed at write %0d", write_number))
			end

			`uvm_info("GHR_PIPELINE_SMOKE",
				$sformatf("Write=%0d logical_pointer=%0d packet=0x%02h", write_number, write_number % MAX_PTR, packet),
				UVM_MEDIUM
			)

			branch_cycle(packet);
		end

		// Move the last accepted transactions through the pipeline.
		repeat (5) idle_cycle();

		`uvm_info("GHR_PIPELINE_SMOKE", "Completed randomized pipeline smoke sequence", UVM_LOW)

	endtask

endclass


class ghr_2cycle_alternating_enable_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_2cycle_alternating_enable_sequence)

	function new(string name = "ghr_2cycle_alternating_enable_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t enabled_packet;
		packet_t disabled_packet;
		int unsigned number_of_transactions = 20;

		`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE", $sformatf("Starting %0d transactions with en_i active every other cycle", number_of_transactions), UVM_LOW)

		for (int transaction = 0; transaction < number_of_transactions; transaction++) begin

			if (!std::randomize(enabled_packet) with {enabled_packet inside {[7'h01:7'h7F]};}) begin
				`uvm_fatal("GHR_2CYCLE_ALTERNATING_ENABLE", "Enabled-cycle packet randomization failed")
			end

			if (!std::randomize(disabled_packet) with {disabled_packet inside {[7'h01:7'h7F]};}) begin
				`uvm_fatal("GHR_2CYCLE_ALTERNATING_ENABLE", "Disabled-cycle packet randomization failed")
			end

			`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE",
				$sformatf("Transaction=%0d ENABLED cycle packet=0x%02h", transaction, enabled_packet),
				UVM_MEDIUM
			)

			// Enabled cycle: this packet should enter the input registers.
			drive_cycle(
				.en(1'b1),
				.br_valid(1'b1),
				.br_packet(enabled_packet),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);

			`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE",
				$sformatf("Transaction=%0d DISABLED cycle raw packet=0x%02h", transaction, disabled_packet),
				UVM_MEDIUM
			)

			// Disabled cycle: raw inputs toggle, but no register should accept them.
			drive_cycle(
				.en(1'b0),
				.br_valid(1'b1),
				.br_packet(disabled_packet),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);
		end

		// Keep the pipeline enabled so the final held transaction can propagate.
		repeat (4) idle_cycle();

		`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE", "Completed alternating-enable sequence", UVM_LOW)

	endtask

endclass


// true alternating sequence
class ghr_alternating_enable_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_alternating_enable_sequence)

	function new(string name = "ghr_alternating_enable_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t enabled_packet;
		packet_t disabled_packet;
		int unsigned number_of_transactions = 20;
		int unsigned accepted_write_count = 0;

		`uvm_info("GHR_ALTERNATING_ENABLE", $sformatf("Starting %0d transactions with en_i alternating ON/OFF", number_of_transactions), UVM_LOW)

		for (int transaction = 0; transaction < number_of_transactions; transaction++) begin

			if (!std::randomize(enabled_packet, disabled_packet) with {
				enabled_packet inside {[7'h01:7'h7F]};
				disabled_packet inside {[7'h01:7'h7F]};
				disabled_packet != enabled_packet;
			}) begin
				`uvm_fatal("GHR_ALTERNATING_ENABLE", "Packet randomization failed")
			end

			`uvm_info("GHR_ALTERNATING_ENABLE",
				$sformatf("Transaction=%0d ENABLED packet=0x%02h expected_write=%0d",
					transaction, enabled_packet, accepted_write_count),
				UVM_MEDIUM
			)

			drive_cycle(
				.en(1'b1),
				.br_valid(1'b1),
				.br_packet(enabled_packet),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);

			accepted_write_count++;

			`uvm_info("GHR_ALTERNATING_ENABLE",
				$sformatf("Transaction=%0d DISABLED raw_packet=0x%02h; packet must not enter GHR",
					transaction, disabled_packet),
				UVM_MEDIUM
			)

			drive_cycle(
				.en(1'b0),
				.br_valid(1'b1),
				.br_packet(disabled_packet),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);

		end

		// Process the final transaction retained during the last disabled cycle.
		repeat (4) idle_cycle();

		`uvm_info("GHR_ALTERNATING_ENABLE",
			$sformatf("Completed alternating-enable sequence. Accepted writes=%0d expected final head=%0d",
				accepted_write_count, accepted_write_count % MAX_PTR),
			UVM_LOW
		)

	endtask

endclass


class ghr_sequencer extends uvm_sequencer #(ghr_seq_item);

    `uvm_component_utils(ghr_sequencer)

    function new(string name = "ghr_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass


class ghr_driver extends uvm_driver #(ghr_seq_item);

    `uvm_component_utils(ghr_driver)

    virtual ghr_if vif;

    function new(string name = "ghr_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(virtual ghr_if)::get(this, "", "vif", vif))
            `uvm_fatal("GHR_DRIVER", "Unable to retrieve virtual ghr_if")
    endfunction

    task run_phase(uvm_phase phase);

        drive_idle();
        wait (vif.rst_n === 1'b1);

        forever begin
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end

    endtask

    task drive_transaction(ghr_seq_item tr);

        wait (vif.rst_n === 1'b1);
        @(vif.driver_cb);

        vif.driver_cb.en_i <= tr.en;
        vif.driver_cb.br_valid_i <= tr.br_valid;
        vif.driver_cb.br_packet_i <= tr.br_packet;
        vif.driver_cb.misprediction_i <= tr.misprediction;
        vif.driver_cb.mispredicted_table_depth_i <= tr.mispredicted_table_depth;
        vif.driver_cb.recovery_active_i <= tr.recovery_active;

    endtask

    task drive_idle();

        @(vif.driver_cb);

        vif.driver_cb.en_i <= 1'b0;
        vif.driver_cb.br_valid_i <= 1'b0;
        vif.driver_cb.br_packet_i <= '0;
        vif.driver_cb.misprediction_i <= 1'b0;
        vif.driver_cb.mispredicted_table_depth_i <= '0;
        vif.driver_cb.recovery_active_i <= 1'b0;

    endtask

endclass


class ghr_monitor extends uvm_monitor;

    `uvm_component_utils(ghr_monitor)

    virtual ghr_if vif;
    uvm_analysis_port #(ghr_seq_item) monitor_port;

    longint unsigned cycle_count;

    function new(string name = "ghr_monitor", uvm_component parent = null);
        super.new(name, parent);
        monitor_port = new("monitor_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(virtual ghr_if)::get(this, "", "vif", vif))
            `uvm_fatal("GHR_MONITOR", "Unable to retrieve virtual ghr_if")
    endfunction

    task run_phase(uvm_phase phase);

        ghr_seq_item observed_tr;

	wait (vif.rst_n === 1'b0);
	@(posedge vif.clk);
        cycle_count = 0;

        forever begin
            @(vif.monitor_cb);
            cycle_count++;

            observed_tr = ghr_seq_item::type_id::create("observed_tr");

            observed_tr.sampled_cycle = cycle_count;
            observed_tr.sample_time = $time;

            observed_tr.rst_n = vif.monitor_cb.rst_n;
            observed_tr.en = vif.monitor_cb.en_i;
            observed_tr.br_valid = vif.monitor_cb.br_valid_i;
            observed_tr.br_packet = vif.monitor_cb.br_packet_i;
            observed_tr.misprediction = vif.monitor_cb.misprediction_i;
            observed_tr.mispredicted_table_depth = vif.monitor_cb.mispredicted_table_depth_i;
            observed_tr.recovery_active = vif.monitor_cb.recovery_active_i;

            observed_tr.observed_incoming_packet = vif.monitor_cb.incoming_packet_o;
            observed_tr.observed_output_valid = vif.monitor_cb.output_valid_o;

            foreach (observed_tr.observed_expiring_packet[i])
                observed_tr.observed_expiring_packet[i] = vif.monitor_cb.expiring_packet_o[i];

            monitor_port.write(observed_tr);
        end

    endtask

endclass


//scoreboard
class ghr_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(ghr_scoreboard)

    localparam int PKT_WIDTH = 7;
    localparam int NUM_BANKS = 9;
    localparam int ENTRIES_PER_BANK = 4;
    localparam int MAX_PTR = 36;
    localparam int NUM_HASH_TABLES = 7;

    localparam int TAP_DEPTHS [0:NUM_HASH_TABLES-1] = '{2, 4, 6, 8, 12, 16, 32};

    uvm_analysis_imp #(ghr_seq_item, ghr_scoreboard) analysis_export;

    logic [PKT_WIDTH-1:0] ref_bank_mem [0:ENTRIES_PER_BANK-1][0:NUM_BANKS-1];
    int unsigned ref_head_ptr;

    bit input_stage_loaded;
    bit input_stage_br_valid;
    bit [PKT_WIDTH-1:0] input_stage_br_packet;
    bit input_stage_misprediction;
    bit [5:0] input_stage_mispredicted_depth;
    bit input_stage_recovery_active;

    logic [PKT_WIDTH-1:0] ref_incoming_packet_o;
    logic [PKT_WIDTH-1:0] ref_expiring_packet_o [0:NUM_HASH_TABLES-1];
    logic ref_output_valid_o;

    int unsigned total_cycles;
    int unsigned reset_cycles;
    int unsigned total_checks;
    int unsigned passed_checks;
    int unsigned failed_checks;
    int unsigned pointer_update_count;
    int unsigned branch_write_count;
    int unsigned rollback_count;

    function new(string name = "ghr_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
        clear_reference_model();
    endfunction

    function void clear_reference_model();

        foreach (ref_bank_mem[row, bank])
            ref_bank_mem[row][bank] = '0;

        foreach (ref_expiring_packet_o[i])
            ref_expiring_packet_o[i] = '0;

        ref_head_ptr = 0;

        input_stage_loaded = 1'b0;
        input_stage_br_valid = 1'b0;
        input_stage_br_packet = '0;
        input_stage_misprediction = 1'b0;
        input_stage_mispredicted_depth = '0;
        input_stage_recovery_active = 1'b0;

        ref_incoming_packet_o = '0;
        ref_output_valid_o = 1'b0;

    endfunction

    function automatic int unsigned get_bank(input int unsigned pointer);
        return pointer % NUM_BANKS;
    endfunction

    function automatic int unsigned get_row(input int unsigned pointer);
        return pointer / NUM_BANKS;
    endfunction

    function automatic int unsigned increment_pointer(input int unsigned pointer);

        if (pointer == MAX_PTR - 1)
            return 0;

        return pointer + 1;

    endfunction

    function automatic int unsigned circular_subtract(
        input int unsigned pointer,
        input int unsigned distance
    );

        if (pointer >= distance)
            return pointer - distance;

        return pointer + MAX_PTR - distance;

    endfunction

    function automatic string get_operation_name(
        input bit branch_valid,
        input bit misprediction,
        input bit recovery_active
    );

        if (recovery_active)
            return "RECOVERY ACTIVE - OPERATION BLOCKED";

        case ({misprediction, branch_valid})
            2'b00: return "IDLE";
            2'b01: return "NORMAL BRANCH";
            2'b10: return "MISPREDICTION ROLLBACK";
            2'b11: return "ROLLBACK + REPLACEMENT BRANCH";
            default: return "UNKNOWN";
        endcase

    endfunction

    function void check_bit(
        input string check_name,
        input logic expected_value,
        input logic observed_value,
        input ghr_seq_item tr
    );

        total_checks++;

        if (observed_value !== expected_value) begin
            failed_checks++;

            `uvm_error("GHR_SCOREBOARD_MISMATCH",
                $sformatf(
                    "%s mismatch at time=%0t cycle=%0d: expected=%0b observed=%0b",
                    check_name,
                    tr.sample_time,
                    tr.sampled_cycle,
                    expected_value,
                    observed_value
                )
            )
        end
        else begin
            passed_checks++;
        end

    endfunction

    function void check_packet(
        input string check_name,
        input logic [PKT_WIDTH-1:0] expected_packet,
        input logic [PKT_WIDTH-1:0] observed_packet,
        input ghr_seq_item tr
    );

        total_checks++;

        if (observed_packet !== expected_packet) begin
            failed_checks++;

            `uvm_error("GHR_SCOREBOARD_MISMATCH",
                $sformatf(
                    "%s mismatch at time=%0t cycle=%0d: expected=0x%02h observed=0x%02h",
                    check_name,
                    tr.sample_time,
                    tr.sampled_cycle,
                    expected_packet,
                    observed_packet
                )
            )
        end
        else begin
            passed_checks++;
        end

    endfunction

    function void display_memory(
        input ghr_seq_item tr,
        input string message
    );

        int unsigned pointer;

        $display("");
        $display("================================================================================");
        $display("GHR REFERENCE MEMORY");
        $display("Time=%0t | Monitored cycle=%0d | %s", tr.sample_time, tr.sampled_cycle, message);
        $display("Reference head pointer=%0d", ref_head_ptr);
        $display("================================================================================");

        for (int row = 0; row < ENTRIES_PER_BANK; row++) begin
            $write("Row %0d :", row);

            for (int bank = 0; bank < NUM_BANKS; bank++) begin
                pointer = (row * NUM_BANKS) + bank;
                $write(" B%0d[P%02d]=0x%02h", bank, pointer, ref_bank_mem[row][bank]);
            end

            $display("");
        end

        $display("================================================================================");
        $display("");

    endfunction

    function void write(ghr_seq_item tr);

		bit stage_branch_valid;
		bit stage_misprediction;
		bit stage_operation_valid;
		bit raw_intermediate_enable;
		bit expected_pointer_enable;

		int unsigned old_head_ptr;
		int unsigned rollback_ptr;
		int unsigned next_head_ptr;
		int unsigned write_ptr;
		int unsigned write_bank;
		int unsigned write_row;

		int target_index [0:NUM_HASH_TABLES-1];
		int read_bank [0:NUM_HASH_TABLES-1];
		int read_row [0:NUM_HASH_TABLES-1];

		string operation_name;

		total_cycles++;

		if (tr.rst_n !== 1'b1) begin
			reset_cycles++;
			clear_reference_model();

			$display("");
			$display("================================================================================");
			$display("GHR RESET");
			$display("Time=%0t | Monitored cycle=%0d", tr.sample_time, tr.sampled_cycle);
			$display("Reference head, memory, pipeline state and outputs cleared");
			$display("================================================================================");
			$display("");

			display_ghr_bank("RESET STATE", tr);
			return;
		end

		old_head_ptr = ref_head_ptr;

		stage_branch_valid = input_stage_loaded && input_stage_br_valid && !input_stage_recovery_active;
		stage_misprediction = input_stage_loaded && input_stage_misprediction && !input_stage_recovery_active;
		stage_operation_valid = stage_branch_valid || stage_misprediction;

		raw_intermediate_enable = tr.en && !tr.recovery_active && (tr.br_valid || tr.misprediction);
		expected_pointer_enable = tr.en && stage_operation_valid;

		operation_name = get_operation_name(input_stage_br_valid, input_stage_misprediction, input_stage_recovery_active);

		rollback_ptr = ref_head_ptr;

		if (stage_misprediction) begin
			if ((input_stage_mispredicted_depth == 0) || (input_stage_mispredicted_depth >= MAX_PTR)) begin
				failed_checks++;

				`uvm_error("GHR_SCOREBOARD_PROTOCOL",
					$sformatf("Illegal registered misprediction depth=%0d at time=%0t cycle=%0d",
						input_stage_mispredicted_depth,
						tr.sample_time,
						tr.sampled_cycle
					)
				)
			end
			else begin
				rollback_ptr = circular_subtract(ref_head_ptr, input_stage_mispredicted_depth);
			end
		end

		next_head_ptr = ref_head_ptr;

		if (expected_pointer_enable) begin
			case ({stage_misprediction, stage_branch_valid})
				2'b00: next_head_ptr = ref_head_ptr;
				2'b01: next_head_ptr = increment_pointer(ref_head_ptr);
				2'b10: next_head_ptr = rollback_ptr;
				2'b11: next_head_ptr = increment_pointer(rollback_ptr);
				default: next_head_ptr = ref_head_ptr;
			endcase
		end

		for (int i = 0; i < NUM_HASH_TABLES; i++) begin
			target_index[i] = -1;
			read_bank[i] = -1;
			read_row[i] = -1;
		end

		if (tr.en) begin
			ref_output_valid_o = stage_branch_valid;

			if (stage_branch_valid) begin
				ref_incoming_packet_o = input_stage_br_packet;

				for (int i = 0; i < NUM_HASH_TABLES; i++) begin
					target_index[i] = circular_subtract(next_head_ptr, TAP_DEPTHS[i]);
					read_bank[i] = get_bank(target_index[i]);
					read_row[i] = get_row(target_index[i]);
					ref_expiring_packet_o[i] = ref_bank_mem[read_row[i]][read_bank[i]];
				end
			end
		end
		else begin
			ref_output_valid_o = 1'b0;
		end

		check_bit("output_valid_o", ref_output_valid_o, tr.observed_output_valid, tr);
		check_packet("incoming_packet_o", ref_incoming_packet_o, tr.observed_incoming_packet, tr);

		foreach (ref_expiring_packet_o[i]) begin
			check_packet($sformatf("expiring_packet_o[%0d]", i), ref_expiring_packet_o[i], tr.observed_expiring_packet[i], tr);
		end

		$display("");
		$display("================================================================================");
		$display("GHR CYCLE ANALYSIS");
		$display("Grouped timestamp : time=%0t | monitored cycle=%0d", tr.sample_time, tr.sampled_cycle);
		$display("================================================================================");

		$display("RAW PORT INPUTS USED AT THE MOST RECENT ACTIVE EDGE");
		$display("  en_i                         : %0b", tr.en);
		$display("  br_valid_i                   : %0b", tr.br_valid);
		$display("  br_packet_i                  : 0x%02h", tr.br_packet);
		$display("  misprediction_i              : %0b", tr.misprediction);
		$display("  mispredicted_table_depth_i   : %0d", tr.mispredicted_table_depth);
		$display("  recovery_active_i            : %0b", tr.recovery_active);

		$display("--------------------------------------------------------------------------------");
		$display("REGISTERED INPUT TRANSACTION BEING PROCESSED");
		$display("  stage loaded                 : %0b", input_stage_loaded);
		$display("  registered br_valid          : %0b", input_stage_br_valid);
		$display("  registered br_packet         : 0x%02h", input_stage_br_packet);
		$display("  registered misprediction     : %0b", input_stage_misprediction);
		$display("  registered rollback depth    : %0d", input_stage_mispredicted_depth);
		$display("  registered recovery active   : %0b", input_stage_recovery_active);
		$display("  decoded operation            : %s", operation_name);

		$display("--------------------------------------------------------------------------------");
		$display("ENABLE ALIGNMENT");
		$display("  Raw RTL intermediate enable  : %0b", raw_intermediate_enable);
		$display("  Expected pipeline enable     : %0b", expected_pointer_enable);

		if (raw_intermediate_enable != expected_pointer_enable)
			$display("  RESULT                        : ENABLE/DATA CYCLE MISALIGNMENT");
		else
			$display("  RESULT                        : Enables agree for this cycle");

		$display("--------------------------------------------------------------------------------");
		$display("POINTER CALCULATION");
		$display("  Old reference head pointer   : %0d", old_head_ptr);
		$display("  Calculated rollback pointer  : %0d", rollback_ptr);
		$display("  Calculated next head pointer : %0d", next_head_ptr);
		$display("  Pointer update expected      : %0b", expected_pointer_enable);

		$display("--------------------------------------------------------------------------------");
		$display("REGISTERED OUTPUTS");
		$display("  Expected output_valid_o      : %0b", ref_output_valid_o);
		$display("  Observed output_valid_o      : %0b", tr.observed_output_valid);
		$display("  Expected incoming_packet_o   : 0x%02h", ref_incoming_packet_o);
		$display("  Observed incoming_packet_o   : 0x%02h", tr.observed_incoming_packet);

		$display("--------------------------------------------------------------------------------");
		$display("EXPIRING-PACKET TABLE");
		$display(" Tap | Depth | Target | Row | Bank | Expected | Observed | Result");
		$display("-----+-------+--------+-----+------+----------+----------+--------");

		for (int i = 0; i < NUM_HASH_TABLES; i++) begin
			if (target_index[i] >= 0) begin
				$display(" %3d | %5d | %6d | %3d | %4d |   0x%02h   |   0x%02h   | %s",
					i,
					TAP_DEPTHS[i],
					target_index[i],
					read_row[i],
					read_bank[i],
					ref_expiring_packet_o[i],
					tr.observed_expiring_packet[i],
					(ref_expiring_packet_o[i] === tr.observed_expiring_packet[i]) ? "PASS" : "FAIL"
				);
			end
			else begin
				$display(" %3d | %5d |    N/A | N/A |  N/A |   0x%02h   |   0x%02h   | %s",
					i,
					TAP_DEPTHS[i],
					ref_expiring_packet_o[i],
					tr.observed_expiring_packet[i],
					(ref_expiring_packet_o[i] === tr.observed_expiring_packet[i]) ? "HOLD" : "FAIL"
				);
			end
		end

		$display("================================================================================");
		$display("");

		// Apply the registered transaction's memory write.
		if (tr.en && stage_branch_valid) begin
			branch_write_count++;

			if (stage_misprediction)
				write_ptr = rollback_ptr;
			else
				write_ptr = ref_head_ptr;

			write_bank = get_bank(write_ptr);
			write_row = get_row(write_ptr);
			ref_bank_mem[write_row][write_bank] = input_stage_br_packet;

			$display("");
			$display("================================================================================");
			$display("GHR MEMORY WRITE");
			$display("Grouped timestamp : time=%0t | monitored cycle=%0d", tr.sample_time, tr.sampled_cycle);
			$display("Write pointer     : P%02d", write_ptr);
			$display("Physical location : Row %0d, Bank %0d", write_row, write_bank);
			$display("Written packet    : 0x%02h", input_stage_br_packet);
			$display("================================================================================");
			$display("");
		end

		// Commit the modeled pointer update.
		if (expected_pointer_enable) begin
			pointer_update_count++;
			ref_head_ptr = next_head_ptr;
		end

		if (tr.en && stage_misprediction) rollback_count++;

		display_ghr_bank($sformatf("END-OF-CYCLE STATE | Processed operation: %s", operation_name),tr);

		// Display the bank after memory and pointer updates, but before loading the next raw input transaction.
		// if (tr.en && stage_operation_valid) begin
		//	display_ghr_bank("STATE AFTER PROCESSED REGISTERED TRANSACTION", tr);
		// end

		// Capture the current raw inputs into the modeled input-register stage.
		if (tr.en) begin
			input_stage_loaded = 1'b1;
			input_stage_br_valid = tr.br_valid;
			input_stage_br_packet = tr.br_packet;
			input_stage_misprediction = tr.misprediction;
			input_stage_mispredicted_depth = tr.mispredicted_table_depth;
			input_stage_recovery_active = tr.recovery_active;
		end

	endfunction

	function void display_ghr_bank(input string message, input ghr_seq_item tr);

		int unsigned pointer;
		int unsigned head_bank;
		int unsigned head_row;

		head_bank = get_bank(ref_head_ptr);
		head_row = get_row(ref_head_ptr);

		$display("");
		$display("========================================================================================================================");
		$display("GHR PHYSICAL BANK MEMORY");
		$display("Simulation time : %0t", tr.sample_time);
		$display("Monitored cycle : %0d", tr.sampled_cycle);
		$display("State           : %s", message);
		$display("Head pointer    : P%02d -> Row %0d, Bank %0d", ref_head_ptr, head_row, head_bank);
		$display("========================================================================================================================");

		$write("%-11s", "ROW/BANK");
		for (int bank = 0; bank < NUM_BANKS; bank++) begin
			$write("|     B%-2d     ", bank);
		end
		$display("|");

		$display("------------------------------------------------------------------------------------------------------------------------");

		for (int row = 0; row < ENTRIES_PER_BANK; row++) begin
			$write("ROW %-7d", row);

			for (int bank = 0; bank < NUM_BANKS; bank++) begin
				pointer = (row * NUM_BANKS) + bank;
				$write("| P%02d : 0x%02h ", pointer, ref_bank_mem[row][bank]);
			end

			$display("|");
		end

		$display("========================================================================================================================");
		$display("");

	endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("GHR_SCOREBOARD_SUMMARY",
            $sformatf(
                {
                    "\n============================================================\n",
                    "GHR SCOREBOARD SUMMARY\n",
                    "============================================================\n",
                    "Total monitored cycles : %0d\n",
                    "Reset cycles           : %0d\n",
                    "Pointer updates        : %0d\n",
                    "Branch writes          : %0d\n",
                    "Rollback operations    : %0d\n",
                    "Total checks           : %0d\n",
                    "Passed checks          : %0d\n",
                    "Failed checks          : %0d\n",
                    "Final reference head   : %0d\n",
                    "============================================================"
                },
                total_cycles,
                reset_cycles,
                pointer_update_count,
                branch_write_count,
                rollback_count,
                total_checks,
                passed_checks,
                failed_checks,
                ref_head_ptr
            ),
            UVM_NONE
        )

        if (failed_checks == 0)
            `uvm_info("GHR_SCOREBOARD_RESULT", "TEST RESULT: PASS", UVM_NONE)
        else
            `uvm_error("GHR_SCOREBOARD_RESULT",
                $sformatf("TEST RESULT: FAIL with %0d failed checks", failed_checks)
            )

    endfunction

endclass


class ghr_agent extends uvm_agent;

	`uvm_component_utils(ghr_agent)

	ghr_sequencer sequencer;
	ghr_driver driver;
	ghr_monitor monitor;

	function new(string name = "ghr_agent", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		monitor = ghr_monitor::type_id::create("monitor", this);

		if (get_is_active() == UVM_ACTIVE) begin
			sequencer = ghr_sequencer::type_id::create("sequencer", this);
			driver = ghr_driver::type_id::create("driver", this);
		end
	endfunction

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		if (get_is_active() == UVM_ACTIVE) begin
			driver.seq_item_port.connect(sequencer.seq_item_export);
		end
	endfunction

endclass


// env
class ghr_env extends uvm_env;

	`uvm_component_utils(ghr_env)

	ghr_agent agent;
	ghr_scoreboard scoreboard;

	function new(string name = "ghr_env", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		agent = ghr_agent::type_id::create("agent", this);
		scoreboard = ghr_scoreboard::type_id::create("scoreboard", this);
	endfunction

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		agent.monitor.monitor_port.connect(scoreboard.analysis_export);
	endfunction

endclass


class ghr_base_test extends uvm_test;

	`uvm_component_utils(ghr_base_test)

	ghr_env env;

	function new(string name = "ghr_base_test", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		env = ghr_env::type_id::create("env", this);
	endfunction

	virtual task run_phase(uvm_phase phase);

		ghr_pipeline_smoke_sequence smoke_sequence;
		GHR_2CYCLE_ALTERNATING_ENABLE_sequence alternating_enable_sequence;

		phase.raise_objection(this);
		// smoke_sequence = ghr_pipeline_smoke_sequence::type_id::create("smoke_sequence");
		// smoke_sequence.start(env.agent.sequencer);

		alternating_enable_sequence = GHR_2CYCLE_ALTERNATING_ENABLE_sequence::type_id::create("alternating_enable_sequence");
		alternating_enable_sequence.start(env.agent.sequencer);

		phase.drop_objection(this);

	endtask


	virtual function void end_of_elaboration_phase(uvm_phase phase);
		super.end_of_elaboration_phase(phase);
		uvm_top.print_topology();
	endfunction

endclass

// tb top
module ghr_tb_top_2reg;

	import uvm_pkg::*;
	import ghr_params_pkg::*;

	logic clk;

	initial clk = 1'b0;
	always #5 clk = ~clk;

	ghr_if #(
		.PKT_WIDTH(PKT_WIDTH),
		.NUM_HASH_TABLES(NUM_HASH_TABLES)
	) ghr_vif (
		.clk(clk)
	);

	LP_ghr_block_2reg #(
		.PKT_WIDTH(PKT_WIDTH),
		.NUM_BANKS(NUM_BANKS),
		.ENTRIES_PER_BANK(ENTRIES_PER_BANK),
		.MAX_PTR(MAX_PTR),
		.NUM_HASH_TABLES(NUM_HASH_TABLES)
	) dut (
		.clk(clk),
		.rst_n(ghr_vif.rst_n),
		.en_i(ghr_vif.en_i),
		.br_valid_i(ghr_vif.br_valid_i),
		.br_packet_i(ghr_vif.br_packet_i),
		.misprediction_i(ghr_vif.misprediction_i),
		.mispredicted_table_depth_i(ghr_vif.mispredicted_table_depth_i),
		.recovery_active_i(ghr_vif.recovery_active_i),
		.incoming_packet_o(ghr_vif.incoming_packet_o),
		.expiring_packet_o(ghr_vif.expiring_packet_o),
		.output_valid_o(ghr_vif.output_valid_o)
	);

	initial begin
		ghr_vif.rst_n = 1'b0;
		ghr_vif.en_i = 1'b0;
		ghr_vif.br_valid_i = 1'b0;
		ghr_vif.br_packet_i = '0;
		ghr_vif.misprediction_i = 1'b0;
		ghr_vif.mispredicted_table_depth_i = '0;
		ghr_vif.recovery_active_i = 1'b0;

		repeat (3) @(negedge clk);
		ghr_vif.rst_n = 1'b1;
	end

	initial begin
		uvm_config_db #(virtual ghr_if)::set(null, "*", "vif", ghr_vif);
		run_test("ghr_base_test");
	end

	initial begin
		#100000;
		`uvm_fatal("GHR_TB_TIMEOUT", "Simulation exceeded the allowed runtime")
	end

endmodule


