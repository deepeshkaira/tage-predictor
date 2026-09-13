// package
package ghr_params_pkg;

	parameter int unsigned PKT_WIDTH        = 7;
	parameter int unsigned NUM_BANKS        = 9;
	parameter int unsigned ENTRIES_PER_BANK = 4;
	parameter int unsigned NUM_HASH_TABLES  = 7;
	parameter int unsigned MAX_PTR          = 36;

	typedef logic [PKT_WIDTH-1:0] packet_t;
	typedef logic [5:0]           history_depth_t;

	typedef packet_t expiring_packet_array_t
		[0:NUM_HASH_TABLES-1];

endpackage


import uvm_pkg::*;
import ghr_params_pkg::*;
`include "uvm_macros.svh"

interface ghr_if (input logic clk);

	import ghr_params_pkg::*;

	logic rst_n;	// Asynchronous, active-low reset.

	// GHR control and branch-decode inputs.
	logic en_i;
	logic br_valid_i;
	logic [PKT_WIDTH-1:0] br_packet_i;

	// Commit/ROB recovery inputs.
	logic misprediction_i;
	logic [5:0] mispredicted_table_depth_i;

	// GHR outputs to the downstream folding logic.
	logic [PKT_WIDTH-1:0] incoming_packet_o;
	logic [PKT_WIDTH-1:0] expiring_packet_o [0:NUM_HASH_TABLES-1];

	clocking driver_cb @(negedge clk);
		output en_i;
		output br_valid_i;
		output br_packet_i;
		output misprediction_i;
		output mispredicted_table_depth_i;
		input  incoming_packet_o;
		input  expiring_packet_o;
	endclocking


	clocking monitor_cb @(posedge clk);    
		input rst_n;
		input en_i;
		input br_valid_i;
		input br_packet_i;
		input misprediction_i;
		input mispredicted_table_depth_i;
		input incoming_packet_o;
		input expiring_packet_o;
	endclocking

	modport DRIVER (
		clocking driver_cb,
		// output rst_n,
		input  clk
	);

	modport MONITOR (
		clocking monitor_cb,
		input clk
	);

	// Direct port mapping used by the testbench-top DUT instance.
	modport DUT (
		input  clk, 
		input  rst_n,
		input  en_i,
		input  br_valid_i,
		input  br_packet_i,
		input  misprediction_i,
		input  mispredicted_table_depth_i,
		output incoming_packet_o,
		output expiring_packet_o
	);

	property misprediction_depth_is_known_p;

		@(posedge clk) disable iff (!rst_n)
		misprediction_i |-> !$isunknown(mispredicted_table_depth_i);
	
	endproperty
  
  
	misprediction_depth_is_known_a:
		assert property (misprediction_depth_is_known_p)
		else begin
	
		$error(
			{
			"GHR ASSERTION FAILURE: ",
			"mispredicted_table_depth_i contains X/Z ",
			"while misprediction_i is asserted. depth=%b"
			},
			mispredicted_table_depth_i
		);
  
	end

endinterface


// sequence item 

class ghr_seq_item extends uvm_sequence_item;

	localparam int PKT_WIDTH       = 7;
	localparam int NUM_HASH_TABLES = 7;
	localparam int MAX_PTR         = 36;

	// Inputs driven to the DUT
	rand bit                 en;
	rand bit                 br_valid;
	rand bit [PKT_WIDTH-1:0] br_packet;

	rand bit       			 misprediction;
	rand bit [5:0]           mispredicted_table_depth;

	// Reset and outputs sampled by the monitor
	bit rst_n;

	logic [PKT_WIDTH-1:0] observed_incoming_packet;
	logic [PKT_WIDTH-1:0] observed_expiring_packet [0:NUM_HASH_TABLES-1];

	// Favor enabled branch traffic while still exercising gated cycles.
	constraint reasonable_control_distribution_c {
		en            dist {1 := 80, 0 := 20};
		br_valid      dist {1 := 60, 0 := 40};
		misprediction dist {1 := 20, 0 := 80};
	}

	// Valid rollback depth is between 1 and MAX_PTR-1
	constraint legal_misprediction_depth_c {
		if (misprediction)
			mispredicted_table_depth inside {[1:MAX_PTR-1]};
		else
			mispredicted_table_depth == 0;
	}

	`uvm_object_utils_begin(ghr_seq_item)
		`uvm_field_int(en,                       UVM_ALL_ON)
		`uvm_field_int(br_valid,                 UVM_ALL_ON)
		`uvm_field_int(br_packet,                UVM_ALL_ON | UVM_HEX)
		`uvm_field_int(misprediction,            UVM_ALL_ON)
		`uvm_field_int(mispredicted_table_depth, UVM_ALL_ON | UVM_DEC)

		`uvm_field_int(rst_n,                     UVM_ALL_ON)
		`uvm_field_int(observed_incoming_packet,  UVM_ALL_ON | UVM_HEX)
		`uvm_field_sarray_int(
		observed_expiring_packet,
		UVM_ALL_ON | UVM_HEX
		)
	`uvm_object_utils_end

	function new(string name = "ghr_seq_item");
		super.new(name);
	endfunction

endclass


// Base sequence
class ghr_base_sequence extends uvm_sequence #(ghr_seq_item);

	`uvm_object_utils(ghr_base_sequence)

	function new(string name = "ghr_base_sequence");
		super.new(name);
	endfunction

	// Generic helper for driving one complete GHR transaction.
	task drive_cycle(
		input bit       en,
		input bit       br_valid,
		input bit [6:0] br_packet,
		input bit       misprediction,
		input bit [5:0] mispredicted_depth
	);

		ghr_seq_item tr;
		tr = ghr_seq_item::type_id::create("tr");

		start_item(tr);

		tr.en                       = en;
		tr.br_valid                 = br_valid;
		tr.br_packet                = br_packet;
		tr.misprediction            = misprediction;
		tr.mispredicted_table_depth = mispredicted_depth;

		finish_item(tr);

	endtask


	// active ENABLE, no BRANCH or MISPREDICTION
	task idle_cycle();

		drive_cycle(
		.en                 (1'b1),
		.br_valid           (1'b0),
		.br_packet          ('0),
		.misprediction      (1'b0),
		.mispredicted_depth ('0)
		);

	endtask


	// one branch packet into GHR
	task branch_cycle(
		input bit [6:0] br_packet
	);

		drive_cycle(
		.en                 (1'b1),
		.br_valid           (1'b1),
		.br_packet          (br_packet),
		.misprediction      (1'b0),
		.mispredicted_depth ('0)
		);

	endtask


	// GHR rollback without inserting a new branch.
	task misprediction_cycle(
		input bit [5:0] mispredicted_depth
	);

		if (!(mispredicted_depth inside {[1:35]})) begin
		`uvm_error(
			"GHR_BASE_SEQUENCE",
			$sformatf(
			"Illegal misprediction depth: %0d",
			mispredicted_depth
			)
		)
		return;
		end

		drive_cycle(
		.en                 (1'b1),
		.br_valid           (1'b0),
		.br_packet          ('0),
		.misprediction      (1'b1),
		.mispredicted_depth (mispredicted_depth)
		);

	endtask


	// GHR rollback and NEW BRANCH inserted in same cycle
	task misprediction_branch_cycle(
		input bit [5:0] mispredicted_depth,
		input bit [6:0] br_packet
	);

		if (!(mispredicted_depth inside {[1:35]})) begin
		`uvm_error(
			"GHR_BASE_SEQUENCE",
			$sformatf(
			"Illegal misprediction depth: %0d",
			mispredicted_depth
			)
		)
		return;
		end

		drive_cycle(
		.en                 (1'b1),
		.br_valid           (1'b1),
		.br_packet          (br_packet),
		.misprediction      (1'b1),
		.mispredicted_depth (mispredicted_depth)
		);

	endtask


	// Disable the GHR while allowing its input signals to toggle.
	// operand isolation check
	task disabled_cycle(
		input bit       br_valid,
		input bit [6:0] br_packet,
		input bit       misprediction,
		input bit [5:0] mispredicted_depth
	);

		drive_cycle(
		.en                 (1'b0),
		.br_valid           (br_valid),
		.br_packet          (br_packet),
		.misprediction      (misprediction),
		.mispredicted_depth (mispredicted_depth)
		);

	endtask

endclass

// directed smoke sequence
// Basic smoke sequence: write five packets into the GHR.
class ghr_smoke_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_smoke_sequence)

	function new(string name = "ghr_smoke_sequence");
		super.new(name);
	endfunction


	virtual task body();

		`uvm_info("GHR_SMOKE_SEQUENCE","Starting five-write GHR smoke test",UVM_LOW)

		// Initial idle cycles after reset.
		idle_cycle();
		idle_cycle();

		// Packet format:{branch_type, taken, target[4:0]}
		// these should occupy T0_L0, T1_L1 etc etc
		branch_cycle(7'b0_1_00001);  // Pointer 0, row 0, bank 0
		branch_cycle(7'b1_0_00010);  // Pointer 1, row 0, bank 1
		branch_cycle(7'b0_1_00101);  // Pointer 2, row 0, bank 2
		branch_cycle(7'b1_1_01010);  // Pointer 3, row 0, bank 3
		branch_cycle(7'b0_0_11111);  // Pointer 4, row 0, bank 4

		// Allow the final write to be sampled and checked.
		idle_cycle();
		idle_cycle();

		`uvm_info("GHR_SMOKE_SEQUENCE","Completed five-write GHR smoke test",UVM_LOW)

	endtask

endclass


// write all 36 GHR locations and then wrap back to 0.
// Write all 36 GHR locations and then wrap back to pointers 0–3.
class ghr_bank_write_wrap_sequence extends ghr_base_sequence;

  `uvm_object_utils(ghr_bank_write_wrap_sequence)

	function new(string name = "ghr_bank_write_wrap_sequence");
		super.new(name);
	endfunction

	virtual task body();

		bit [6:0] packet;

		int unsigned logical_pointer;
		int unsigned expected_row;
		int unsigned expected_bank;

		`uvm_info("GHR_BANK_WRAP_SEQUENCE","Starting 40-write bank mapping and pointer-wrap sequence",UVM_LOW)

		idle_cycle();
		idle_cycle();

		// Write 40 distinct packets.
		// Writes 0–35 fill all 36 locations.
		// Writes 36–39 wrap around and overwrite pointers 0–3.
		for (int write_number = 0; write_number < 40; write_number++)
		begin

			packet = write_number + 1;

			logical_pointer = write_number % 36;
			expected_row = logical_pointer / 9;
			expected_bank = logical_pointer % 9;

			`uvm_info(
				"GHR_BANK_WRAP_SEQUENCE",
				$sformatf(
				{"Write=%0d packet=0x%02h ","pointer=%0d row=%0d bank=%0d"},
				write_number,packet,logical_pointer,expected_row,expected_bank),UVM_MEDIUM
			)

			branch_cycle(packet);

		end

		idle_cycle();
		idle_cycle();

		`uvm_info("GHR_BANK_WRAP_SEQUENCE","Completed 40-write bank mapping and pointer-wrap sequence",UVM_LOW)

	endtask

endclass


// sequece to chck the 7 pckt depths
class ghr_packet_depth_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_packet_depth_sequence)

	function new(string name = "ghr_packet_depth_sequence");
		super.new(name);
	endfunction

	virtual task body();

		bit [6:0] packet;

		`uvm_info("GHR_PACKET_DEPTH_SEQUENCE","Starting packet-depth verification sequence",UVM_LOW)

		idle_cycle();
		idle_cycle();


		// Fill all 36 GHR locations.
		//
		// Logical pointer 0  receives 0x01.
		// Logical pointer 1  receives 0x02.
		// ...
		// Logical pointer 35 receives 0x24.
		for (int pointer = 0; pointer < 36; pointer++) 
		begin
			packet = pointer + 1;

			`uvm_info("GHR_PACKET_DEPTH_SEQUENCE",
				$sformatf("Writing packet=0x%02h at logical pointer=%0d",
				packet,pointer),
				UVM_MEDIUM
			)

			branch_cycle(packet);

		end


		// The head pointer has wrapped to zero.
		// Using clearly different packet values for pointers 0–3
		// so that I can distinguish the new data from
		// the original values.
		branch_cycle(7'h61);  // Overwrite pointer 0
		branch_cycle(7'h62);  // Overwrite pointer 1
		branch_cycle(7'h63);  // Overwrite pointer 2
		branch_cycle(7'h64);  // Overwrite pointer 3

		idle_cycle();
		idle_cycle();

		`uvm_info("GHR_PACKET_DEPTH_SEQUENCE","Completed packet-depth verification sequence",UVM_LOW)

	endtask

endclass


// toggling while enable = 0. To check gating of the design
class ghr_enable_gating_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_enable_gating_sequence)

	function new(string name = "ghr_enable_gating_sequence");
		super.new(name);
	endfunction


	virtual task body();

		bit [6:0] packet;

		`uvm_info("GHR_ENABLE_GATING_SEQUENCE",
		"Starting GHR enable-gating sequence",
		UVM_LOW)

		idle_cycle();
		idle_cycle();


		// Fill 32 history locations so all seven geometric-history taps contain meaningful nonzero data.
		for (int pointer = 0; pointer < 32; pointer++)
		begin
			packet = pointer + 1;
			branch_cycle(packet);
		end

		`uvm_info("GHR_ENABLE_GATING_SEQUENCE",{"GHR contains 32 packets. Pulling en_i low. ","Expected head pointer must remain 32."},UVM_LOW)

		// br_valid toggles while disabled - No packet should be written.
		disabled_cycle(
		.br_valid           (1'b1),
		.br_packet          (7'h55),
		.misprediction      (1'b0),
		.mispredicted_depth (6'd0)
		);


		// misprediction toggles while disabled. No rollback may occur.
		disabled_cycle(
		.br_valid           (1'b0),
		.br_packet          (7'h2A),
		.misprediction      (1'b1),
		.mispredicted_depth (6'd4)
		);


		// branch and misprediction are both asserted. No write or rollback may occur.
		disabled_cycle(
		.br_valid           (1'b1),
		.br_packet          (7'h7F),
		.misprediction      (1'b1),
		.mispredicted_depth (6'd8)
		);


		// Illegal raw rollback depth while disabled.DUT must gate the misprediction
		// before it reaches the pointer logic and assertion.
		disabled_cycle(
		.br_valid           (1'b0),
		.br_packet          (7'h11),
		.misprediction      (1'b1),
		.mispredicted_depth (6'd0)
		);


		// Maximum raw depth while disabled.
		disabled_cycle(
		.br_valid           (1'b1),
		.br_packet          (7'h33),
		.misprediction      (1'b1),
		.mispredicted_depth (6'd63)
		);


		// Enable remains high, but no operation occurs.
		idle_cycle();


		// Confirm normal operation resumes at pointer 32.
		// This packet must be written to pointer 32, and the
		// next head pointer must become 33.
		branch_cycle(7'h6D);

		idle_cycle();
		idle_cycle();


		`uvm_info("GHR_ENABLE_GATING_SEQUENCE",{"Completed enable-gating sequence. ","Expected final head pointer=33."},UVM_LOW)

	endtask

endclass


// mispreediction rollback without a simultaneous incoming branch
// --Write 20 known packets
// --Head pointer becomes 20
// --Roll back by 5
// --Head pointer becomes 15
// --Confirm no memory write occurred
// --Insert a normal branch at recovered pointer 15
// --Head pointer becomes 16
// Verify rollback without a simultaneous incoming branch.
class ghr_rollback_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_rollback_sequence)

	function new(string name = "ghr_rollback_sequence");
		super.new(name);
	endfunction

	virtual task body();

		bit [6:0] packet;

		`uvm_info("GHR_ROLLBACK_SEQUENCE","Starting rollback-without-branch sequence",UVM_LOW)

		idle_cycle();
		idle_cycle();

		// Fill pointers 0 through 19 with packets 0x01 through 0x14.
		for (int pointer = 0; pointer < 20; pointer++) begin

			packet = pointer + 1;
			branch_cycle(packet);

		end

		`uvm_info("GHR_ROLLBACK_SEQUENCE",{"Twenty packets inserted. Current head=20. ","Applying rollback depth=5 without a new branch."},UVM_LOW)

		// old_head_ptr = 20
		// rollback_depth = 5
		// recovered_head_ptr = 15
		//
		// No packet to be written during this cycle.
		misprediction_cycle(6'd5);

		// Keep the recovered pointer unchanged for one cycle.
		idle_cycle();

		`uvm_info("GHR_ROLLBACK_SEQUENCE",{"Rollback completed. Expected recovered head=15. ","Inserting packet 0x55 at recovered pointer 15."},UVM_LOW)

		// Normal branch after recovery.
		// The packet must be written at pointer 15.
		// The next head pointer must become 16.
		branch_cycle(7'h55);
		idle_cycle();
		idle_cycle();

		`uvm_info("GHR_ROLLBACK_SEQUENCE",{"Completed rollback sequence. ","Expected final head pointer=16."},UVM_LOW)

	endtask

endclass


/// robustness sequence.
// valid depth = 10, but requested deepth for misprediction can be from 12,16,32 etc.
class ghr_deep_rollback_replacement_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_deep_rollback_replacement_sequence)

	rand int unsigned history_packet_count;
	rand bit [5:0] selected_misprediction_depth;

	// keeping valid history packets inside like 10 or 11
	constraint history_packet_count_c {
		history_packet_count dist {
									10 := 50,
									11 := 50
		};
	}


	// Select one of three rollback depths.
	// Depth 12-  40% weight.
	// Depth 16- 35% weight.
	// Depth 32- 25% weight.
	constraint misprediction_depth_c {
		selected_misprediction_depth dist {
											6'd12 := 40,
											6'd16 := 35,
											6'd32 := 25
		};
	}


	// misprediction depth shiould be greater than valid history depth
	constraint depth_exceeds_history_c {
		selected_misprediction_depth > history_packet_count;
	}

	function new(string name = "ghr_deep_rollback_replacement_sequence");
		super.new(name);
	endfunction

	virtual task body();

		bit [6:0] packet;

		int unsigned expected_rollback_ptr;
		int unsigned expected_head_after_replacement;
		int unsigned expected_final_head;


		assert (this.randomize()) 
		else  `uvm_fatal("GHR_DEEP_ROLLBACK_SEQUENCE","Failed to randomize history count and rollback depth")


		// Calculation of expected pointer
		expected_rollback_ptr = (history_packet_count + 36 - selected_misprediction_depth) % 36;
		expected_head_after_replacement = (expected_rollback_ptr + 1) % 36;
		expected_final_head = (expected_rollback_ptr + 2) % 36;

		`uvm_info("GHR_DEEP_ROLLBACK_SEQUENCE",
			$sformatf(
				{"Starting robustness sequence: ",
				"valid_history=%0d selected_depth=%0d ",
				"expected_rollback_ptr=%0d"},
				history_packet_count,
				selected_misprediction_depth,
				expected_rollback_ptr
			),
			UVM_LOW
		)


		idle_cycle();
		idle_cycle();


		// Filling either 10 or 11 history entries with unique packets into GHR bank.
		for (int pointer = 0; pointer < history_packet_count; pointer++) begin
			packet = pointer + 1;
			branch_cycle(packet);
		end


		`uvm_info("GHR_DEEP_ROLLBACK_SEQUENCE",
			$sformatf(
				{"Requesting simultaneous rollback/replacement: ",
				"old_head=%0d depth=%0d rollback_ptr=%0d ",
				"replacement_packet=0x55"},
				history_packet_count,
				selected_misprediction_depth,
				expected_rollback_ptr
			),
			UVM_LOW
		)


		// The selected depth is greater than the valid-history count, but within range 1–35.
		misprediction_branch_cycle(.mispredicted_depth (selected_misprediction_depth),.br_packet (7'h55));

		// Insert one more packet.
		branch_cycle(7'h66);

		idle_cycle();
		idle_cycle();


		`uvm_info("GHR_DEEP_ROLLBACK_SEQUENCE",
			$sformatf(
				{
				"Completed robustness sequence: ",
				"head_after_replacement=%0d final_head=%0d"
				},
				expected_head_after_replacement,
				expected_final_head
			),
			UVM_LOW
		)

	endtask

endclass


/// robustness sequence with multiple rollbacks
class ghr_deep_multiple_rollback_replacement_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_deep_multiple_rollback_replacement_sequence)

	// entries for first rollback
	rand int unsigned initial_write_count;
	// normal writes between successive rollback operations.
	rand int unsigned interval_write_count [0:2];
	// Rollback depth used by each of the successive mispredictions.
	rand bit [5:0] rollback_depth [0:3];

	// Initially write either 10 or 11 packets.
	constraint initial_write_count_c {
		initial_write_count dist {
								10 := 50,
								11 := 50
		};
	}

	// Writes after first rollback.
	constraint interval_write_count_c {

		// After rollback 1, write 5 or 6 packets.
		interval_write_count[0] dist {
									5 := 50,
									6 := 50
		};

		// After rollback 2, write some 10-15 packets.
		interval_write_count[1] inside {[10:15]};

		// After rollback 3, write some 10-15 packets.
		interval_write_count[2] inside {[10:15]};
	}

	// Each rollback to select depth 12, 16, or 32.
	constraint rollback_depth_c {
		foreach (rollback_depth[index]) {rollback_depth[index] dist {
																	6'd12 := 40,
																	6'd16 := 35,
																	6'd32 := 25
			};
		}
		}

	function new(string name = "ghr_deep_multiple_rollback_replacement_sequence");
		super.new(name);
	endfunction

	virtual task body();

		bit [PKT_WIDTH-1:0] packet;
		bit [PKT_WIDTH-1:0] replacement_packet [0:3];

		int unsigned expected_head;
		int unsigned expected_rollback_ptr;
		int unsigned packet_number;

		// assertion to check if the randomization fails
		assert (this.randomize()) 
		else `uvm_fatal("GHR_DEEP_MULTIPLE_ROLLBACK_SEQUENCE","Failed to randomize sequence parameters")

		replacement_packet[0] = 7'h55;
		replacement_packet[1] = 7'h56;
		replacement_packet[2] = 7'h57;
		replacement_packet[3] = 7'h58;

		expected_head = 0;
		packet_number = 1;

		`uvm_info(
			"GHR_DEEP_MULTIPLE_ROLLBACK_SEQUENCE",
			$sformatf(
				{"Starting multiple rollback sequence\n",
				 "Initial writes      = %0d\n",
				 "Interval writes     = %0d, %0d, %0d\n",
				 "Rollback depths     = %0d, %0d, %0d, %0d"},
				initial_write_count,
				interval_write_count[0],
				interval_write_count[1],
				interval_write_count[2],
				rollback_depth[0],
				rollback_depth[1],
				rollback_depth[2],
				rollback_depth[3]
			),
			UVM_LOW
		)


		// Allow the DUT to settle after reset.
		idle_cycle();
		idle_cycle();


		// Phase 1: Initial write of 10 or 11 packets.
		for (int write_index = 0; write_index < initial_write_count; write_index++) begin

			packet = packet_number[PKT_WIDTH-1:0];
			branch_cycle(packet);
			expected_head = (expected_head + 1) % MAX_PTR;
			packet_number++;
		end


		// Rollback 1 with replacement packet 0x55.
		expected_rollback_ptr = (expected_head + MAX_PTR - rollback_depth[0]) % MAX_PTR;

		`uvm_info(
			"GHR_DEEP_MULTIPLE_ROLLBACK_SEQUENCE",
			$sformatf(
				{"ROLLBACK 1: old_head=%0d depth=%0d ",
				 "rollback_ptr=%0d replacement=0x%02h"},
				expected_head,
				rollback_depth[0],
				expected_rollback_ptr,
				replacement_packet[0]
			),
			UVM_LOW
		)

		misprediction_branch_cycle(rollback_depth[0],replacement_packet[0]);

		// Simultaneous rollback and replacement advances the pointer once after writing the replacement packet.
		expected_head = (expected_rollback_ptr + 1) % MAX_PTR;

		idle_cycle();

		// Write 5 or 6 more packets.
		for (int write_index = 0; write_index < interval_write_count[0]; write_index++) begin

			packet = packet_number[PKT_WIDTH-1:0];
			branch_cycle(packet);

			expected_head = (expected_head + 1) % MAX_PTR;
			packet_number++;
		end


		// ROLLBACK AGAIN with replacement packet 0x56.
		// ------------------------------------------------------------
		expected_rollback_ptr = (expected_head + MAX_PTR - rollback_depth[1]) % MAX_PTR;

		`uvm_info(
			"GHR_DEEP_MULTIPLE_ROLLBACK_SEQUENCE",
			$sformatf(
				{"ROLLBACK 2: old_head=%0d depth=%0d ",
				 "rollback_ptr=%0d replacement=0x%02h"},
				expected_head,
				rollback_depth[1],
				expected_rollback_ptr,
				replacement_packet[1]
			),
			UVM_LOW
		)

		misprediction_branch_cycle(rollback_depth[1],replacement_packet[1]);

		expected_head = (expected_rollback_ptr + 1) % MAX_PTR;

		idle_cycle();


		// Write operation again between 10 and 15 more packets.
		for (int write_index = 0; write_index < interval_write_count[1]; write_index++)
		begin

			packet = packet_number[PKT_WIDTH-1:0];
			branch_cycle(packet);

			expected_head = (expected_head + 1) % MAX_PTR;
			packet_number++;
		end


		// ROLLBACK AGAIN with replacement packet 0x57.
		expected_rollback_ptr = (expected_head + MAX_PTR - rollback_depth[2]) % MAX_PTR;

		`uvm_info(
			"GHR_DEEP_MULTIPLE_ROLLBACK_SEQUENCE",
			$sformatf(
				{"ROLLBACK 3: old_head=%0d depth=%0d ",
				 "rollback_ptr=%0d replacement=0x%02h"},
				expected_head,
				rollback_depth[2],
				expected_rollback_ptr,
				replacement_packet[2]
			),
			UVM_LOW
		)

		misprediction_branch_cycle(rollback_depth[2],replacement_packet[2]);

		expected_head = (expected_rollback_ptr + 1) % MAX_PTR;

		idle_cycle();


		// WRITE AGAIN between 10 and 15 packets.
		for (int write_index = 0; write_index < interval_write_count[2]; write_index++) 
		begin

			packet = packet_number[PKT_WIDTH-1:0];
			branch_cycle(packet);

			expected_head = (expected_head + 1) % MAX_PTR;
			packet_number++;
		end


		// ROLLBACK AGAIN with replacement packet 0x58.
		expected_rollback_ptr = (expected_head + MAX_PTR - rollback_depth[3]) % MAX_PTR;

		`uvm_info(
			"GHR_DEEP_MULTIPLE_ROLLBACK_SEQUENCE",
			$sformatf(
				{"ROLLBACK 4: old_head=%0d depth=%0d ",
				 "rollback_ptr=%0d replacement=0x%02h"},
				expected_head,
				rollback_depth[3],
				expected_rollback_ptr,
				replacement_packet[3]
			),
			UVM_LOW
		)

		misprediction_branch_cycle(rollback_depth[3],replacement_packet[3]);

		expected_head = (expected_rollback_ptr + 1) % MAX_PTR;

		idle_cycle();
		idle_cycle();

		`uvm_info(
			"GHR_DEEP_MULTIPLE_ROLLBACK_SEQUENCE",
			$sformatf(
				{"Completed multiple rollback sequence: ",
				 "final_expected_head=%0d total_normal_writes=%0d ",
				 "rollback_operations=4"},
				expected_head,
				packet_number - 1
			),
			UVM_LOW
		)

	endtask

endclass


/// rollback_verification across the circular pointer zero boundary - to check the wrap around
// After 39 writes:
//   head pointer = 39 % 36 = 3
//
// Rollback depth = 8: recovered pointer = (3 + 36 - 8) % 36 = 31
class ghr_rollback_across_zero_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_rollback_across_zero_sequence)

	function new(string name = "ghr_rollback_across_zero_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;

		int unsigned expected_head;
		int unsigned rollback_depth;
		int unsigned expected_rollback_ptr;
		int unsigned expected_final_head;

		expected_head         = 0;
		rollback_depth        = 8;
		expected_rollback_ptr = 0;
		expected_final_head   = 0;

		`uvm_info("GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE","Starting rollback-across-pointer-zero sequence",UVM_LOW)

		idle_cycle();
		idle_cycle();

		// Writing 39 packets - 0 through 35 fill the GHR and return the head to 0.
		// then for 36 through 38 overwrite pointers 0 through 2.
		// The resulting head pointer should be 3.
		for (int write_number = 0; write_number < MAX_PTR + 3; write_number++) 
		begin

			packet = packet_t'(write_number + 1);

			`uvm_info(
				"GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE",
				$sformatf(
					"Writing packet=0x%02h at pointer=%0d",
					packet,
					expected_head
				),
				UVM_MEDIUM
			)

			branch_cycle(packet);

			expected_head = (expected_head + 1) % MAX_PTR;

		end

		// expected_head is now 3.
		expected_rollback_ptr = (expected_head + MAX_PTR - rollback_depth) % MAX_PTR;

		`uvm_info(
			"GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE",
			$sformatf(
				{"Applying rollback across pointer zero: ",
				 "old_head=%0d depth=%0d recovered_head=%0d"},
				expected_head,
				rollback_depth,
				expected_rollback_ptr
			),
			UVM_LOW
		)

		// Rollback without inserting a replacement packet.
		// old head = 3
		// depth    = 8
		// new head = 31
		misprediction_cycle(history_depth_t'(rollback_depth));

		expected_head = expected_rollback_ptr;

		idle_cycle(); // to allow the ptr to get stable

		// Write a packet at recovered pointer 31.
		`uvm_info(
			"GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE",
			$sformatf(
				{"Writing packet 0x6A at recovered pointer=%0d. ",
				 "Expected next head=%0d"},
				expected_head,
				(expected_head + 1) % MAX_PTR
			),
			UVM_LOW
		)

		branch_cycle(packet_t'(7'h6A));

		expected_final_head = (expected_head + 1) % MAX_PTR;

		idle_cycle();
		idle_cycle();

		`uvm_info(
			"GHR_ROLLBACK_ACROSS_ZERO_SEQUENCE",
			$sformatf(
				{"Completed rollback-across-zero sequence: ",
				 "expected final head=%0d"},
				expected_final_head
			),
			UVM_LOW
		)

	endtask

endclass


//// sequence to check the 4 operating modes transition sequence with only one cycle gap
// 00 = idle
// 01 = normal branch insertion
// 10 = rollback without branch
// 11 = rollback with replacement branch
// 00 -> 01 -> 00 -> 10 -> 00 -> 11 -> 00
class ghr_mode_transition_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_mode_transition_sequence)

	// Number of idle cycles between active operating modes.
	rand int unsigned branch_gap [0:2];

	constraint idle_gap_c {
					foreach (branch_gap[index]) {
						branch_gap[index] inside {[4:5]};
					}
	}

	function new(string name = "ghr_mode_transition_sequence");
		super.new(name);
	endfunction


	virtual task body();

		packet_t packet;
		int unsigned packet_number;

		assert (this.randomize())
		else `uvm_fatal("GHR_MODE_TRANSITION_SEQUENCE","Failed to randomize idle-cycle intervals")


		// packet_number = 7'h40;
		packet_number = $urandom_range(7'h6F, 7'h15);

		`uvm_info(
			"GHR_MODE_TRANSITION_SEQUENCE",
			$sformatf(
				{"Starting directed operating-mode sequence: ","idle gaps=%0d, %0d, %0d"},
				branch_gap[0],
				branch_gap[1],
				branch_gap[2]
			),UVM_LOW)


		// Initial idle cycles after reset.
		idle_cycle();
		idle_cycle();

		// putting in some values inside the GHR fr initial start
		for (int write_number = 0; write_number < 20; write_number++) begin
			packet = packet_t'(write_number + 1);
			branch_cycle(packet);
		end

		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",{"GHR initialized with 20 packets. ","Starting directed mode operations."},UVM_LOW)


		// MODE 00: IDLE
		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE","Applying mode 00: IDLE",UVM_MEDIUM)

		idle_cycle();

		// MODE 01: NORMAL BRANCH INSERTION ( 00 --> 01)
		packet = packet_t'(packet_number);

		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",
			$sformatf("Applying mode 01: NORMAL BRANCH packet=0x%02h",packet),UVM_MEDIUM)

		branch_cycle(packet);
		packet_number++;

		// MODE 01: NORMAL FOR ADDITIONAL 3 OR 4 CYCLES (stay at 01)
		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",
			$sformatf("Applying mode 01 for %0d additional cycles",branch_gap[0]),UVM_MEDIUM)

		repeat (branch_gap[0]) begin
			packet = packet_t'(packet_number);
			branch_cycle(packet);
			packet_number++;
		end


		// MODE 10: ROLLBACK WITHOUT A NEW BRANCH (01 -> 10)
		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE","Applying mode 10: ROLLBACK-ONLY depth=1",UVM_MEDIUM)

		misprediction_cycle(6'd1);

		// MODE 01: NORMAL FOR 3 OR 4 CYCLES (10 -> 01)
		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",
			$sformatf("Applying mode 01 for %0d cycles after mode 10",branch_gap[1]),UVM_MEDIUM)

		repeat (branch_gap[1]) begin
			packet = packet_t'(packet_number);
			branch_cycle(packet);
			packet_number++;
		end


		// MODE 11: ROLLBACK WITH REPLACEMENT BRANCH (01 -> 11)
		packet = packet_t'(packet_number);

		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",
			$sformatf({"Applying mode 11: ROLLBACK + REPLACEMENT ","depth=1 packet=0x%02h"},packet),UVM_MEDIUM)

		misprediction_branch_cycle(6'd1,packet);

		packet_number++;


		// MODE 01: NORMAL BRANCH INSERTION (11 -> 01)
		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",
			$sformatf("Applying mode 01 for %0d cycles after mode 11",branch_gap[2]),UVM_MEDIUM)

		repeat (branch_gap[2]) begin
			packet = packet_t'(packet_number);
			branch_cycle(packet);
			packet_number++;
		end

		// MODE 00: IDLE FOR 3 OR 4 CYCLES (01--> 00)
		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",
			$sformatf("Applying mode 00 for %0d cycles after mode 01",branch_gap[2]),UVM_MEDIUM)

		repeat (branch_gap[2]) begin
			idle_cycle();
		end

		`uvm_info("GHR_MODE_TRANSITION_SEQUENCE",
			{"Completed directed mode sequence: ","00 -> 01 -> 00 -> 10 -> 00 -> 11 -> 00"},UVM_LOW)

	endtask

endclass



/// sequence checking combination of normal + rollback with no replacement back to back
// Initial memory fill -> 00  -> 01 (for 4–5 cycles) -> 10 -> 01 -> 10 -> 01 -> 10
class ghr_normal_plus_rollback_back2back_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_normal_plus_rollback_back2back_sequence)

	// Number of normal branch insertions before beginning the
	// back-to-back rollback/branch pattern.
	rand int unsigned initial_branch_cycles;

	constraint initial_branch_cycles_c {
		initial_branch_cycles inside {[4:5]};
	}

	function new(string name = "ghr_normal_plus_rollback_back2back_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;
		int unsigned packet_number;

		assert (this.randomize())
		else `uvm_fatal("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE","Failed to randomize initial branch-cycle count")

		packet_number = $urandom_range(7'h79, 7'h15);

		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE",
			$sformatf(
				{"Starting back-to-back rollback sequence: ",
				"initial mode-01 cycles=%0d ",
				"first random packet=0x%02h"},
				initial_branch_cycles,
				packet_number
			),
			UVM_LOW
		)

		idle_cycle();
		idle_cycle();

		// Initial memory fill.
		for (int write_number = 0; write_number < 30; write_number++) begin
			packet = packet_t'(write_number + 1);
			branch_cycle(packet);
		end

		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE","GHR initialized with 20 packets; expected head pointer=20",UVM_LOW)

		// MODE 00: one idle cycle.
		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE","Applying mode 00: IDLE",UVM_MEDIUM)

		idle_cycle();

		// MODE 01: normal branch insertion for 4 or 5 cycles.
		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE",
			$sformatf("Applying mode 01 for %0d cycles",initial_branch_cycles),UVM_MEDIUM)

		repeat (initial_branch_cycles) begin

			packet = packet_t'(packet_number);

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE",
				$sformatf("Normal branch insertion: packet=0x%02h",packet),UVM_MEDIUM)

			branch_cycle(packet);
			packet_number++;

		end

		// MODE 10: rollback only.
		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE","Applying first mode 10: ROLLBACK-ONLY depth=1",UVM_MEDIUM)

		misprediction_cycle(6'd1);

		// MODE 01: one normal branch insertion.
		packet = packet_t'(packet_number);

		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE",
			$sformatf("Applying mode 01: packet=0x%02h",packet),UVM_MEDIUM)

		branch_cycle(packet);
		packet_number++;

		// MODE 10: second rollback - no replacement
		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE","Applying second mode 10: ROLLBACK-ONLY depth=1",UVM_MEDIUM)

		misprediction_cycle(6'd4);	// 4 rollbacks

		// MODE 01: one normal branch insertion.
		packet = packet_t'(packet_number);

		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE",
			$sformatf("Applying mode 01: packet=0x%02h",packet),UVM_MEDIUM)

		branch_cycle(packet);
		packet_number++;


		// MODE 10: fourth rollback only.
		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE","Applying third mode 10: ROLLBACK-ONLY depth=1",UVM_MEDIUM)

		misprediction_cycle(6'd1);

		// MODE 01: one normal branch insertion.
		packet = packet_t'(packet_number);

		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE",
			$sformatf("Applying mode 01: packet=0x%02h",packet),UVM_MEDIUM)

		branch_cycle(packet);
		packet_number++;

		// Allow the final rollback to be sampled and checked.
		idle_cycle();
		idle_cycle();

		`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_BACK2BACK_SEQUENCE",{"Completed mode pattern: ","00 -> 01 -> 10 -> 01 -> 10 -> 01 -> 10"},UVM_LOW)

	endtask

endclass



/// sequence for checking in combination of normal + rollback with replacement back to back
// Back-to-back normal branch and rollback-with-replacement operations.
//
// The initial 34 writes leave the head at pointer 34.
// The following 4–5 normal writes force the head to wrap through zero.
//
// Mode pattern:
//   01 -> 11 -> 01 -> 11 -> 01
class ghr_normal_plus_rollback_wth_replacement_back2back_sequence extends ghr_base_sequence;

		`uvm_object_utils(ghr_normal_plus_rollback_wth_replacement_back2back_sequence)

		// Normal insertions before the first rollback-and-replacement.
		rand int unsigned initial_branch_cycles;

		constraint initial_branch_cycles_c {
			initial_branch_cycles inside {[4:5]};
		}

		function new(string name = "ghr_normal_plus_rollback_wth_replacement_back2back_sequence");
			super.new(name);
		endfunction


		virtual task body();

			packet_t packet;
			packet_t previous_replacement_packet = '0;
			// previous_replacement_packet = '0;
			int unsigned packet_number;

			assert (this.randomize())
			else `uvm_fatal("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE","Failed to randomize initial branch-cycle count")

			packet_number = $urandom_range(7'h70, 7'h40);

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",
				$sformatf({"Starting replacement-mode sequence: ","initial mode-01 cycles=%0d ","first generated packet=0x%02h"},
				initial_branch_cycles,packet_number),
				UVM_LOW
			)

			idle_cycle();
			idle_cycle();

			// filling up GHR
			for (int write_number = 0; write_number < 34; write_number++) 
			begin
				packet = packet_t'(write_number + 1);
				branch_cycle(packet);
			end

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",{"GHR initialized with 34 packets. ","Expected head pointer=34."},UVM_LOW)


			// MODE 01: normal insertion for 4 or 5 cycles.
			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",$sformatf({"Applying mode 01 for %0d cycles. ","The head pointer will wrap through zero."},initial_branch_cycles),UVM_MEDIUM)

			repeat (initial_branch_cycles) begin

				packet = packet_t'(packet_number);
				`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",$sformatf("Mode 01: inserting packet=0x%02h",packet),UVM_MEDIUM)

				branch_cycle(packet);
				packet_number++;
			end

			// MODE 11: first rollback and replacement.
			packet = packet_t'(packet_number);

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",
				$sformatf({"Applying first mode 11: depth=4 ","replacement packet=0x%02h"},packet),UVM_MEDIUM)

			misprediction_branch_cycle(6'd4,packet);

			packet_number++;

			// MODE 01: one normal branch insertion.
			packet = packet_t'(packet_number);

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",
				$sformatf("Applying mode 01: packet=0x%02h",packet),UVM_MEDIUM)

			branch_cycle(packet);
			packet_number++;

			// MODE 11: second rollback and replacement.
			packet = packet_t'(packet_number);

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",
				$sformatf({"Applying second mode 11: depth=2 ","replacement packet=0x%02h"},packet),UVM_MEDIUM)

			// for getting a new replacement packet
			do begin
				packet = packet_t'($urandom_range(7'h7F, 7'h23));
			end
			while (packet == previous_replacement_packet);

			misprediction_branch_cycle(6'd2,packet);

			packet_number++;

			// for getting a new replacement packet
			do begin
				packet = packet_t'($urandom_range(7'h7F, 7'h23));
			end
			while (packet == previous_replacement_packet);

			misprediction_branch_cycle(6'd1,packet);

			packet_number++;

			// for getting a new replacement packet
			do begin
				packet = packet_t'($urandom_range(7'h7F, 7'h23));
			end
			while (packet == previous_replacement_packet);

			misprediction_branch_cycle(6'd1,packet);

			packet_number++;

			// MODE 01: final normal branch insertion.
			packet = packet_t'(packet_number);

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",
				$sformatf("Applying final mode 01: packet=0x%02h",packet),UVM_MEDIUM)

			branch_cycle(packet);
			packet_number++;

			// some idle cycles after transaction
			idle_cycle();
			idle_cycle();

			`uvm_info("GHR_NORMAL_PLUS_ROLLBACK_WTH_REPLACEMENT_BACK2BACK_SEQUENCE",{"Completed mode pattern: ","01 -> 11 -> 01 -> 11 -> 01"},UVM_LOW)

		endtask

endclass


// sequence to do a mixup of normal + rollback + rollback_with_replacement
class ghr_normal_rollback_n_rollbackreplacement_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_normal_rollback_n_rollbackreplacement_sequence)

	// Number of normal branch insertions before the first rollback.
	rand int unsigned initial_branch_cycles;

	constraint initial_branch_cycles_c {
		initial_branch_cycles inside {[4:5]};
	}


	function new(string name ="ghr_normal_rollback_n_rollbackreplacement_sequence");
		super.new(name);
	endfunction


	virtual task body();

		packet_t packet;
		packet_t previous_replacement_packet;

		int unsigned packet_number;


		assert (this.randomize())
		else `uvm_fatal("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE","Failed to randomize initial branch-cycle count")

		
		packet_number = $urandom_range(7'h70, 7'h40);

		previous_replacement_packet = '0;

		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",
			$sformatf({"Starting normal/rollback/replacement sequence: ",
				 "initial normal writes=%0d ",
				 "first normal packet=0x%02h"},
				initial_branch_cycles,
				packet_number
			),UVM_LOW
		)

		idle_cycle();
		idle_cycle();


		/// initial fill up
		for (int write_number = 0; write_number < 34; write_number++) 
		begin
			packet = packet_t'(write_number + 1);
			branch_cycle(packet);
		end


		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",{"GHR initialized with 34 packets. ","Expected head pointer=34."},UVM_LOW)


		// MODE 01: four or five normal branch insertions.
		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",
			$sformatf("Applying mode 01 for %0d cycles",initial_branch_cycles),UVM_MEDIUM)

		repeat (initial_branch_cycles) begin

			packet = packet_t'(packet_number);

			`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",
				$sformatf("Mode 01: normal packet=0x%02h",packet),UVM_MEDIUM)

			branch_cycle(packet);
			packet_number++;

		end

		// MODE 10: rollback without replacement.
		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE","Applying first mode 10: ROLLBACK-ONLY depth=4",UVM_MEDIUM)

		misprediction_cycle(6'd4);


		// MODE 11: rollback with first unique replacement.
		packet = packet_t'($urandom_range(7'h3F, 7'h23));

		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",
			$sformatf({"Applying first mode 11: depth=2 ","replacement packet=0x%02h"},packet),UVM_MEDIUM)

		misprediction_branch_cycle(6'd2,packet);

		previous_replacement_packet = packet;


		// MODE 01: one normal branch insertion.
		packet = packet_t'(packet_number);

		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",
			$sformatf("Applying mode 01: normal packet=0x%02h",packet),UVM_MEDIUM)

		branch_cycle(packet);
		packet_number++;


		// MODE 10: second rollback without replacement.
		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE","Applying second mode 10: ROLLBACK-ONLY depth=3",UVM_MEDIUM)

		misprediction_cycle(6'd3);


		// MODE 11: second rollback with replacement.
		do begin
			packet = packet_t'($urandom_range(7'h3F, 7'h23));
		end
		while (packet == previous_replacement_packet);

		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",
			$sformatf({"Applying second mode 11: depth=1 ","replacement packet=0x%02h"},packet),UVM_MEDIUM)

		misprediction_branch_cycle(6'd1,packet);

		previous_replacement_packet = packet;

		// MODE 01: final normal insertion.
		packet = packet_t'(packet_number);

		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",
			$sformatf("Applying final mode 01: packet=0x%02h",packet),UVM_MEDIUM)

		branch_cycle(packet);
		packet_number++;

		idle_cycle();
		idle_cycle();

		`uvm_info("GHR_NORMAL_ROLLBACK_N_ROLLBACKREPLACEMENT_SEQUENCE",{"Completed mode combination: ",
			 "01 -> 10 -> 11 -> 01 -> 10 -> 11 -> 01"},UVM_LOW)

	endtask

endclass



//  asynchronous reset after the GHR contains valid history.
class ghr_async_reset_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_async_reset_sequence)

	virtual ghr_if vif;

	function new(string name = "ghr_async_reset_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;

		// Obtain the same interface used by the driver and monitor.
		if (!uvm_config_db #(virtual ghr_if)::get(null,"*","vif",vif)) begin
			`uvm_fatal("GHR_ASYNC_RESET_SEQUENCE","Unable to retrieve virtual ghr_if")
		end

		`uvm_info("GHR_ASYNC_RESET_SEQUENCE","Starting asynchronous-reset sequence",UVM_LOW)

		idle_cycle();
		idle_cycle();

		for (int write_number = 0; write_number < 32; write_number++) begin
			packet = packet_t'(write_number + 1);
			branch_cycle(packet);
		end

		idle_cycle();

		`uvm_info("GHR_ASYNC_RESET_SEQUENCE",{"GHR contains 32 packets. ","Asserting asynchronous reset between clock edges."},UVM_LOW)

		// #2;
		repeat (2) begin
			@(posedge vif.clk);
		end

		vif.rst_n = 1'b0;

		#1;

		if (vif.incoming_packet_o !== '0) begin
			`uvm_error("GHR_ASYNC_RESET_SEQUENCE",
			$sformatf({"incoming_packet_o did not clear ","asynchronously: observed=0x%02h"},vif.incoming_packet_o))
		end

		foreach (vif.expiring_packet_o[index]) begin

			if (vif.expiring_packet_o[index] !== '0) begin

				`uvm_error("GHR_ASYNC_RESET_SEQUENCE",
					$sformatf({"expiring_packet_o[%0d] did not clear ","asynchronously: observed=0x%02h"},index,vif.expiring_packet_o[index]))
			end
		end


		`uvm_info("GHR_ASYNC_RESET_SEQUENCE","Immediate asynchronous-reset output check completed",UVM_LOW)

		repeat (2) begin
			@(posedge vif.clk);
		end


		#2;				// Deassert reset between clock edges as well.
		vif.rst_n = 1'b1;

		`uvm_info("GHR_ASYNC_RESET_SEQUENCE",{"Asynchronous reset deasserted. ",
			 "Expected head pointer=0 and all GHR entries=0."},UVM_LOW)

		idle_cycle();
		idle_cycle();

		branch_cycle(7'h61);  // Expected pointer 0
		branch_cycle(7'h62);  // Expected pointer 1
		branch_cycle(7'h63);  // Expected pointer 2
		branch_cycle(7'h64);  // Expected pointer 3
		branch_cycle(7'h65);  // Expected pointer 4

		idle_cycle();
		idle_cycle();


		`uvm_info("GHR_ASYNC_RESET_SEQUENCE",{"Completed asynchronous-reset sequence. ",
			 "Expected final head pointer=5."},UVM_LOW)

	endtask

endclass



// rollback with misprediction table depth = 0
//   DUT assertion should report an error. No valid rollback operation should be accepted.
//   Head pointer and GHR memory should remain unchanged.
class ghr_zero_misprediction_depth_sequence	extends ghr_base_sequence;

	`uvm_object_utils(ghr_zero_misprediction_depth_sequence)

	function new(string name = "ghr_zero_misprediction_depth_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;

		`uvm_info("GHR_ZERO_DEPTH_SEQUENCE","Starting misprediction-depth-zero negative test",UVM_LOW)

		idle_cycle();
		idle_cycle();

		for (int write_number = 0; write_number < 20; write_number++) begin
			packet = packet_t'(write_number + 1);
			branch_cycle(packet);
		end

		`uvm_info("GHR_ZERO_DEPTH_SEQUENCE",{"GHR initialized with 20 packets. ","Expected head pointer=20."},UVM_LOW)

		idle_cycle();

		`uvm_info("GHR_ZERO_DEPTH_SEQUENCE",{"Driving illegal rollback request: ","misprediction=1, br_valid=0, depth=0"},UVM_LOW)

		drive_cycle(
			.en                  (1'b1),
			.br_valid            (1'b0),
			.br_packet           ('0),
			.misprediction       (1'b1),
			.mispredicted_depth  (6'd0)
		);

		idle_cycle();
		idle_cycle();
		branch_cycle(7'h55);

		idle_cycle();
		idle_cycle();


		`uvm_info("GHR_ZERO_DEPTH_SEQUENCE",{"Completed depth-zero negative test. ","Expected final head pointer=21."},UVM_LOW)

	endtask

endclass



// illegal misprediction depth (36-63)
class ghr_out_of_range_depth_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_out_of_range_depth_sequence)

	rand bit [5:0] illegal_depth;

	constraint illegal_depth_c {
		illegal_depth inside {[6'd36:6'd63]};
	}

	function new(string name = "ghr_out_of_range_depth_sequence");
		super.new(name);
	endfunction

	virtual task body();

		packet_t packet;

		assert (this.randomize())
		else `uvm_fatal("GHR_OUT_OF_RANGE_DEPTH_SEQUENCE","Failed to randomize illegal misprediction depth")

		`uvm_info("GHR_OUT_OF_RANGE_DEPTH_SEQUENCE",
			$sformatf("Starting illegal-depth test with depth=%0d",illegal_depth),UVM_LOW)

		idle_cycle();
		idle_cycle();

		// fill up all the locations in the GHR
		for (int write_number = 0; write_number < MAX_PTR; write_number++) begin
			packet = packet_t'(write_number + 1);
			branch_cycle(packet);
		end

		`uvm_info("GHR_OUT_OF_RANGE_DEPTH_SEQUENCE",{"All 36 GHR locations initialized. ","Expected head pointer=0 after wraparound."},UVM_LOW)

		idle_cycle();

		`uvm_info("GHR_OUT_OF_RANGE_DEPTH_SEQUENCE",
			$sformatf({"Driving illegal rollback request: ","misprediction=1, br_valid=0, depth=%0d"},illegal_depth),UVM_LOW)

		drive_cycle(
			.en                  (1'b1),
			.br_valid            (1'b0),
			.br_packet           ('0),
			.misprediction       (1'b1),
			.mispredicted_depth  (illegal_depth)
		);

		idle_cycle();

		`uvm_info("GHR_OUT_OF_RANGE_DEPTH_SEQUENCE",
			$sformatf({"Completed illegal-depth stimulus: depth=%0d. ","An assertion/protocol error is expected."},illegal_depth),UVM_LOW)

	endtask

endclass


// Constrained-random GHR sequence
class ghr_random_sequence extends ghr_base_sequence;

	`uvm_object_utils(ghr_random_sequence)

	rand int unsigned num_transactions;

	constraint num_transactions_c {
		num_transactions inside {[2000:4000]};
	}

	function new(string name = "ghr_random_sequence");
		super.new(name);
	endfunction

	virtual task body();

		ghr_seq_item tr;
		int unsigned valid_history_depth;
		int unsigned rollback_depth;

		valid_history_depth = 0;

		if (!randomize()) begin
		`uvm_error("GHR_RANDOM_SEQUENCE",
			"Failed to randomize num_transactions"
		)
		return;
		end

		`uvm_info("GHR_RANDOM_SEQUENCE",
			$sformatf(
				"Starting random sequence with %0d transactions",
				num_transactions
			),
			UVM_LOW
		)

		repeat (num_transactions) begin

		tr = ghr_seq_item::type_id::create("tr");

		start_item(tr);

		if (!tr.randomize() with {

			// A real misprediction is not allowed until history exists.
			if (local::valid_history_depth == 0)
			!(en && misprediction);

			// Do not roll back farther than the valid history.
			if (en && misprediction)
			mispredicted_table_depth inside {
				[1:local::valid_history_depth]
			};

		}) begin
			`uvm_error(
			"GHR_RANDOM_SEQUENCE",
			"Failed to randomize GHR transaction"
			)
		end

		finish_item(tr);

		// Update the sequence-side valid-history model only when
		// the DUT is enabled.
		if (tr.en) begin

			case ({tr.misprediction, tr.br_valid})

			2'b00: begin
				// Nothing running here
			end

			2'b01: begin
				// Normal branch insertion. History saturates at 36 entries.
				if (valid_history_depth < 36)
				valid_history_depth++;
			end

			2'b10: begin
				// Rollback without inserting a replacement branch.
				rollback_depth = tr.mispredicted_table_depth;
				valid_history_depth -= rollback_depth;
			end

			2'b11: begin
				// Rollback followed by a branch insertion.
				rollback_depth = tr.mispredicted_table_depth;
				valid_history_depth =
				valid_history_depth - rollback_depth + 1;
			end

			endcase

		end

		end

		// Allow final DUT activity to settle.
		repeat (3)
		idle_cycle();

		`uvm_info("GHR_RANDOM_SEQUENCE",
			$sformatf(
				"Completed random sequence; final valid history depth=%0d",
				valid_history_depth
			),
		UVM_LOW
		)

	endtask

	endclass


// sequencer
class ghr_sequencer extends uvm_sequencer #(ghr_seq_item);

	`uvm_component_utils(ghr_sequencer)

	function new(string name = "ghr_sequencer",uvm_component parent = null);
		super.new(name, parent);
	endfunction

endclass





// driver
class ghr_driver extends uvm_driver #(ghr_seq_item);

	`uvm_component_utils(ghr_driver)
	virtual ghr_if vif;

	function new(string name = "ghr_driver",uvm_component parent = null);
		super.new(name, parent);
	endfunction


	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db #(virtual ghr_if)::get(this,"","vif",vif)) begin
			`uvm_fatal("GHR_DRIVER","Unable to retrieve virtual ghr_if from uvm_config_db")
		end

	endfunction

	virtual task run_phase(uvm_phase phase);

		drive_idle();
		// wait for reset
		wait (vif.rst_n === 1'b1);

		forever begin
			seq_item_port.get_next_item(req);
			drive_transaction(req);
			seq_item_port.item_done();
		end

	endtask


	virtual task drive_transaction(ghr_seq_item tr);

		// wait until asynchronous reset is active
		wait (vif.rst_n === 1'b1);

		@(vif.driver_cb);
		vif.driver_cb.en_i                       <= tr.en;
		vif.driver_cb.br_valid_i                 <= tr.br_valid;
		vif.driver_cb.br_packet_i                <= tr.br_packet;
		vif.driver_cb.misprediction_i            <= tr.misprediction;
		vif.driver_cb.mispredicted_table_depth_i <=	tr.mispredicted_table_depth;

	endtask

	virtual task drive_idle();

		@(vif.driver_cb);
		vif.driver_cb.en_i                       <= 1'b0;
		vif.driver_cb.br_valid_i                 <= 1'b0;
		vif.driver_cb.br_packet_i                <= '0;
		vif.driver_cb.misprediction_i            <= 1'b0;
		vif.driver_cb.mispredicted_table_depth_i <= '0;

	endtask

endclass

// GHR monitor
class ghr_monitor extends uvm_monitor;

	`uvm_component_utils(ghr_monitor)
	virtual ghr_if vif;

	uvm_analysis_port #(ghr_seq_item) monitor_port;

	function new(string name = "ghr_monitor",uvm_component parent = null);
		super.new(name, parent);
		monitor_port = new("monitor_port", this);
	endfunction

	function void build_phase(uvm_phase phase);

		super.build_phase(phase);

		if (!uvm_config_db #(virtual ghr_if)::get(this,"","vif",vif)) begin
			`uvm_fatal("GHR_MONITOR","Unable to retrieve virtual ghr_if from uvm_config_db")
		end

	endfunction

	virtual task run_phase(uvm_phase phase);

		ghr_seq_item observed_tr;
		forever begin

			@(vif.monitor_cb);
			observed_tr = ghr_seq_item::type_id::create("observed_tr");

			// Sample reset and DUT inputs.
			observed_tr.rst_n = vif.monitor_cb.rst_n;
			observed_tr.en = vif.monitor_cb.en_i;
			observed_tr.br_valid = vif.monitor_cb.br_valid_i; 
			observed_tr.br_packet = vif.monitor_cb.br_packet_i;
			observed_tr.misprediction = vif.monitor_cb.misprediction_i;
			observed_tr.mispredicted_table_depth = vif.monitor_cb.mispredicted_table_depth_i;

			// Sample DUT outputs.
			observed_tr.observed_incoming_packet = vif.monitor_cb.incoming_packet_o;

			foreach (observed_tr.observed_expiring_packet[i]) begin
				observed_tr.observed_expiring_packet[i] = vif.monitor_cb.expiring_packet_o[i];
			end

			monitor_port.write(observed_tr);
		end

	endtask

endclass


// scoreboard

class ghr_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(ghr_scoreboard)

	localparam int PKT_WIDTH        = 7;
	localparam int NUM_BANKS        = 9;
	localparam int ENTRIES_PER_BANK = 4;
	localparam int MAX_PTR          = 36;
	localparam int NUM_HASH_TABLES  = 7;

	localparam int unsigned TAP_DEPTHS [0:NUM_HASH_TABLES-1] = '{2,4,6,8,12,16,32};

	uvm_analysis_imp #(ghr_seq_item,ghr_scoreboard) analysis_export;


	// Reference-memory organization matches the DUT:
	//
	//   ref_bank_mem[row][bank]
	//
	// Row 0 contains pointers  0–8
	// Row 1 contains pointers  9–17
	// Row 2 contains pointers 18–26
	// Row 3 contains pointers 27–35
	logic [PKT_WIDTH-1:0] ref_bank_mem [0:ENTRIES_PER_BANK-1][0:NUM_BANKS-1];

	int unsigned ref_head_ptr;

	int unsigned total_cycles;
	int unsigned total_checks;
	int unsigned passed_checks;
	int unsigned failed_checks;

	int unsigned reset_count;
	int unsigned branch_write_count;
	int unsigned rollback_count;


	function new(string name = "ghr_scoreboard",uvm_component parent = null);

		super.new(name, parent);

		analysis_export = new("analysis_export",this);
		clear_reference_model();

	endfunction


	// Clearing all reference-memory locations and restore the reference head pointer to zero.
	function void clear_reference_model();

		foreach (ref_bank_mem[row, bank]) begin
			ref_bank_mem[row][bank] = '0;
		end

		ref_head_ptr = 0;

	endfunction


	// Display the complete four-row by nine-bank reference memory.
	function void display_reference_model(input string message);

		int unsigned pointer;

		$display("\n============================================================");
		$display("GHR SCOREBOARD REFERENCE MEMORY");
		$display("%s", message);
		$display("Current head pointer = %0d", ref_head_ptr);
		$display("============================================================");

		for (int row = 0; row < ENTRIES_PER_BANK; row++) 
		begin

			$write("Row %0d : ", row);

			for (int bank = 0; bank < NUM_BANKS; bank++) 
			begin
				pointer = (row * NUM_BANKS) + bank;
				$write(
					"  B%0d [P%02d] = 0x%02h",
					bank,
					pointer,
					ref_bank_mem[row][bank]
			);
			end

			$display("");

		end
		$display("============================================================\n");

	endfunction


	// Translate a logical pointer into a physical bank number.
	function automatic int unsigned get_bank(input int unsigned pointer);
		return pointer % NUM_BANKS;
	endfunction


	// Translate a logical pointer into a physical row number.
	function automatic int unsigned get_row(input int unsigned pointer);
		return pointer / NUM_BANKS;
	endfunction


	// Increment a pointer with circular wrap at MAX_PTR.
	function automatic int unsigned increment_pointer(input int unsigned pointer);

		if (pointer == MAX_PTR - 1)
			return 0;
		else
			return pointer + 1;
	endfunction


	// Move backward through the circular GHR.
	function automatic int unsigned circular_subtract(input int unsigned pointer,input int unsigned distance);
		if (pointer >= distance)
			return pointer - distance;
		else
			return pointer + MAX_PTR - distance;
	endfunction


	// Compare one observed packet against its expected value.
	function void check_packet(input string check_name,input logic [PKT_WIDTH-1:0] expected_packet,input logic [PKT_WIDTH-1:0] observed_packet);

		total_checks++;
		if (observed_packet !== expected_packet) begin

			failed_checks++;
			`uvm_error("GHR_SCOREBOARD_MISMATCH",$sformatf({"%s mismatch: expected=0x%02h ","observed=0x%02h head_ptr=%0d"},check_name,expected_packet,observed_packet,ref_head_ptr))
		end
		else begin
			passed_checks++;
		end

	endfunction


	// Receive one complete cycle from the monitor.
	function void write(ghr_seq_item tr);

		int unsigned rollback_ptr;
		int unsigned next_head_ptr;
		int unsigned write_ptr;

		int unsigned write_bank;
		int unsigned write_row;

		int unsigned target_index;
		int unsigned read_bank;
		int unsigned read_row;

		logic [PKT_WIDTH-1:0] expected_incoming_packet;

		logic [PKT_WIDTH-1:0] expected_expiring_packet [0:NUM_HASH_TABLES-1];
		total_cycles++;


		// Asynchronous reset clears every bank and resets the head.
		if (!tr.rst_n) begin
			reset_count++;
			clear_reference_model();
			return;
		end


		// A legal rollback depth is between 1 and MAX_PTR-1.
		if (tr.en && tr.misprediction && (tr.mispredicted_table_depth == 0 || tr.mispredicted_table_depth >= MAX_PTR))
			begin

			failed_checks++;
			`uvm_error("GHR_SCOREBOARD_PROTOCOL",$sformatf("Illegal misprediction depth=%0d",tr.mispredicted_table_depth))
			return;

		end


		// Calculate the rollback pointer when recovery is active.
		rollback_ptr = ref_head_ptr;

		if (tr.en && tr.misprediction) begin
			rollback_ptr = circular_subtract(ref_head_ptr,tr.mispredicted_table_depth);
		end


		// Calculate the next reference head pointer.
		next_head_ptr = ref_head_ptr;

		if (tr.en) begin
			case ({tr.misprediction,tr.br_valid})

				// Idle operation.
				2'b00: begin
					next_head_ptr = ref_head_ptr;
				end

				// Normal branch insertion.
				2'b01: begin
					next_head_ptr =	increment_pointer(ref_head_ptr);
				end

				// Rollback without branch insertion.
				2'b10: begin
					next_head_ptr = rollback_ptr;
				end

				// Rollback followed by replacement branch insertion.
				2'b11: begin
					next_head_ptr =	increment_pointer(rollback_ptr);
				end

			endcase

		end


		// incoming_packet_o is valid only when the GHR accepts
		// a branch packet.
		if (tr.en && tr.br_valid)
			expected_incoming_packet = tr.br_packet;
		else
			expected_incoming_packet = '0;


		check_packet("incoming_packet_o",expected_incoming_packet,tr.observed_incoming_packet);

		// Calculate and check all seven expiring history packets.
		// ************ ???????????? ///////////
		// The reference memory is read before applying the current
		// cycle's branch write. This matches the monitor's sampling
		// and the DUT's clocked bank-memory update.
		for (int i = 0; i < NUM_HASH_TABLES; i++) begin

			target_index = circular_subtract(next_head_ptr,TAP_DEPTHS[i]);

			read_bank = get_bank(target_index);
			read_row  = get_row(target_index);

			expected_expiring_packet[i] = ref_bank_mem[read_row][read_bank];
			check_packet($sformatf("expiring_packet_o[%0d]",i),expected_expiring_packet[i],tr.observed_expiring_packet[i]);

		end

		/// adding the disabled cycle check here in the design
		if (!tr.en) 
		begin

			$display("\n============================================================");
			$display("GHR DISABLED-CYCLE CHECK");
			$display("============================================================");
		  
			$display("Reference head pointer      : %0d",ref_head_ptr);
			$display("Calculated next head        : %0d",next_head_ptr);
			$display("Raw br_valid                : %0b",tr.br_valid);
			$display("Raw br_packet               : 0x%02h",tr.br_packet);
			$display("Raw misprediction           : %0b",tr.misprediction);
			$display("Raw misprediction depth     : %0d",tr.mispredicted_table_depth);
			$display("Expected incoming_packet_o  : 0x%02h",expected_incoming_packet);
			$display("Observed incoming_packet_o  : 0x%02h",tr.observed_incoming_packet);
			$display("Expected expiring_packet_o  : %p",expected_expiring_packet);
			$display("Observed expiring_packet_o  : %p",tr.observed_expiring_packet);
		  
			$display("Expected state change        : NONE");
			$display("============================================================\n");
		  
		end
		

		/// adding a Rollback only display things here
		if (tr.en && tr.misprediction && !tr.br_valid) 
		begin
		  
			$display("\n============================================================");
			$display("GHR ROLLBACK-ONLY CHECK");
			$display("============================================================");
		  
			$display("Old current head pointer    : %0d",ref_head_ptr);
		  
			$display("Misprediction depth         : %0d",tr.mispredicted_table_depth);
		  
			$display("Calculated rollback pointer : %0d",rollback_ptr);
		  
			$display("Calculated next head        : %0d",next_head_ptr);
			$display("Expected incoming_packet_o  : 0x%02h",expected_incoming_packet);
			$display("Observed incoming_packet_o  : 0x%02h",tr.observed_incoming_packet);
			$display("Expected expiring_packet_o  : %p",expected_expiring_packet);
			$display("Observed expiring_packet_o  : %p",tr.observed_expiring_packet);
			$display("Expected memory write       : NONE");
		  
			$display("Expected pointer movement   : %0d -> %0d",ref_head_ptr,next_head_ptr);
		  
			$display("============================================================\n");
		  
		end
		  

		// Display the complete input/output packet bundle whenever
		// the GHR accepts a valid branch.
		if (tr.en && tr.br_valid) begin

			$display("\n============================================================");
			$display("GHR INPUT/OUTPUT PACKET BUNDLE");
			$display("============================================================");

			$display("Current head pointer       : %0d",ref_head_ptr);

			$display("Next head pointer          : %0d",next_head_ptr);

			$display("Enable signal en_i         : %0b",tr.en);

			$display("Branch valid br_valid_i    : %0b",tr.br_valid);

			/// in case of misprediction
			$display("Misprediction              : %0b",tr.misprediction);
		
			if (tr.misprediction) begin
			
				$display("Misprediction depth        : %0d",tr.mispredicted_table_depth);
			
				$display("Calculated rollback ptr    : %0d",rollback_ptr);
				$display("Replacement write pointer  : %0d",rollback_ptr);
				$display("Operation                  : ROLLBACK + REPLACEMENT");
			
			end
			else begin
			
				$display("Misprediction depth        : 0");
				$display("Operation  : NORMAL BRANCH INSERTION");
			
			end

			// ends the case of misprediction

			$display("Input br_packet            : 0x%02h",tr.br_packet);

			$display("Expected incoming_packet_o : 0x%02h",expected_incoming_packet);

			$display("Observed incoming_packet_o : 0x%02h",tr.observed_incoming_packet);

			$display("------------------------------------------------------------");
			$display("Array index               : {0, 1, 2, 3, 4, 5, 6}");
			$display("History depth             : {2, 4, 6, 8, 12, 16, 32}");

			$display("Expected expiring_packet_o : %p",expected_expiring_packet);

			$display("Observed expiring_packet_o : %p",tr.observed_expiring_packet);

			$display("============================================================\n");

		end


		// Apply the current branch write after checking outputs.
		if (tr.en && tr.br_valid) begin

			branch_write_count++;

			// A normal branch writes at the current free head. A replacement branch writes at the recovered head.
			if (tr.misprediction)
				write_ptr = rollback_ptr;
			else
				write_ptr = ref_head_ptr;

			write_bank = get_bank(write_ptr);
			write_row  = get_row(write_ptr);

			ref_bank_mem[write_row][write_bank] = tr.br_packet;

		end


		if (tr.en && tr.misprediction) begin
			rollback_count++;
		end


		// Commit the calculated next pointer after output checking
		// and after updating the reference memory.
		ref_head_ptr = next_head_ptr;

		// Show the updated physical reference memory after any
		// operation that changes the GHR state.
		if (tr.en && (tr.br_valid || tr.misprediction)) 
		begin
			display_reference_model("State after GHR operation");
		end

	endfunction


	virtual function void report_phase(uvm_phase phase);

		super.report_phase(phase);

		`uvm_info("GHR_SCOREBOARD_SUMMARY",
		$sformatf(
			{
			"\n----------------------------------------\n",
			"GHR SCOREBOARD SUMMARY\n",
			"----------------------------------------\n",
			"Total monitored cycles : %0d\n",
			"Reset cycles           : %0d\n",
			"Branch writes          : %0d\n",
			"Rollback operations    : %0d\n",
			"Total packet checks    : %0d\n",
			"Passed checks          : %0d\n",
			"Failed checks          : %0d\n",
			"Final head pointer     : %0d\n",
			"----------------------------------------"
			},
			total_cycles,
			reset_count,
			branch_write_count,
			rollback_count,
			total_checks,
			passed_checks,
			failed_checks,
			ref_head_ptr
		),
		UVM_NONE
		)

		if (failed_checks == 0) begin
			`uvm_info("GHR_SCOREBOARD_RESULT","TEST RESULT: PASS",UVM_NONE)
		end
		else begin
			`uvm_error("GHR_SCOREBOARD_RESULT",$sformatf("TEST RESULT: FAIL with %0d failed checks",failed_checks))
		end

	endfunction

endclass

// coverage model

class ghr_coverage extends uvm_subscriber #(ghr_seq_item);

	`uvm_component_utils(ghr_coverage)
	localparam int NUM_HASH_TABLES = 7;
	ghr_seq_item sampled_tr;

	covergroup ghr_control_cg;

		option.per_instance = 1;
		option.name = "ghr_control_cg";

		reset_cp: coverpoint sampled_tr.rst_n {
			bins reset_asserted   = {0};
			bins reset_deasserted = {1};
		}

		enable_cp: coverpoint sampled_tr.en
			iff (sampled_tr.rst_n) {
			bins disabled = {0};
			bins enabled  = {1};
		}

		branch_valid_cp: coverpoint sampled_tr.br_valid
			iff (sampled_tr.rst_n) {
			bins invalid_branch = {0};
			bins valid_branch   = {1};
		}

		misprediction_cp: coverpoint sampled_tr.misprediction
			iff (sampled_tr.rst_n) {
			bins no_misprediction = {0};
			bins misprediction    = {1};
		}

		// GHR operating modes: 00 = idle || 01 = branch insertion || 10 = rollback || 11 = rollback followed by branch insertion
		operation_cp: coverpoint {sampled_tr.misprediction, sampled_tr.br_valid}
			
			iff (sampled_tr.rst_n && sampled_tr.en) {

			bins idle                  = {2'b00};
			bins branch_insert         = {2'b01};
			bins rollback              = {2'b10};
			bins rollback_and_insert   = {2'b11};

			bins idle_to_branch        = (2'b00 => 2'b01);
			bins idle_to_rollback      = (2'b00 => 2'b10);
			bins idle_to_combined      = (2'b00 => 2'b11);

			bins branch_to_idle        = (2'b01 => 2'b00);
			bins branch_to_branch      = (2'b01 => 2'b01);
			bins branch_to_rollback    = (2'b01 => 2'b10);
			bins branch_to_combined    = (2'b01 => 2'b11);

			bins rollback_to_idle      = (2'b10 => 2'b00);
			bins rollback_to_branch    = (2'b10 => 2'b01);
			bins rollback_to_rollback  = (2'b10 => 2'b10);
			bins rollback_to_combined  = (2'b10 => 2'b11);

			bins combined_to_idle      = (2'b11 => 2'b00);
			bins combined_to_branch    = (2'b11 => 2'b01);
			bins combined_to_rollback  = (2'b11 => 2'b10);
			bins combined_to_combined  = (2'b11 => 2'b11);
		}

		rollback_depth_cp:	coverpoint sampled_tr.mispredicted_table_depth
		iff (
			sampled_tr.rst_n &&
			sampled_tr.en &&
			sampled_tr.misprediction
		) {
			bins minimum_depth = {1};
			bins low_depth     = {[2:8]};
			bins medium_depth  = {[9:17]};
			bins high_depth    = {[18:34]};
			bins maximum_depth = {35};

			illegal_bins zero_depth = {0};
			illegal_bins too_large  = {[36:63]};
		}

		branch_type_cp: coverpoint sampled_tr.br_packet[6]
		iff (
			sampled_tr.rst_n &&
			sampled_tr.en &&
			sampled_tr.br_valid
		) {
			bins type_0 = {0};
			bins type_1 = {1};
		}

		taken_cp: coverpoint sampled_tr.br_packet[5]
		iff (
			sampled_tr.rst_n &&
			sampled_tr.en &&
			sampled_tr.br_valid
		) {
			bins not_taken = {0};
			bins taken     = {1};
		}

		target_cp: coverpoint sampled_tr.br_packet[4:0]
		iff (
			sampled_tr.rst_n &&
			sampled_tr.en &&
			sampled_tr.br_valid
		) {
			bins zero_target = {0};
			bins low_target  = {[1:15]};
			bins high_target = {[16:30]};
			bins max_target  = {31};
		}

		enabled_control_cross: cross enable_cp, branch_valid_cp, misprediction_cp;

		branch_packet_cross: cross branch_type_cp, taken_cp;

	endgroup


	// This covergroup checks whether every hash-table tap has
	// produced both zero and nonzero expiring packets.
	covergroup expiring_packet_cg with function sample(
		input int unsigned table_index,
		input logic [6:0]  expiring_packet
	);

		option.per_instance = 1;
		option.name = "expiring_packet_cg";

		table_index_cp: coverpoint table_index {
			bins tables[] = {[0:NUM_HASH_TABLES-1]};
		}

		expiring_value_cp: coverpoint expiring_packet {
			bins zero_value    = {0};
			bins nonzero_value = {[1:127]};
		}

		table_value_cross: cross table_index_cp, expiring_value_cp;
	endgroup


	function new(string name = "ghr_coverage",uvm_component parent = null);
		super.new(name, parent);
		ghr_control_cg = new();
		expiring_packet_cg = new();
	endfunction


	virtual function void write(ghr_seq_item tr);

		sampled_tr = tr;
		ghr_control_cg.sample();

		if (tr.rst_n) begin
			foreach (tr.observed_expiring_packet[i]) begin
				expiring_packet_cg.sample(i,tr.observed_expiring_packet[i]);
			end
		end

	endfunction


	virtual function void report_phase(uvm_phase phase);

		super.report_phase(phase);

		`uvm_info("GHR_COVERAGE_SUMMARY",
			$sformatf(
			{
			"\n----------------------------------------\n",
			"GHR FUNCTIONAL COVERAGE\n",
			"----------------------------------------\n",
			"Control coverage         : %0.2f%%\n",
			"Expiring packet coverage : %0.2f%%\n",
			"----------------------------------------"
			},
			ghr_control_cg.get_coverage(),
			expiring_packet_cg.get_coverage()
		),
		UVM_NONE
		)

	endfunction

endclass

// agent

class ghr_agent extends uvm_agent;

	`uvm_component_utils(ghr_agent)

	ghr_sequencer sequencer;
	ghr_driver    driver;
	ghr_monitor   monitor;


	function new(string name = "ghr_agent",uvm_component parent = null);
		super.new(name, parent);
	endfunction


	virtual function void build_phase(uvm_phase phase);

		super.build_phase(phase);
		monitor = ghr_monitor::type_id::create("monitor",this);
		if (get_is_active() == UVM_ACTIVE) begin
			sequencer = ghr_sequencer::type_id::create("sequencer",this);
			driver = ghr_driver::type_id::create("driver",this);
		end

	endfunction


	virtual function void connect_phase(uvm_phase phase);

		super.connect_phase(phase);
		if (get_is_active() == UVM_ACTIVE) begin
			driver.seq_item_port.connect(sequencer.seq_item_export);
		end

	endfunction

endclass

// environment
// GHR environment
class ghr_env extends uvm_env;

	`uvm_component_utils(ghr_env)

	ghr_agent      agent;
	ghr_scoreboard scoreboard;
	ghr_coverage   coverage;


	function new(string name = "ghr_env",uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);

		super.build_phase(phase);
		agent = ghr_agent::type_id::create("agent",this);
		scoreboard = ghr_scoreboard::type_id::create("scoreboard",this);
		coverage = ghr_coverage::type_id::create("coverage",this);

	endfunction


	virtual function void connect_phase(uvm_phase phase);

		super.connect_phase(phase);
		agent.monitor.monitor_port.connect(scoreboard.analysis_export);
		agent.monitor.monitor_port.connect(coverage.analysis_export);

	endfunction

	endclass


// test class
// GHR base test
class ghr_base_test extends uvm_test;

	`uvm_component_utils(ghr_base_test)
	ghr_env env;

	function new(string name = "ghr_base_test",uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		env = ghr_env::type_id::create("env",this);
	endfunction

	task run_phase(uvm_phase phase);
		ghr_smoke_sequence ghr_smoke;
		ghr_bank_write_wrap_sequence ghr_write_wrap;
		ghr_packet_depth_sequence ghr_pkt_depth;
		ghr_enable_gating_sequence ghr_enable_gating;
		ghr_rollback_sequence ghr_rollback;
		ghr_deep_rollback_replacement_sequence ghr_rollback_GT_valid_history;
		ghr_deep_multiple_rollback_replacement_sequence ghr_rollback_multiple_times;
		ghr_rollback_across_zero_sequence ghr_rollback_across_zero;
		ghr_mode_transition_sequence ghr_modes;
		ghr_normal_plus_rollback_back2back_sequence ghr_normal_rollback_only;
		ghr_normal_plus_rollback_wth_replacement_back2back_sequence ghr_nomral_rollback_wth_rplcmnt;
		ghr_normal_rollback_n_rollbackreplacement_sequence ghr_normal_rollback_rollbackwithreplacement;
		ghr_async_reset_sequence ghr_reset;
		ghr_zero_misprediction_depth_sequence ghr_zero_misp_dpth;
		ghr_out_of_range_depth_sequence ghr_invalid_range;

		phase.raise_objection(this);
		// ghr_smoke = ghr_smoke_sequence::type_id::create("ghr_smoke");
		// ghr_smoke.start(env.agent.sequencer);

		// ghr_write_wrap = ghr_bank_write_wrap_sequence::type_id::create("ghr_write_wrap");
		// ghr_write_wrap.start(env.agent.sequencer);

		// ghr_pkt_depth = ghr_packet_depth_sequence::type_id::create("ghr_pkt_depth");
		// ghr_pkt_depth.start(env.agent.sequencer);

		// ghr_enable_gating = ghr_enable_gating_sequence::type_id::create("ghr_enable_gating");
		// ghr_enable_gating.start(env.agent.sequencer);

		// ghr_rollback = ghr_rollback_sequence::type_id::create("ghr_rollback");
		// ghr_rollback.start(env.agent.sequencer);

		// ghr_rollback_GT_valid_history = ghr_deep_rollback_replacement_sequence::type_id::create("ghr_rollback_GT_valid_history");
		// ghr_rollback_GT_valid_history.start(env.agent.sequencer);

		// ghr_rollback_multiple_times = ghr_deep_multiple_rollback_replacement_sequence::type_id::create("ghr_rollback_multiple_times");
		// ghr_rollback_multiple_times.start(env.agent.sequencer);

		// ghr_rollback_across_zero = ghr_rollback_across_zero_sequence::type_id::create("ghr_rollback_across_zero");
		// ghr_rollback_across_zero.start(env.agent.sequencer);
		
		// ghr_modes = ghr_mode_transition_sequence::type_id::create("ghr_modes");
		// ghr_modes.start(env.agent.sequencer);

		// ghr_normal_rollback_only = ghr_normal_plus_rollback_back2back_sequence::type_id::create("ghr_normal_rollback_only");
		// ghr_normal_rollback_only.start(env.agent.sequencer);

		// ghr_nomral_rollback_wth_rplcmnt = ghr_normal_plus_rollback_wth_replacement_back2back_sequence::type_id::create("ghr_nomral_rollback_wth_rplcmnt");
		// ghr_nomral_rollback_wth_rplcmnt.start(env.agent.sequencer);
		
		// ghr_normal_rollback_rollbackwithreplacement = ghr_normal_rollback_n_rollbackreplacement_sequence::type_id::create("ghr_normal_rollback_rollbackwithreplacement");
		// ghr_normal_rollback_rollbackwithreplacement.start(env.agent.sequencer);

		// ghr_reset = ghr_async_reset_sequence::type_id::create("ghr_reset");
		// ghr_reset.start(env.agent.sequencer);

		// ghr_zero_misp_dpth = ghr_zero_misprediction_depth_sequence::type_id::create("ghr_zero_misp_dpth");
		// ghr_zero_misp_dpth.start(env.agent.sequencer);

		ghr_invalid_range = ghr_out_of_range_depth_sequence::type_id::create("ghr_invalid_range");
		ghr_invalid_range.start(env.agent.sequencer);

		phase.drop_objection(this);
	endtask

	// 	virtual function void end_of_elaboration_phase(uvm_phase phase);

	// 		super.end_of_elaboration_phase(phase);
	// 		uvm_top.print_topology();

	// 	endfunction

endclass


// tb top
// Testbench top
module tb_top;

	import uvm_pkg::*;

	localparam int PKT_WIDTH         = 7;
	localparam int NUM_BANKS         = 9;
	localparam int ENTRIES_PER_BANK  = 4;
	localparam int MAX_PTR           = 36;
	localparam int NUM_HASH_TABLES   = 7;

	logic clk;

	initial begin
		clk = 1'b0;
	end

	always #5 clk = ~clk;

	// GHR interface instance.
	ghr_if #(
			.PKT_WIDTH       (PKT_WIDTH),
			.NUM_HASH_TABLES (NUM_HASH_TABLES)
		) ghr_vif (
			.clk (clk)
	);

	initial begin

		ghr_vif.rst_n                       = 1'b0;
		ghr_vif.en_i                        = 1'b0;
		ghr_vif.br_valid_i                  = 1'b0;
		ghr_vif.br_packet_i                 = '0;
		ghr_vif.misprediction_i             = 1'b0;
		ghr_vif.mispredicted_table_depth_i  = '0;

		// Reset active for three complete cycles.
		repeat (3)
		@(negedge clk);
		ghr_vif.rst_n = 1'b1;

	end

	// DUT instance.
	LP_ghr_block #(
		.PKT_WIDTH        (PKT_WIDTH),
		.NUM_BANKS        (NUM_BANKS),
		.ENTRIES_PER_BANK (ENTRIES_PER_BANK),
		.MAX_PTR          (MAX_PTR),
		.NUM_HASH_TABLES  (NUM_HASH_TABLES)
	) dut (
		.clk                         (clk),
		.rst_n                       (ghr_vif.rst_n),

		.en_i                        (ghr_vif.en_i),
		.br_valid_i                  (ghr_vif.br_valid_i),
		.br_packet_i                 (ghr_vif.br_packet_i),

		.misprediction_i             (ghr_vif.misprediction_i),
		.mispredicted_table_depth_i  (ghr_vif.mispredicted_table_depth_i),

		.incoming_packet_o           (ghr_vif.incoming_packet_o),
		.expiring_packet_o           (ghr_vif.expiring_packet_o)
	);


	initial begin

		uvm_config_db #(virtual ghr_if)::set(null,"*","vif",ghr_vif);
		run_test("ghr_base_test");

	end

endmodule