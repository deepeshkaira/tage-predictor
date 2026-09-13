
`timescale 1ns/1ps

//`include "TB_Combine_wrapper_ghr_fifo_hash_sequences.sv"

/// 
package predictor_history_tb_params_pkg;

// Common clock and reset configuration.
parameter time CLK_PERIOD = 10ns;
parameter int RESET_ACTIVE_CYCLES = 3;

// Common input widths.
parameter int PKT_WIDTH = 7;
parameter int PC_WIDTH = 32;
parameter int MISPREDICT_DEPTH_WIDTH = 6;

// GHR configuration.
parameter int NUM_GHR_PACKETS = 7;
parameter int NUM_GHR_BANKS = 9;
parameter int GHR_ENTRIES_PER_BANK = 4;
parameter int GHR_MAX_PTR = 36;
parameter int GHR_DEPTHS [0:NUM_GHR_PACKETS-1] = '{2, 4, 6, 8, 12, 16, 32};

// Single tagged-table hash configuration.
parameter int NUM_SELECTED_HASHES = 1;
parameter int S_WIDTH = 7;
parameter int T_WIDTH = 16;
parameter int FOLD_WIDTH = S_WIDTH + T_WIDTH ;
parameter int SELECTED_HASH_TABLE = 0;
parameter int SELECTED_HISTORY_DEPTH = GHR_DEPTHS[SELECTED_HASH_TABLE];
parameter int SELECTED_HASH_DEPTHS [0:NUM_SELECTED_HASHES-1] = '{SELECTED_HISTORY_DEPTH};

// Checkpoint FIFO configuration.
parameter int FIFO_DEPTH = 16;
parameter int FIFO_ADDR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);
parameter int FIFO_COUNT_WIDTH = $clog2(FIFO_DEPTH + 1);

// Reusable packed data types.
typedef logic [PKT_WIDTH-1:0] branch_packet_t;
typedef logic [PC_WIDTH-1:0] program_counter_t;
typedef logic [MISPREDICT_DEPTH_WIDTH-1:0] misprediction_depth_t;
typedef logic [S_WIDTH-1:0] tagged_index_t;
typedef logic [T_WIDTH-1:0] tagged_tag_t;
typedef logic [FOLD_WIDTH-1:0] folded_history_t;

// Reusable unpacked array types.
typedef branch_packet_t ghr_packet_array_t [0:NUM_GHR_PACKETS-1];
typedef branch_packet_t selected_packet_array_t [0:NUM_SELECTED_HASHES-1];
typedef folded_history_t selected_folded_history_array_t [0:NUM_SELECTED_HASHES-1];
typedef tagged_index_t selected_tagged_index_array_t [0:NUM_SELECTED_HASHES-1];
typedef tagged_tag_t selected_tagged_tag_array_t [0:NUM_SELECTED_HASHES-1];

endpackage

import uvm_pkg::*;
import predictor_history_tb_params_pkg::*;
`include "uvm_macros.svh"


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


// GHR controls sampled before the risign edge and state sampled after it
logic [5:0] ghr_head_pre;
logic [5:0] ghr_head_post;
logic [5:0] ghr_next_head_pre;
logic [5:0] ghr_write_ptr_pre;
logic [3:0] ghr_write_bank_pre;
logic [1:0] ghr_write_row_pre;
logic [NUM_GHR_BANKS-1:0] ghr_bank_we_pre;
logic ghr_ptr_enable_pre;
logic ghr_recovery_pre;
branch_packet_t ghr_write_data_pre;
branch_packet_t ghr_incoming_post;
branch_packet_t ghr_memory_post [0:GHR_MAX_PTR-1];


// The driver places the next request after the falling edge. Status inputs
// let it avoid illegal traffic when the FIFO is full or recovery is active.
clocking drv_cb @(negedge clk);
	// default input #1step output #0;
	default input #0;
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
clocking mon_cb @(posedge clk);
	 default input #1step;
	//default input #0;
	input rst_n;
	input en_i;
	input br_valid_i;
	input br_packet_i;
	input load_pc_i;
	input branch_commit_i;
	input misprediction_i;
	input mispredicted_table_depth_i;

	// GHR operands presented to the hash before this rising edge.
	input ghr_incoming_packet_o;
	input ghr_expiring_packets_o;
	input selected_expiring_packet_o;

	// These inherit the existing default input #1step.
	input ghr_head_pre;
	input ghr_next_head_pre;
	input ghr_write_ptr_pre;
	input ghr_write_bank_pre;
	input ghr_write_row_pre;
	input ghr_bank_we_pre;
	input ghr_ptr_enable_pre;
	input ghr_recovery_pre;
	input ghr_write_data_pre;

	// Registered state after this same rising edge.
	input #0 ghr_head_post;
	input #0 ghr_incoming_post;
	input #0 ghr_memory_post;
	
	input #0 tagged_index_o;
	input #0 tagged_tag_o;
	input #0 fifo_full_o;
	input #0 fifo_empty_o;
	input #0 recovery_active_o;
	input #0 folded_history_state_o;
	input #0 recovery_folded_history_o;
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


/// sequence item and sequences
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

	/// some additional observation fields
	logic [5:0] ghr_head_pre;
	logic [5:0] ghr_head_post;
	logic [5:0] ghr_next_head_pre;
	logic [5:0] ghr_write_ptr_pre;
	logic [3:0] ghr_write_bank_pre;
	logic [1:0] ghr_write_row_pre;
	logic [NUM_GHR_BANKS-1:0] ghr_bank_we_pre;
	logic ghr_ptr_enable_pre;
	logic ghr_recovery_pre;
	branch_packet_t ghr_write_data_pre;
	branch_packet_t ghr_incoming_post;
	branch_packet_t ghr_memory_post [0:GHR_MAX_PTR-1];

	bit reset_request = 1'b0;

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
		`uvm_field_int(reset_request, UVM_DEFAULT)
		`uvm_field_int(ghr_head_pre, UVM_HEX)
		`uvm_field_int(ghr_head_post, UVM_HEX)
		`uvm_field_int(ghr_next_head_pre, UVM_HEX)
		`uvm_field_int(ghr_write_ptr_pre, UVM_HEX)
		`uvm_field_int(ghr_write_bank_pre, UVM_HEX)
		`uvm_field_int(ghr_write_row_pre, UVM_HEX)
		`uvm_field_int(ghr_bank_we_pre, UVM_HEX)
		`uvm_field_int(ghr_ptr_enable_pre, UVM_DEFAULT)
		`uvm_field_int(ghr_recovery_pre, UVM_DEFAULT)
		`uvm_field_int(ghr_write_data_pre, UVM_HEX)
		`uvm_field_int(ghr_incoming_post, UVM_HEX)
		`uvm_field_sarray_int(ghr_memory_post, UVM_HEX)
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
		return $sformatf("name=%s cycle=%0d en=%b br_valid=%b packet=0x%0h pc=0x%08h commit=%b misprediction=%b depth=%0d fifo_full=%b fifo_empty=%b recovery=%b folded_history=0x%0h index=0x%0h tag=0x%0h", 
		transaction_name, cycle_number, en_i, br_valid_i, br_packet_i, load_pc_i, branch_commit_i, misprediction_i, mispredicted_table_depth_i, fifo_full_o, fifo_empty_o, recovery_active_o, folded_history_state_o, tagged_index_o, tagged_tag_o);
	endfunction

endclass

/// base sequence
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


	virtual task reset_cycle(input string cycle_name = "reset_cycle");
		predictor_history_sequence_item req;

		req = predictor_history_sequence_item::type_id::create("reset_req");

		start_item(req);
		req.reset_request = 1'b1;
		req.en_i = 1'b0;
		req.br_valid_i = 1'b0;
		req.br_packet_i = '0;
		req.load_pc_i = '0;
		req.branch_commit_i = 1'b0;
		req.misprediction_i = 1'b0;
		req.mispredicted_table_depth_i = '0;
		req.transaction_name = cycle_name;
		finish_item(req);

		generated_transaction_count++;
	endtask

endclass



//// basic /smoke sequence
class predictor_history_smoke_sequence extends predictor_history_base_sequence;

`uvm_object_utils(predictor_history_smoke_sequence)

function new(string name = "predictor_history_smoke_sequence");
	super.new(name);
endfunction

virtual task body();

	branch_packet_t random_packet;
	program_counter_t random_pc;
	
	// int unsigned branch_count;
	int unsigned transaction_count;

	// branch_count = 0;
	transaction_count = (FIFO_DEPTH < 16) ? FIFO_DEPTH : 16;	
	`uvm_info(get_type_name(), "Starting predictor-history smoke sequence", UVM_LOW)

	idle_cycle("initial_idle");
	
	for(int unsigned iteration = 0; iteration < transaction_count ;iteration++)
	begin
			case(iteration)
			0:branch_cycle(7'h11, 32'd4, "prefill_branch_0");	
			1:branch_cycle(7'h22, 32'd8, "prefill_branch_1");
			2:branch_cycle(7'h35, 32'd12, "prefill_branch_2");
			3:branch_cycle(7'h4A, 32'd16, "prefill_branch_3");
			default: begin
				random_packet = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1,1));
				random_pc = program_counter_t'($urandom_range(7,0)*4);
				branch_cycle(random_packet, random_pc, $sformatf("random_branch_%0d",iteration));
			end	
			endcase	
		
		`uvm_info(get_type_name(), $sformatf("Completed smoke sequence: %0d continuous branch transactions", transaction_count), UVM_LOW);
		
	end	

	idle_cycle("final_settle_0");
	idle_cycle("final_settle_1");

	
	`uvm_info(get_type_name(), "Completed predictor-history smoke sequence", UVM_LOW)
endtask

endclass


