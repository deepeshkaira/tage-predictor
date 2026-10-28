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

		packet_t enabled_packet_1;
		packet_t enabled_packet_2;
		packet_t disabled_packet;
		int unsigned accepted_write_count = 0;
		int unsigned number_of_groups = 20;

		`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE", $sformatf("Starting %0d groups with enable pattern 1,1,0", number_of_groups), UVM_LOW)

		for (int group = 0; group < number_of_groups; group++) begin

			if (!std::randomize(enabled_packet_1, enabled_packet_2, disabled_packet) with {
				enabled_packet_1 inside {[7'h01:7'h7F]};
				enabled_packet_2 inside {[7'h01:7'h7F]};
				disabled_packet inside {[7'h01:7'h7F]};
				enabled_packet_2 != enabled_packet_1;
				disabled_packet != enabled_packet_1;
				disabled_packet != enabled_packet_2;
			}) begin
				`uvm_fatal("GHR_2CYCLE_ALTERNATING_ENABLE", "Packet randomization failed")
			end

			`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE",$sformatf("Group=%0d Slot=EN1 Write=%0d Expected pointer=%0d Packet=0x%02h",group, accepted_write_count, accepted_write_count % MAX_PTR,enabled_packet_1),UVM_MEDIUM)

			drive_cycle(
				.en(1'b1),
				.br_valid(1'b1),
				.br_packet(enabled_packet_1),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);

			accepted_write_count++;

			`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE",$sformatf("Group=%0d Slot=EN2 Write=%0d Expected pointer=%0d Packet=0x%02h",group, accepted_write_count, accepted_write_count % MAX_PTR, enabled_packet_2),UVM_MEDIUM)

			drive_cycle(
				.en(1'b1),
				.br_valid(1'b1),
				.br_packet(enabled_packet_2),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);

			accepted_write_count++;

			`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE",$sformatf("Group=%0d Slot=DISABLED Raw packet=0x%02h -- must not be written",group, disabled_packet),UVM_MEDIUM)

			drive_cycle(
				.en(1'b0),
				.br_valid(1'b1),
				.br_packet(disabled_packet),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);
		end

		repeat (4) idle_cycle();

		`uvm_info("GHR_2CYCLE_ALTERNATING_ENABLE",$sformatf("Completed 1,1,0 enable sequence with %0d accepted writes", accepted_write_count),UVM_LOW)

	endtask

endclass


// TRUE ALTERNATING ENABLE SEQUENCE
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

			`uvm_info("GHR_ALTERNATING_ENABLE",$sformatf("Transaction=%0d ENABLED packet=0x%02h expected_write=%0d",transaction, enabled_packet, accepted_write_count),UVM_MEDIUM)

			drive_cycle(
				.en(1'b1),
				.br_valid(1'b1),
				.br_packet(enabled_packet),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);

			accepted_write_count++;

			`uvm_info("GHR_ALTERNATING_ENABLE",$sformatf("Transaction=%0d DISABLED raw_packet=0x%02h; packet must not enter GHR",transaction, disabled_packet),UVM_MEDIUM)

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

		`uvm_info("GHR_ALTERNATING_ENABLE",$sformatf("Completed alternating-enable sequence. Accepted writes=%0d expected final head=%0d",accepted_write_count, accepted_write_count % MAX_PTR),UVM_LOW)

	endtask

endclass


/// reset sequence 
class ghr_reset_idle_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_reset_idle_sequence)

		virtual ghr_if ghr_vif;

	function new(string name = "ghr_reset_idle_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;

		if (!uvm_config_db #(virtual ghr_if)::get(null, "*", "vif", ghr_vif))
			`uvm_fatal("GHR_RESET_IDLE_SEQUENCE", "Unable to retrieve virtual ghr_if")

		`uvm_info("GHR_RESET_IDLE_SEQUENCE", "Starting reset assertion/deassertion sequence", UVM_LOW)

		wait (ghr_vif.rst_n === 1'b1);		// running with reset = 1

		repeat (2) idle_cycle();

		// Insert packets so the pointer, memory and outputs contain non-reset values.
		for (int write_number = 0; write_number < 8; write_number++) begin
			packet = packet_t'(write_number + 1);
			branch_cycle(packet);
		end

		// Drain the pending pipeline transaction before asserting reset.
		repeat (3) idle_cycle();

		`uvm_info("GHR_RESET_IDLE_SEQUENCE", "Normal operation completed. Asserting asynchronous reset", UVM_LOW)

		// Assert active-low reset between clock edges.
		@(negedge ghr_vif.clk);
		#2;
		ghr_vif.rst_n = 1'b0;

		// Check asynchronously cleared interface outputs.
		#1;

		if (ghr_vif.incoming_packet_o !== '0)
			`uvm_error("GHR_RESET_IDLE_SEQUENCE", $sformatf("incoming_packet_o did not clear during reset: observed=0x%02h", ghr_vif.incoming_packet_o))

		if (ghr_vif.output_valid_o !== 1'b0)
			`uvm_error("GHR_RESET_IDLE_SEQUENCE", $sformatf("output_valid_o did not clear during reset: observed=%0b", ghr_vif.output_valid_o))

		foreach (ghr_vif.expiring_packet_o[i]) begin
			if (ghr_vif.expiring_packet_o[i] !== '0)
				`uvm_error("GHR_RESET_IDLE_SEQUENCE", $sformatf("expiring_packet_o[%0d] did not clear during reset: observed=0x%02h", i, ghr_vif.expiring_packet_o[i]))
		end

		// Hold reset active across two rising clock edges.
		repeat (2) @(posedge ghr_vif.clk);

		`uvm_info("GHR_RESET_IDLE_SEQUENCE", "Reset checks completed. Deasserting reset", UVM_LOW)

		
		@(negedge ghr_vif.clk);		// Phase 3: Deassert reset between clock edges.
		#2;
		ghr_vif.rst_n = 1'b1;

		// Confirm that the reset state remains stable after deassertion.
		repeat (3) idle_cycle();

		// Phase 4: Confirm operation restarts from pointer zero.
		branch_cycle(7'h61);
		branch_cycle(7'h62);
		branch_cycle(7'h63);

		// Drain the final pending transaction.
		repeat (3) idle_cycle();

		`uvm_info("GHR_RESET_IDLE_SEQUENCE",
			"Completed reset sequence. Expected final head pointer=3 with packets 0x61, 0x62 and 0x63 at pointers 0, 1 and 2",
			UVM_LOW
		)

	endtask

endclass


///continuous write sequence
class ghr_continuous_write_sequence extends ghr_base_sequence;

`uvm_object_utils(ghr_continuous_write_sequence)

	function new(string name = "ghr_continuous_write_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		int unsigned number_of_writes = 20;

		`uvm_info("GHR_CONTINUOUS_WRITE_SEQUENCE",$sformatf("Starting %0d consecutive branch writes with en_i continuously high", number_of_writes),UVM_LOW)

		// Initial enabled-idle cycles after reset.
		repeat (2) idle_cycle();

		// Present one new branch packet during every enabled cycle.
		for (int write_number = 0; write_number < number_of_writes; write_number++) begin
			packet = packet_t'(write_number + 1);
			`uvm_info("GHR_CONTINUOUS_WRITE_SEQUENCE",$sformatf("Input transaction=%0d packet=0x%02h expected_pointer=%0d",write_number, packet, write_number % MAX_PTR),UVM_MEDIUM)
			branch_cycle(packet);
		end

		// The final input transaction remains pending in the input register. The first idle cycle processes it, and the remaining cycles drain outputs.
		repeat (4) idle_cycle();

		`uvm_info("GHR_CONTINUOUS_WRITE_SEQUENCE",$sformatf("Completed continuous-write sequence. Expected writes=%0d expected final head=%0d",number_of_writes, number_of_writes % MAX_PTR),UVM_LOW)

	endtask

endclass


/// fill enable seq
class ghr_fill_level_enable_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_fill_level_enable_sequence)

	function new(string name = "ghr_fill_level_enable_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		int unsigned packet_number = 1;
		int unsigned accepted_write_count = 0;

		`uvm_info("GHR_FILL_LEVEL_ENABLE_SEQUENCE","Starting enable-pattern checks at empty, half-populated and fully populated GHR states",UVM_LOW)

		repeat (2) idle_cycle();

		// Phase 1: Begin from empty memory. Pattern: one enabled cycle followed by one disabled cycle.
		for (int iteration = 0; iteration < 8; iteration++) begin
			packet = packet_t'(packet_number);

			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;

			drive_cycle(
				.en(1'b0),
				.br_valid(1'b1),
				.br_packet(packet_t'(7'h70 + iteration)),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);
		end

		// Commit the last pending transaction.
		repeat (3) idle_cycle();

		`uvm_info("GHR_FILL_LEVEL_ENABLE_SEQUENCE",$sformatf("Initial alternating phase complete: accepted=%0d expected_head=%0d",accepted_write_count, accepted_write_count % MAX_PTR),UVM_LOW)

		// Fill until exactly 18 packets have been accepted.
		while (accepted_write_count < 18) begin
			packet = packet_t'(packet_number);
			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;
		end

		repeat (3) idle_cycle();

		`uvm_info("GHR_FILL_LEVEL_ENABLE_SEQUENCE","Half-populated checkpoint reached: 18 accepted writes and expected head pointer=18",UVM_LOW)

		// Phase 2: Check a two-enabled/one-disabled pattern when half populated.
		for (int iteration = 0; iteration < 8; iteration++) begin
			packet = packet_t'(packet_number);
			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;

			packet = packet_t'(packet_number);
			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;

			drive_cycle(
				.en(1'b0),
				.br_valid(1'b1),
				.br_packet(packet_t'(7'h60 + iteration)),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);
		end

		repeat (3) idle_cycle();

		`uvm_info("GHR_FILL_LEVEL_ENABLE_SEQUENCE",$sformatf("Half-populated enable-pattern phase complete: accepted=%0d expected_head=%0d",accepted_write_count, accepted_write_count % MAX_PTR),UVM_LOW)

		// Continue writing until all 36 physical locations have been populated.
		while (accepted_write_count < MAX_PTR) begin
			packet = packet_t'(packet_number);
			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;
		end

		repeat (3) idle_cycle();

		`uvm_info("GHR_FILL_LEVEL_ENABLE_SEQUENCE","Full-memory checkpoint reached: 36 accepted writes and expected head pointer=0",UVM_LOW)

		// Phase 3: Repeat the one-enabled/one-disabled pattern after the GHR is full. These writes wrap around and overwrite pointers 0 through 7.
		for (int iteration = 0; iteration < 8; iteration++) begin
			packet = packet_t'(packet_number);

			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;

			drive_cycle(
				.en(1'b0),
				.br_valid(1'b1),
				.br_packet(packet_t'(7'h50 + iteration)),
				.misprediction(1'b0),
				.mispredicted_depth(6'd0),
				.recovery_active(1'b0)
			);
		end

		repeat (4) idle_cycle();

		`uvm_info("GHR_FILL_LEVEL_ENABLE_SEQUENCE",$sformatf("Completed fill-level sequence: accepted writes=%0d expected final head=%0d",accepted_write_count, accepted_write_count % MAX_PTR),UVM_LOW)

	endtask

endclass


//packet value sequences - checking that validity comes from control signals
// to check that the packet's value does not determine its validity
class ghr_packet_value_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_packet_value_sequence)

	function new(string name = "ghr_packet_value_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet_patterns [0:7] = '{7'h00,7'h01,7'h7F,7'h55,7'h2A,7'h20,7'h40,7'h6D};

		int unsigned accepted_write_count = 0;
		int unsigned number_of_rounds = 5;

		`uvm_info("GHR_PACKET_VALUE_SEQUENCE",$sformatf("Starting packet-value sequence with %0d rounds", number_of_rounds),UVM_LOW)

		repeat (2) idle_cycle();

		for (int round = 0; round < number_of_rounds; round++) begin

			`uvm_info("GHR_PACKET_VALUE_SEQUENCE",$sformatf("Starting round=%0d at expected head pointer=%0d",round, accepted_write_count % MAX_PTR),UVM_LOW)

			for (int pattern = 0; pattern < 8; pattern++) begin

				`uvm_info("GHR_PACKET_VALUE_SEQUENCE",$sformatf("Round=%0d pattern=%0d packet=0x%02h expected_pointer=%0d",round, pattern, packet_patterns[pattern], accepted_write_count % MAX_PTR),UVM_MEDIUM)

				branch_cycle(packet_patterns[pattern]);
				accepted_write_count++;
			end

			// Process the final registered transaction and create a clean burst boundary before the next round.
			repeat (3) idle_cycle();

			`uvm_info("GHR_PACKET_VALUE_SEQUENCE",$sformatf("Completed round=%0d accepted_writes=%0d expected_head=%0d",round, accepted_write_count, accepted_write_count % MAX_PTR),UVM_LOW)

		end

		repeat (2) idle_cycle();

		`uvm_info("GHR_PACKET_VALUE_SEQUENCE",$sformatf("Completed packet-value sequence: accepted writes=%0d expected final head=%0d",accepted_write_count, accepted_write_count % MAX_PTR),UVM_LOW)

	endtask

endclass



// bank boundary sequence
class ghr_bank_boundary_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_bank_boundary_sequence)

	function new(string name = "ghr_bank_boundary_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		int unsigned accepted_write_count = 0;
		int unsigned boundary_pointer [0:3] = '{8, 17, 26, 35};
		packet_t boundary_packet [0:3] = '{7'h48, 7'h51, 7'h5A, 7'h63};
		packet_t next_row_packet [0:3] = '{7'h49, 7'h52, 7'h5B, 7'h64};

		`uvm_info("GHR_BANK_BOUNDARY_SEQUENCE", "Starting physical bank and row boundary verification", UVM_LOW)

		repeat (2) idle_cycle();

		for (int boundary = 0; boundary < 4; boundary++) begin

			// Fill until the head reaches the required boundary pointer.
			while ((accepted_write_count % MAX_PTR) != boundary_pointer[boundary]) begin
				packet = packet_t'((accepted_write_count % 7'h7F) + 1);
				branch_cycle(packet);
				accepted_write_count++;
			end

			// Commit the final fill transaction before testing the boundary.
			repeat (3) idle_cycle();

			`uvm_info("GHR_BANK_BOUNDARY_SEQUENCE", $sformatf("Testing boundary=%0d first_pointer=%0d second_pointer=%0d", boundary, boundary_pointer[boundary], (boundary_pointer[boundary] + 1) % MAX_PTR), UVM_LOW)

			// Write to Bank 8 of the current row.
			`uvm_info("GHR_BANK_BOUNDARY_SEQUENCE", $sformatf("Writing packet=0x%02h to pointer=%0d row=%0d bank=8", boundary_packet[boundary], boundary_pointer[boundary], boundary_pointer[boundary] / NUM_BANKS), UVM_MEDIUM)

			branch_cycle(boundary_packet[boundary]);
			accepted_write_count++;

			// Write to Bank 0 of the next row or wrap from pointer 35 to pointer 0.
			`uvm_info("GHR_BANK_BOUNDARY_SEQUENCE", $sformatf("Writing packet=0x%02h to pointer=%0d row=%0d bank=0", next_row_packet[boundary], accepted_write_count % MAX_PTR, (accepted_write_count % MAX_PTR) / NUM_BANKS), UVM_MEDIUM)

			branch_cycle(next_row_packet[boundary]);
			accepted_write_count++;

			// Commit the second boundary transaction and drain the pipeline.
			repeat (3) idle_cycle();

			`uvm_info("GHR_BANK_BOUNDARY_SEQUENCE", $sformatf("Boundary=%0d complete: accepted writes=%0d expected head=%0d", boundary, accepted_write_count, accepted_write_count % MAX_PTR), UVM_LOW)
		end

		repeat (2) idle_cycle();

		`uvm_info("GHR_BANK_BOUNDARY_SEQUENCE", $sformatf("Completed bank-boundary sequence: accepted writes=%0d expected final head=%0d", accepted_write_count, accepted_write_count % MAX_PTR), UVM_LOW)

	endtask

endclass


/// full memory wrap sequnce
class ghr_full_wrap_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_full_wrap_sequence)

	function new(string name = "ghr_full_wrap_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		packet_t pass_base [0:2] = '{7'h01, 7'h41, 7'h21};
		int unsigned accepted_write_count = 0;
		int unsigned number_of_passes = 3;

		`uvm_info("GHR_FULL_WRAP_SEQUENCE", $sformatf("Starting %0d complete passes through the 36-entry GHR", number_of_passes), UVM_LOW)

		repeat (2) idle_cycle();

		for (int pass = 0; pass < number_of_passes; pass++) begin

			`uvm_info("GHR_FULL_WRAP_SEQUENCE", $sformatf("Starting pass=%0d expected starting head=%0d packet base=0x%02h", pass, accepted_write_count % MAX_PTR, pass_base[pass]), UVM_LOW)

			for (int pointer = 0; pointer < MAX_PTR; pointer++) begin
				packet = packet_t'(pass_base[pass] + pointer);

				`uvm_info("GHR_FULL_WRAP_SEQUENCE", $sformatf("Pass=%0d pointer=%0d row=%0d bank=%0d packet=0x%02h", pass, pointer, pointer / NUM_BANKS, pointer % NUM_BANKS, packet), UVM_MEDIUM)

				branch_cycle(packet);
				accepted_write_count++;
			end

			// Commit the packet written to pointer 35 and drain the output pipeline.
			repeat (4) idle_cycle();

			`uvm_info("GHR_FULL_WRAP_SEQUENCE", $sformatf("Completed pass=%0d accepted writes=%0d expected head=%0d", pass, accepted_write_count, accepted_write_count % MAX_PTR), UVM_LOW)
		end

		`uvm_info("GHR_FULL_WRAP_SEQUENCE", $sformatf("Completed full-wrap sequence: accepted writes=%0d expected final head=%0d", accepted_write_count, accepted_write_count % MAX_PTR), UVM_LOW)

	endtask

endclass



/// fill memory and then selecively tap the mem locations to write on
class ghr_tap_depth_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_tap_depth_sequence)

	function new(string name = "ghr_tap_depth_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		packet_t expected_memory [0:MAX_PTR-1];
		int unsigned tap_depths [0:NUM_HASH_TABLES-1] = '{2, 4, 6, 8, 12, 16, 32};
		int unsigned expected_head = 0;
		int unsigned write_pointer;
		int unsigned next_head;
		int unsigned target_pointer;
		int unsigned number_of_probes = 12;

		`uvm_info("GHR_TAP_DEPTH_SEQUENCE", "Starting exact geometric-history tap verification", UVM_LOW)

		foreach (expected_memory[pointer]) expected_memory[pointer] = '0;

		repeat (2) idle_cycle();

		// Initialize every physical GHR location with a known packet.
		for (int pointer = 0; pointer < MAX_PTR; pointer++) begin
			packet = packet_t'(pointer + 1);
			branch_cycle(packet);
			expected_memory[pointer] = packet;
			expected_head = (expected_head + 1) % MAX_PTR;
		end

		// Commit pointer 35 and return the expected head to pointer zero.
		repeat (4) idle_cycle();

		`uvm_info("GHR_TAP_DEPTH_SEQUENCE", $sformatf("Initial fill completed. Expected head=%0d", expected_head), UVM_LOW)

		// Apply isolated probe writes at pointers 0 through 11.
		for (int probe = 0; probe < number_of_probes; probe++) begin

			packet = packet_t'(7'h60 + probe);
			write_pointer = expected_head;
			next_head = (expected_head + 1) % MAX_PTR;

			`uvm_info("GHR_TAP_DEPTH_SEQUENCE", $sformatf("Probe=%0d packet=0x%02h write_pointer=%0d next_head=%0d", probe, packet, write_pointer, next_head), UVM_LOW)

			// Log the expected physical source location and packet for every tap.
			for (int tap = 0; tap < NUM_HASH_TABLES; tap++) begin
				target_pointer = (next_head + MAX_PTR - tap_depths[tap]) % MAX_PTR;

				`uvm_info("GHR_TAP_DEPTH_EXPECTATION", $sformatf("Probe=%0d tap=%0d depth=%0d target_pointer=%0d row=%0d bank=%0d expected_packet=0x%02h", probe, tap, tap_depths[tap], target_pointer, target_pointer / NUM_BANKS, target_pointer % NUM_BANKS, expected_memory[target_pointer]), UVM_MEDIUM)
			end

			branch_cycle(packet);

			expected_memory[write_pointer] = packet;
			expected_head = next_head;

			// Process the probe independently and return the pipeline to idle.
			repeat (3) idle_cycle();
		end

		`uvm_info("GHR_TAP_DEPTH_SEQUENCE", $sformatf("Completed tap-depth sequence. Expected final head=%0d", expected_head), UVM_LOW)

	endtask

endclass



/// output alignment with continous traffic, disabled cycles and restarts
class ghr_output_alignment_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_output_alignment_sequence)

	function new(string name = "ghr_output_alignment_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		packet_t disabled_packet;
		int unsigned stall_cycles;
		int unsigned accepted_write_count = 0;
		int unsigned number_of_transactions = 16;

		`uvm_info("GHR_OUTPUT_ALIGNMENT_SEQUENCE", "Starting incoming, expiring and output-valid alignment verification", UVM_LOW)

		repeat (2) idle_cycle();

		// Fill all 36 locations so every geometric-history tap contains meaningful data.
		for (int pointer = 0; pointer < MAX_PTR; pointer++) begin
			packet = packet_t'(pointer + 1);
			branch_cycle(packet);
			accepted_write_count++;
		end

		// Commit pointer 35 and return the pipeline to idle.
		repeat (4) idle_cycle();

		`uvm_info("GHR_OUTPUT_ALIGNMENT_SEQUENCE", $sformatf("Initial GHR fill complete: accepted=%0d expected_head=%0d", accepted_write_count, accepted_write_count % MAX_PTR), UVM_LOW)

		for (int transaction = 0; transaction < number_of_transactions; transaction++) begin

			packet = packet_t'(7'h50 + transaction);
			disabled_packet = packet_t'(7'h20 + transaction);
			stall_cycles = transaction % 4;

			`uvm_info("GHR_OUTPUT_ALIGNMENT_SEQUENCE", $sformatf("Transaction=%0d packet=0x%02h expected_write_pointer=%0d stall_cycles=%0d", transaction, packet, accepted_write_count % MAX_PTR, stall_cycles), UVM_LOW)

			branch_cycle(packet);
			accepted_write_count++;

			// Hold the pipeline for zero, one, two or three cycles while raw inputs continue toggling.
			repeat (stall_cycles) begin
				drive_cycle(.en(1'b0), .br_valid(1'b1), .br_packet(disabled_packet), .misprediction(1'b0), .mispredicted_depth(6'd0), .recovery_active(1'b0));
			end

			// Every fourth transaction is followed by an enabled bubble to test a complete valid-to-idle-to-valid transition.
			if (((transaction + 1) % 4) == 0) repeat (3) idle_cycle();
		end

		// Commit the final transaction and drain all registered outputs.
		repeat (5) idle_cycle();

		`uvm_info("GHR_OUTPUT_ALIGNMENT_SEQUENCE", $sformatf("Completed output-alignment sequence: accepted writes=%0d expected final head=%0d", accepted_write_count, accepted_write_count % MAX_PTR), UVM_LOW)

	endtask

endclass


/// rollback only sequence
class ghr_rollback_only_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_rollback_only_sequence)

	function new(string name = "ghr_rollback_only_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		int unsigned rollback_depths [0:7] = '{1, 2, 4, 8, 12, 16, 32, 35};
		int unsigned expected_head = 0;
		int unsigned packet_number = 1;
		int unsigned expected_rollback_head;

		`uvm_info("GHR_ROLLBACK_ONLY_SEQUENCE", "Starting rollback-only verification across multiple legal depths", UVM_LOW)

		repeat (2) idle_cycle();

		// Fill all 36 locations so every rollback depth is initially legal.
		for (int pointer = 0; pointer < MAX_PTR; pointer++) begin
			packet = packet_t'((packet_number % 7'h7F) + 1);
			branch_cycle(packet);
			packet_number++;
			expected_head = (expected_head + 1) % MAX_PTR;
		end

		repeat (4) idle_cycle();

		`uvm_info("GHR_ROLLBACK_ONLY_SEQUENCE", $sformatf("Initial fill complete. Expected head=%0d", expected_head), UVM_LOW)

		for (int iteration = 0; iteration < 8; iteration++) begin

			expected_rollback_head = (expected_head + MAX_PTR - rollback_depths[iteration]) % MAX_PTR;

			`uvm_info("GHR_ROLLBACK_ONLY_SEQUENCE", $sformatf("Iteration=%0d old_head=%0d rollback_depth=%0d expected_recovered_head=%0d", iteration, expected_head, rollback_depths[iteration], expected_rollback_head), UVM_LOW)

			// Rollback without a simultaneous replacement branch.
			misprediction_cycle(history_depth_t'(rollback_depths[iteration]));
			expected_head = expected_rollback_head;

			// Process the registered rollback and return the pipeline to idle.
			repeat (3) idle_cycle();

			`uvm_info("GHR_ROLLBACK_ONLY_SEQUENCE", $sformatf("Rollback processed. No memory write expected. Current expected head=%0d", expected_head), UVM_LOW)

			// Refill exactly the number of entries removed by the rollback.
			for (int refill = 0; refill < rollback_depths[iteration]; refill++) begin
				packet = packet_t'((packet_number % 7'h7F) + 1);

				`uvm_info("GHR_ROLLBACK_ONLY_SEQUENCE", $sformatf("Iteration=%0d refill=%0d packet=0x%02h expected_write_pointer=%0d", iteration, refill, packet, expected_head), UVM_MEDIUM)

				branch_cycle(packet);
				packet_number++;
				expected_head = (expected_head + 1) % MAX_PTR;
			end

			// Commit the final refill transaction before the next rollback.
			repeat (4) idle_cycle();

			`uvm_info("GHR_ROLLBACK_ONLY_SEQUENCE", $sformatf("Iteration=%0d refill complete. Expected head=%0d", iteration, expected_head), UVM_LOW)
		end

		`uvm_info("GHR_ROLLBACK_ONLY_SEQUENCE", $sformatf("Completed rollback-only sequence. Expected final head=%0d", expected_head), UVM_LOW)

	endtask

endclass



//// rollback across zero sequence - (currnt head ptr < rollback depth)
class ghr_rollback_across_zero_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_rollback_across_zero_sequence)

	function new(string name = "ghr_rollback_across_zero_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		int unsigned starting_heads [0:3] = '{1, 3, 5, 7};
		int unsigned rollback_depths [0:3] = '{2, 8, 16, 32};
		int unsigned expected_head = 0;
		int unsigned expected_rollback_head;
		int unsigned packet_number = 1;
		int unsigned accepted_write_count = 0;

		`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE", "Starting rollback verification across circular pointer zero", UVM_LOW)

		repeat (2) idle_cycle();

		// Fill all memory locations so every wrapped read and replacement location contains valid history.
		for (int pointer = 0; pointer < MAX_PTR; pointer++) begin
			packet = packet_t'((packet_number % 7'h7F) + 1);
			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;
			expected_head = (expected_head + 1) % MAX_PTR;
		end

		repeat (4) idle_cycle();

		`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE", $sformatf("Initial fill complete. Expected head=%0d", expected_head), UVM_LOW)

		for (int iteration = 0; iteration < 4; iteration++) begin

			// Advance normally until the required low starting pointer is reached.
			while (expected_head != starting_heads[iteration]) begin
				packet = packet_t'((packet_number % 7'h7F) + 1);
				branch_cycle(packet);
				packet_number++;
				accepted_write_count++;
				expected_head = (expected_head + 1) % MAX_PTR;
			end

			repeat (3) idle_cycle();

			expected_rollback_head = (expected_head + MAX_PTR - rollback_depths[iteration]) % MAX_PTR;

			`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE", $sformatf("Iteration=%0d old_head=%0d depth=%0d expected_wrapped_head=%0d", iteration, expected_head, rollback_depths[iteration], expected_rollback_head), UVM_LOW)

			misprediction_cycle(history_depth_t'(rollback_depths[iteration]));
			expected_head = expected_rollback_head;

			// Process the rollback without performing a memory write.
			repeat (3) idle_cycle();

			`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE", $sformatf("Iteration=%0d rollback complete. Refilling %0d squashed entries from pointer=%0d", iteration, rollback_depths[iteration], expected_head), UVM_LOW)

			// Refill the rolled-back region and return to the original starting head.
			for (int refill = 0; refill < rollback_depths[iteration]; refill++) begin
				packet = packet_t'((packet_number % 7'h7F) + 1);

				`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE", $sformatf("Iteration=%0d refill=%0d packet=0x%02h expected_pointer=%0d", iteration, refill, packet, expected_head), UVM_MEDIUM)

				branch_cycle(packet);
				packet_number++;
				accepted_write_count++;
				expected_head = (expected_head + 1) % MAX_PTR;
			end

			repeat (4) idle_cycle();

			`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE", $sformatf("Iteration=%0d complete. Expected restored head=%0d", iteration, expected_head), UVM_LOW)
		end

		`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE", $sformatf("Completed rollback-across-zero sequence. Accepted writes=%0d expected final head=%0d", accepted_write_count, expected_head), UVM_LOW)

	endtask

endclass


//// rollback with simultaneous replacement
class ghr_rollback_replacement_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_rollback_replacement_sequence)

	function new(string name = "ghr_rollback_replacement_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		packet_t replacement_packet;
		int unsigned rollback_depths [0:6] = '{1, 2, 4, 8, 16, 32, 35};
		int unsigned expected_head = 0;
		int unsigned rollback_pointer;
		int unsigned replacement_next_head;
		int unsigned packet_number = 1;
		int unsigned accepted_write_count = 0;

		`uvm_info("GHR_ROLLBACK_REPLACEMENT_SEQUENCE", "Starting simultaneous rollback and replacement verification", UVM_LOW)

		repeat (2) idle_cycle();

		// Fill all 36 locations so every rollback depth is legal and all expiring taps contain valid data.
		for (int pointer = 0; pointer < MAX_PTR; pointer++) begin
			packet = packet_t'((packet_number % 7'h7F) + 1);
			branch_cycle(packet);
			packet_number++;
			accepted_write_count++;
			expected_head = (expected_head + 1) % MAX_PTR;
		end

		repeat (4) idle_cycle();

		`uvm_info("GHR_ROLLBACK_REPLACEMENT_SEQUENCE", $sformatf("Initial fill complete. Expected head=%0d", expected_head), UVM_LOW)

		for (int iteration = 0; iteration < 7; iteration++) begin

			replacement_packet = packet_t'(7'h70 + iteration);
			rollback_pointer = (expected_head + MAX_PTR - rollback_depths[iteration]) % MAX_PTR;
			replacement_next_head = (rollback_pointer + 1) % MAX_PTR;

			`uvm_info("GHR_ROLLBACK_REPLACEMENT_SEQUENCE", $sformatf("Iteration=%0d old_head=%0d depth=%0d rollback_pointer=%0d replacement=0x%02h expected_next_head=%0d", iteration, expected_head, rollback_depths[iteration], rollback_pointer, replacement_packet, replacement_next_head), UVM_LOW)

			// Roll back and write the replacement packet at the recovered pointer in the same operation.
			misprediction_branch_cycle(history_depth_t'(rollback_depths[iteration]), replacement_packet);
			accepted_write_count++;
			expected_head = replacement_next_head;

			// Commit the registered rollback-and-replacement transaction.
			repeat (3) idle_cycle();

			`uvm_info("GHR_ROLLBACK_REPLACEMENT_SEQUENCE", $sformatf("Replacement committed at pointer=%0d. Expected head=%0d", rollback_pointer, expected_head), UVM_LOW)

			// Write depth-1 packets so this iteration returns the head pointer to zero.
			for (int refill = 0; refill < rollback_depths[iteration] - 1; refill++) begin
				packet = packet_t'((packet_number % 7'h6F) + 1);

				`uvm_info("GHR_ROLLBACK_REPLACEMENT_SEQUENCE", $sformatf("Iteration=%0d refill=%0d packet=0x%02h expected_pointer=%0d", iteration, refill, packet, expected_head), UVM_MEDIUM)

				branch_cycle(packet);
				packet_number++;
				accepted_write_count++;
				expected_head = (expected_head + 1) % MAX_PTR;
			end

			repeat (4) idle_cycle();

			`uvm_info("GHR_ROLLBACK_REPLACEMENT_SEQUENCE", $sformatf("Iteration=%0d complete. Expected head=%0d", iteration, expected_head), UVM_LOW)
		end

		`uvm_info("GHR_ROLLBACK_REPLACEMENT_SEQUENCE", $sformatf("Completed rollback-replacement sequence. Accepted writes=%0d expected final head=%0d", accepted_write_count, expected_head), UVM_LOW)

	endtask

endclass


//// back to back rollback
class ghr_back_to_back_rollback_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_back_to_back_rollback_sequence)

	function new(string name = "ghr_back_to_back_rollback_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		packet_t replacement_a;
		packet_t replacement_b;
		packet_t normal_packet;
		int unsigned expected_head;
		int unsigned accepted_write_count;

		expected_head = 0;
		accepted_write_count = 0;

		`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", "Starting back-to-back rollback sequence", UVM_LOW)

		repeat (2) idle_cycle();

		// Fill all 36 locations. The head returns to pointer zero.
		for (int pointer = 0; pointer < MAX_PTR; pointer++) begin
			packet = packet_t'(pointer + 1);
			branch_cycle(packet);
			accepted_write_count++;
		end

		repeat (4) idle_cycle();

		`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Initial fill completed. Expected head=%0d accepted writes=%0d", expected_head, accepted_write_count), UVM_LOW)

		// Repeat the dense rollback pattern three times.
		for (int round = 0; round < 3; round++) begin

			replacement_a = packet_t'(7'h60 + (round * 2));
			replacement_b = packet_t'(7'h61 + (round * 2));
			normal_packet = packet_t'(7'h50 + round);

			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Starting round=%0d at expected head=%0d", round, expected_head), UVM_LOW)

			// Operation 1: rollback-only by one. Expected head: 0 -> 35.
			misprediction_cycle(6'd1);
			expected_head = (expected_head + MAX_PTR - 1) % MAX_PTR;
			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Round=%0d rollback-only depth=1 expected head=%0d", round, expected_head), UVM_MEDIUM)

			// Operation 2: immediately rollback-only by two. Expected head: 35 -> 33.
			misprediction_cycle(6'd2);
			expected_head = (expected_head + MAX_PTR - 2) % MAX_PTR;
			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Round=%0d rollback-only depth=2 expected head=%0d", round, expected_head), UVM_MEDIUM)

			// Operation 3: immediately rollback by four and insert a replacement. Expected head: 33 -> 30.
			misprediction_branch_cycle(6'd4, replacement_a);
			expected_head = (expected_head + MAX_PTR - 4 + 1) % MAX_PTR;
			accepted_write_count++;
			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Round=%0d rollback+replacement depth=4 packet=0x%02h expected head=%0d", round, replacement_a, expected_head), UVM_MEDIUM)

			// Operation 4: immediately insert a normal branch. Expected head: 30 -> 31.
			branch_cycle(normal_packet);
			expected_head = (expected_head + 1) % MAX_PTR;
			accepted_write_count++;
			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Round=%0d normal branch packet=0x%02h expected head=%0d", round, normal_packet, expected_head), UVM_MEDIUM)

			// Operation 5: immediately rollback by one and insert a replacement. Expected head remains 31.
			misprediction_branch_cycle(6'd1, replacement_b);
			expected_head = (expected_head + MAX_PTR - 1 + 1) % MAX_PTR;
			accepted_write_count++;
			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Round=%0d rollback+replacement depth=1 packet=0x%02h expected head=%0d", round, replacement_b, expected_head), UVM_MEDIUM)

			// Operation 6: immediately rollback-only by eight. Expected head: 31 -> 23.
			misprediction_cycle(6'd8);
			expected_head = (expected_head + MAX_PTR - 8) % MAX_PTR;
			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Round=%0d rollback-only depth=8 expected head=%0d", round, expected_head), UVM_MEDIUM)

			// Drain the final operations before restoring the valid-history depth.
			repeat (5) idle_cycle();

			// The operation chain reduces valid history from 36 to 23. Thirteen writes restore a full history and return the head to zero.
			for (int refill = 0; refill < 13; refill++) begin
				packet = packet_t'(((round * 13 + refill + 7'h10) % 7'h7F) + 1);
				branch_cycle(packet);
				expected_head = (expected_head + 1) % MAX_PTR;
				accepted_write_count++;
			end

			repeat (4) idle_cycle();

			if (expected_head != 0)
				`uvm_error("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Round=%0d reference head did not return to zero: expected_head=%0d", round, expected_head))

			`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Completed round=%0d expected head=%0d accepted writes=%0d", round, expected_head, accepted_write_count), UVM_LOW)

		end

		repeat (3) idle_cycle();

		`uvm_info("GHR_BACK_TO_BACK_ROLLBACK", $sformatf("Completed back-to-back rollback sequence. Expected final head=%0d total accepted writes=%0d", expected_head, accepted_write_count), UVM_LOW)

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
	//@(posedge vif.clk);
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
	virtual ghr_if ghr_vif;

	function new(string name = "ghr_base_test", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		env = ghr_env::type_id::create("env", this);
		if (!uvm_config_db #(virtual ghr_if)::get(this, "", "vif", ghr_vif))
		`uvm_fatal("GHR_BASE_TEST", "Unable to retrieve ghr_if")
	endfunction

	task reset_dut();
		@(negedge ghr_vif.clk);
		ghr_vif.rst_n = 1'b0;
		repeat (3) @(negedge ghr_vif.clk);
		ghr_vif.rst_n = 1'b1;
		repeat (2) @(negedge ghr_vif.clk);
	endtask

	virtual task run_phase(uvm_phase phase);

		ghr_pipeline_smoke_sequence smoke_sequence;
		ghr_2cycle_alternating_enable_sequence two_cycle_alternating_enable_sequence;
		ghr_alternating_enable_sequence alternate_enable_sequence;
		ghr_reset_idle_sequence reset_seq;
		ghr_continuous_write_sequence continuous_write_seq;
		ghr_fill_level_enable_sequence fill_enable_seq;
		ghr_packet_value_sequence pckt_val_seq;
		ghr_bank_boundary_sequence bank_boundary_sequence;
		ghr_full_wrap_sequence full_wrap_sequence;
		ghr_tap_depth_sequence tap_depth_sequence;
		ghr_output_alignment_sequence output_alignment_sequence;
		ghr_rollback_only_sequence rollback_only;
		ghr_rollback_across_zero_sequence rollback_depth_greter_than_headptr;
		ghr_rollback_replacement_sequence rollbck_simult_replcmnt;
		ghr_back_to_back_rollback_sequence b2b_rollback;

		phase.raise_objection(this);
/*	
		reset_dut();
		smoke_sequence = ghr_pipeline_smoke_sequence::type_id::create("smoke_sequence");
		smoke_sequence.start(env.agent.sequencer);

		reset_dut();
		two_cycle_alternating_enable_sequence = ghr_2cycle_alternating_enable_sequence::type_id::create("two_cycle_alternating_enable_sequence");
		two_cycle_alternating_enable_sequence.start(env.agent.sequencer);

		reset_dut();
		alternate_enable_sequence = ghr_alternating_enable_sequence::type_id::create("alternate_enable_sequence");
		alternate_enable_sequence.start(env.agent.sequencer);

		reset_dut();
		reset_seq = ghr_reset_idle_sequence::type_id::create("reset_seq");
		reset_seq.start(env.agent.sequencer);

		reset_dut();
		continuous_write_seq = ghr_continuous_write_sequence::type_id::create("continuous_write_seq");
		continuous_write_seq.start(env.agent.sequencer);

		reset_dut();
		fill_enable_seq = ghr_fill_level_enable_sequence::type_id::create("fill_enable_seq");
		fill_enable_seq.start(env.agent.sequencer);

		reset_dut();
		pckt_val_seq = ghr_packet_value_sequence::type_id::create("pckt_val_seq");
		pckt_val_seq.start(env.agent.sequencer);

		reset_dut();
		bank_boundary_sequence = ghr_bank_boundary_sequence::type_id::create("bank_boundary_sequence");
		bank_boundary_sequence.start(env.agent.sequencer);

		reset_dut();
		full_wrap_sequence = ghr_full_wrap_sequence::type_id::create("full_wrap_sequence");
		full_wrap_sequence.start(env.agent.sequencer);

		reset_dut();
		tap_depth_sequence = ghr_tap_depth_sequence::type_id::create("tap_depth_sequence");
		tap_depth_sequence.start(env.agent.sequencer);

		reset_dut();
		output_alignment_sequence = ghr_output_alignment_sequence::type_id::create("output_alignment_sequence");
		output_alignment_sequence.start(env.agent.sequencer);

		reset_dut();
		rollback_only = ghr_rollback_only_sequence::type_id::create("rollback_only");
		rollback_only.start(env.agent.sequencer);

		reset_dut();
		rollback_depth_greter_than_headptr = ghr_rollback_across_zero_sequence::type_id::create("rollback_depth_greter_than_headptr");
		rollback_depth_greter_than_headptr.start(env.agent.sequencer);

		reset_dut();
		rollbck_simult_replcmnt = ghr_rollback_replacement_sequence::type_id::create("rollbck_simult_replcmnt");
		rollbck_simult_replcmnt.start(env.agent.sequencer);

		reset_dut();
		b2b_rollback = ghr_back_to_back_rollback_sequence::type_id::create("b2b_rollback");
		b2b_rollback.start(env.agent.sequencer);
*/

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

	always @(posedge clk) begin
		if (ghr_vif.rst_n && dut.target_index[6] == 6'd33) begin
			$display("");
			$display("========== DEPTH-32 P33 DIAGNOSTIC ==========");
			$display("Time                    : %0t", $time);
			$display("DUT head_ptr            : %0d", dut.head_ptr);
			$display("DUT next_head_ptr       : %0d", dut.next_head_ptr);
			$display("DUT target_index[6]     : %0d", dut.target_index[6]);
			$display("DUT read_row[6]         : %0d", dut.read_row[6]);
			$display("DUT read_bank[6]        : %0d", dut.read_bank[6]);
			$display("DUT bank_mem[3][6] P33  : 0x%02h", dut.bank_mem[3][6]);
			$display("DUT bank_mem[3][8] P35  : 0x%02h", dut.bank_mem[3][8]);
			$display("DUT expiring_next[6]    : 0x%02h", dut.expiring_packet_next[6]);
			$display("DUT expiring_output[6]  : 0x%02h", dut.expiring_packet_o[6]);
			$display("=============================================");
		end
	end

	always @(dut.bank_mem[3][6]) begin
	if (ghr_vif.rst_n) begin
		$display("");
		$display("========== DUT P33 MEMORY CHANGE ==========");
		$display("Time                : %0t", $time);
		$display("New P33 value       : 0x%02h", dut.bank_mem[3][6]);
		$display("write_ptr           : %0d", dut.write_ptr);
		$display("write_row           : %0d", dut.write_row);
		$display("write_bank          : %0d", dut.write_bank);
		$display("registered packet   : 0x%02h", dut.br_packet_i_reg);
		$display("bank_we[6]          : %0b", dut.bank_we[6]);
		$display("bank_we[8]          : %0b", dut.bank_we[8]);
		$display("===========================================");
	end
end

always @(dut.bank_mem[3][8]) begin
	if (ghr_vif.rst_n) begin
		$display("");
		$display("========== DUT P35 MEMORY CHANGE ==========");
		$display("Time                : %0t", $time);
		$display("New P35 value       : 0x%02h", dut.bank_mem[3][8]);
		$display("write_ptr           : %0d", dut.write_ptr);
		$display("write_row           : %0d", dut.write_row);
		$display("write_bank          : %0d", dut.write_bank);
		$display("registered packet   : 0x%02h", dut.br_packet_i_reg);
		$display("bank_we[6]          : %0b", dut.bank_we[6]);
		$display("bank_we[8]          : %0b", dut.bank_we[8]);
		$display("===========================================");
	end
end

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
		#200000;
		`uvm_fatal("GHR_TB_TIMEOUT", "Simulation exceeded the allowed runtime")
	end

endmodule