// reset sequence check
class predictor_history_startup_reset_sequence extends predictor_history_base_sequence;
	
	`uvm_object_utils(predictor_history_startup_reset_sequence)
	
	function new(string name = "predictor_history_startup_reset_sequence");
		super.new(name);
	endfunction

	virtual task body();

		`uvm_info(get_type_name(), "Starting startup reset sequence", UVM_LOW)
	
		repeat(3) begin
			disabled_cycle("post_reset_disabled");
		end


		repeat(3) begin
			idle_cycle("post_reset_enabled_idle");
		end
		
		`uvm_info(get_type_name(),"completed startup reset stimulus",UVM_LOW)
	endtask

endclass



/// data populated reset check design
class predictor_history_populated_reset_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_populated_reset_sequence)

	function new(string name = "predictor_history_populated_reset_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned prefill_count;

		prefill_count = (FIFO_DEPTH < 4) ? FIFO_DEPTH : 4;

		`uvm_info(get_type_name(), "Starting reset with populated history and checkpoints", UVM_LOW)

		for (int unsigned iteration = 0; iteration < prefill_count; iteration++) begin
			branch_cycle(branch_packet_t'(iteration + 1), program_counter_t'((iteration + 1) * 4), $sformatf("prefill_branch_%0d", iteration));
		end

		reset_cycle("reset_populated_design");

		repeat (3) begin
			disabled_cycle("post_reset_disabled");
		end

		repeat (3) begin
			idle_cycle("post_reset_enabled_idle");
		end

		`uvm_info(get_type_name(), "Completed reset with populated state", UVM_LOW)
	endtask

endclass


/// reset while enable flag is disabled in the design
class predictor_history_reset_while_disabled_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_reset_while_disabled_sequence)

	function new(string name = "predictor_history_reset_while_disabled_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned prefill_count;

		prefill_count = (FIFO_DEPTH < 4) ? FIFO_DEPTH : 4;

		`uvm_info(get_type_name(), "Starting reset while disabled sequence", UVM_LOW)

		for (int unsigned iteration = 0; iteration < prefill_count; iteration++) begin
			branch_cycle(branch_packet_t'(iteration + 1), program_counter_t'((iteration + 1) * 4), $sformatf("prefill_branch_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			disabled_cycle($sformatf("disabled_before_reset_%0d", iteration));
		end

		reset_cycle("reset_while_disabled");

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			disabled_cycle($sformatf("disabled_after_reset_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("enabled_idle_after_reset_%0d", iteration));
		end

		`uvm_info(get_type_name(), "Completed reset while disabled stimulus", UVM_LOW)
	endtask
	
endclass



///repeated resets to the design
class predictor_history_repeated_resets_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_repeated_resets_sequence)

	function new(string name = "predictor_history_repeated_resets_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned prefill_count;
		branch_packet_t packet_value;

		program_counter_t pc_value;

		prefill_count = (FIFO_DEPTH < 4) ? FIFO_DEPTH : 4;

		`uvm_info(get_type_name(),"starting repeated reset sequence", UVM_LOW)

		for (int unsigned reset_iteration = 0; reset_iteration < 3; reset_iteration++) begin

			for (int unsigned branch_iteration = 0; branch_iteration < prefill_count; branch_iteration++) begin
				packet_value = branch_packet_t'((reset_iteration * 16) + branch_iteration + 1);
				pc_value = program_counter_t'((branch_iteration + 1) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("reset_%0d_prefill_branch_%0d", reset_iteration, branch_iteration));
			end

			reset_cycle($sformatf("repeated_reset_%0d", reset_iteration));

			for (int unsigned idle_iteration = 0; idle_iteration < 3; idle_iteration++) begin
				idle_cycle($sformatf("reset_%0d_post_reset_idle_%0d", reset_iteration, idle_iteration));
			end

		end
		`uvm_info(get_type_name(), "Completed three reset rounds with branch activity between resets", UVM_LOW)
	endtask

endclass


/// branch valid toggle
class predictor_history_branch_valid_toggle_sequence extends predictor_history_base_sequence;
	
	`uvm_object_utils(predictor_history_branch_valid_toggle_sequence)

	function new(string name = "predictor_history_branch_valid_toggle_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned branch_count;
		int unsigned branch_limit;
		int unsigned gap_cycles;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		branch_count = 0;
		branch_limit = (FIFO_DEPTH < 8) ? FIFO_DEPTH : 8;

		`uvm_info(get_type_name(), "Starting branch-valid toggle sequence", UVM_LOW)

		idle_cycle("initial_invalid_cycle");

		for (int unsigned iteration = 0; iteration < branch_limit; iteration++) begin
			packet_value = branch_packet_t'(iteration + 1);
			pc_value = program_counter_t'((iteration % 7 + 1) * 4);

			branch_cycle(packet_value, pc_value, $sformatf("valid_branch_%0d", iteration));
			branch_count++;

			case (iteration % 4)
				0: gap_cycles = 1;
				1: gap_cycles = 3;
				2: gap_cycles = 0;
				3: gap_cycles = 2;
			endcase

			for (int unsigned gap_index = 0; gap_index < gap_cycles; gap_index++) begin
				packet_value = branch_packet_t'(64 + iteration + gap_index);
				pc_value = program_counter_t'(((iteration + gap_index) % 8) * 4);
				send_cycle($sformatf("invalid_gap_%0d_%0d", iteration, gap_index), 1'b1, 1'b0, packet_value, pc_value, 1'b0, 1'b0, '0);
			end
		end

		repeat (3) begin
			idle_cycle("final_invalid_cycle");
		end

		`uvm_info(get_type_name(), $sformatf("Completed branch-valid toggle sequence with %0d valid branches", branch_count), UVM_LOW)
	endtask

endclass


// global enable toggle - br_valid_i with en_i high
class predictor_history_global_enable_toggle_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_global_enable_toggle_sequence)

	function new(string name = "predictor_history_global_enable_toggle_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned disabled_cycles;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting global-enable toggle sequence", UVM_LOW)

		for (int unsigned iteration = 0; iteration < FIFO_DEPTH; iteration++) begin
			packet_value = branch_packet_t'(iteration + 1);
			pc_value = program_counter_t'((iteration % 8) * 4);

			send_cycle($sformatf("enabled_branch_%0d", iteration), 1'b1, 1'b1, packet_value, pc_value, 1'b0, 1'b0, '0);

			case (iteration % 4)
				0: disabled_cycles = 1;
				1: disabled_cycles = 3;
				2: disabled_cycles = 0;
				3: disabled_cycles = 5;
			endcase

			for (int unsigned disabled_index = 0; disabled_index < disabled_cycles; disabled_index++) begin
				packet_value = branch_packet_t'(64 + iteration + disabled_index);
				pc_value = program_counter_t'(((iteration + disabled_index + 1) % 8) * 4);

				send_cycle($sformatf("disabled_branch_%0d_%0d", iteration, disabled_index), 1'b0, 1'b1, packet_value, pc_value, 1'b0, 1'b0, '0);
			end
		end

		repeat (3) begin
			idle_cycle("final_settle");
		end

		`uvm_info(get_type_name(), "Completed global-enable toggle stimulus", UVM_LOW)
	endtask

endclass


//// toggle with enable filling up the data
class predictor_history_prefill_enable_toggle_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_prefill_enable_toggle_sequence)

	function new(string name = "predictor_history_prefill_enable_toggle_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned prefill_count;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 13) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 13 for at least 12 prefill branches and one resume branch")
		end

		//prefill_count = ((FIFO_DEPTH - 1) < 15) ? (FIFO_DEPTH - 1) : 15;
		prefill_count = 25;		/// greater than the depth of FIFO

		`uvm_info(get_type_name(), $sformatf("Starting enable test with %0d consecutive prefill branches", prefill_count), UVM_LOW)

		for (int unsigned iteration = 0; iteration < prefill_count; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			send_cycle($sformatf("continuous_prefill_%0d", iteration), 1'b1, 1'b1, packet_value, pc_value, 1'b0, 1'b0, '0);
		end

		for (int unsigned iteration = 0; iteration < 20; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			send_cycle($sformatf("disabled_with_valid_%0d", iteration), 1'b0, 1'b1, packet_value, pc_value, 1'b0, 1'b0, '0);
		end

		packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
		pc_value = program_counter_t'($urandom_range(7, 0) * 4);
		send_cycle("resume_enabled_branch", 1'b1, 1'b1, packet_value, pc_value, 1'b0, 1'b0, '0);

		`uvm_info(get_type_name(), "Completed continuous prefill, disabled hold, and enabled resume stimulus", UVM_LOW)
	endtask

endclass


/// enable branch valid sequence
class predictor_history_enable_valid_combinations_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_enable_valid_combinations_sequence)

	function new(string name = "predictor_history_enable_valid_combinations_sequence");
		super.new(name);
	endfunction
	
	virtual task body();
		int unsigned round_count;
		int unsigned combination;
		logic enable_value;
		logic valid_value;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		round_count = (FIFO_DEPTH < 12) ? FIFO_DEPTH : 12;

		`uvm_info(get_type_name(), "Starting enable and branch-valid combinations sequence", UVM_LOW)

		for (int unsigned round_index = 0; round_index < round_count; round_index++) begin
			for (int unsigned combination_index = 0; combination_index < 4; combination_index++) begin
				combination = (combination_index + round_index) % 4;
				enable_value = ((combination & 2) != 0);
				valid_value = ((combination & 1) != 0);

				packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
				pc_value = program_counter_t'($urandom_range(7, 0) * 4);

				send_cycle($sformatf("round_%0d_en_%0b_valid_%0b", round_index, enable_value, valid_value), enable_value, valid_value, packet_value, pc_value, 1'b0, 1'b0, '0);
			end
		end

		`uvm_info(get_type_name(), $sformatf("Completed %0d rounds of all four enable/valid combinations", round_count), UVM_LOW)
	endtask

endclass


//// FIFO Single write sequence
class predictor_history_fifo_single_write_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_single_write_sequence)

	function new(string name = "predictor_history_fifo_single_write_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 3) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 3")
		end

		`uvm_info(get_type_name(), "Starting FIFO three-write stimulus", UVM_LOW)

		idle_cycle("verify_initial_empty");

		branch_cycle(7'h11, 32'd4, "checkpoint_write_0");
		branch_cycle(7'h22, 32'd8, "checkpoint_write_1");
		branch_cycle(7'h35, 32'd12, "checkpoint_write_2");

		for (int unsigned iteration = 0; iteration < 5; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			send_cycle($sformatf("hold_checkpoints_%0d", iteration), 1'b1, 1'b0, packet_value, pc_value, 1'b0, 1'b0, '0);
		end
	endtask

endclass


//// FIFO single read sequence
class predictor_history_fifo_read_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_read_sequence)

	function new(string name = "predictor_history_fifo_read_sequence");
		super.new(name);
	endfunction

	virtual task body();
		if (FIFO_DEPTH < 5) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 5")
		end

		`uvm_info(get_type_name(), "Starting FIFO five-write and five-read stimulus", UVM_LOW)

		idle_cycle("verify_initial_empty");

		branch_cycle(7'h11, 32'd4, "checkpoint_write_0");
		branch_cycle(7'h22, 32'd8, "checkpoint_write_1");
		branch_cycle(7'h35, 32'd12, "checkpoint_write_2");
		branch_cycle(7'h4A, 32'd16, "checkpoint_write_3");
		branch_cycle(7'h63, 32'd20, "checkpoint_write_4");
		branch_cycle(7'h23, 32'd24, "checkpoint_write_5");
		branch_cycle(7'h67, 32'd29, "checkpoint_write_6");
		branch_cycle(7'h1B, 32'd30, "checkpoint_write_7");
		branch_cycle(7'h33, 32'd33, "checkpoint_write_8");
		branch_cycle(7'h71, 32'd40, "checkpoint_write_9");

		idle_cycle("hold_before_commits");

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("wait_before_commit_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 10; iteration++) begin
			send_cycle($sformatf("commit_and_misprediction_%0d", iteration), 1'b1, 1'b0, '0, program_counter_t'(24), 1'b1, 1'b1, misprediction_depth_t'(1));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("hold_after_drain_%0d", iteration));
		end

		`uvm_info(get_type_name(), "Completed FIFO five-write and five-read stimulus", UVM_LOW)
	endtask
endclass


//// fifo fillup to full capacity sequence
class predictor_history_fifo_fill_to_full_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_fill_to_full_sequence)

	function new(string name = "predictor_history_fifo_fill_to_full_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting FIFO fill-to-full sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < FIFO_DEPTH; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("fill_checkpoint_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 5; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			send_cycle($sformatf("hold_full_%0d", iteration), 1'b1, 1'b0, packet_value, pc_value, 1'b0, 1'b0, '0);
		end

		`uvm_info(get_type_name(), "Completed FIFO fill-to-full stimulus", UVM_LOW)
	endtask
endclass



/// FIFO write while full
class predictor_history_fifo_write_while_full_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_write_while_full_sequence)

	function new(string name = "predictor_history_fifo_write_while_full_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting FIFO write-while-full sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < FIFO_DEPTH; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("fill_checkpoint_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 5; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("blocked_writes_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("hold_after_blocked_writes_%0d", iteration));
		end

		`uvm_info(get_type_name(), "Completed FIFO write-while-full stimulus", UVM_LOW)
	endtask

endclass


/// FIFO drain to empty sequence
class predictor_history_fifo_drain_to_empty_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_drain_to_empty_sequence)

	function new(string name = "predictor_history_fifo_drain_to_empty_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		program_counter_t pc_value;
		int unsigned refill_count;

		`uvm_info(get_type_name(), "Starting FIFO drain-to-empty and then refill sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < FIFO_DEPTH; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("fill_checkpoint_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("hold_full_before_drain_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < FIFO_DEPTH; iteration++) begin
			branch_commit_cycle($sformatf("drain_checkpoint_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 5; iteration++) begin
			idle_cycle($sformatf("hold_empty_%0d", iteration));
		end

		refill_count = (FIFO_DEPTH < 4) ? FIFO_DEPTH : 4;

		for (int unsigned iteration = 0; iteration < refill_count; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("refill_checkpoint_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("hold_after_refill_%0d", iteration));
		end
		
		`uvm_info(get_type_name(), "Completed FIFO fill, drain-to-empty, and refill stimulus", UVM_LOW)
	endtask

endclass


/// fifo read while empty
class predictor_history_fifo_read_while_empty_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_read_while_empty_sequence)

	function new(string name = "predictor_history_fifo_read_while_empty_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned write_count;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		write_count = (FIFO_DEPTH < 4) ? FIFO_DEPTH : 4;

		`uvm_info(get_type_name(), "Starting FIFO read-while-empty sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < 5; iteration++) begin
			branch_commit_cycle($sformatf("read_request_while_empty_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("hold_after_empty_reads_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < write_count; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("write_after_empty_reads_%0d", iteration));
		end

		idle_cycle("hold_before_valid_reads");

		for (int unsigned iteration = 0; iteration < write_count; iteration++) begin
			branch_commit_cycle($sformatf("valid_read_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			branch_commit_cycle($sformatf("read_request_after_drain_%0d", iteration));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed FIFO read-while-empty stimulus", UVM_LOW)
	endtask

endclass



// simultaneous FIFO read and write with intermediate occupancy
class predictor_history_fifo_simultaneous_read_write_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_simultaneous_read_write_sequence)

	function new(string name = "predictor_history_fifo_simultaneous_read_write_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned prefill_count;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		// some stressing to the design
		int unsigned stress_cycles;

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2 for intermediate occupancy")
		end

		prefill_count = ((FIFO_DEPTH - 1) < 4) ? (FIFO_DEPTH - 1) : 4;

		`uvm_info(get_type_name(), "Starting simultaneous FIFO read and write sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < prefill_count; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("prefill_checkpoint_%0d", iteration));
		end

		idle_cycle("hold_before_simultaneous_requests");

		stress_cycles = 20 * FIFO_DEPTH;

		for (int unsigned iteration = 0; iteration < stress_cycles; iteration++) begin
			case (iteration % 6)
				0: packet_value = '0;
				1: packet_value = '1;
				2: packet_value = branch_packet_t'(7'h55);
				3: packet_value = branch_packet_t'(7'h2A);
				4: packet_value = branch_packet_t'(1) << ((iteration / 6) % PKT_WIDTH);
				5: packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
		endcase

			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_and_commit_cycle(packet_value, pc_value, $sformatf("stress_read_write_%0d", iteration));
		end	

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("hold_after_simultaneous_requests_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < prefill_count; iteration++) begin
			branch_commit_cycle($sformatf("drain_remaining_checkpoint_%0d", iteration));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed simultaneous FIFO read and write stimulus", UVM_LOW)
	endtask

endclass



/// random burst sequnce
class predictor_history_fifo_random_bursts_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_random_bursts_sequence)

	function new(string name = "predictor_history_fifo_random_bursts_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned write_burst_length;
		int unsigned read_burst_length;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 1) begin
			`uvm_fatal(get_type_name(), "FIFO_DEPTH must be positive")
		end

		`uvm_info(get_type_name(), "Starting FIFO random write/read bursts", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned round_index = 0; round_index < 20; round_index++) begin
			write_burst_length = $urandom_range(2 * FIFO_DEPTH, 1);
			read_burst_length = $urandom_range(2 * FIFO_DEPTH, 1);

			`uvm_info(get_type_name(), $sformatf("Round %0d: write_requests=%0d read_requests=%0d", round_index, write_burst_length, read_burst_length), UVM_LOW)

			for (int unsigned write_index = 0; write_index < write_burst_length; write_index++) begin
				packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
				pc_value = program_counter_t'($urandom_range(7, 0) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("round_%0d_write_%0d", round_index, write_index));
			end

			for (int unsigned read_index = 0; read_index < read_burst_length; read_index++) begin
				branch_commit_cycle($sformatf("round_%0d_read_%0d", round_index, read_index));
			end
		end

		// Enough read requests to empty the FIFO regardless of its remaining occupancy.
		for (int unsigned read_index = 0; read_index < FIFO_DEPTH; read_index++) begin
			branch_commit_cycle($sformatf("final_drain_%0d", read_index));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed FIFO random write/read bursts", UVM_LOW)
	endtask

endclass



/// simultaenous read write when the FIFO is full
class predictor_history_fifo_full_read_write_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_full_read_write_sequence)

	function new(string name = "predictor_history_fifo_full_read_write_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 1) begin
			`uvm_fatal(get_type_name(), "FIFO_DEPTH must be positive")
		end

		`uvm_info(get_type_name(), "Starting simultaneous read/write while full", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < FIFO_DEPTH; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("fill_checkpoint_%0d", iteration));
		end

		idle_cycle("hold_full_before_replacement");

		for (int unsigned iteration = 0; iteration < (4 * FIFO_DEPTH); iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_and_commit_cycle(packet_value, pc_value, $sformatf("full_read_write_%0d", iteration));
		end

		// Remove one entry, then refill that slot to check full deassertion and assertion.
		branch_commit_cycle("read_one_from_full");
		idle_cycle("hold_one_free_slot");

		packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
		pc_value = program_counter_t'($urandom_range(7, 0) * 4);
		branch_cycle(packet_value, pc_value, "refill_one_free_slot");

		idle_cycle("hold_full_after_refill");

		for (int unsigned iteration = 0; iteration < FIFO_DEPTH; iteration++) begin
			branch_commit_cycle($sformatf("final_drain_%0d", iteration));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed simultaneous read/write while full stimulus", UVM_LOW)
	endtask

endclass


/// simultaneous read write when FIFO is empty
class predictor_history_fifo_empty_read_write_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_empty_read_write_sequence)

	function new(string name = "predictor_history_fifo_empty_read_write_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 1) begin
			`uvm_fatal(get_type_name(), "FIFO_DEPTH must be positive")
		end

		`uvm_info(get_type_name(), "Starting simultaneous read/write while empty", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < (4 * FIFO_DEPTH); iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);

			branch_and_commit_cycle(packet_value, pc_value, $sformatf("empty_read_write_%0d", iteration));
			branch_commit_cycle($sformatf("drain_single_entry_%0d", iteration));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed simultaneous read/write while empty stimulus", UVM_LOW)
	endtask

endclass



/// FIFO Wraparound pointer
class predictor_history_fifo_pointer_wraparound_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_pointer_wraparound_sequence)

	function new(string name = "predictor_history_fifo_pointer_wraparound_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned prefill_count;
		int unsigned wrap_iterations;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 3) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 3")
		end

		prefill_count = FIFO_DEPTH / 2;
		wrap_iterations = 4 * FIFO_DEPTH;

		`uvm_info(get_type_name(), "Starting FIFO pointer-wraparound sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned iteration = 0; iteration < prefill_count; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("prefill_checkpoint_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < wrap_iterations; iteration++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);

			branch_cycle(packet_value, pc_value, $sformatf("wrap_write_%0d", iteration));
			branch_commit_cycle($sformatf("wrap_read_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < prefill_count; iteration++) begin
			branch_commit_cycle($sformatf("final_drain_%0d", iteration));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed FIFO pointer-wraparound stimulus", UVM_LOW)
	endtask

endclass



/// repeated FIFO fill and drain sequence
class predictor_history_fifo_repeated_fill_drain_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_fifo_repeated_fill_drain_sequence)

	function new(string name = "predictor_history_fifo_repeated_fill_drain_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 1) begin
			`uvm_fatal(get_type_name(), "FIFO_DEPTH must be positive")
		end

		`uvm_info(get_type_name(), "Starting repeated FIFO fill and drain sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned round_index = 0; round_index < 10; round_index++) begin
			`uvm_info(get_type_name(), $sformatf("Starting fill/drain round %0d", round_index), UVM_LOW)

			for (int unsigned write_index = 0; write_index < FIFO_DEPTH; write_index++) begin
				packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
				pc_value = program_counter_t'($urandom_range(7, 0) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("round_%0d_write_%0d", round_index, write_index));
			end

			for (int unsigned hold_index = 0; hold_index < 3; hold_index++) begin
				idle_cycle($sformatf("round_%0d_hold_full_%0d", round_index, hold_index));
			end

			for (int unsigned read_index = 0; read_index < FIFO_DEPTH; read_index++) begin
				branch_commit_cycle($sformatf("round_%0d_read_%0d", round_index, read_index));
			end

			for (int unsigned hold_index = 0; hold_index < 3; hold_index++) begin
				idle_cycle($sformatf("round_%0d_hold_empty_%0d", round_index, hold_index));
			end
		end

		`uvm_info(get_type_name(), "Completed ten FIFO fill and drain rounds", UVM_LOW)
	endtask

endclass



/////checkpoint data ordering
class predictor_history_checkpoint_data_ordering_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_checkpoint_data_ordering_sequence)

	function new(string name = "predictor_history_checkpoint_data_ordering_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned checkpoint_count;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		checkpoint_count = (FIFO_DEPTH < 8) ? FIFO_DEPTH : 8;

		`uvm_info(get_type_name(), "Starting checkpoint-data ordering sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned write_index = 0; write_index < checkpoint_count; write_index++) begin
			packet_value = branch_packet_t'(7'h11 + (write_index * 7));
			pc_value = program_counter_t'((write_index % 8) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("ordered_checkpoint_write_%0d", write_index));
		end

		idle_cycle("hold_before_ordered_reads");

		for (int unsigned read_index = 0; read_index < checkpoint_count; read_index++) begin
			misprediction_cycle(misprediction_depth_t'(1), program_counter_t'(24), $sformatf("ordered_checkpoint_read_%0d", read_index));
			recovery_cycle(program_counter_t'(24), $sformatf("apply_checkpoint_%0d", read_index));
			idle_cycle($sformatf("settle_after_checkpoint_%0d", read_index));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed checkpoint-data ordering stimulus", UVM_LOW)
	endtask

endclass



//// GHR Packets pattern
class predictor_history_ghr_packet_patterns_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_ghr_packet_patterns_sequence)

	function new(string name = "predictor_history_ghr_packet_patterns_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t alternating_packet;
		branch_packet_t packet_value;
		int unsigned pattern_cycles;

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		alternating_packet = '0;

		for (int unsigned bit_index = 0; bit_index < PKT_WIDTH; bit_index++) begin
			alternating_packet[bit_index] = ((bit_index % 2) == 0);
		end

		pattern_cycles = GHR_MAX_PTR + 2;

		`uvm_info(get_type_name(), "Starting GHR packet-pattern sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");
		branch_cycle(branch_packet_t'('0), program_counter_t'(4), "initial_checkpoint");

		for (int unsigned pattern_index = 0; pattern_index < 6; pattern_index++) begin
			for (int unsigned iteration = 0; iteration < pattern_cycles; iteration++) begin
				case (pattern_index)
					0: packet_value = '0;
					1: packet_value = '1;
					2: packet_value = alternating_packet;
					3: packet_value = ~alternating_packet;
					4: packet_value = branch_packet_t'(1) << (iteration % PKT_WIDTH);
					5: packet_value = branch_packet_t'(7'h35);
					default: packet_value = '0;
				endcase

				branch_and_commit_cycle(packet_value, program_counter_t'(4), $sformatf("pattern_%0d_branch_%0d", pattern_index, iteration));
			end
		end

		branch_commit_cycle("drain_final_checkpoint");

		repeat (3) begin
			idle_cycle("final_hold");
		end

		`uvm_info(get_type_name(), "Completed GHR packet-pattern stimulus", UVM_LOW)
	endtask

endclass



/// predctor history depth 2 transition
class predictor_history_depth2_transition_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_transition_sequence)

	function new(string name = "predictor_history_depth2_transition_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		int unsigned branch_number;

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH == 2")
		end

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		branch_number = 1;

		`uvm_info(get_type_name(), "Starting depth-2 history transition sequence", UVM_LOW)

		idle_cycle("initial_idle");

		branch_cycle(branch_packet_t'(branch_number), program_counter_t'(4), "initial_depth2_branch");
		branch_number++;

		for (int unsigned round_index = 0; round_index < 4; round_index++) begin
			for (int unsigned branch_index = 0; branch_index < 5; branch_index++) begin
				packet_value = branch_packet_t'(branch_number);
				branch_and_commit_cycle(packet_value, program_counter_t'(4), $sformatf("depth2_round_%0d_branch_%0d", round_index, branch_index));
				branch_number++;
			end

			for (int unsigned gap_index = 0; gap_index < 3; gap_index++) begin
				packet_value = branch_packet_t'(7'h70 + gap_index);
				send_cycle($sformatf("depth2_round_%0d_invalid_%0d", round_index, gap_index), 1'b1, 1'b0, packet_value, program_counter_t'(4), 1'b0, 1'b0, '0);
			end
		end

		branch_commit_cycle("drain_final_checkpoint");

		repeat (3) begin
			idle_cycle("final_hold");
		end

		`uvm_info(get_type_name(), "Completed depth-2 history transition stimulus", UVM_LOW)
	endtask

endclass



////GHR bank/row transitions for the depth-2
class predictor_history_depth2_bank_row_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_bank_row_sequence)

	function new(string name = "predictor_history_depth2_bank_row_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned total_branches;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH == 2")
		end

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		total_branches = GHR_MAX_PTR + NUM_GHR_BANKS + 2;

		`uvm_info(get_type_name(), "Starting depth-2 GHR bank and row transition sequence", UVM_LOW)

		idle_cycle("initial_idle");

		for (int unsigned branch_index = 0; branch_index < total_branches; branch_index++) begin
			packet_value = branch_packet_t'(branch_index + 1);
			pc_value = program_counter_t'((branch_index % 8) * 4);

			if (branch_index == 0) begin
				branch_cycle(packet_value, pc_value, "initial_checkpoint");
			end else begin
				branch_and_commit_cycle(packet_value, pc_value, $sformatf("bank_row_branch_%0d", branch_index));
			end

			if (((branch_index + 1) % NUM_GHR_BANKS) == 0) begin
				idle_cycle($sformatf("row_boundary_hold_%0d", branch_index));
			end
		end

		branch_commit_cycle("drain_final_checkpoint");

		repeat (3) begin
			idle_cycle("final_hold");
		end

		`uvm_info(get_type_name(), "Completed depth-2 GHR bank and row transition stimulus", UVM_LOW)
	endtask

endclass



/// ghr circular wrap around
class predictor_history_depth2_wraparound_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_wraparound_sequence)

	function new(string name = "predictor_history_depth2_wraparound_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned total_branches;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH == 2")
		end

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		total_branches = (4 * GHR_MAX_PTR) + 2;

		`uvm_info(get_type_name(), "Starting repeated depth-2 GHR wraparound sequence", UVM_LOW)

		idle_cycle("initial_idle");

		for (int unsigned branch_index = 0; branch_index < total_branches; branch_index++) begin
			packet_value = branch_packet_t'($urandom_range((1 << PKT_WIDTH) - 1, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);

			if (branch_index == 0) begin
				branch_cycle(packet_value, pc_value, "initial_checkpoint");
			end else begin
				branch_and_commit_cycle(packet_value, pc_value, $sformatf("wraparound_branch_%0d", branch_index));
			end

			if (((branch_index + 1) % GHR_MAX_PTR) == 0) begin
				`uvm_info(get_type_name(), $sformatf("Issued %0d branches; GHR wrap number %0d will complete when the latest transaction is consumed", branch_index + 1, (branch_index + 1) / GHR_MAX_PTR), UVM_LOW)
			end
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("hold_after_wraparound_%0d", iteration));
		end

		branch_commit_cycle("drain_final_checkpoint");

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed repeated depth-2 GHR wraparound stimulus", UVM_LOW)
	endtask

endclass



// depth 2 hash fold arithematic check the XOR beingcalculated well.
class predictor_history_depth2_fold_arithmetic_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_fold_arithmetic_sequence)

	function new(string name = "predictor_history_depth2_fold_arithmetic_sequence");
		super.new(name);
	endfunction

	virtual task body();
		branch_packet_t packet_value;
		branch_packet_t alternating_packet;

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH == 2")
		end

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		alternating_packet = '0;

		for (int unsigned bit_index = 0; bit_index < PKT_WIDTH; bit_index++) begin
			alternating_packet[bit_index] = ((bit_index % 2) == 0);
		end

		`uvm_info(get_type_name(), "Starting depth-2 fold arithmetic sequence", UVM_LOW)

		idle_cycle("initial_idle");
		branch_cycle(branch_packet_t'('0), program_counter_t'(4), "initial_zero_checkpoint");

		// Introduce one packet bit at a time, followed by zeros.
		for (int unsigned bit_index = 0; bit_index < PKT_WIDTH; bit_index++) begin
			packet_value = branch_packet_t'(1) << bit_index;
			branch_and_commit_cycle(packet_value, program_counter_t'(4), $sformatf("walking_one_bit_%0d", bit_index));

			for (int unsigned zero_index = 0; zero_index < 4; zero_index++) begin
				branch_and_commit_cycle(branch_packet_t'('0), program_counter_t'(4), $sformatf("bit_%0d_zero_%0d", bit_index, zero_index));
			end
		end

		// Exercise multiple set bits and complementary packets.
		for (int unsigned iteration = 0; iteration < (2 * FOLD_WIDTH); iteration++) begin
			case (iteration % 4)
				0: packet_value = '1;
				1: packet_value = '0;
				2: packet_value = alternating_packet;
				3: packet_value = ~alternating_packet;
				default: packet_value = '0;
			endcase

			branch_and_commit_cycle(packet_value, program_counter_t'(4), $sformatf("xor_pattern_%0d", iteration));
		end

		// Continue valid updates with zero input to observe history eviction.
		for (int unsigned iteration = 0; iteration < (FOLD_WIDTH + SELECTED_HISTORY_DEPTH); iteration++) begin
			branch_and_commit_cycle(branch_packet_t'('0), program_counter_t'(4), $sformatf("zero_tail_%0d", iteration));
		end

		for (int unsigned iteration = 0; iteration < 3; iteration++) begin
			idle_cycle($sformatf("fold_hold_%0d", iteration));
		end

		branch_commit_cycle("drain_final_checkpoint");

		repeat (3) begin
			idle_cycle("final_hold");
		end

		`uvm_info(get_type_name(), "Completed depth-2 fold arithmetic stimulus", UVM_LOW)
	endtask

endclass



// PC  mixing with depth 2 hash.
class predictor_history_depth2_pc_mixing_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_pc_mixing_sequence)

	function new(string name = "predictor_history_depth2_pc_mixing_sequence");
		super.new(name);
	endfunction

	virtual task body();

		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting depth-2 PC-mixing sequence with zero history", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence is intended for SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		// Start from cleared GHR, folded history and FIFO.
		reset_cycle("pc_mixing_reset");
		idle_cycle("pc_mixing_post_reset_idle");

		// Establish one FIFO entry before simultaneous reads and writes.
		branch_cycle(branch_packet_t'('0), program_counter_t'(0), "pc_mixing_initial_branch");

		// Three complete sweeps through aligned PCs: 0, 4, 8, ... 28.
		for (int unsigned sweep = 0; sweep < 3; sweep++) begin
			for (int unsigned pc_index = 0; pc_index < 8; pc_index++) begin
				pc_value = program_counter_t'(pc_index * 4);
				branch_and_commit_cycle(branch_packet_t'('0), pc_value, $sformatf("pc_aligned_sweep_%0d_pc_%0d", sweep, pc_value));
			end
		end

		// Exercise the two discarded PC bits: each group must give identical hashes.
		for (int unsigned word_index = 0; word_index < 7; word_index++) begin
			for (int unsigned low_bits = 0; low_bits < 4; low_bits++) begin
				pc_value = program_counter_t'((word_index * 4) + low_bits);
				branch_and_commit_cycle(branch_packet_t'('0), pc_value, $sformatf("pc_low_bits_word_%0d_offset_%0d", word_index, low_bits));
			end
		end

		// Random aligned PC transitions, still below 30.
		for (int unsigned iteration = 0; iteration < 15; iteration++) begin
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_and_commit_cycle(branch_packet_t'('0), pc_value, $sformatf("pc_random_%0d_pc_%0d", iteration, pc_value));
		end

		branch_commit_cycle("pc_mixing_final_drain");
		repeat (3) idle_cycle("pc_mixing_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 PC-mixing sequence", UVM_LOW)

	endtask

endclass



/// DEPTH 2 MISPREDICTION AND RECOVERY SEQUENCE
class predictor_history_depth2_basic_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_basic_recovery_sequence)

	function new(string name = "predictor_history_depth2_basic_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		`uvm_info(get_type_name(), "Starting depth-2 basic misprediction and recovery sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 8) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 8")
		end

		reset_cycle("basic_recovery_reset");

		// Global enable is low: unknown payload inputs must not affect stored state.
		repeat (3) begin
			send_cycle("startup_x_inputs_disabled", 1'b0, 1'b0, branch_packet_t'('x), program_counter_t'('x), 1'b0, 1'b0, misprediction_depth_t'('x));
		end

		// Global enable is high but no operation is valid: unknown payload inputs remain inactive.
		repeat (3) begin
			send_cycle("startup_x_inputs_invalid", 1'b1, 1'b0, branch_packet_t'('x), program_counter_t'('x), 1'b0, 1'b0, misprediction_depth_t'('x));
		end

		// Return to known inputs without another reset, so any corruption remains visible.
		idle_cycle("startup_x_inputs_clear_0");
		idle_cycle("startup_x_inputs_clear_1");

		// Populate six checkpoints without reads.
		branch_cycle(branch_packet_t'(7'h11), program_counter_t'(4), "recovery_prefill_0");
		branch_cycle(branch_packet_t'(7'h22), program_counter_t'(8), "recovery_prefill_1");
		branch_cycle(branch_packet_t'(7'h35), program_counter_t'(12), "recovery_prefill_2");
		branch_cycle(branch_packet_t'(7'h4A), program_counter_t'(16), "recovery_prefill_3");
		branch_cycle(branch_packet_t'(7'h57), program_counter_t'(20), "recovery_prefill_4");
		branch_cycle(branch_packet_t'(7'h63), program_counter_t'(24), "recovery_prefill_5");

		// Retire the first two checkpoints, which can contain startup zeros.
		branch_commit_cycle("retire_checkpoint_0");
		branch_commit_cycle("retire_checkpoint_1");

		idle_cycle("before_misprediction");

		// Read the oldest remaining checkpoint and expose it for recovery.
		misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), "depth2_misprediction");

		// Allow the hash register to capture the recovered folded history.
		recovery_cycle(program_counter_t'(24), "apply_depth2_recovery");
		idle_cycle("after_recovery_hold_0");
		idle_cycle("after_recovery_hold_1");

		// Confirm that new branch updates resume after recovery.
		branch_cycle(branch_packet_t'(7'h19), program_counter_t'(4), "post_recovery_branch_0");
		branch_cycle(branch_packet_t'(7'h2D), program_counter_t'(8), "post_recovery_branch_1");
		branch_cycle(branch_packet_t'(7'h46), program_counter_t'(12), "post_recovery_branch_2");
		branch_cycle(branch_packet_t'(7'h6B), program_counter_t'(16), "post_recovery_branch_3");

		// Current FIFO behavior pops one checkpoint on misprediction; it does not flush the others.
		// Six writes - two commits - one recovery read + four writes = seven entries.
		for (int unsigned read_index = 0; read_index < 7; read_index++) begin
			branch_commit_cycle($sformatf("post_recovery_drain_%0d", read_index));
		end

		repeat (3) idle_cycle("basic_recovery_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 basic misprediction and recovery sequence", UVM_LOW)

	endtask

endclass



//// misprediction at depth when FIFO empty
class predictor_history_depth2_empty_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_empty_recovery_sequence)

	function new(string name = "predictor_history_depth2_empty_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		`uvm_info(get_type_name(), "Starting depth-2 misprediction-on-empty sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 4) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 4")
		end

		reset_cycle("empty_recovery_reset");
		idle_cycle("empty_recovery_post_reset_idle");

		// Request recovery while the FIFO has never contained any checkpoints.
		misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), "empty_recovery_after_reset");
		recovery_cycle(program_counter_t'(24), "empty_recovery_after_reset_settle");
		idle_cycle("empty_recovery_after_reset_hold");

		// Populate the FIFO with four checkpoints.
		branch_cycle(branch_packet_t'(7'h11), program_counter_t'(4), "empty_recovery_prefill_0");
		branch_cycle(branch_packet_t'(7'h2B), program_counter_t'(8), "empty_recovery_prefill_1");
		branch_cycle(branch_packet_t'(7'h46), program_counter_t'(12), "empty_recovery_prefill_2");
		branch_cycle(branch_packet_t'(7'h65), program_counter_t'(16), "empty_recovery_prefill_3");

		// Drain all four entries using normal commits.
		for (int unsigned read_index = 0; read_index < 4; read_index++) begin
			branch_commit_cycle($sformatf("empty_recovery_drain_%0d", read_index));
		end

		idle_cycle("empty_recovery_confirm_empty");

		// Repeat recovery requests while empty, with a settling cycle between requests.
		for (int unsigned attempt = 0; attempt < 3; attempt++) begin
			misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), $sformatf("empty_recovery_attempt_%0d", attempt));
			recovery_cycle(program_counter_t'(24), $sformatf("empty_recovery_settle_%0d", attempt));
		end

		// Confirm that empty recovery requests did not prevent subsequent writes.
		branch_cycle(branch_packet_t'(7'h19), program_counter_t'(4), "empty_recovery_resume_0");
		branch_cycle(branch_packet_t'(7'h37), program_counter_t'(8), "empty_recovery_resume_1");
		branch_cycle(branch_packet_t'(7'h52), program_counter_t'(12), "empty_recovery_resume_2");
		branch_cycle(branch_packet_t'(7'h6C), program_counter_t'(16), "empty_recovery_resume_3");

		for (int unsigned read_index = 0; read_index < 4; read_index++) begin
			branch_commit_cycle($sformatf("empty_recovery_final_drain_%0d", read_index));
		end

		repeat (3) idle_cycle("empty_recovery_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 misprediction-on-empty sequence", UVM_LOW)

	endtask

endclass



/// misprediction while the FIFO is full
class predictor_history_depth2_full_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_full_recovery_sequence)

	function new(string name = "predictor_history_depth2_full_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting depth-2 misprediction-on-full sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 4) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 4")
		end

		reset_cycle("full_recovery_reset");
		idle_cycle("full_recovery_post_reset_idle");

		// Generate and retire startup checkpoints before filling the FIFO.
		for (int unsigned warmup_index = 0; warmup_index < 4; warmup_index++) begin
			packet_value = branch_packet_t'(7'h11 + (warmup_index * 7));
			pc_value = program_counter_t'((warmup_index + 1) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("full_recovery_warmup_write_%0d", warmup_index));
		end

		for (int unsigned read_index = 0; read_index < 4; read_index++) begin
			branch_commit_cycle($sformatf("full_recovery_warmup_drain_%0d", read_index));
		end

		// Fill every FIFO entry without requesting reads.
		for (int unsigned write_index = 0; write_index < FIFO_DEPTH; write_index++) begin
			packet_value = branch_packet_t'($urandom_range(127, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("full_recovery_fill_%0d", write_index));
		end

		idle_cycle("full_recovery_confirm_full");

		// Pop the oldest checkpoint while full.
		misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), "full_recovery_misprediction");

		// Capture the checkpoint into the hash folded-history register.
		recovery_cycle(program_counter_t'(24), "full_recovery_apply");
		idle_cycle("full_recovery_hold");

		// Reuse the single slot released by the recovery read.
		branch_cycle(branch_packet_t'(7'h59), program_counter_t'(12), "full_recovery_refill_freed_slot");
		idle_cycle("full_recovery_confirm_full_again");

		// Drain all entries, including the newly written checkpoint.
		for (int unsigned read_index = 0; read_index < FIFO_DEPTH; read_index++) begin
			branch_commit_cycle($sformatf("full_recovery_final_drain_%0d", read_index));
		end

		repeat (3) idle_cycle("full_recovery_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 misprediction-on-full sequence", UVM_LOW)

	endtask

endclass



// valid branch during recovery
class predictor_history_depth2_branch_during_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_branch_during_recovery_sequence)

	function new(string name = "predictor_history_depth2_branch_during_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		`uvm_info(get_type_name(), "Starting depth-2 branch-during-recovery sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 8) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 8")
		end

		reset_cycle("branch_during_recovery_reset");
		idle_cycle("branch_during_recovery_post_reset_idle");

		// Generate six checkpoints.
		branch_cycle(branch_packet_t'(7'h11), program_counter_t'(4), "overlap_prefill_0");
		branch_cycle(branch_packet_t'(7'h22), program_counter_t'(8), "overlap_prefill_1");
		branch_cycle(branch_packet_t'(7'h35), program_counter_t'(12), "overlap_prefill_2");
		branch_cycle(branch_packet_t'(7'h4A), program_counter_t'(16), "overlap_prefill_3");
		branch_cycle(branch_packet_t'(7'h57), program_counter_t'(20), "overlap_prefill_4");
		branch_cycle(branch_packet_t'(7'h63), program_counter_t'(24), "overlap_prefill_5");

		// Retire two startup checkpoints.
		branch_commit_cycle("overlap_retire_0");
		branch_commit_cycle("overlap_retire_1");
		idle_cycle("overlap_before_misprediction");

		// This edge generates the registered recovery-valid indication.
		misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), "overlap_misprediction");

		// Present a branch on the immediately following recovery-application edge.
		send_cycle("branch_while_recovery_active", 1'b1, 1'b1, branch_packet_t'(7'h7E), program_counter_t'(28), 1'b0, 1'b0, misprediction_depth_t'(0));

		// Observe the recovered state before submitting another branch.
		idle_cycle("overlap_recovery_hold_0");
		idle_cycle("overlap_recovery_hold_1");

		// Normal branch processing must resume after recovery.
		branch_cycle(branch_packet_t'(7'h19), program_counter_t'(4), "overlap_resume_0");
		branch_cycle(branch_packet_t'(7'h2D), program_counter_t'(8), "overlap_resume_1");
		branch_cycle(branch_packet_t'(7'h46), program_counter_t'(12), "overlap_resume_2");

		repeat (3) idle_cycle("overlap_final_hold");

		`uvm_info(get_type_name(), "Completed depth-2 branch-during-recovery sequence", UVM_LOW)

	endtask

endclass



//// global enable low during recovery
class predictor_history_depth2_disabled_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_disabled_recovery_sequence)

	function new(string name = "predictor_history_depth2_disabled_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		`uvm_info(get_type_name(), "Starting depth-2 global-disable-during-recovery sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 8) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 8")
		end

		reset_cycle("disabled_recovery_reset");
		idle_cycle("disabled_recovery_post_reset_idle");

		branch_cycle(branch_packet_t'(7'h11), program_counter_t'(4), "disabled_recovery_prefill_0");
		branch_cycle(branch_packet_t'(7'h22), program_counter_t'(8), "disabled_recovery_prefill_1");
		branch_cycle(branch_packet_t'(7'h35), program_counter_t'(12), "disabled_recovery_prefill_2");
		branch_cycle(branch_packet_t'(7'h4A), program_counter_t'(16), "disabled_recovery_prefill_3");
		branch_cycle(branch_packet_t'(7'h57), program_counter_t'(20), "disabled_recovery_prefill_4");
		branch_cycle(branch_packet_t'(7'h63), program_counter_t'(24), "disabled_recovery_prefill_5");

		// Remove two startup checkpoints.
		branch_commit_cycle("disabled_recovery_retire_0");
		branch_commit_cycle("disabled_recovery_retire_1");
		idle_cycle("disabled_recovery_before_misprediction");

		// Produce a valid recovery checkpoint with global enable high.
		misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), "disabled_recovery_misprediction");

		// Disable the block on the immediately following recovery-application edge.
		for (int unsigned disabled_index = 0; disabled_index < 3; disabled_index++) begin
			send_cycle($sformatf("disabled_recovery_hold_%0d", disabled_index), 1'b0, 1'b0, branch_packet_t'(0), program_counter_t'(24), 1'b0, 1'b0, misprediction_depth_t'(0));
		end

		// Re-enable without a branch to observe whether recovery was retained.
		recovery_cycle(program_counter_t'(24), "disabled_recovery_reenable");
		idle_cycle("disabled_recovery_observe_0");
		idle_cycle("disabled_recovery_observe_1");

		`uvm_info(get_type_name(), "Completed depth-2 global-disable-during-recovery sequence", UVM_LOW)

	endtask

endclass



//commit and misprediction asserted together
class predictor_history_depth2_commit_misprediction_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_commit_misprediction_sequence)

	function new(string name = "predictor_history_depth2_commit_misprediction_sequence");
		super.new(name);
	endfunction

	virtual task body();

		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting depth-2 simultaneous commit and misprediction sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 8) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 8")
		end

		reset_cycle("commit_misprediction_reset");
		idle_cycle("commit_misprediction_post_reset_idle");

		// Populate eight checkpoints without reads.
		for (int unsigned write_index = 0; write_index < 8; write_index++) begin
			packet_value = branch_packet_t'(7'h11 + (write_index * 9));
			pc_value = program_counter_t'((write_index % 8) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("commit_misprediction_prefill_%0d", write_index));
		end

		// Retire two startup checkpoints using ordinary commits.
		branch_commit_cycle("commit_misprediction_retire_0");
		branch_commit_cycle("commit_misprediction_retire_1");
		idle_cycle("commit_misprediction_before_overlap");

		// Each overlap must pop exactly one checkpoint and generate recovery.
		for (int unsigned attempt = 0; attempt < 3; attempt++) begin
			send_cycle($sformatf("commit_misprediction_overlap_%0d", attempt), 1'b1, 1'b0, branch_packet_t'(0), program_counter_t'(24), 1'b1, 1'b1, misprediction_depth_t'(2));
			recovery_cycle(program_counter_t'(24), $sformatf("commit_misprediction_apply_%0d", attempt));
			idle_cycle($sformatf("commit_misprediction_hold_%0d", attempt));
		end

		// Eight writes - two ordinary reads - three overlap reads = three entries.
		for (int unsigned read_index = 0; read_index < 3; read_index++) begin
			branch_commit_cycle($sformatf("commit_misprediction_final_drain_%0d", read_index));
		end

		repeat (3) idle_cycle("commit_misprediction_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 simultaneous commit and misprediction sequence", UVM_LOW)

	endtask

endclass



/// valid branch and misprediction asserted on the same cycle.
class predictor_history_depth2_branch_misprediction_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_branch_misprediction_sequence)

	function new(string name = "predictor_history_depth2_branch_misprediction_sequence");
		super.new(name);
	endfunction

	virtual task body();

		`uvm_info(get_type_name(), "Starting depth-2 simultaneous branch and misprediction sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 8) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 8")
		end

		reset_cycle("branch_misprediction_reset");
		idle_cycle("branch_misprediction_post_reset_idle");

		branch_cycle(branch_packet_t'(7'h11), program_counter_t'(4), "branch_misprediction_prefill_0");
		branch_cycle(branch_packet_t'(7'h22), program_counter_t'(8), "branch_misprediction_prefill_1");
		branch_cycle(branch_packet_t'(7'h35), program_counter_t'(12), "branch_misprediction_prefill_2");
		branch_cycle(branch_packet_t'(7'h4A), program_counter_t'(16), "branch_misprediction_prefill_3");
		branch_cycle(branch_packet_t'(7'h57), program_counter_t'(20), "branch_misprediction_prefill_4");
		branch_cycle(branch_packet_t'(7'h63), program_counter_t'(24), "branch_misprediction_prefill_5");

		// Retire two startup checkpoints, leaving four entries.
		branch_commit_cycle("branch_misprediction_retire_0");
		branch_commit_cycle("branch_misprediction_retire_1");
		idle_cycle("branch_misprediction_before_overlap");

		// Request a branch write and a misprediction read on the same edge.
		for (int unsigned overlap_index = 0; overlap_index < 4; overlap_index++) begin
			send_cycle($sformatf("branch_misprediction_overlap_%0d", overlap_index), 1'b1, 1'b1, branch_packet_t'(7'h31 + (overlap_index * 13)), program_counter_t'((overlap_index + 1) * 4), 1'b0, 1'b1, misprediction_depth_t'(2));
		end

		// Apply the checkpoint produced by the preceding FIFO read.
		recovery_cycle(program_counter_t'(24), "branch_misprediction_apply_recovery");
		idle_cycle("branch_misprediction_recovery_hold_0");
		idle_cycle("branch_misprediction_recovery_hold_1");

		// Verify that normal branch processing resumes.
		branch_cycle(branch_packet_t'(7'h19), program_counter_t'(4), "branch_misprediction_resume_0");
		branch_cycle(branch_packet_t'(7'h2D), program_counter_t'(8), "branch_misprediction_resume_1");
		branch_cycle(branch_packet_t'(7'h46), program_counter_t'(12), "branch_misprediction_resume_2");

		// Four entries before overlap + simultaneous read/write + three writes = seven.
		for (int unsigned read_index = 0; read_index < 7; read_index++) begin
			branch_commit_cycle($sformatf("branch_misprediction_final_drain_%0d", read_index));
		end

		repeat (3) idle_cycle("branch_misprediction_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 simultaneous branch and misprediction sequence", UVM_LOW)

	endtask

endclass



/// back 2 back mispredictions with no branch writes\
class predictor_history_depth2_back_to_back_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_back_to_back_recovery_sequence)

	function new(string name = "predictor_history_depth2_back_to_back_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting depth-2 back-to-back recovery sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 8) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 8")
		end

		reset_cycle("back_to_back_recovery_reset");
		idle_cycle("back_to_back_recovery_post_reset_idle");

		// Populate eight checkpoints.
		for (int unsigned write_index = 0; write_index < 8; write_index++) begin
			packet_value = branch_packet_t'(7'h11 + (write_index * 9));
			pc_value = program_counter_t'((write_index % 8) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("back_to_back_recovery_prefill_%0d", write_index));
		end

		// Remove two startup checkpoints, leaving six entries.
		branch_commit_cycle("back_to_back_recovery_retire_0");
		branch_commit_cycle("back_to_back_recovery_retire_1");
		idle_cycle("back_to_back_recovery_before_requests");

		// Four consecutive recovery reads, with no writes or settling gaps.
		for (int unsigned request_index = 0; request_index < 4; request_index++) begin
			misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), $sformatf("back_to_back_recovery_request_%0d", request_index));
		end

		// Capture the checkpoint produced by the final recovery read.
		recovery_cycle(program_counter_t'(24), "back_to_back_recovery_apply_last");

		repeat (3) idle_cycle("back_to_back_recovery_hold");

		// Two checkpoints remain after the four recovery reads.
		for (int unsigned read_index = 0; read_index < 2; read_index++) begin
			branch_commit_cycle($sformatf("back_to_back_recovery_final_drain_%0d", read_index));
		end

		repeat (3) idle_cycle("back_to_back_recovery_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 back-to-back recovery sequence", UVM_LOW)

	endtask

endclass



//// repeated recovery followed by new branches
class predictor_history_depth2_recovery_resume_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_recovery_resume_sequence)

	function new(string name = "predictor_history_depth2_recovery_resume_sequence");
		super.new(name);
	endfunction

	virtual task body();

		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting depth-2 repeated recovery and branch-resumption sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 6) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 6")
		end

		reset_cycle("recovery_resume_reset");
		idle_cycle("recovery_resume_post_reset_idle");

		// Generate and retire startup checkpoints before the repeated test rounds.
		for (int unsigned warmup_index = 0; warmup_index < 4; warmup_index++) begin
			packet_value = branch_packet_t'(7'h11 + (warmup_index * 9));
			pc_value = program_counter_t'((warmup_index + 1) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("recovery_resume_warmup_%0d", warmup_index));
		end

		for (int unsigned read_index = 0; read_index < 4; read_index++) begin
			branch_commit_cycle($sformatf("recovery_resume_warmup_drain_%0d", read_index));
		end

		for (int unsigned round_index = 0; round_index < 3; round_index++) begin

			// Begin each round with an empty FIFO and fill four checkpoints.
			for (int unsigned write_index = 0; write_index < 4; write_index++) begin
				packet_value = branch_packet_t'(7'h15 + (round_index * 11) + (write_index * 7));
				pc_value = program_counter_t'((write_index + 1) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("recovery_resume_round_%0d_prefill_%0d", round_index, write_index));
			end

			// Two consecutive reads expose two successive recovery checkpoints.
			for (int unsigned request_index = 0; request_index < 2; request_index++) begin
				misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), $sformatf("recovery_resume_round_%0d_request_%0d", round_index, request_index));
			end

			// Capture the second checkpoint before restarting normal branches.
			recovery_cycle(program_counter_t'(24), $sformatf("recovery_resume_round_%0d_apply_last", round_index));

			// No idle gap: resume branch processing on the next cycle.
			for (int unsigned branch_index = 0; branch_index < 4; branch_index++) begin
				packet_value = branch_packet_t'(7'h41 + (round_index * 5) + (branch_index * 9));
				pc_value = program_counter_t'((branch_index + 1) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("recovery_resume_round_%0d_new_branch_%0d", round_index, branch_index));
			end

			idle_cycle($sformatf("recovery_resume_round_%0d_hold", round_index));

			// Four initial writes - two recovery reads + four resume writes = six entries.
			for (int unsigned read_index = 0; read_index < 6; read_index++) begin
				branch_commit_cycle($sformatf("recovery_resume_round_%0d_drain_%0d", round_index, read_index));
			end

			idle_cycle($sformatf("recovery_resume_round_%0d_empty", round_index));

		end

		repeat (3) idle_cycle("recovery_resume_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 repeated recovery and branch-resumption sequence", UVM_LOW)

	endtask

endclass



///depth 2 GHR rollback across circular buffer boundary
class predictor_history_depth2_wrap_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_wrap_recovery_sequence)

	function new(string name = "predictor_history_depth2_wrap_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		branch_packet_t packet_value;
		program_counter_t pc_value;
		int unsigned branch_count;

		`uvm_info(get_type_name(), "Starting depth-2 GHR wrap-boundary recovery sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (GHR_MAX_PTR < 3) begin
			`uvm_fatal(get_type_name(), "This sequence requires at least three GHR entries")
		end

		if (FIFO_DEPTH < 5) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 5")
		end

		for (int unsigned case_index = 0; case_index < 3; case_index++) begin

			reset_cycle($sformatf("wrap_recovery_case_%0d_reset", case_index));
			idle_cycle($sformatf("wrap_recovery_case_%0d_post_reset", case_index));

			// One complete GHR traversal plus zero, one or two additional branches.
			branch_count = GHR_MAX_PTR + case_index;

			for (int unsigned write_index = 0; write_index < branch_count; write_index++) begin

				packet_value = branch_packet_t'(write_index + 1);
				pc_value = program_counter_t'((write_index % 8) * 4);

				// Establish two checkpoints, then maintain occupancy at two.
				if (write_index < 2) begin
					branch_cycle(packet_value, pc_value, $sformatf("wrap_recovery_case_%0d_fill_%0d", case_index, write_index));
				end else begin
					branch_and_commit_cycle(packet_value, pc_value, $sformatf("wrap_recovery_case_%0d_fill_%0d", case_index, write_index));
				end

			end

			idle_cycle($sformatf("wrap_recovery_case_%0d_before_rollback", case_index));

			`uvm_info(get_type_name(), $sformatf("Case %0d: intended GHR head before rollback=%0d, after rollback=%0d", case_index, case_index, (case_index + GHR_MAX_PTR - 2) % GHR_MAX_PTR), UVM_LOW)

			misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), $sformatf("wrap_recovery_case_%0d_misprediction", case_index));
			recovery_cycle(program_counter_t'(24), $sformatf("wrap_recovery_case_%0d_apply", case_index));
			idle_cycle($sformatf("wrap_recovery_case_%0d_hold", case_index));

			// Resume writes at the recovered head and cross the boundary again.
			for (int unsigned resume_index = 0; resume_index < 4; resume_index++) begin
				packet_value = branch_packet_t'(7'h61 + resume_index);
				pc_value = program_counter_t'((resume_index + 1) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("wrap_recovery_case_%0d_resume_%0d", case_index, resume_index));
			end

			// Two checkpoints - one recovery read + four resume writes = five.
			for (int unsigned read_index = 0; read_index < 5; read_index++) begin
				branch_commit_cycle($sformatf("wrap_recovery_case_%0d_drain_%0d", case_index, read_index));
			end

			idle_cycle($sformatf("wrap_recovery_case_%0d_final_idle", case_index));

		end

		`uvm_info(get_type_name(), "Completed depth-2 GHR wrap-boundary recovery sequence", UVM_LOW)

	endtask

endclass



/// mixed randomized test
class predictor_history_depth2_mixed_random_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_mixed_random_sequence)

	function new(string name = "predictor_history_depth2_mixed_random_sequence");
		super.new(name);
	endfunction

	virtual task body();

		branch_packet_t packet_value;
		program_counter_t pc_value;
		logic en_value;
		logic br_valid_value;
		logic commit_value;
		logic misprediction_value;
		bit read_accepted;
		bit write_accepted;
		int unsigned operation_select;
		int unsigned tracked_fifo_count;
		int unsigned drain_count;
		int unsigned available_history;

		`uvm_info(get_type_name(), "Starting depth-2 mixed randomized sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end

		if (FIFO_DEPTH < 4) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 4")
		end

		reset_cycle("mixed_random_reset");
		idle_cycle("mixed_random_post_reset_idle");

		tracked_fifo_count = 0;
		available_history = 0;

		// Establish valid history and four checkpoints.
		for (int unsigned prefill_index = 0; prefill_index < 4; prefill_index++) begin
			packet_value = branch_packet_t'($urandom_range(127, 1));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("mixed_random_prefill_%0d", prefill_index));
			tracked_fifo_count++;
			available_history++;
		end

		for (int unsigned iteration = 0; iteration < 3000; iteration++) begin

			packet_value = branch_packet_t'($urandom_range(127, 0));
			pc_value = program_counter_t'($urandom_range(7, 0) * 4);
			operation_select = $urandom_range(9, 0);

			en_value = 1'b1;
			br_valid_value = 1'b0;
			commit_value = 1'b0;
			misprediction_value = 1'b0;

		case (operation_select)
				0, 1, 2: br_valid_value = 1'b1;
				3, 4: commit_value = 1'b1;
				5: begin
					br_valid_value = 1'b1;
					commit_value = 1'b1;
				end
				6: begin
					// Enabled idle cycle.
				end
				7: begin
					// Exercise input isolation while globally disabled.
					en_value = 1'b0;
					br_valid_value = 1'b1;
					commit_value = 1'b1;
				end
				8, 9: begin
					if ((tracked_fifo_count != 0) && (available_history >= 2)) begin
						misprediction_value = 1'b1;
						commit_value = (operation_select == 9);
					end else begin
						br_valid_value = 1'b1;
					end
				end
			endcase

		// Calculate acceptance using occupancy before this transaction.
			read_accepted = en_value && (commit_value || misprediction_value) && (tracked_fifo_count != 0);
			write_accepted = en_value && br_valid_value && ((tracked_fifo_count < FIFO_DEPTH) || read_accepted);

			send_cycle($sformatf("mixed_random_iteration_%0d_operation_%0d", iteration, operation_select), en_value, br_valid_value, packet_value, pc_value, commit_value, misprediction_value, misprediction_value ? misprediction_depth_t'(2) : misprediction_depth_t'(0));

			case ({write_accepted, read_accepted})
				2'b10: tracked_fifo_count++;
				2'b01: tracked_fifo_count--;
				default: begin
				end
			endcase

			// GHR branch acceptance is not backpressured by FIFO full in the current wrapper.
			if (en_value && br_valid_value) begin
				if (available_history < GHR_MAX_PTR) available_history++;
			end

			if (misprediction_value) begin
				available_history -= 2;

				// Complete recovery before selecting the next random operation.
				recovery_cycle(program_counter_t'(24), $sformatf("mixed_random_apply_recovery_%0d", iteration));
			end

		end

		// Drain exactly the predicted remaining entries.
		drain_count = tracked_fifo_count;

		for (int unsigned read_index = 0; read_index < drain_count; read_index++) begin
			branch_commit_cycle($sformatf("mixed_random_final_drain_%0d", read_index));
			tracked_fifo_count--;
		end

		repeat (3) idle_cycle("mixed_random_final_idle");

		`uvm_info(get_type_name(), "Completed depth-2 mixed randomized sequence", UVM_LOW)

	endtask

endclass




/// reset_while_recovery_is_active
class predictor_history_depth2_reset_during_recovery_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_depth2_reset_during_recovery_sequence)

	function new(string name = "predictor_history_depth2_reset_during_recovery_sequence");
		super.new(name);
	endfunction

	virtual task body();

		branch_packet_t packet_value;
		program_counter_t pc_value;

		`uvm_info(get_type_name(), "Starting depth-2 reset-during-active-recovery sequence", UVM_LOW)

		if (SELECTED_HISTORY_DEPTH != 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires SELECTED_HISTORY_DEPTH = 2")
		end
	
		if (FIFO_DEPTH < 6) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 6")
		end

		for (int unsigned round_index = 0; round_index < 3; round_index++) begin

			reset_cycle($sformatf("active_recovery_round_%0d_initial_reset", round_index));
			idle_cycle($sformatf("active_recovery_round_%0d_initial_idle", round_index));

			// Generate six checkpoints with different branch packets.
			for (int unsigned write_index = 0; write_index < 6; write_index++) begin
				packet_value = branch_packet_t'(7'h11 + (round_index * 5) + (write_index * 9));
				pc_value = program_counter_t'((write_index + 1) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("active_recovery_round_%0d_prefill_%0d", round_index, write_index));
			end

			// Remove two startup checkpoints, leaving four entries.
			branch_commit_cycle($sformatf("active_recovery_round_%0d_retire_0", round_index));
			branch_commit_cycle($sformatf("active_recovery_round_%0d_retire_1", round_index));
			idle_cycle($sformatf("active_recovery_round_%0d_before_misprediction", round_index));

			// The next rising edge produces recovery-valid and the popped checkpoint.
			misprediction_cycle(misprediction_depth_t'(2), program_counter_t'(24), $sformatf("active_recovery_round_%0d_misprediction", round_index));

			// Reset at the following driver edge, before the next hash capture edge.
			// Do not insert recovery_cycle() or idle_cycle() before this reset.
			reset_cycle($sformatf("active_recovery_round_%0d_interrupt_with_reset", round_index));

			// After reset release, first hold disabled, then enable without a branch.
			repeat (2) disabled_cycle($sformatf("active_recovery_round_%0d_post_reset_disabled", round_index));
			repeat (2) idle_cycle($sformatf("active_recovery_round_%0d_post_reset_idle", round_index));

			// Confirm that fresh branch processing works after interrupted recovery.
			for (int unsigned resume_index = 0; resume_index < 4; resume_index++) begin
				packet_value = branch_packet_t'(7'h41 + (round_index * 3) + (resume_index * 7));
				pc_value = program_counter_t'((resume_index + 1) * 4);
				branch_cycle(packet_value, pc_value, $sformatf("active_recovery_round_%0d_resume_%0d", round_index, resume_index));
			end

			// Only the four post-reset checkpoints should remain.
			for (int unsigned read_index = 0; read_index < 4; read_index++) begin
				branch_commit_cycle($sformatf("active_recovery_round_%0d_final_drain_%0d", round_index, read_index));
			end

			repeat (2) idle_cycle($sformatf("active_recovery_round_%0d_final_idle", round_index));

		end

		`uvm_info(get_type_name(), "Completed depth-2 reset-during-active-recovery sequence", UVM_LOW)

	endtask

endclass




//sequencer class
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

	// reset
	task apply_reset();
		vif.rst_n <= 1'b0;
		drive_initial_values();
		repeat(RESET_ACTIVE_CYCLES) @(negedge vif.clk);
		vif.rst_n <= 1'b1;
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
		
		apply_reset();
	
		forever begin
			@(vif.drv_cb);
			req = null;
			seq_item_port.try_next_item(req);

			if (req == null) begin
				drive_idle();
			end else begin

				if (req.reset_request) begin
					apply_reset();
				end else begin
					drive_transaction(req);
				end

				driven_transaction_count++;
				// `uvm_info(get_type_name(), $sformatf("Driving transaction %0d: reset_request=%b %s", driven_transaction_count, req.reset_request, req.convert2string()), UVM_MEDIUM)
				`uvm_info(get_type_name(), $sformatf("Driving transaction %0d: name=%s reset_request=%b en=%b br_valid=%b packet=0x%0h pc=%0d commit=%b misprediction=%b depth=%0d", driven_transaction_count, req.transaction_name, req.reset_request, req.en_i, req.br_valid_i, req.br_packet_i, req.load_pc_i, req.branch_commit_i, req.misprediction_i, req.mispredicted_table_depth_i), UVM_MEDIUM)	
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


			/// additional fields for GHR observation
			observed_item.ghr_head_pre = vif.mon_cb.ghr_head_pre;
			observed_item.ghr_head_post = vif.mon_cb.ghr_head_post;
			observed_item.ghr_next_head_pre = vif.mon_cb.ghr_next_head_pre;
			observed_item.ghr_write_ptr_pre = vif.mon_cb.ghr_write_ptr_pre;
			observed_item.ghr_write_bank_pre = vif.mon_cb.ghr_write_bank_pre;
			observed_item.ghr_write_row_pre = vif.mon_cb.ghr_write_row_pre;
			observed_item.ghr_bank_we_pre = vif.mon_cb.ghr_bank_we_pre;
			observed_item.ghr_ptr_enable_pre = vif.mon_cb.ghr_ptr_enable_pre;
			observed_item.ghr_recovery_pre = vif.mon_cb.ghr_recovery_pre;
			observed_item.ghr_write_data_pre = vif.mon_cb.ghr_write_data_pre;
			observed_item.ghr_incoming_post = vif.mon_cb.ghr_incoming_post;

			foreach (observed_item.ghr_memory_post[location]) begin
				observed_item.ghr_memory_post[location] = vif.mon_cb.ghr_memory_post[location];
			end

			`uvm_info("CYCLE_MONITOR", observed_item.convert2string(), UVM_LOW)

			analysis_port.write(observed_item);
			monitored_cycle_count++;
		end
	endtask

endclass


/// reference model
class predictor_history_reference_model extends uvm_object;

		`uvm_object_utils(predictor_history_reference_model)

		branch_packet_t ghr_memory_state [0:GHR_MAX_PTR-1];
		folded_history_t fifo_memory_state [0:FIFO_DEPTH-1];

		int unsigned ghr_head_state;
		int unsigned fifo_write_pointer_state;
		int unsigned fifo_read_pointer_state;
		int unsigned fifo_count_state;
		// int unsigned startup_fifo_write_count = 0;	/// this is so that the FIFO writes  ZEROs for the very first 2 clock cycles.
		folded_history_t folded_history_state;
		folded_history_t recovery_data_state;
		logic recovery_valid_state;

		branch_packet_t ghr_memory_current [0:GHR_MAX_PTR-1];
		int unsigned ghr_head_current;
		int unsigned ghr_head_next_expected;
		folded_history_t folded_history_current_expected;
		folded_history_t folded_history_next_expected;
		logic previous_recovery_valid;

		logic fifo_write_request;
		logic fifo_read_request;
		logic fifo_write_enable;
		logic fifo_read_enable;

		logic expected_fifo_empty;
		logic expected_fifo_full;
		logic expected_recovery_valid;

		folded_history_t expected_recovery_data;
		folded_history_t popped_fifo_data;

		branch_packet_t ghr_incoming_state;
		branch_packet_t expected_ghr_incoming_post;
		logic expected_ghr_write_enable;
		logic expected_ghr_ptr_enable;
		logic [NUM_GHR_BANKS-1:0] expected_ghr_bank_we;
		int unsigned expected_ghr_write_location;
		branch_packet_t expected_ghr_incoming_packet;
		branch_packet_t selected_expiring_packet;

		int unsigned rollback_pointer;

		ghr_packet_array_t expected_expiring_packets_at_edge;

		// varibales for showing the Ref model GHR Bank for looking up the values
		folded_history_t shifted_fold_model;
		folded_history_t padded_incoming_model;
		folded_history_t padded_expiring_model;
		folded_history_t aligned_expiring_model;
		folded_history_t xor_result_model;
		folded_history_t recovery_data_current_model;
		int unsigned selected_expiring_location_model;
		logic normal_hash_branch_valid_model;
		string fold_operation_model;


		// vars for predict and compare the hash model
		tagged_index_t expected_tagged_index;
		tagged_tag_t expected_tagged_tag;
		folded_history_t expected_hash_fold_after_edge;
		branch_packet_t expected_hash_expiring_after_edge;

		/// trying with delaying the reference model's padded incoming fby one cycle - trial one (FAIL)
		// branch_packet_t incoming_packet_previous_cycle;
		// branch_packet_t incoming_packet_current_cycle;

		function new(string name = "predictor_history_reference_model");
			super.new(name);
			reset_model();
		endfunction

		function void reset_model();
			foreach (ghr_memory_state[i]) ghr_memory_state[i] = '0;
			foreach (ghr_memory_current[i]) ghr_memory_current[i] = '0;
			foreach (fifo_memory_state[i]) fifo_memory_state[i] = '0;
			foreach (expected_expiring_packets_at_edge[i]) expected_expiring_packets_at_edge[i] = '0;

			/// trying with delaying the reference model's padded incoming fby one cycle - trial one (FAIL)
			// incoming_packet_previous_cycle = 0;
			// incoming_packet_current_cycle = 0;

			// reset variables for the GHR Bank design
			shifted_fold_model = '0;
			padded_incoming_model = '0;
			padded_expiring_model = '0;
			aligned_expiring_model = '0;
			xor_result_model = '0;
			recovery_data_current_model = '0;
			selected_expiring_location_model = 0;
			normal_hash_branch_valid_model = 1'b0;
			fold_operation_model = "RESET";
			/// end of variables for shwing the ref model GHR Bank replication

			ghr_head_state = 0;
			ghr_head_current = 0;
			ghr_head_next_expected = 0;

			fifo_write_pointer_state = 0;
			fifo_read_pointer_state = 0;
			fifo_count_state = 0;

			folded_history_state = '0;
			folded_history_current_expected = '0;
			folded_history_next_expected = '0;

			recovery_data_state = '0;
			recovery_valid_state = 1'b0;
			previous_recovery_valid = 1'b0;

			fifo_write_request = 1'b0;
			fifo_read_request = 1'b0;
			fifo_write_enable = 1'b0;
			fifo_read_enable = 1'b0;

			expected_fifo_empty = 1'b1;
			expected_fifo_full = 1'b0;
			expected_recovery_valid = 1'b0;
			expected_recovery_data = '0;
			expected_ghr_incoming_packet = '0;

			rollback_pointer = 0;
			popped_fifo_data = '0;
			selected_expiring_packet = '0;

			/// additional fields fr tracking GHR
			ghr_incoming_state = '0;
			expected_ghr_incoming_post = '0;
			expected_ghr_write_enable = 1'b0;
			expected_ghr_ptr_enable = 1'b0;
			expected_ghr_bank_we = '0;
			expected_ghr_write_location = 0;

			/// initialize the model to ZERO for hash index and tag
			expected_tagged_index = '0;
			expected_tagged_tag = '0;
			expected_hash_fold_after_edge = '0;
			expected_hash_expiring_after_edge = '0;
			
		endfunction

		function automatic int unsigned circular_subtract(input int unsigned pointer_value, input int unsigned distance_value, input int unsigned modulus_value);
			return (pointer_value >= distance_value) ? pointer_value - distance_value : pointer_value + modulus_value - distance_value;
		endfunction

		function automatic folded_history_t rotate_left(input folded_history_t value, input int unsigned shift_amount);
			int unsigned effective_shift;

			effective_shift = shift_amount % FOLD_WIDTH;

			if (effective_shift == 0) begin
				return value;
			end

			return (value << effective_shift) | (value >> (FOLD_WIDTH - effective_shift));
		endfunction


		/// block to calculate the hash prediction block
		function void predict_hash_outputs(input predictor_history_sequence_item observed_item);

			logic hash_branch_active;
			logic hash_recovery_active;
			int unsigned address_head;
			int unsigned expiring_location;
			logic [29:0] pc_word;
			logic [29:0] index_mix;
			logic [29:0] tag_mix;

			// Called after step() updates the predicted registered state.
			hash_recovery_active = observed_item.en_i && recovery_valid_state;
			hash_branch_active = observed_item.en_i && observed_item.br_valid_i && !hash_recovery_active;

			expected_hash_fold_after_edge = folded_history_state;
			expected_hash_expiring_after_edge = '0;

			if (hash_recovery_active === 1'b1) begin

				expected_hash_fold_after_edge = expected_recovery_data;

			end else if (hash_branch_active === 1'b1) begin

				// Predict the combinational next_head_ptr from the POST-edge head.
					// This is address calculation only; do not modify ghr_head_state again.
				address_head = ghr_head_state;

				if (observed_item.misprediction_i === 1'b1) begin
					address_head = circular_subtract(address_head, observed_item.mispredicted_table_depth_i, GHR_MAX_PTR);
				end

				address_head = (address_head + 1) % GHR_MAX_PTR;
				expiring_location = circular_subtract(address_head, SELECTED_HISTORY_DEPTH, GHR_MAX_PTR);

				expected_hash_expiring_after_edge = ghr_memory_state[expiring_location];
				expected_hash_fold_after_edge = rotate_left(folded_history_state, 1) ^ folded_history_t'(ghr_incoming_state) ^ rotate_left(folded_history_t'(expected_hash_expiring_after_edge), SELECTED_HISTORY_DEPTH);

			end

			pc_word = (hash_branch_active || hash_recovery_active) ? observed_item.load_pc_i[31:2] : '0;

			index_mix = pc_word ^ (pc_word >> 2) ^ (pc_word >> 5);
			tag_mix = pc_word ^ (pc_word >> 3) ^ (pc_word >> 7);

			expected_tagged_index = expected_hash_fold_after_edge[FOLD_WIDTH-1:T_WIDTH] ^ index_mix[S_WIDTH-1:0];
			expected_tagged_tag = expected_hash_fold_after_edge[T_WIDTH-1:0] ^ tag_mix[T_WIDTH-1:0];

		endfunction	

		function void step(input predictor_history_sequence_item observed_item);
			logic normal_ghr_branch_valid;
			logic normal_hash_branch_valid;
			int unsigned selected_history_location;
			int unsigned ghr_write_location;
			// folded_history_t padded_incoming_packet;
			// folded_history_t padded_expiring_packet;

			ghr_head_current = ghr_head_state;
			foreach (ghr_memory_state[i]) ghr_memory_current[i] = ghr_memory_state[i];	

			folded_history_current_expected = folded_history_state;
			folded_history_next_expected = folded_history_current_expected;
			previous_recovery_valid = recovery_valid_state;		

			fifo_write_request = observed_item.en_i && observed_item.br_valid_i;
			fifo_read_request = observed_item.branch_commit_i || observed_item.misprediction_i;
			fifo_read_enable = observed_item.en_i && fifo_read_request && (fifo_count_state != 0);
			fifo_write_enable = observed_item.en_i && fifo_write_request && ((fifo_count_state != FIFO_DEPTH) || fifo_read_enable);

			normal_ghr_branch_valid = observed_item.en_i && observed_item.br_valid_i && !previous_recovery_valid;
			normal_hash_branch_valid = observed_item.en_i && observed_item.br_valid_i && !previous_recovery_valid;

			///expected_ghr_incoming_packet = normal_ghr_branch_valid ? observed_item.br_packet_i : branch_packet_t'('0);
			// The RTL incoming output is a register clocked whenever the pointer updates.
			expected_ghr_incoming_packet = ghr_incoming_state;
			expected_ghr_write_enable = normal_ghr_branch_valid;
			expected_ghr_ptr_enable = normal_ghr_branch_valid || (observed_item.en_i && observed_item.misprediction_i);

			expected_ghr_incoming_post = ghr_incoming_state;
			if (expected_ghr_ptr_enable === 1'b1) expected_ghr_incoming_post = observed_item.br_packet_i;			

			rollback_pointer = ghr_head_current;

			if (observed_item.en_i && observed_item.misprediction_i) begin
				rollback_pointer = circular_subtract(ghr_head_current, observed_item.mispredicted_table_depth_i, GHR_MAX_PTR);
			end

			ghr_head_next_expected = ghr_head_current;

			case ({observed_item.en_i && observed_item.misprediction_i, normal_ghr_branch_valid})
				2'b01: ghr_head_next_expected = (ghr_head_current + 1) % GHR_MAX_PTR;
				2'b10: ghr_head_next_expected = rollback_pointer;
				2'b11: ghr_head_next_expected = (rollback_pointer + 1) % GHR_MAX_PTR;
				default: ghr_head_next_expected = ghr_head_current;
			endcase

			// additional fields for GHR tracking
			// rollback_pointer already equals the current head when no rollback is requested.
			expected_ghr_write_location = rollback_pointer;
			expected_ghr_bank_we = '0;

			if (expected_ghr_write_enable === 1'b1) begin
				expected_ghr_bank_we[expected_ghr_write_location % NUM_GHR_BANKS] = 1'b1;
			end

			foreach (expected_expiring_packets_at_edge[i]) begin
				selected_history_location = circular_subtract(ghr_head_next_expected, GHR_DEPTHS[i], GHR_MAX_PTR);
				//expected_expiring_packets_at_edge[i] = ghr_memory_current[selected_history_location];
				expected_expiring_packets_at_edge[i] = normal_ghr_branch_valid ? ghr_memory_current[selected_history_location] : branch_packet_t'('0);
			end

			selected_expiring_packet = expected_expiring_packets_at_edge[SELECTED_HASH_TABLE];


			/// for GHR MOdel replicated in reference model
			selected_expiring_location_model = circular_subtract(ghr_head_next_expected, SELECTED_HISTORY_DEPTH, GHR_MAX_PTR);
			normal_hash_branch_valid_model = normal_hash_branch_valid;
			recovery_data_current_model = recovery_data_state;
			
			folded_history_next_expected = folded_history_current_expected;
			fold_operation_model = "HOLD";
			shifted_fold_model = '0;
			padded_incoming_model = '0;
			padded_expiring_model = '0;
			aligned_expiring_model = '0;
			xor_result_model = '0;

			/// end of GHR MOdel in ref model


			popped_fifo_data = '0;

			if (fifo_read_enable) begin
				popped_fifo_data = fifo_memory_state[fifo_read_pointer_state];
			end

			// if (observed_item.en_i && previous_recovery_valid) begin
			// 	folded_history_next_expected = recovery_data_state;
			// end else if (normal_hash_branch_valid) begin
			// 	padded_incoming_packet = {{(FOLD_WIDTH-PKT_WIDTH){1'b0}}, expected_ghr_incoming_packet};
			// 	padded_expiring_packet = {{(FOLD_WIDTH-PKT_WIDTH){1'b0}}, selected_expiring_packet};
			// 	folded_history_next_expected = rotate_left(folded_history_current_expected, 1) ^ padded_incoming_packet ^ rotate_left(padded_expiring_packet, SELECTED_HISTORY_DEPTH);
			// end

			if ((observed_item.en_i === 1'b1) && (previous_recovery_valid === 1'b1)) begin
				fold_operation_model = "RECOVERY";
				folded_history_next_expected = recovery_data_current_model;
			end else if (normal_hash_branch_valid === 1'b1) begin
				fold_operation_model = "BRANCH";
				shifted_fold_model = rotate_left(folded_history_current_expected, 1);
				padded_incoming_model = folded_history_t'(observed_item.ghr_incoming_packet_o);
				padded_expiring_model = folded_history_t'(observed_item.selected_expiring_packet_o);
				aligned_expiring_model = rotate_left(padded_expiring_model, SELECTED_HISTORY_DEPTH);
				xor_result_model = shifted_fold_model ^ padded_incoming_model ^ aligned_expiring_model;
				folded_history_next_expected = xor_result_model;
			end

			if (fifo_write_enable) begin
			/*	
				if (startup_fifo_write_count < 2) begin
					fifo_memory_state[fifo_write_pointer_state] = '0;
					startup_fifo_write_count++;
				end else begin
					fifo_memory_state[fifo_write_pointer_state] = folded_history_current_expected;
				end
			*/
				fifo_memory_state[fifo_write_pointer_state] = folded_history_current_expected;
				fifo_write_pointer_state = (fifo_write_pointer_state + 1) % FIFO_DEPTH;
			end

			if (fifo_read_enable) begin
				fifo_read_pointer_state = (fifo_read_pointer_state + 1) % FIFO_DEPTH;
			end

			case ({fifo_write_enable, fifo_read_enable})
				2'b10: fifo_count_state++;
				2'b01: fifo_count_state--;
				default: fifo_count_state = fifo_count_state;
			endcase

			if (normal_ghr_branch_valid) begin
				ghr_write_location = observed_item.misprediction_i ? rollback_pointer : ghr_head_current;
				ghr_memory_state[ghr_write_location] = observed_item.br_packet_i;
			end

			ghr_head_state = ghr_head_next_expected;
			ghr_incoming_state = expected_ghr_incoming_post;

			expected_recovery_valid = fifo_read_enable && observed_item.misprediction_i;
			expected_recovery_data = expected_recovery_valid ? popped_fifo_data : folded_history_t'('0);

			recovery_valid_state = expected_recovery_valid;

			if (expected_recovery_valid) begin
				recovery_data_state = popped_fifo_data;
			end

			expected_fifo_empty = (fifo_count_state == 0);
			expected_fifo_full = (fifo_count_state == FIFO_DEPTH);

			folded_history_state = folded_history_next_expected;

			predict_hash_outputs(observed_item);
		endfunction

endclass



//// scoreboard
class predictor_history_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(predictor_history_scoreboard)

	uvm_analysis_imp #(predictor_history_sequence_item, predictor_history_scoreboard) analysis_export;

	predictor_history_reference_model reference_model;

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
		reference_model = predictor_history_reference_model::type_id::create("reference_model");
	endfunction


	function automatic string format_ghr_packets(input ghr_packet_array_t packets);
		string packet_string;
		packet_string = "";
		foreach (packets[i]) packet_string = {packet_string, $sformatf(" depth%0d=0x%0h", GHR_DEPTHS[i], packets[i])};
		return packet_string;
	endfunction

	function void record_pass(string check_name);
		passed_check_count++;
		`uvm_info("SCOREBOARD_PASS", $sformatf("cycle=%0d %s", checked_cycle_count, check_name), UVM_HIGH)
	endfunction

	function void record_failure(string check_name, string failure_detail);
		failed_check_count++;
		`uvm_error("SCOREBOARD_MISMATCH", $sformatf("cycle=%0d %s: %s", checked_cycle_count, check_name, failure_detail))
	endfunction

	function automatic string format_ghr_model(input branch_packet_t memory_snapshot [0:GHR_MAX_PTR-1], input int unsigned head_snapshot);
		string history_string;
		int unsigned memory_location;
		history_string = "";
		for (int unsigned depth = 1; depth <= GHR_MAX_PTR; depth++) begin
			memory_location = reference_model.circular_subtract(head_snapshot, depth, GHR_MAX_PTR);
			history_string = {history_string, $sformatf(" d%0d=0x%0h", depth, memory_snapshot[memory_location])};
		end
		return history_string;
	endfunction
	

	/// function to display the data better
	function automatic string format_ghr_bank_table(input branch_packet_t memory_snapshot [0:GHR_MAX_PTR-1], input int unsigned head_snapshot);
		string bank_table;
		int unsigned memory_location;

		bank_table = "\n             BANK |";
		for (int unsigned bank = 0; bank < NUM_GHR_BANKS; bank++) begin
			bank_table = {bank_table, $sformatf("  B%0d ", bank)};
		end

		bank_table = {bank_table, "\n             -----+"};
		for (int unsigned bank = 0; bank < NUM_GHR_BANKS; bank++) begin
			bank_table = {bank_table, "-----"};
		end

		for (int unsigned row = 0; row < GHR_ENTRIES_PER_BANK; row++) begin
			bank_table = {bank_table, $sformatf("\n             R%0d   |", row)};

			for (int unsigned bank = 0; bank < NUM_GHR_BANKS; bank++) begin
				memory_location = (row * NUM_GHR_BANKS) + bank;

				if (memory_location == head_snapshot) begin
					bank_table = {bank_table, $sformatf(" *%02h ", memory_snapshot[memory_location])};
				end else begin
					bank_table = {bank_table, $sformatf("  %02h ", memory_snapshot[memory_location])};
				end
			end
		end

		bank_table = {bank_table, "\n             * marks the head/next-write location"};
		return bank_table;
	endfunction


	function automatic string format_ghr_expiring_table(input ghr_packet_array_t packets);
		string tap_table;

		tap_table = "\n             DEPTH |";
		foreach (packets[i]) tap_table = {tap_table, $sformatf(" %4d", GHR_DEPTHS[i])};

		tap_table = {tap_table, "\n             ------+-----------------------------------"};
		tap_table = {tap_table, "\n             DATA  |"};

		foreach (packets[i]) tap_table = {tap_table, $sformatf("  %02h", packets[i])};

		return tap_table;
	endfunction

	
	function void write(predictor_history_sequence_item observed_item);
		string cycle_report;

		if (observed_item.rst_n !== 1'b1) begin
			reference_model.reset_model();

			if (observed_item.rst_n === 1'b0) begin
				checked_cycle_count++;
				check_reset_outputs(observed_item);
				check_ghr_outputs(observed_item);
				`uvm_info("SB_RESET_TRACE", $sformatf("time=%0t monitor_cycle=%0d rst_n=%b fifo_count=%0d fifo_empty_expected/actual=1/%b fifo_full_expected/actual=0/%b recovery_expected/actual=0/%b folded_expected/actual=0x0/0x%0h", observed_item.sample_time, observed_item.cycle_number, observed_item.rst_n, reference_model.fifo_count_state, observed_item.fifo_empty_o, observed_item.fifo_full_o, observed_item.recovery_active_o, observed_item.folded_history_state_o), UVM_LOW)
			end else begin
				`uvm_info("SB_STARTUP_SKIP", $sformatf("time=%0t monitor_cycle=%0d reset is unknown; skipping this startup sample", observed_item.sample_time, observed_item.cycle_number), UVM_LOW)
			end

			return;
		end


		/// to stop checking the design once the valid branch FLAG is down.
	//	if ((observed_item.br_valid_i && observed_item.en_i) || (observed_item.recovery_active_o && observed_item.en_i) === 1'b0) begin
	//		return;
	//	end   

		checked_cycle_count++;

		reference_model.step(observed_item);
		check_ghr_outputs(observed_item);
/*
		check_vector_value("ghr_incoming_packet_o", folded_history_t'(reference_model.expected_ghr_incoming_packet), folded_history_t'(observed_item.ghr_incoming_packet_o));

		foreach (observed_item.ghr_expiring_packets_o[tap_index]) begin
			check_vector_value($sformatf("ghr_expiring_packets_o[%0d]", tap_index), folded_history_t'(reference_model.expected_expiring_packets_at_edge[tap_index]), folded_history_t'(observed_item.ghr_expiring_packets_o[tap_index]));
		end

		check_vector_value("selected_expiring_packet_o", folded_history_t'(reference_model.selected_expiring_packet), folded_history_t'(observed_item.selected_expiring_packet_o));
*/
		check_logic_value("fifo_empty_o", reference_model.expected_fifo_empty, observed_item.fifo_empty_o);
		check_logic_value("fifo_full_o", reference_model.expected_fifo_full, observed_item.fifo_full_o);
		check_logic_value("recovery_active_o", reference_model.expected_recovery_valid, observed_item.recovery_active_o);
		check_vector_value("folded_history_state_o", reference_model.folded_history_next_expected, observed_item.folded_history_state_o);
		check_vector_value("recovery_folded_history_o", reference_model.expected_recovery_data, observed_item.recovery_folded_history_o);
		check_vector_value("tagged_index_o", folded_history_t'(reference_model.expected_tagged_index), folded_history_t'(observed_item.tagged_index_o));
		check_vector_value("tagged_tag_o", folded_history_t'(reference_model.expected_tagged_tag), folded_history_t'(observed_item.tagged_tag_o));

		cycle_report = "\n======================================================================";
		cycle_report = {cycle_report, $sformatf("\nCYCLE %0d   TIME %0t", observed_item.cycle_number, observed_item.sample_time)};
		cycle_report = {cycle_report, $sformatf("\nCONTROL   en=%b   br_valid=%b   commit=%b   misprediction=%b   depth=%0d", observed_item.en_i, observed_item.br_valid_i, observed_item.branch_commit_i, observed_item.misprediction_i, observed_item.mispredicted_table_depth_i)};
		cycle_report = {cycle_report, $sformatf("\nINPUT     packet=0x%0h   pc=0x%08h", observed_item.br_packet_i, observed_item.load_pc_i)};
		cycle_report = {cycle_report, $sformatf("\nGHR       head_current=%0d   head_next=%0d   incoming_expected/actual=0x%0h/0x%0h", reference_model.ghr_head_current, reference_model.ghr_head_next_expected, reference_model.expected_ghr_incoming_packet, observed_item.ghr_incoming_packet_o)};
	//	cycle_report = {cycle_report, $sformatf("\nFOLD      current_expected/actual=0x%0h/0x%0h   next_expected=0x%0h", reference_model.folded_history_current_expected, observed_item.folded_history_state_o, reference_model.folded_history_next_expected)};
		cycle_report = {cycle_report, $sformatf("\nFOLD      before_edge=0x%0h   after_edge_expected=0x%0h   after_edge_actual=0x%0h", reference_model.folded_history_current_expected, reference_model.folded_history_next_expected, observed_item.folded_history_state_o)};	
		cycle_report = {cycle_report, $sformatf("\nMODEL FOLD operation=%s   branch_update=%b   recovery_before_step=%b", reference_model.fold_operation_model, reference_model.normal_hash_branch_valid_model, reference_model.previous_recovery_valid)};
		cycle_report = {cycle_report, $sformatf("\nMODEL OPERANDS shifted_fold=0x%0h   padded_incoming=0x%0h   padded_expiring=0x%0h   aligned_expiring=0x%0h", reference_model.shifted_fold_model, reference_model.padded_incoming_model, reference_model.padded_expiring_model, reference_model.aligned_expiring_model)};
		cycle_report = {cycle_report, $sformatf("\nMODEL EQUATION 0x%0h XOR 0x%0h XOR 0x%0h = 0x%0h", reference_model.shifted_fold_model, reference_model.padded_incoming_model, reference_model.aligned_expiring_model, reference_model.xor_result_model)};
		cycle_report = {cycle_report, $sformatf("\nMODEL RESULT current=0x%0h   next=0x%0h   recovery_source=0x%0h   DUT_sample=0x%0h", reference_model.folded_history_current_expected, reference_model.folded_history_next_expected, reference_model.recovery_data_current_model, observed_item.folded_history_state_o)};
		cycle_report = {cycle_report, $sformatf("\nMODEL GHR TAP table=%0d   depth=%0d   address_head=%0d   location=%0d   bank=%0d   row=%0d   packet=0x%0h", SELECTED_HASH_TABLE, SELECTED_HISTORY_DEPTH, reference_model.ghr_head_next_expected, reference_model.selected_expiring_location_model, reference_model.selected_expiring_location_model % NUM_GHR_BANKS, reference_model.selected_expiring_location_model / NUM_GHR_BANKS, reference_model.selected_expiring_packet)};
		cycle_report = {cycle_report, $sformatf("\nFIFO      wr_req=%b   wr_accept=%b   rd_req=%b   rd_accept=%b   count=%0d   write_ptr=%0d   read_ptr=%0d", reference_model.fifo_write_request, reference_model.fifo_write_enable, reference_model.fifo_read_request, reference_model.fifo_read_enable, reference_model.fifo_count_state, reference_model.fifo_write_pointer_state, reference_model.fifo_read_pointer_state)};
		cycle_report = {cycle_report, $sformatf("\nFLAGS     empty_expected/actual=%b/%b   full_expected/actual=%b/%b   recovery_expected/actual=%b/%b", reference_model.expected_fifo_empty, observed_item.fifo_empty_o, reference_model.expected_fifo_full, observed_item.fifo_full_o, reference_model.expected_recovery_valid, observed_item.recovery_active_o)};
		cycle_report = {cycle_report, $sformatf("\nRECOVERY  data_expected/actual=0x%0h/0x%0h   previous_recovery=%b", reference_model.expected_recovery_data, observed_item.recovery_folded_history_o, reference_model.previous_recovery_valid)};
		cycle_report = {cycle_report, "\nGHR EXPIRING USED BY HASH (expected)", format_ghr_expiring_table(reference_model.expected_expiring_packets_at_edge)};
		cycle_report = {cycle_report, $sformatf("\nHASH INPUT selected_expiring_expected=0x%0h   selected_expiring_observed=0x%0h", reference_model.selected_expiring_packet, observed_item.selected_expiring_packet_o)};
	//	cycle_report = {cycle_report, $sformatf("\nHASH OUTPUT index_actual=0x%0h   tag_actual=0x%0h", observed_item.tagged_index_o, observed_item.tagged_tag_o)};
		cycle_report = {cycle_report, $sformatf("\nHASH OUTPUT index_expected/actual=0x%0h/0x%0h   tag_expected/actual=0x%0h/0x%0h", reference_model.expected_tagged_index, observed_item.tagged_index_o, reference_model.expected_tagged_tag, observed_item.tagged_tag_o)};
		cycle_report = {cycle_report, $sformatf("\nHASH POST-EDGE COMBINATIONAL fold_expected=0x%0h   expiring_expected=0x%0h", reference_model.expected_hash_fold_after_edge, reference_model.expected_hash_expiring_after_edge)};	
		cycle_report = {cycle_report, "\nGHR CURRENT MODEL", format_ghr_bank_table(reference_model.ghr_memory_current, reference_model.ghr_head_current)};
		cycle_report = {cycle_report, $sformatf("\nGHR CHECK head_pre expected/actual=%0d/%0d   head_post expected/actual=%0d/%0d   bank_we expected/actual=%b/%b", reference_model.ghr_head_current, observed_item.ghr_head_pre, reference_model.ghr_head_state, observed_item.ghr_head_post, reference_model.expected_ghr_bank_we, observed_item.ghr_bank_we_pre)};
		cycle_report = {cycle_report, $sformatf("\nGHR WRITE enabled_expected=%b   location_expected=%0d   location_actual=%0d   row_actual=%0d   bank_actual=%0d   data_actual=0x%0h", reference_model.expected_ghr_write_enable, reference_model.expected_ghr_write_location, observed_item.ghr_write_ptr_pre, observed_item.ghr_write_row_pre, observed_item.ghr_write_bank_pre, observed_item.ghr_write_data_pre)};
		cycle_report = {cycle_report, "\nGHR AFTER EDGE MODEL", format_ghr_bank_table(reference_model.ghr_memory_state, reference_model.ghr_head_state)};
		cycle_report = {cycle_report, "\nGHR AFTER EDGE DUT", format_ghr_bank_table(observed_item.ghr_memory_post, int'(observed_item.ghr_head_post))};
		// cycle_report = {cycle_report, "\nGHR NEXT MODEL", format_ghr_bank_table(reference_model.ghr_memory_state, reference_model.ghr_head_state)};
		cycle_report = {cycle_report, $sformatf("\nGHR ACTUAL EXPOSED TAPS:%s", format_ghr_packets(observed_item.ghr_expiring_packets_o))};
		cycle_report = {cycle_report, "\n======================================================================"};

		`uvm_info("SB_CYCLE_REPORT", cycle_report, UVM_LOW)
	endfunction

function void check_ghr_outputs(predictor_history_sequence_item observed_item);

	string context_name;

	context_name = $sformatf("GHR monitor_cycle=%0d time=%0t", observed_item.cycle_number, observed_item.sample_time);

	// Compare independently predicted pointer state with the actual DUT.
	check_vector_value({context_name, " head_pre"}, folded_history_t'(reference_model.ghr_head_current), folded_history_t'(observed_item.ghr_head_pre));
	check_vector_value({context_name, " next_head_pre"}, folded_history_t'(reference_model.ghr_head_next_expected), folded_history_t'(observed_item.ghr_next_head_pre));
	check_vector_value({context_name, " head_post"}, folded_history_t'(reference_model.ghr_head_state), folded_history_t'(observed_item.ghr_head_post));

	check_logic_value({context_name, " ptr_enable_pre"}, reference_model.expected_ghr_ptr_enable, observed_item.ghr_ptr_enable_pre);
	check_logic_value({context_name, " recovery_pre"}, reference_model.previous_recovery_valid, observed_item.ghr_recovery_pre);

	// Check every bank enable, including cycles when all banks must be disabled.
	for (int unsigned bank_index = 0; bank_index < NUM_GHR_BANKS; bank_index++) begin
		check_logic_value($sformatf("%s bank_we_pre[%0d]", context_name, bank_index), reference_model.expected_ghr_bank_we[bank_index], observed_item.ghr_bank_we_pre[bank_index]);
	end

	// Write address and data are meaningful when a write is expected.
	if (reference_model.expected_ghr_write_enable === 1'b1) begin
		check_vector_value({context_name, " write_ptr_pre"}, folded_history_t'(reference_model.expected_ghr_write_location), folded_history_t'(observed_item.ghr_write_ptr_pre));
		check_vector_value({context_name, " write_bank_pre"}, folded_history_t'(reference_model.expected_ghr_write_location % NUM_GHR_BANKS), folded_history_t'(observed_item.ghr_write_bank_pre));
		check_vector_value({context_name, " write_row_pre"}, folded_history_t'(reference_model.expected_ghr_write_location / NUM_GHR_BANKS), folded_history_t'(observed_item.ghr_write_row_pre));
		check_vector_value({context_name, " write_data_pre"}, folded_history_t'(observed_item.br_packet_i), folded_history_t'(observed_item.ghr_write_data_pre));
	end

	// Check the incoming register on both sides of the edge.
	check_vector_value({context_name, " incoming_pre"}, folded_history_t'(reference_model.expected_ghr_incoming_packet), folded_history_t'(observed_item.ghr_incoming_packet_o));
	check_vector_value({context_name, " incoming_post"}, folded_history_t'(reference_model.expected_ghr_incoming_post), folded_history_t'(observed_item.ghr_incoming_post));

	// Check only the selected depth-2 expiring lane.
	check_vector_value({context_name, " selected_expiring_pre"}, folded_history_t'(reference_model.selected_expiring_packet), folded_history_t'(observed_item.selected_expiring_packet_o));
	check_vector_value({context_name, " selected_ghr_tap_pre"}, folded_history_t'(reference_model.selected_expiring_packet), folded_history_t'(observed_item.ghr_expiring_packets_o[SELECTED_HASH_TABLE]));

	// Compare all cells, not only the cell that should have been written.
	foreach (observed_item.ghr_memory_post[location]) begin
		check_vector_value($sformatf("%s memory_post location=%0d row=%0d bank=%0d", context_name, location, location / NUM_GHR_BANKS, location % NUM_GHR_BANKS), folded_history_t'(reference_model.ghr_memory_state[location]), folded_history_t'(observed_item.ghr_memory_post[location]));
	end

endfunction

	function void check_ghr_reset_outputs(predictor_history_sequence_item observed_item);

		check_vector_value("GHR reset head_post", folded_history_t'(0), folded_history_t'(observed_item.ghr_head_post));
		check_vector_value("GHR reset incoming_post", folded_history_t'(0), folded_history_t'(observed_item.ghr_incoming_post));

		foreach (observed_item.ghr_memory_post[location]) begin
			check_vector_value($sformatf("GHR reset memory_post location=%0d row=%0d bank=%0d", location, location / NUM_GHR_BANKS, location % NUM_GHR_BANKS), folded_history_t'(0), folded_history_t'(observed_item.ghr_memory_post[location]));
		end

	endfunction
	
	function void check_reset_outputs(predictor_history_sequence_item observed_item);
		check_logic_value("reset fifo_empty_o", 1'b1, observed_item.fifo_empty_o);
		check_logic_value("reset fifo_full_o", 1'b0, observed_item.fifo_full_o);
		check_logic_value("reset recovery_active_o", 1'b0, observed_item.recovery_active_o);
		if(observed_item.br_valid_i === 1'b1) begin
			check_vector_value("folded_history_state_o", reference_model.folded_history_current_expected, observed_item.folded_history_state_o);
		end	
	//	check_vector_value("reset folded_history_state_o", folded_history_t'('0), observed_item.folded_history_state_o);
		check_vector_value("reset recovery_folded_history_o", folded_history_t'('0), observed_item.recovery_folded_history_o);

		reference_model.predict_hash_outputs(observed_item);
		check_vector_value("reset tagged_index_o", folded_history_t'(reference_model.expected_tagged_index), folded_history_t'(observed_item.tagged_index_o));
		check_vector_value("reset tagged_tag_o", folded_history_t'(reference_model.expected_tagged_tag), folded_history_t'(observed_item.tagged_tag_o));
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



/// predictor coverage
class predictor_history_coverage extends uvm_subscriber #(predictor_history_sequence_item);

	`uvm_component_utils(predictor_history_coverage)

	int unsigned covered_cycle_count;
	int unsigned reset_cycle_count;
	int unsigned skipped_unknown_cycle_count;

	covergroup predictor_cg with function sample(predictor_history_sequence_item t);

		option.per_instance = 1;

		cp_enable: coverpoint t.en_i {
			bins disabled = {0};
			bins enabled = {1};
		}

		cp_branch: coverpoint t.br_valid_i {
			bins low = {0};
			bins high = {1};
		}

		cp_commit: coverpoint t.branch_commit_i {
			bins low = {0};
			bins high = {1};
		}

		cp_misprediction: coverpoint t.misprediction_i {
			bins low = {0};
			bins high = {1};
		}

		cp_recovery_before: coverpoint t.ghr_recovery_pre {
			bins inactive = {0};
			bins active = {1};
		}

		cp_recovery_after: coverpoint t.recovery_active_o {
			bins inactive = {0};
			bins active = {1};
		}

		// Actual FIFO flags after the edge, not an internal occupancy measurement.
		cp_fifo_state: coverpoint {t.fifo_full_o, t.fifo_empty_o} {
			bins interior = {2'b00};
			bins empty = {2'b01};
			bins full = {2'b10};
			illegal_bins inconsistent = {2'b11};
		}

		cp_packet: coverpoint t.br_packet_i iff (t.en_i && t.br_valid_i && !t.ghr_recovery_pre) {
			bins zero = {0};
			bins all_ones = {branch_packet_t'('1)};
			bins other_packets = {[1:((2**PKT_WIDTH)-2)]};
		}

		// PC contribution to the post-edge combinational hash outputs.
		cp_pc_word: coverpoint t.load_pc_i[31:2] iff (t.en_i && (t.br_valid_i || t.recovery_active_o)) {
			bins zero = {0};
			bins small_words[] = {[1:7]};
			bins tag_shift3_range = {[8:31]};
			bins index_shift5_range = {[32:127]};
			bins tag_shift7_range = {[128:30'h3fffffff]};
		}

		cp_pc_low_bits: coverpoint t.load_pc_i[1:0] iff (t.en_i && (t.br_valid_i || t.recovery_active_o)) {
			bins offsets[] = {[0:3]};
		}

		cp_index: coverpoint t.tagged_index_o iff (t.en_i && (t.br_valid_i || t.recovery_active_o)) {
			bins zero = {0};
			bins maximum = {tagged_index_t'('1)};
			bins other_indices = {[1:((2**S_WIDTH)-2)]};
		}

		cp_tag: coverpoint t.tagged_tag_o iff (t.en_i && (t.br_valid_i || t.recovery_active_o)) {
			bins zero = {0};
			bins maximum = {tagged_tag_t'('1)};
			bins other_tags = {[1:((2**T_WIDTH)-2)]};
		}

		cp_write_bank: coverpoint t.ghr_write_bank_pre iff (t.ghr_bank_we_pre != '0) {
			bins banks[] = {[0:NUM_GHR_BANKS-1]};
		}

		cp_write_row: coverpoint t.ghr_write_row_pre iff (t.ghr_bank_we_pre != '0) {
			bins rows[] = {[0:GHR_ENTRIES_PER_BANK-1]};
		}

		// A rollback crosses the circular boundary when head is below the requested depth.
		cp_rollback_wrap: coverpoint (t.ghr_head_pre < t.mispredicted_table_depth_i) iff (t.en_i && t.misprediction_i) {
			bins no_wrap = {0};
			bins wraps = {1};
		}

		cp_forward_wrap: coverpoint (t.ghr_head_pre == GHR_MAX_PTR-1) iff (t.en_i && t.br_valid_i && !t.ghr_recovery_pre && !t.misprediction_i) {
			bins no_wrap = {0};
			bins wraps = {1};
		}

		cx_enable_branch: cross cp_enable, cp_branch;
		cx_requests: cross cp_branch, cp_commit, cp_misprediction iff (t.en_i);
		cx_recovery_enable_branch: cross cp_recovery_before, cp_enable, cp_branch;
		cx_recovery_transition: cross cp_recovery_before, cp_recovery_after;
		cx_bank_row: cross cp_write_bank, cp_write_row;

	endgroup

	function new(string name = "predictor_history_coverage", uvm_component parent = null);

		super.new(name, parent);

		predictor_cg = new();
		covered_cycle_count = 0;
		reset_cycle_count = 0;
		skipped_unknown_cycle_count = 0;

	endfunction

	function void write(predictor_history_sequence_item t);

		if (t.rst_n === 1'b0) begin
			reset_cycle_count++;
			return;
		end

		if (t.rst_n !== 1'b1) begin
			skipped_unknown_cycle_count++;
			return;
		end

		if ($isunknown({t.en_i, t.br_valid_i, t.branch_commit_i, t.misprediction_i, t.ghr_recovery_pre, t.recovery_active_o, t.fifo_full_o, t.fifo_empty_o, t.ghr_bank_we_pre})) begin
			skipped_unknown_cycle_count++;
			`uvm_warning("COVERAGE_UNKNOWN_CONTROL", $sformatf("Skipping coverage sample at monitor_cycle=%0d time=%0t because a control/status signal is unknown; scoreboard checking is unchanged", t.cycle_number, t.sample_time))
			return;
		end

		predictor_cg.sample(t);
		covered_cycle_count++;

	endfunction

	function void report_phase(uvm_phase phase);

		string coverage_report;

		super.report_phase(phase);

		coverage_report = "\n======================================================================";
		coverage_report = {coverage_report, "\n                 FINAL FUNCTIONAL COVERAGE REPORT"};
		coverage_report = {coverage_report, "\n======================================================================"};

		coverage_report = {coverage_report, $sformatf("\nCollector               : %s", get_full_name())};
		coverage_report = {coverage_report, $sformatf("\nSampled cycles          : %0d", covered_cycle_count)};
		coverage_report = {coverage_report, $sformatf("\nReset cycles            : %0d", reset_cycle_count)};
		coverage_report = {coverage_report, $sformatf("\nSkipped unknown cycles  : %0d", skipped_unknown_cycle_count)};
		coverage_report = {coverage_report, $sformatf("\nOverall coverage        : %6.2f%%", predictor_cg.get_inst_coverage())};

		coverage_report = {coverage_report, "\n----------------------------------------------------------------------"};
		coverage_report = {coverage_report, "\nCONTROL COVERPOINTS"};
		coverage_report = {coverage_report, $sformatf("\n  Global enable         : %6.2f%%", predictor_cg.cp_enable.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Branch valid          : %6.2f%%", predictor_cg.cp_branch.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Branch commit         : %6.2f%%", predictor_cg.cp_commit.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Misprediction         : %6.2f%%", predictor_cg.cp_misprediction.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Recovery before edge  : %6.2f%%", predictor_cg.cp_recovery_before.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Recovery after edge   : %6.2f%%", predictor_cg.cp_recovery_after.get_inst_coverage())};

		coverage_report = {coverage_report, "\n----------------------------------------------------------------------"};
		coverage_report = {coverage_report, "\nFIFO AND DATA COVERPOINTS"};
		coverage_report = {coverage_report, $sformatf("\n  FIFO state            : %6.2f%%", predictor_cg.cp_fifo_state.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Branch packet         : %6.2f%%", predictor_cg.cp_packet.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  PC word               : %6.2f%%", predictor_cg.cp_pc_word.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  PC low bits           : %6.2f%%", predictor_cg.cp_pc_low_bits.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Hash index            : %6.2f%%", predictor_cg.cp_index.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Hash tag              : %6.2f%%", predictor_cg.cp_tag.get_inst_coverage())};

		coverage_report = {coverage_report, "\n----------------------------------------------------------------------"};
		coverage_report = {coverage_report, "\nGHR COVERPOINTS"};
		coverage_report = {coverage_report, $sformatf("\n  Write bank            : %6.2f%%", predictor_cg.cp_write_bank.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Write row             : %6.2f%%", predictor_cg.cp_write_row.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Rollback wrap         : %6.2f%%", predictor_cg.cp_rollback_wrap.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Forward wrap          : %6.2f%%", predictor_cg.cp_forward_wrap.get_inst_coverage())};

		coverage_report = {coverage_report, "\n----------------------------------------------------------------------"};
		coverage_report = {coverage_report, "\nCROSS COVERAGE"};
		coverage_report = {coverage_report, $sformatf("\n  Enable x branch                  : %6.2f%%", predictor_cg.cx_enable_branch.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Branch x commit x misprediction  : %6.2f%%", predictor_cg.cx_requests.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Recovery x enable x branch       : %6.2f%%", predictor_cg.cx_recovery_enable_branch.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Recovery before x after          : %6.2f%%", predictor_cg.cx_recovery_transition.get_inst_coverage())};
		coverage_report = {coverage_report, $sformatf("\n  Bank x row                       : %6.2f%%", predictor_cg.cx_bank_row.get_inst_coverage())};

		coverage_report = {coverage_report, "\n======================================================================"};

		`uvm_info("FINAL_FUNCTIONAL_COVERAGE", coverage_report, UVM_NONE)

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
	predictor_history_coverage coverage_collector;

	function new(string name = "predictor_history_env", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		agent = predictor_history_agent::type_id::create("agent", this);
		scoreboard = predictor_history_scoreboard::type_id::create("scoreboard", this);
		coverage_collector = predictor_history_coverage::type_id::create("coverage_collector", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		agent.monitor.analysis_port.connect(scoreboard.analysis_export);
		agent.monitor.analysis_port.connect(coverage_collector.analysis_export);
	endfunction

endclass


//`include "TB_Combine_wrapper_ghr_fifo_hash_other_components.sv"

/// test class
class predictor_history_base_test extends uvm_test;

`uvm_component_utils(predictor_history_base_test)

predictor_history_env env;

function new(string name = "predictor_history_base_test", uvm_component parent = null);
	super.new(name, parent);
endfunction

function void build_phase(uvm_phase phase);
	super.build_phase(phase);

	uvm_config_db #(uvm_active_passive_enum)::set(this, "env.agent", "is_active", UVM_ACTIVE);
	env = predictor_history_env::type_id::create("env", this);
endfunction

function void end_of_elaboration_phase(uvm_phase phase);
	super.end_of_elaboration_phase(phase);
	uvm_top.print_topology();
endfunction


task run_phase(uvm_phase phase);
	predictor_history_smoke_sequence smoke_sequence;
	predictor_history_startup_reset_sequence reset_sequence;
	predictor_history_populated_reset_sequence populated_reset_sequence;
	predictor_history_reset_while_disabled_sequence reset_while_disabled;
	predictor_history_repeated_resets_sequence repeated_resets_sequence;
	predictor_history_branch_valid_toggle_sequence valid_toggle_seq;
	predictor_history_global_enable_toggle_sequence valid_enable_toggle_seq;
	predictor_history_prefill_enable_toggle_sequence toggle_with_data;
	predictor_history_enable_valid_combinations_sequence enable_br_valid_combinations;
	predictor_history_fifo_single_write_sequence single_write_fifo_sequence;
	predictor_history_fifo_read_sequence  read_sequence;
	predictor_history_fifo_fill_to_full_sequence fifo_full_seq;
	predictor_history_fifo_write_while_full_sequence fifo_write_while_full;
	predictor_history_fifo_drain_to_empty_sequence drain_2_empty_seq;
	predictor_history_fifo_read_while_empty_sequence fifo_read_while_empty_seq;
	predictor_history_fifo_simultaneous_read_write_sequence fifo_simultaneous_read_write_seq;
	predictor_history_fifo_random_bursts_sequence random_rd_wr_bursts;
	predictor_history_fifo_full_read_write_sequence read_write_on_fifo_full_seq;
	predictor_history_fifo_empty_read_write_sequence read_write_on_fifo_empty_seq;
	predictor_history_fifo_pointer_wraparound_sequence fifo_wrap_around_seq;
	predictor_history_fifo_repeated_fill_drain_sequence fifo_repeated_fill_drain_seq;
	predictor_history_checkpoint_data_ordering_sequence checkpt_data_order_seq;
	predictor_history_ghr_packet_patterns_sequence ghr_packets_seq;
	predictor_history_depth2_transition_sequence ghr_depth2_seq;
	predictor_history_depth2_bank_row_sequence all_the_way_fr_GHR_depth2;
	predictor_history_depth2_wraparound_sequence GHR_depth2_wraparound;
	predictor_history_depth2_fold_arithmetic_sequence HASH_depth2_fold_arithematic;
	predictor_history_depth2_pc_mixing_sequence HASH_depth2_PC_mix_seq;
	predictor_history_depth2_basic_recovery_sequence depth2_misp_recover_seq;
	predictor_history_depth2_empty_recovery_sequence depth2_empty_FIFO_misp_recovery_seq;
	predictor_history_depth2_full_recovery_sequence depth2_full_FIFO_misp_recovery_seq;
	predictor_history_depth2_branch_during_recovery_sequence depth2_valid_branch_recover_seq;
	predictor_history_depth2_disabled_recovery_sequence depth2_global_enable_low_during_recover_Seq;
	predictor_history_depth2_commit_misprediction_sequence commit_misp_together_seq;
	predictor_history_depth2_branch_misprediction_sequence br_valid_mispred_same_cycle;
	predictor_history_depth2_back_to_back_recovery_sequence back2back_misp_no_branch_write;
	predictor_history_depth2_recovery_resume_sequence depth2_repeated_recovery_then_new_branches;
	predictor_history_depth2_wrap_recovery_sequence GHR_rollback_across_buffer_boundary;
	predictor_history_depth2_mixed_random_sequence mixed_random_seq;
	predictor_history_depth2_reset_during_recovery_sequence reset_during_recovery;


	phase.raise_objection(this, "Starting predictor-history sequence");

/*
	smoke_sequence = predictor_history_smoke_sequence::type_id::create("smoke_sequence");
	run_sequence(smoke_sequence);
	#(2 * CLK_PERIOD);


	reset_sequence = predictor_history_startup_reset_sequence::type_id::create("reset_sequence");
	run_sequence(reset_sequence);
	#(2 * CLK_PERIOD);


	populated_reset_sequence = predictor_history_populated_reset_sequence::type_id::create("populated_reset_sequence");
	run_sequence(populated_reset_sequence);
	#(2 * CLK_PERIOD)

	
	reset_while_disabled = predictor_history_reset_while_disabled_sequence::type_id::create("reset_while_disabled");
	run_sequence(reset_while_disabled);
	#(2 * CLK_PERIOD)

	
	repeated_resets_sequence = predictor_history_repeated_resets_sequence::type_id::create("repeated_resets_sequence");
	run_sequence(repeated_resets_sequence);
	#(2 * CLK_PERIOD)	

		
	valid_toggle_seq = predictor_history_branch_valid_toggle_sequence::type_id::create("valid_toggle_seq");
	run_sequence(valid_toggle_seq);
	#(2 * CLK_PERIOD)	

	
	valid_enable_toggle_seq = predictor_history_global_enable_toggle_sequence::type_id::create("valid_enable_toggle_seq");
	run_sequence(valid_enable_toggle_seq);
	#(2 * CLK_PERIOD)

	
	toggle_with_data = predictor_history_prefill_enable_toggle_sequence::type_id::create("toggle_with_data");
	run_sequence(toggle_with_data);
	#(2 * CLK_PERIOD)

	
	enable_br_valid_combinations = predictor_history_enable_valid_combinations_sequence::type_id::create("enable_br_valid_combinations");
	run_sequence(enable_br_valid_combinations);
	#(2 * CLK_PERIOD)


	single_write_fifo_sequence = predictor_history_fifo_single_write_sequence::type_id::create("single_write_fifo_sequence");
	run_sequence(single_write_fifo_sequence);
	#(2 * CLK_PERIOD)	


	fifo_full_seq = predictor_history_fifo_fill_to_full_sequence::type_id::create("fifo_full_seq");
	run_sequence(fifo_full_seq);
	#(2 * CLK_PERIOD)	


	fifo_write_while_full = predictor_history_fifo_write_while_full_sequence::type_id::create("fifo_write_while_full");
	run_sequence(fifo_write_while_full);
	#(2 * CLK_PERIOD)	

	
	drain_2_empty_seq = predictor_history_fifo_drain_to_empty_sequence::type_id::create("drain_2_empty_seq");
	run_sequence(drain_2_empty_seq);
	#(2 * CLK_PERIOD)


	fifo_read_while_empty_seq = predictor_history_fifo_read_while_empty_sequence::type_id::create("fifo_read_while_empty_seq");
	run_sequence(fifo_read_while_empty_seq);
	#(2 * CLK_PERIOD)


	fifo_simultaneous_read_write_seq = predictor_history_fifo_simultaneous_read_write_sequence::type_id::create("fifo_simultaneous_read_write_seq");
	run_sequence(fifo_simultaneous_read_write_seq);
	#(2 * CLK_PERIOD)

	
	random_rd_wr_bursts = predictor_history_fifo_random_bursts_sequence::type_id::create("random_rd_wr_bursts");
	run_sequence(random_rd_wr_bursts);
	#(2 * CLK_PERIOD)


	read_write_on_fifo_full_seq = predictor_history_fifo_full_read_write_sequence::type_id::create("read_write_on_fifo_full_seq");
	run_sequence(read_write_on_fifo_full_seq);
	#(2 * CLK_PERIOD)


	read_write_on_fifo_empty_seq = predictor_history_fifo_empty_read_write_sequence::type_id::create("read_write_on_fifo_empty_seq");
	run_sequence(read_write_on_fifo_empty_seq);
	#(2 * CLK_PERIOD)


	fifo_wrap_around_seq = predictor_history_fifo_pointer_wraparound_sequence::type_id::create("fifo_wrap_around_seq");
	run_sequence(fifo_wrap_around_seq);
	#(2 * CLK_PERIOD)	
*/
/*
	fifo_repeated_fill_drain_seq = predictor_history_fifo_repeated_fill_drain_sequence::type_id::create("fifo_repeated_fill_drain_seq");
	run_sequence(fifo_repeated_fill_drain_seq);
	#(2 * CLK_PERIOD)	
/*
/*
	checkpt_data_order_seq = predictor_history_checkpoint_data_ordering_sequence::type_id::create("checkpt_data_order_seq");
	run_sequence(checkpt_data_order_seq);
	#(2 * CLK_PERIOD)	


	ghr_packets_seq = predictor_history_ghr_packet_patterns_sequence::type_id::create("ghr_packets_seq");
	run_sequence(ghr_packets_seq);
	#(2 * CLK_PERIOD)	


	ghr_depth2_seq = predictor_history_depth2_transition_sequence::type_id::create("ghr_depth2_seq");
	run_sequence(ghr_depth2_seq);
	#(2 * CLK_PERIOD)	

	all_the_way_fr_GHR_depth2 = predictor_history_depth2_bank_row_sequence::type_id::create("all_the_way_fr_GHR_depth2");
	run_sequence(all_the_way_fr_GHR_depth2);
	#(2 * CLK_PERIOD)	

	
	GHR_depth2_wraparound = predictor_history_depth2_wraparound_sequence::type_id::create("GHR_depth2_wraparound");
	run_sequence(GHR_depth2_wraparound);
	#(2 * CLK_PERIOD)


	HASH_depth2_fold_arithematic = predictor_history_depth2_fold_arithmetic_sequence::type_id::create("HASH_depth2_fold_arithematic");
	run_sequence(HASH_depth2_fold_arithematic);
	#(2 * CLK_PERIOD)


	HASH_depth2_PC_mix_seq = predictor_history_depth2_pc_mixing_sequence::type_id::create("HASH_depth2_PC_mix_seq");
	run_sequence(HASH_depth2_PC_mix_seq);
	#(2 * CLK_PERIOD)

	
	depth2_misp_recover_seq = predictor_history_depth2_basic_recovery_sequence::type_id::create("depth2_misp_recover_seq");
	run_sequence(depth2_misp_recover_seq);
	#(2 * CLK_PERIOD)
	

	depth2_empty_FIFO_misp_recovery_seq = predictor_history_depth2_empty_recovery_sequence::type_id::create("depth2_empty_FIFO_misp_recovery_seq");
	run_sequence(depth2_empty_FIFO_misp_recovery_seq);
	#(2 * CLK_PERIOD)


	depth2_full_FIFO_misp_recovery_seq = predictor_history_depth2_full_recovery_sequence::type_id::create("depth2_full_FIFO_misp_recovery_seq");
	run_sequence(depth2_full_FIFO_misp_recovery_seq);
	#(2 * CLK_PERIOD)


	depth2_valid_branch_recover_seq = predictor_history_depth2_branch_during_recovery_sequence::type_id::create("depth2_valid_branch_recover_seq");
	run_sequence(depth2_valid_branch_recover_seq);
	#(2 * CLK_PERIOD)


	depth2_global_enable_low_during_recover_Seq = predictor_history_depth2_disabled_recovery_sequence::type_id::create("depth2_global_enable_low_during_recover_Seq");
	run_sequence(depth2_global_enable_low_during_recover_Seq);
	#(2 * CLK_PERIOD)

	
	commit_misp_together_seq = predictor_history_depth2_commit_misprediction_sequence::type_id::create("commit_misp_together_seq");
	run_sequence(commit_misp_together_seq);
	#(2 * CLK_PERIOD)

	br_valid_mispred_same_cycle = predictor_history_depth2_branch_misprediction_sequence::type_id::create("br_valid_mispred_same_cycle");
	run_sequence(br_valid_mispred_same_cycle);
	#(2 * CLK_PERIOD)


	back2back_misp_no_branch_write = predictor_history_depth2_back_to_back_recovery_sequence::type_id::create("back2back_misp_no_branch_write");
	run_sequence(back2back_misp_no_branch_write);
	#(2 * CLK_PERIOD)


	depth2_repeated_recovery_then_new_branches = predictor_history_depth2_recovery_resume_sequence::type_id::create("depth2_repeated_recovery_then_new_branches");
	run_sequence(depth2_repeated_recovery_then_new_branches);
	#(2 * CLK_PERIOD)


	GHR_rollback_across_buffer_boundary = predictor_history_depth2_wrap_recovery_sequence::type_id::create("GHR_rollback_across_buffer_boundary");
	run_sequence(GHR_rollback_across_buffer_boundary);
	#(2 * CLK_PERIOD)


	mixed_random_seq = predictor_history_depth2_mixed_random_sequence::type_id::create("mixed_random_seq");
	run_sequence(mixed_random_seq);
	#(2 * CLK_PERIOD)
*/

	reset_during_recovery = predictor_history_depth2_reset_during_recovery_sequence::type_id::create("reset_during_recovery");
	run_sequence(reset_during_recovery);
	#(2 * CLK_PERIOD)
	

	phase.drop_objection(this, "Completed predictor-history sequence");
endtask

virtual task run_sequence(uvm_sequence #(predictor_history_sequence_item) sequence_handle);
	if (sequence_handle == null) begin
		`uvm_fatal(get_type_name(), "A null sequence handle was passed to run_sequence")
	end

	sequence_handle.start(env.agent.sequencer);
endtask

endclass

/// tb top
module predictor_history_tb_top;

import uvm_pkg::*;
import predictor_history_tb_params_pkg::*;

logic clk;

predictor_history_if tb_if(clk);

/// connecting the observation to exisitng GHR instance
// Read-only testbench probes into the existing GHR instance.
assign tb_if.ghr_head_pre = dut.u_ghr.head_ptr;
assign tb_if.ghr_head_post = dut.u_ghr.head_ptr;
assign tb_if.ghr_next_head_pre = dut.u_ghr.next_head_ptr;
assign tb_if.ghr_write_ptr_pre = dut.u_ghr.write_ptr;
assign tb_if.ghr_write_bank_pre = dut.u_ghr.write_bank;
assign tb_if.ghr_write_row_pre = dut.u_ghr.write_row;
assign tb_if.ghr_ptr_enable_pre = dut.u_ghr.ptr_update_en;
assign tb_if.ghr_recovery_pre = tb_if.recovery_active_o;
assign tb_if.ghr_write_data_pre = dut.u_ghr.br_packet_i_gated;
assign tb_if.ghr_incoming_post = tb_if.ghr_incoming_packet_o;

generate
	for (genvar bank_index = 0; bank_index < NUM_GHR_BANKS; bank_index++) begin : gen_ghr_debug_enable
		assign tb_if.ghr_bank_we_pre[bank_index] = dut.u_ghr.bank_we[bank_index];
	end

	for (genvar location = 0; location < GHR_MAX_PTR; location++) begin : gen_ghr_debug_memory
		assign tb_if.ghr_memory_post[location] = dut.u_ghr.bank_mem[location / NUM_GHR_BANKS][location % NUM_GHR_BANKS];
	end
endgenerate

initial begin
	if (GHR_MAX_PTR != dut.u_ghr.MAX_PTR || NUM_GHR_BANKS != dut.u_ghr.NUM_BANKS || GHR_ENTRIES_PER_BANK != dut.u_ghr.ENTRIES_PER_BANK) $fatal(1, "GHR debug geometry does not match the DUT");
	if (GHR_MAX_PTR != NUM_GHR_BANKS * GHR_ENTRIES_PER_BANK) $fatal(1, "GHR debug memory mapping requires a complete bank array");
	if (SELECTED_HISTORY_DEPTH != 2) $fatal(1, "Independent GHR packet-selection checking is scoped to depth 2");
end

predictor_history_single_hash_wrapper #(
	.PKT_WIDTH(PKT_WIDTH),
	.NUM_GHR_PACKETS(NUM_GHR_PACKETS),
	.S_WIDTH(S_WIDTH),
	.T_WIDTH(T_WIDTH),
	.FIFO_DEPTH(FIFO_DEPTH),
	.SELECTED_HASH_TABLE(SELECTED_HASH_TABLE)
) dut (
	.clk(clk),
	.rst_n(tb_if.rst_n),
	.en_i(tb_if.en_i),
	.br_valid_i(tb_if.br_valid_i),
	.br_packet_i(tb_if.br_packet_i),
	.load_pc_i(tb_if.load_pc_i),
	.branch_commit_i(tb_if.branch_commit_i),
	.misprediction_i(tb_if.misprediction_i),
	.mispredicted_table_depth_i(tb_if.mispredicted_table_depth_i),
	.tagged_index_o(tb_if.tagged_index_o),
	.tagged_tag_o(tb_if.tagged_tag_o),
	.fifo_full_o(tb_if.fifo_full_o),
	.fifo_empty_o(tb_if.fifo_empty_o),
	.recovery_active_o(tb_if.recovery_active_o),
	.ghr_incoming_packet_o(tb_if.ghr_incoming_packet_o),
	.ghr_expiring_packets_o(tb_if.ghr_expiring_packets_o),
	.selected_expiring_packet_o(tb_if.selected_expiring_packet_o),
	.folded_history_state_o(tb_if.folded_history_state_o),
	.recovery_folded_history_o(tb_if.recovery_folded_history_o)
);

initial begin
	clk = 1'b0;
	forever #(CLK_PERIOD / 2) clk = ~clk;
end

/*
initial begin
	tb_if.rst_n = 1'b0;
	repeat (RESET_ACTIVE_CYCLES) @(posedge clk);
	tb_if.rst_n <= 1'b1;
end
*/

initial begin
	uvm_config_db #(virtual predictor_history_if)::set(null, "uvm_test_top.env.agent.*", "vif", tb_if);
	run_test("predictor_history_base_test");
end

endmodule
