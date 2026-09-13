package tagged_table_hash_param_pkg;

	parameter int PKT_WIDTH  = 7;
	parameter int NUM_TAGGED = 7;
	parameter int S_WIDTH    = 7;
	parameter int T_WIDTH    = 16;

	parameter int CSR_WIDTH = S_WIDTH + T_WIDTH;

	parameter int PC_WIDTH      = 32;
	parameter int PC_WORD_WIDTH = 30;

	parameter int DEPTHS [0:NUM_TAGGED-1] = '{
		2,
		4,
		6,
		8,
		12,
		16,
		32
	};

endpackage

import uvm_pkg::*;
`include "uvm_macros.svh"
import tagged_table_hash_param_pkg::*;


interface tagged_table_hash_if #(
  parameter int PKT_WIDTH  = 7,
  parameter int NUM_TAGGED = 7,
  parameter int S_WIDTH    = 7,
  parameter int T_WIDTH    = 16
) (
  input logic clk
);

	logic rst_n;
	logic en_i;
	logic br_valid_i;

	logic [PKT_WIDTH-1:0] incoming_pkt_i;
	logic [PKT_WIDTH-1:0] expiring_pkts_i [0:NUM_TAGGED-1];
	logic [31:0]          load_pc_i;

	logic [S_WIDTH-1:0] tagged_indices_o [0:NUM_TAGGED-1];
	logic [T_WIDTH-1:0] tagged_tags_o    [0:NUM_TAGGED-1];

	clocking drv_cb @(negedge clk);
		output en_i;
		output br_valid_i;
		output incoming_pkt_i;
		output expiring_pkts_i;
		output load_pc_i;
	endclocking

	clocking mon_cb @(posedge clk);
		input rst_n;
		input en_i;
		input br_valid_i;
		input incoming_pkt_i;
		input expiring_pkts_i;
		input load_pc_i;
		input tagged_indices_o;
		input tagged_tags_o;
	endclocking

	modport DUT_MP (
		input  clk,
		input  rst_n,
		input  en_i,
		input  br_valid_i,
		input  incoming_pkt_i,
		input  expiring_pkts_i,
		input  load_pc_i,

		output tagged_indices_o,
		output tagged_tags_o
	);

	modport DRV_MP (
		clocking drv_cb,
		input    clk,
		input    rst_n
	);


	modport MON_MP (
		clocking mon_cb,
		input    clk
	);

	// Reset and control signals must never contain X/Z.
	property controls_are_known_p;
		@(posedge clk) !$isunknown({rst_n,en_i,br_valid_i});
	endproperty

	controls_are_known_a:
		assert property (controls_are_known_p)
		else  $error("rst_n, en_i, or br_valid_i contains X/Z");

	property active_scalar_inputs_are_known_p;
		@(posedge clk) disable iff (!rst_n) (en_i && br_valid_i) |-> !$isunknown({incoming_pkt_i,load_pc_i});
	endproperty

	active_scalar_inputs_are_known_a:
		assert property (active_scalar_inputs_are_known_p)
		else  $error("Active request contains X/Z in incoming_pkt_i or load_pc_i");

	// Assertions for each tagged table.
	generate

		for (genvar i = 0; i < NUM_TAGGED; i++) begin

		property active_expiring_packet_is_known_p;
			@(posedge clk) disable iff (!rst_n) (en_i && br_valid_i) |-> !$isunknown(expiring_pkts_i[i]);
		endproperty

		active_expiring_packet_is_known_a:
			assert property (active_expiring_packet_is_known_p)
			else  $error("Active request has X/Z in expiring_pkts_i[%0d]",i);

		// Index and tag outputs must be known during an active request.
		property active_outputs_are_known_p;
			@(posedge clk) disable iff (!rst_n)(en_i && br_valid_i) |-> !$isunknown({tagged_indices_o[i],tagged_tags_o[i]});
		endproperty

		active_outputs_are_known_a:
			assert property (active_outputs_are_known_p)
			else  $error("Hash outputs contain X/Z for tagged table %0d",i);

		property outputs_hold_while_inactive_p;
			@(posedge clk) disable iff (!rst_n)
			(!(en_i && br_valid_i) && !$past(en_i && br_valid_i)) |-> $stable({tagged_indices_o[i],tagged_tags_o[i]});
		endproperty

		outputs_hold_while_inactive_a:
			assert property (outputs_hold_while_inactive_p)
			else  $error("Hash outputs changed during sustained inactivity for table %0d",i);

		end

	endgenerate

endinterface


// sequence item
class tagged_table_hash_item extends uvm_sequence_item;

	localparam int PKT_WIDTH  = 7;
	localparam int NUM_TAGGED = 7;
	localparam int S_WIDTH    = 7;
	localparam int T_WIDTH    = 16;

	rand bit en;
	rand bit br_valid;
	rand bit [PKT_WIDTH-1:0] incoming_pkt;
	rand bit [PKT_WIDTH-1:0] expiring_pkts [0:NUM_TAGGED-1];
	rand bit [31:0]          load_pc;

	logic [S_WIDTH-1:0] observed_indices [0:NUM_TAGGED-1];
	logic [T_WIDTH-1:0] observed_tags    [0:NUM_TAGGED-1];

	constraint enable_distribution_c {
		en dist {
		1'b1 := 75,
		1'b0 := 25
		};
	}

	constraint branch_valid_distribution_c {
		br_valid dist {
		1'b1 := 70,
		1'b0 := 30
		};
	}

	`uvm_object_utils_begin(tagged_table_hash_item)

		`uvm_field_int(en,           UVM_ALL_ON)
		`uvm_field_int(br_valid,     UVM_ALL_ON)
		`uvm_field_int(incoming_pkt, UVM_ALL_ON)
		`uvm_field_int(load_pc,      UVM_ALL_ON)

		`uvm_field_sarray_int(expiring_pkts,   UVM_ALL_ON)
		`uvm_field_sarray_int(observed_indices, UVM_ALL_ON)
		`uvm_field_sarray_int(observed_tags,    UVM_ALL_ON)

	`uvm_object_utils_end


	function new(string name = "tagged_table_hash_item");
		super.new(name);
	endfunction

	function bit is_active_request();
		return en && br_valid;
	endfunction

	function string convert2string();

		string message;
		message = $sformatf("en=%0b br_valid=%0b incoming_pkt=0x%0h load_pc=0x%08h",en,br_valid,incoming_pkt,load_pc);

		foreach (expiring_pkts[i]) begin
			message = {message,$sformatf(" expiring_pkt[%0d]=0x%0h",i,expiring_pkts[i])};
		end

		foreach (observed_indices[i]) begin
			message = {message,$sformatf(" table[%0d]={index:0x%0h tag:0x%0h}",i,observed_indices[i],observed_tags[i])};
		end

		return message;

	endfunction

endclass


// base sequence

class tagged_table_hash_base_seq extends uvm_sequence #(tagged_table_hash_item);

	`uvm_object_utils(tagged_table_hash_base_seq)

	localparam int PKT_WIDTH  = 7;
	localparam int NUM_TAGGED = 7;

	function new(string name = "tagged_table_hash_base_seq");
		super.new(name);
	endfunction

	task send_cycle(
		input bit                 en,
		input bit                 br_valid,
		input bit [PKT_WIDTH-1:0] incoming_pkt,
		input bit [PKT_WIDTH-1:0] expiring_pkt_values
										[0:NUM_TAGGED-1],
		input bit [31:0]          load_pc
	);

		tagged_table_hash_item tr;

		tr = tagged_table_hash_item::type_id::create("tr");
		start_item(tr);
		tr.en           = en;
		tr.br_valid     = br_valid;
		tr.incoming_pkt = incoming_pkt;
		tr.load_pc      = load_pc;
	
		foreach (tr.expiring_pkts[i]) begin
			tr.expiring_pkts[i] = expiring_pkt_values[i];
		end

		finish_item(tr);

	endtask

	// Both enables are asserted, so the folded histories update.
	task active_cycle(
		input bit [PKT_WIDTH-1:0] incoming_pkt,
		input bit [PKT_WIDTH-1:0] expiring_pkt_values
										[0:NUM_TAGGED-1],
		input bit [31:0]          load_pc
	);
		send_cycle(
			.en                    (1'b1),
			.br_valid              (1'b1),
			.incoming_pkt          (incoming_pkt),
			.expiring_pkt_values   (expiring_pkt_values),
			.load_pc               (load_pc)
		);

	endtask


	// Block enabled, but no valid branch request.
	task invalid_branch_cycle();

		bit [PKT_WIDTH-1:0] zero_expiring [0:NUM_TAGGED-1];
		zero_expiring = '{default:'0};

		send_cycle(
			.en                    (1'b1),
			.br_valid              (1'b0),
			.incoming_pkt          ('0),
			.expiring_pkt_values   (zero_expiring),
			.load_pc               ('0)
		);
	endtask


	// Entire hash block disabled.
	task disabled_cycle();

		bit [PKT_WIDTH-1:0] zero_expiring [0:NUM_TAGGED-1];
		zero_expiring = '{default:'0};

		send_cycle(
			.en                    (1'b0),
			.br_valid              (1'b0),
			.incoming_pkt          ('0),
			.expiring_pkt_values   (zero_expiring),
			.load_pc               ('0)
		);
	endtask

	// random cycle
	task random_cycle(input bit en,input bit br_valid);

		bit [PKT_WIDTH-1:0] expiring_values [0:NUM_TAGGED-1];

		foreach (expiring_values[i]) begin
			expiring_values[i] = $urandom_range((2**PKT_WIDTH)-1, 0);
		end

		send_cycle(
			.en                   (en),
			.br_valid             (br_valid),
			.incoming_pkt         ($urandom_range((2**PKT_WIDTH)-1,0)),
			.expiring_pkt_values  (expiring_values),
			.load_pc              ($urandom)
		);

	endtask

	// Completely idle cycle.
	task idle_cycle();
		disabled_cycle();
	endtask

endclass


// smoke/basic sequence
class tagged_table_hash_smoke_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_smoke_seq)

	function new(string name = "tagged_table_hash_smoke_seq");
		super.new(name);
	endfunction

	task body();

		bit [PKT_WIDTH-1:0] expiring_values [0:NUM_TAGGED-1];

		`uvm_info("HASH_SMOKE_SEQ","Starting tagged-table hash smoke sequence",UVM_LOW)

		repeat (2) begin
			idle_cycle();
		end

		expiring_values = '{
			7'h01,
			7'h02,
			7'h03,
			7'h04,
			7'h05,
			7'h06,
			7'h07
		};

		active_cycle(
			.incoming_pkt(7'h15),
			.expiring_pkt_values (expiring_values),
			.load_pc(32'h0000_1000)
		);

		expiring_values = '{
			7'h10,
			7'h20,
			7'h30,
			7'h40,
			7'h50,
			7'h60,
			7'h70
		};

		active_cycle(
			.incoming_pkt(7'h2A),
			.expiring_pkt_values (expiring_values),
			.load_pc(32'h0000_2004)
		);

		invalid_branch_cycle();

		expiring_values = '{default:'1};

		active_cycle(
			.incoming_pkt        ('1),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'hFFFF_FFFC)
		);

		repeat (3) begin
			disabled_cycle();
		end

		expiring_values = '{default:'0};

		active_cycle(
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);

		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_SMOKE_SEQ","Tagged-table hash smoke sequence completed",UVM_LOW)

	endtask

endclass



// control gating sequence with random cycles - 
// turns out that the design needs around 9-11 cycles to  give totally distince indexes for each table 
class tagged_table_hash_gating_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_gating_seq)

	function new(string name = "tagged_table_hash_gating_seq");
		super.new(name);
	endfunction

	task body();

		`uvm_info("HASH_GATING_SEQ","Starting control-gating sequence",UVM_LOW)

		// Folded histories begin at zero after reset.
		repeat (2) begin
			idle_cycle();
		end

		repeat (12) begin
			random_cycle(
				.en       (1'b1),
				.br_valid (1'b1)
			);
		end

		// Testing all inactive control combinations.The random inputs continue changing, but folded history
		// must not update during any of these cycles.

		// en=0, br_valid=0
		repeat (3) begin
		random_cycle(
			.en       (1'b0),
			.br_valid (1'b0)
		);
		end

		// en=0, br_valid=1
		repeat (3) begin
		random_cycle(
			.en       (1'b0),
			.br_valid (1'b1)
		);
		end

		// en=1, br_valid=0
		repeat (3) begin
		random_cycle(
			.en       (1'b1),
			.br_valid (1'b0)
		);
		end

		// Resume valid operation. The update must start from the folded-history state preserved during inactive cycles.
		repeat (5) begin
		random_cycle(
			.en       (1'b1),
			.br_valid (1'b1)
		);
		end

		// Allow the last transaction to be sampled and checked.
		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_GATING_SEQ","Control-gating sequence completed",UVM_LOW)

	endtask

endclass


// active incoming packets request back to back
class tagged_table_hash_back_to_back_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_back_to_back_seq)

	function new(string name = "tagged_table_hash_back_to_back_seq");
		super.new(name);
	endfunction

	task body();

		int unsigned num_active_cycles;

		num_active_cycles = 20;

		`uvm_info("HASH_BACK_TO_BACK_SEQ",
				$sformatf("Starting %0d consecutive active transactions",num_active_cycles),UVM_LOW)

		// idle state for some time after reset
		repeat (2) begin
			idle_cycle();
		end

		// en = 1, b valid = 1
		for (int unsigned cycle = 0; cycle < num_active_cycles; cycle++) 
		begin

			`uvm_info("HASH_BACK_TO_BACK_SEQ",
				$sformatf("Sending active transaction %0d of %0d",cycle + 1,num_active_cycles),UVM_MEDIUM)

			random_cycle(
				.en       (1'b1),
				.br_valid (1'b1)
			);
		end


		/// send idle cycles so thatmonitor and scoreboard can check what they have
		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_BACK_TO_BACK_SEQ",
			$sformatf("Completed %0d consecutive active transactions",num_active_cycles),UVM_LOW)

	endtask

endclass




/// hold and resume sequence - to check if the block is inactive for sometime and it resumes the operation 
/// with last actvie session's folded_history table.
class tagged_table_hash_hold_resume_seq extends
	
	tagged_table_hash_base_seq;
	`uvm_object_utils(tagged_table_hash_hold_resume_seq)

	function new(string name = "tagged_table_hash_hold_resume_seq");
		super.new(name);
	endfunction

	task body();

		int unsigned build_cycles;
		int unsigned hold_cycles;
		int unsigned resume_cycles;

		build_cycles  = 13;		// this is the time it takese to genrate unique index-tag pair for each tagged tables
		hold_cycles   = 12;
		resume_cycles = 6;

		`uvm_info("HASH_HOLD_RESUME_SEQ","Starting folded-history hold-and-resume sequence",UVM_LOW)

		/// idle for some cycles at the start
		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_HOLD_RESUME_SEQ",
			$sformatf("BUILD phase: applying %0d active requests",build_cycles),UVM_LOW)

		/// build cycles = 6. build some distinct value for indeces and tags for each table
		repeat (build_cycles) begin
			random_cycle(
				.en       (1'b1),
				.br_valid (1'b1)
			);
		end

		// Hold cycle = 12. Holding the regsiter vvalues for the history
		`uvm_info("HASH_HOLD_RESUME_SEQ",
			$sformatf("HOLD phase: preserving history for %0d cycles while inputs toggle",hold_cycles),UVM_LOW)

		for (int unsigned cycle = 0; cycle < hold_cycles; cycle++) begin

			case (cycle % 3)
				0: begin
					random_cycle(
						.en       (1'b0),
						.br_valid (1'b0)
					);
				end

				1: begin
					random_cycle(
						.en       (1'b0),
						.br_valid (1'b1)
					);
				end

				2: begin
					random_cycle(
						.en       (1'b1),
						.br_valid (1'b0)
					);
				end
			endcase
		end

		// resume active operation for next few cycles
		`uvm_info("HASH_HOLD_RESUME_SEQ",
			$sformatf("RESUME phase: applying %0d active requests",resume_cycles),UVM_LOW)

		repeat (resume_cycles) begin
			random_cycle(
				.en       (1'b1),
				.br_valid (1'b1)
			);
		end

		// let it sit some time to sample and check the request buddy
		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_HOLD_RESUME_SEQ","Folded-history hold-and-resume sequence completed",UVM_LOW)
	endtask
endclass



//// incmoing packet only sequence
// Only INCOMING packet is there. rest all are ZERO
// pc_valid = '0
// expiring_packet_i = '0;
// incoming_packet_i = some valid value
// so all the calculated values inside should be identical for ALL TABLES, like shifted fold, folded history, next folded history etc. etc
class tagged_table_hash_incoming_only_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_incoming_only_seq)

	function new(string name = "tagged_table_hash_incoming_only_seq");
		super.new(name);
	endfunction

	task body();

		bit [PKT_WIDTH-1:0] zero_expiring [0:NUM_TAGGED-1];
		bit [PKT_WIDTH-1:0] incoming_value;
		int unsigned random_cycles;

		random_cycles = 12;

		for (int unsigned i = 0; i < NUM_TAGGED; i++) begin
			zero_expiring[i] = '0;
		end

		`uvm_info("HASH_INCOMING_ONLY_SEQ","Starting incoming-packet-only sequence",UVM_LOW)

		repeat (2) begin
			idle_cycle();
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_0000)
		);

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ({{(PKT_WIDTH-1){1'b0}}, 1'b1}),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_0000)
		);

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('1),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_0000)
		);


		// Alternating-bit pattern: 7'b1010101 for PKT_WIDTH=7.
		incoming_value = '0;

		for (int unsigned bit_index = 0;bit_index < PKT_WIDTH;bit_index += 2) begin
			incoming_value[bit_index] = 1'b1;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        (incoming_value),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_0000)
		);

		incoming_value = ~incoming_value;

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        (incoming_value),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_0000)
		);


		for (int unsigned bit_index = 0; bit_index < PKT_WIDTH; bit_index++) begin
			incoming_value = '0;
			incoming_value[bit_index] = 1'b1;
			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        (incoming_value),
				.expiring_pkt_values (zero_expiring),
				.load_pc             (32'h0000_0000)
			);
		end

		repeat (random_cycles) begin

			incoming_value = $urandom;
			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        (incoming_value),
				.expiring_pkt_values (zero_expiring),
				.load_pc             (32'h0000_0000)
			);

		end


		// let the final active request to be monitored.
		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_INCOMING_ONLY_SEQ","Incoming-packet-only sequence completed",UVM_LOW)

	endtask

endclass


// expiring packet only sequence
// othe incoming data packets except the expiring packets are ZERO.
// / expectations are :-
// Previous next_folded_history
//              ↓
// Current folded_history
//              ↓ rotate left by 1
// Current shifted_fold
//              ↓ XOR current aligned_expiring
// Current next_folded_history
class tagged_table_hash_expiring_only_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_expiring_only_seq)

	function new(string name = "tagged_table_hash_expiring_only_seq");
		super.new(name);
	endfunction

	task body();

		bit [PKT_WIDTH-1:0] expiring_values	[0:NUM_TAGGED-1];
		int unsigned table_index;
		int unsigned packet_index;
		int unsigned random_cycles;

		random_cycles = 10;
		`uvm_info("HASH_EXPIRING_ONLY_SEQ","Starting expiring-packet-only sequence",UVM_LOW)

		repeat (2) begin
			idle_cycle();
		end

		for (packet_index = 0; packet_index < NUM_TAGGED; packet_index++) begin
			expiring_values[packet_index] = '0;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);

		for (table_index = 0; table_index < NUM_TAGGED; table_index++) begin
			for (packet_index = 0; packet_index < NUM_TAGGED; packet_index++) begin
				expiring_values[packet_index] = '0;
			end


			expiring_values[table_index] = {{(PKT_WIDTH-1){1'b0}}, 1'b1};

			`uvm_info("HASH_EXPIRING_ONLY_SEQ",
				$sformatf("Driving expiring packet 0x%0h only into table %0d",expiring_values[table_index],table_index),UVM_MEDIUM)

			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (expiring_values),
				.load_pc             (32'h0000_0000)
			);

			for (packet_index = 0; packet_index < NUM_TAGGED; packet_index++) begin
				expiring_values[packet_index] = '0;
			end

			expiring_values[table_index] = '1;

			`uvm_info("HASH_EXPIRING_ONLY_SEQ",
				$sformatf("Driving maximum expiring packet 0x%0h only into table %0d",expiring_values[table_index],table_index),UVM_MEDIUM)

			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (expiring_values),
				.load_pc             (32'h0000_0000)
			);

		end

		// packets with only expiring packets
		repeat (random_cycles) begin

			for (packet_index = 0; packet_index < NUM_TAGGED; packet_index++) begin
				expiring_values[packet_index] = $urandom;
			end

			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (expiring_values),
				.load_pc             (32'h0000_0000)
			);

		end

		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_EXPIRING_ONLY_SEQ","Expiring-packet-only sequence completed",UVM_LOW)

	endtask

endclass



// table dePth rotation sequence
// will send same epiring packets to all the tables. but their outputs should be different because each one is using
// different value of EVICT _SHIFT
// SO, LETS CHECK THAT.
// ------------------------------------------------------------
// Table-depth rotation sequence
// ------------------------------------------------------------

class tagged_table_hash_depth_rotation_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_depth_rotation_seq)

	function new(string name = "tagged_table_hash_depth_rotation_seq");
		super.new(name);
	endfunction

	task body();

		bit [PKT_WIDTH-1:0] expiring_values	[0:NUM_TAGGED-1];
		bit [PKT_WIDTH-1:0] packet_value;
		int unsigned table_index;
		int unsigned bit_index;

		`uvm_info("HASH_DEPTH_ROTATION_SEQ","Starting table-depth rotation sequence",UVM_LOW)

		repeat (2) begin
			idle_cycle();
		end

		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			expiring_values[table_index] = '0;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);


		for (bit_index = 0;	bit_index < PKT_WIDTH; bit_index++) begin

			packet_value = '0;
			packet_value[bit_index] = 1'b1;

			for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
				expiring_values[table_index] = packet_value;
			end

			`uvm_info("HASH_DEPTH_ROTATION_SEQ",
				$sformatf("Applying expiring packet 0x%0h to all tagged tables",packet_value),UVM_MEDIUM)

			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (expiring_values),
				.load_pc             (32'h0000_0000)
			);

		end

		packet_value = '1;

		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			expiring_values[table_index] = packet_value;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);


		packet_value = '0;

		for (bit_index = 0;	bit_index < PKT_WIDTH;bit_index += 2) begin
			packet_value[bit_index] = 1'b1;
		end

		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			expiring_values[table_index] = packet_value;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);

		packet_value = ~packet_value;

		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			expiring_values[table_index] = packet_value;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);


		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_DEPTH_ROTATION_SEQ","Table-depth rotation sequence completed",UVM_LOW)

	endtask
endclass


//// Sequence to jsut check with PC hash. by keeping other inputs like incoming pckt and expiring pkt as zero
class tagged_table_hash_only_pc_seq extends	tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_only_pc_seq)

	function new(string name = "tagged_table_hash_only_pc_seq");
		super.new(name);
	endfunction

	task body();

		bit [PKT_WIDTH-1:0] zero_expiring [0:NUM_TAGGED-1];
		bit [31:0] pc_value;
		int unsigned table_index;
		int unsigned pc_bit_index;
		int unsigned random_cycle_index;
		int unsigned random_cycles;

		random_cycles = 15;

		`uvm_info("HASH_PC_HASH_SEQ","Starting PC-hash-only sequence",UVM_LOW)

		// All expiring packets remain zero for this sequence.
		for (table_index = 0; table_index < NUM_TAGGED;	table_index++) begin
			zero_expiring[table_index] = '0;
		end

		// Establish an initial idle condition.
		repeat (2) begin
			idle_cycle();
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_0000)
		);

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_0004)
		);

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h0000_1000)
		);

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h1234_5678)
		);

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'h8000_0000)
		);

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (zero_expiring),
			.load_pc             (32'hFFFF_FFFC)
		);

		for (pc_bit_index = 2; pc_bit_index < 32; pc_bit_index++) begin
			pc_value = '0;
			pc_value[pc_bit_index] = 1'b1;
			`uvm_info("HASH_PC_HASH_SEQ",
				$sformatf("Walking PC bit %0d: load_pc_i=0x%08h",pc_bit_index,pc_value),UVM_MEDIUM)

			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (zero_expiring),
				.load_pc             (pc_value)
			);
		end

		for (random_cycle_index = 0; random_cycle_index < random_cycles; random_cycle_index++) begin
			pc_value = $urandom;
			pc_value[1:0] = 2'b00;

			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (zero_expiring),
				.load_pc             (pc_value)
			);
		end

		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_PC_HASH_SEQ","PC-hash-only sequence completed",UVM_LOW)
	endtask

endclass


// PC-Alignment check
/// sequence to check that load_pc[1:0] has no effect on design outcomes
// All should have same - tagged_indices_o && tagged_tags_o

class tagged_table_hash_pc_alignment_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_pc_alignment_seq)

	function new(string name = "tagged_table_hash_pc_alignment_seq");
		super.new(name);
	endfunction

	task body();

		bit [PKT_WIDTH-1:0] zero_expiring  [0:NUM_TAGGED-1];
		bit [31:0] base_pc;
		bit [31:0] pc_value;

		int unsigned table_index;
		int unsigned low_bits;
		int unsigned random_group;
		int unsigned random_groups;

		random_groups = 10;

		`uvm_info("HASH_PC_ALIGNMENT_SEQ","Starting PC-alignment sequence",	UVM_LOW)

		// Keeping every history-related input at zero.
		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			zero_expiring[table_index] = '0;
		end

		repeat (2) begin
			idle_cycle();
		end

		// Directed PC group 1
		// The sequence sends:
		//   00001000
		//   00001001
		//   00001002
		//   00001003
		// All four should produce the same values for - "tagged_indices_o", "tagged_tags_o"

		base_pc = 32'h0000_1000;

		for (low_bits = 0;low_bits < 4;low_bits++) begin
			pc_value = base_pc | low_bits;
			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (zero_expiring),
				.load_pc             (pc_value)
			);
		end


		// Directed PC group 2
		base_pc = 32'h1234_5678;
		base_pc[1:0] = 2'b00;

		for (low_bits = 0;low_bits < 4;low_bits++) begin
			pc_value = base_pc | low_bits;
			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (zero_expiring),
				.load_pc             (pc_value)
			);
		end

		// Directed high-PC group
		base_pc = 32'hFFFF_FFFC;

		for (low_bits = 0;low_bits < 4;low_bits++) begin
			pc_value = base_pc | low_bits;
			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (zero_expiring),
				.load_pc             (pc_value)
			);
		end


		// Random PC-alignment groups
		for (random_group = 0;random_group < random_groups;random_group++) begin
			base_pc = $urandom;
			base_pc[1:0] = 2'b00;

			`uvm_info("HASH_PC_ALIGNMENT_SEQ",
				$sformatf("Testing alignment group with base PC 0x%08h",base_pc),UVM_MEDIUM)

			for (low_bits = 0;low_bits < 4;low_bits++) begin
				pc_value = base_pc | low_bits;
				send_cycle(
					.en                  (1'b1),
					.br_valid            (1'b1),
					.incoming_pkt        ('0),
					.expiring_pkt_values (zero_expiring),
					.load_pc             (pc_value)
				);
			end
		end

		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_PC_ALIGNMENT_SEQ","PC-alignment sequence completed",UVM_LOW)
	endtask

endclass




/// boundary value sequence
// so there are going to be certain directed cases as input - DIRECTED SEQUENCE
class tagged_table_hash_boundary_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_boundary_seq)

	function new(string name = "tagged_table_hash_boundary_seq");
		super.new(name);
	endfunction

	task send_uniform_active_cycle(
		input bit [PKT_WIDTH-1:0] incoming_value,
		input bit [PKT_WIDTH-1:0] expiring_value,
		input bit [31:0]          pc_value
	);

		bit [PKT_WIDTH-1:0] expiring_values	[0:NUM_TAGGED-1];

		int unsigned table_index;

		for (table_index = 0; table_index < NUM_TAGGED;	table_index++) begin
			expiring_values[table_index] = expiring_value;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        (incoming_value),
			.expiring_pkt_values (expiring_values),
			.load_pc             (pc_value)
		);

	endtask

	task body();

		bit [PKT_WIDTH-1:0] alternating_1010;
		bit [PKT_WIDTH-1:0] alternating_0101;
		bit [PKT_WIDTH-1:0] packet_lsb_only;
		bit [PKT_WIDTH-1:0] packet_msb_only;

		int unsigned bit_index;
		alternating_1010 = '0;

		for (bit_index = 0;	bit_index < PKT_WIDTH;	bit_index += 2) begin
			alternating_1010[bit_index] = 1'b1;
		end

		alternating_0101 = ~alternating_1010;

		packet_lsb_only = '0;
		packet_lsb_only[0] = 1'b1;

		packet_msb_only = '0;
		packet_msb_only[PKT_WIDTH-1] = 1'b1;

		`uvm_info("HASH_BOUNDARY_SEQ","Starting boundary-values sequence",UVM_LOW)

		repeat (2) begin
			idle_cycle();
		end

		// case 1: all-zero inputs
		send_uniform_active_cycle(
			.incoming_value ('0),
			.expiring_value ('0),
			.pc_value       (32'h0000_0000)
		);


		// case 2: maximum value on every input
		send_uniform_active_cycle(
			.incoming_value ('1),
			.expiring_value ('1),
			.pc_value       (32'hFFFF_FFFC)
		);


		// case 3: maximum incoming packet only
		send_uniform_active_cycle(
			.incoming_value ('1),
			.expiring_value ('0),
			.pc_value       (32'h0000_0000)
		);


		// case 4: maximum expiring packets only
		send_uniform_active_cycle(
			.incoming_value ('0),
			.expiring_value ('1),
			.pc_value       (32'h0000_0000)
		);


		// case 5: maximum PC only
		send_uniform_active_cycle(
			.incoming_value ('0),
			.expiring_value ('0),
			.pc_value       (32'hFFFF_FFFC)
		);


		// case 6: alternating packet patterns
		send_uniform_active_cycle(
			.incoming_value (alternating_1010),
			.expiring_value (alternating_0101),
			.pc_value       (32'hAAAA_AAA8)
		);


		// case 7: complementary alternating patterns
		send_uniform_active_cycle(
			.incoming_value (alternating_0101),
			.expiring_value (alternating_1010),
			.pc_value       (32'h5555_5554)
		);


		// case 8: packet LSB boundaries
		send_uniform_active_cycle(
			.incoming_value (packet_lsb_only),
			.expiring_value (packet_lsb_only),
			.pc_value       (32'h0000_0004)
		);


		// case 9: packet MSB boundaries
		send_uniform_active_cycle(
			.incoming_value (packet_msb_only),
			.expiring_value (packet_msb_only),
			.pc_value       (32'h8000_0000)
		);


		// case 10: opposite packet boundaries
		send_uniform_active_cycle(
			.incoming_value (packet_lsb_only),
			.expiring_value (packet_msb_only),
			.pc_value       (32'h7FFF_FFFC)
		);


		// case 11: opposite packet boundaries reversed
		send_uniform_active_cycle(
			.incoming_value (packet_msb_only),
			.expiring_value (packet_lsb_only),
			.pc_value       (32'h0000_0004)
		);


		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_BOUNDARY_SEQ","Boundary-values sequence completed",	UVM_LOW)

	endtask
endclass


// Folded-history wraparound sequence
// need to check if the circular rotation is correct for CSR number of rotations i.e. 23

/// observation after running this sequence
/// at transaction number 4 in table 5 - injected == expiring_pkts_i = 40. 
/// It reaches inside the design at transaction numnber 5 , folded history = 400000
//// next_folded histroy for transaction number 6 will be as :-
// T0	000183
// T1	00078f
// T2	001fbf
// T3	007f7f
// T4	07f07f
// T5	7f007d
// T6	00fe7f

/// after full rortation of 23 cycles , Transsaction number 29 shuould get get back the same "next_folded_history" values
//  Table		Transaction 6 seed		Transaction 29 next_folded_history
// 	T0				000183					000183
//  T1				00078f					00078f
//  T2				001fbf					001fbf
//  T3				007f7f					007f7f
//  T4				07f07f					07f07f
//  T5				7f007d					7f007d
//  T6				00fe7f					00fe7f
/// Retains full values aftera full circle.

class tagged_table_hash_fold_wrap_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_fold_wrap_seq)

	function new(string name = "tagged_table_hash_fold_wrap_seq");
		super.new(name);
	endfunction

	task body();

		bit [PKT_WIDTH-1:0] expiring_values	[0:NUM_TAGGED-1];
		int unsigned table_index;
		int unsigned rotation_cycle;

		`uvm_info("HASH_FOLD_WRAP_SEQ","Starting folded-history wraparound sequence",UVM_LOW)


		// Initializing all expiring packets to zero.
		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			expiring_values[table_index] = '0;
		end

		repeat (2) begin
			idle_cycle();
		end

		// activeating all zero state 
		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);

		// For table 5 (technically table 6) we have
		//   DEPTHS[5]   = 16
		//   EVICT_SHIFT = 16
		// expiring packet bit 6 rotates to:
		//   6 + 16 = 22
		// Thus: aligned_expiring = 23'h400000

		expiring_values[5] = {1'b1,{(PKT_WIDTH-1){1'b0}}};

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);

		// Clearing the expiring packet and rotate once
		// Expected table 5 transition:
		//   folded_history = 400000
		//   shifted_fold   = 000001
		//   next_fold      = 000001
		
		expiring_values[5] = '0;

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('0),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);


		// putting in nonzero histories in all tables
		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			expiring_values[table_index] = '1;
		end

		send_cycle(
			.en                  (1'b1),
			.br_valid            (1'b1),
			.incoming_pkt        ('1),
			.expiring_pkt_values (expiring_values),
			.load_pc             (32'h0000_0000)
		);


		// Remove all new XOR contributions
		for (table_index = 0;table_index < NUM_TAGGED;table_index++) begin
			expiring_values[table_index] = '0;
		end

		// Rotating histories by CSR nbr of rotations, after exactly 23 rotations, each table must return to its original seeded value.
		for (rotation_cycle = 0;rotation_cycle < (CSR_WIDTH + 2);rotation_cycle++) begin

			`uvm_info("HASH_FOLD_WRAP_SEQ",
					$sformatf("Applying zero-input rotation cycle %0d of %0d",rotation_cycle + 1,CSR_WIDTH + 2),UVM_MEDIUM)

			send_cycle(
				.en                  (1'b1),
				.br_valid            (1'b1),
				.incoming_pkt        ('0),
				.expiring_pkt_values (expiring_values),
				.load_pc             (32'h0000_0000)
			);
		end

		repeat (2) begin
			idle_cycle();
		end

		`uvm_info("HASH_FOLD_WRAP_SEQ","Folded-history wraparound sequence completed",UVM_LOW)

	endtask
endclass



/// constrained random sequence

class tagged_table_hash_random_seq extends tagged_table_hash_base_seq;

	`uvm_object_utils(tagged_table_hash_random_seq)

	rand int unsigned num_transactions;

	constraint num_transactions_c {
		num_transactions inside {[60:70]};
	}

	function new(string name = "tagged_table_hash_random_seq");
		super.new(name);
	endfunction

	task body();

		tagged_table_hash_item tr;
		int unsigned transaction_index;

		if (!randomize()) begin
			`uvm_fatal("HASH_RANDOM_SEQ","Failed to randomize num_transactions")
		end

		`uvm_info("HASH_RANDOM_SEQ",
			$sformatf("Starting constrained-random sequence with %0d transactions",num_transactions),UVM_LOW)

		// Establish an initial idle condition.
		repeat (2) begin
			idle_cycle();
		end

		random_cycle(
			.en       (1'b0),
			.br_valid (1'b0)
		);

		random_cycle(
			.en       (1'b0),
			.br_valid (1'b1)
		);

		random_cycle(
			.en       (1'b1),
			.br_valid (1'b0)
		);

		random_cycle(
			.en       (1'b1),
			.br_valid (1'b1)
		);


		// randomized transactions
		for (transaction_index = 0;transaction_index < num_transactions;transaction_index++) begin
			tr = tagged_table_hash_item::type_id::create($sformatf("random_tr_%0d", transaction_index));

			start_item(tr);
			if (!tr.randomize()) begin

				`uvm_error("HASH_RANDOM_SEQ",
					$sformatf("Failed to randomize transaction %0d",transaction_index))

				tr.en           = 1'b0;
				tr.br_valid     = 1'b0;
				tr.incoming_pkt = '0;
				tr.load_pc      = '0;

				for (int unsigned table_index = 0;table_index < NUM_TAGGED;table_index++) begin
					tr.expiring_pkts[table_index] = '0;
				end

			end
			finish_item(tr);


			if (((transaction_index + 1) % 50) == 0) begin

				`uvm_info("HASH_RANDOM_SEQ",
					$sformatf("Completed %0d of %0d random transactions",transaction_index + 1,num_transactions	),UVM_LOW)
			end

		end

		// Final idle cycles
		repeat (3) begin
			idle_cycle();
		end

		`uvm_info("HASH_RANDOM_SEQ",
			$sformatf("Constrained-random sequence completed: %0d randomized transactions",num_transactions),UVM_LOW)
	endtask

endclass


// sequencer
class tagged_table_hash_sequencer extends uvm_sequencer #(tagged_table_hash_item);

	`uvm_component_utils(tagged_table_hash_sequencer)

	function new(string        name = "tagged_table_hash_sequencer",uvm_component parent = null);
		super.new(name, parent);
	endfunction

endclass


// driver
class tagged_table_hash_driver extends  uvm_driver #(tagged_table_hash_item);

	`uvm_component_utils(tagged_table_hash_driver)

	virtual tagged_table_hash_if vif;

	function new(string name = "tagged_table_hash_driver",uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);

		super.build_phase(phase);

		if (!uvm_config_db#(virtual tagged_table_hash_if)::get(this,"","vif",vif)) begin
			`uvm_error("NO_VIF","tagged_table_hash_if was not found in the configuration database")
		end

	endfunction

	task drive_idle();

		vif.drv_cb.en_i           <= 1'b0;
		vif.drv_cb.br_valid_i     <= 1'b0;
		vif.drv_cb.incoming_pkt_i <= '0;
		vif.drv_cb.load_pc_i      <= '0;

		for (int i = 0; i < NUM_TAGGED; i++) begin
			vif.drv_cb.expiring_pkts_i[i] <= '0;
		end

	endtask

	task drive_item(tagged_table_hash_item tr);

		vif.drv_cb.en_i           <= tr.en;
		vif.drv_cb.br_valid_i     <= tr.br_valid;
		vif.drv_cb.incoming_pkt_i <= tr.incoming_pkt;
		vif.drv_cb.load_pc_i      <= tr.load_pc;

		for (int i = 0; i < NUM_TAGGED; i++) begin
			vif.drv_cb.expiring_pkts_i[i] <= tr.expiring_pkts[i];
		end

		`uvm_info("HASH_DRIVER",$sformatf("Driving transaction: %s", tr.convert2string()),UVM_HIGH)

	endtask


	task run_phase(uvm_phase phase);

		@(vif.drv_cb);
		drive_idle();

		wait (vif.rst_n === 1'b1);

		forever begin

			seq_item_port.get_next_item(req);

			@(vif.drv_cb);

			if (vif.rst_n === 1'b1) begin
				drive_item(req);
			end
			else begin
				drive_idle();
				`uvm_warning("HASH_DRIVER","Reset was asserted while a transaction was pending")
			end

			seq_item_port.item_done();
		end
	endtask

endclass


////  monitor
class tagged_table_hash_monitor extends uvm_monitor;

	`uvm_component_utils(tagged_table_hash_monitor)

	virtual tagged_table_hash_if vif;
	uvm_analysis_port #(tagged_table_hash_item) monitor_port;

	function new(string        name = "tagged_table_hash_monitor",uvm_component parent = null);
		super.new(name, parent);
		monitor_port = new("monitor_port", this);
	endfunction

	function void build_phase(uvm_phase phase);

		super.build_phase(phase);

		if (!uvm_config_db#(virtual tagged_table_hash_if)::get(this,"","vif",vif))
		begin
			`uvm_fatal("NO_VIF","tagged_table_hash_if was not found in the configuration database")
		end

	endfunction

	task run_phase(uvm_phase phase);

		tagged_table_hash_item tr;
		wait (vif.rst_n === 1'b1);

		forever begin
			@(vif.mon_cb);

			if (vif.mon_cb.rst_n !== 1'b1) begin
				continue;
			end

			tr = tagged_table_hash_item::type_id::create("monitored_tr",this);
			tr.en           = vif.mon_cb.en_i;
			tr.br_valid     = vif.mon_cb.br_valid_i;
			tr.incoming_pkt = vif.mon_cb.incoming_pkt_i;
			tr.load_pc      = vif.mon_cb.load_pc_i;

			// get DUT outputs
			foreach (tr.expiring_pkts[i]) begin
				tr.expiring_pkts[i] = vif.mon_cb.expiring_pkts_i[i];
			end

			foreach (tr.observed_indices[i]) begin
				tr.observed_indices[i] = vif.mon_cb.tagged_indices_o[i];
				tr.observed_tags[i] = vif.mon_cb.tagged_tags_o[i];
			end

			`uvm_info("HASH_MONITOR",$sformatf("Observed transaction: %s",tr.convert2string()),UVM_HIGH)

			monitor_port.write(tr);
		end
	endtask

endclass


// scoreboard
class tagged_table_hash_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(tagged_table_hash_scoreboard)

	uvm_analysis_imp #(tagged_table_hash_item,tagged_table_hash_scoreboard) analysis_export;

	bit [CSR_WIDTH-1:0] ref_folded_history [0:NUM_TAGGED-1];

	int unsigned total_transactions;
	int unsigned total_table_checks;
	int unsigned passed_table_checks;
	int unsigned failed_table_checks;
	int unsigned active_transactions;
	int unsigned inactive_transactions;

	bit enable_detailed_log = 1'b1;

	function new(string name = "tagged_table_hash_scoreboard",uvm_component parent = null);

		super.new(name, parent);
		analysis_export = new("analysis_export", this);
		foreach (ref_folded_history[i]) begin
			ref_folded_history[i] = '0;
		end
	endfunction

	function automatic bit [CSR_WIDTH-1:0] rotate_left(input bit [CSR_WIDTH-1:0] value,input int unsigned shift_amount);

		int unsigned normalized_shift;
		normalized_shift = shift_amount % CSR_WIDTH;
	
		if (normalized_shift == 0) begin
			return value;
		end

		return ((value << normalized_shift) | (value >> (CSR_WIDTH - normalized_shift)));
	endfunction


	// function for proper padding and column duisplay in log
	function automatic string pad_right(
		input string value,
		input int    column_width
		);

		string result;

		result = value;

		while (result.len() < column_width) begin
			result = {result, " "};
		end

		return result;

	endfunction


	function automatic string pad_left(
		input string value,
		input int    column_width
		);

		string result;

		result = value;

		while (result.len() < column_width) begin
			result = {" ", result};
		end

		return result;

		endfunction

	function void write(tagged_table_hash_item tr);

		bit active_request;
		bit [29:0] pc_word;
		bit [29:0] hash_pc_idx_full;
		bit [29:0] hash_pc_tag_full;
		bit [CSR_WIDTH-1:0] incoming_pkt_i_gated;
		bit [CSR_WIDTH-1:0] padded_incoming;
		bit [CSR_WIDTH-1:0] current_folded_history;
		bit [CSR_WIDTH-1:0] shifted_fold;
		bit [CSR_WIDTH-1:0] expiring_pkt_i_gated;
		bit [CSR_WIDTH-1:0] padded_expiring;
		bit [CSR_WIDTH-1:0] aligned_expiring;
		bit [CSR_WIDTH-1:0] next_folded_history;

		bit [S_WIDTH-1:0] expected_tagged_index;
		bit [T_WIDTH-1:0] expected_tagged_tag;

		int unsigned eviction_shift;
		int unsigned i;

		bit table_passed;

		string transaction_type;
		string check_result;
		string history_table;
		string output_table;
		string complete_report;

		total_transactions++;

		active_request = tr.en && tr.br_valid;

		if (active_request) begin
			active_transactions++;
			transaction_type = "ACTIVE - folded_history updates";
		end
		else begin
			inactive_transactions++;
			transaction_type = "INACTIVE - folded_history holds";
		end

		// DUT Input gating
		if (active_request) begin
			pc_word = tr.load_pc[31:2];
			incoming_pkt_i_gated = {{(CSR_WIDTH-PKT_WIDTH){1'b0}},tr.incoming_pkt};
		end
		else begin
			pc_word               = '0;
			incoming_pkt_i_gated  = '0;
		end

		// The RTL pads incoming_pkt_i_gated to CSR_WIDTH.
		padded_incoming = incoming_pkt_i_gated;
		// RTL PC Hashes
		hash_pc_idx_full = pc_word ^ (pc_word >> 2) ^ (pc_word >> 5);
		hash_pc_tag_full = pc_word ^ (pc_word >> 3) ^ (pc_word >> 7);


		// history_table = {
		// 	"\n",
		// 	"FOLDED-HISTORY CALCULATION\n",
		// 	"-----------------------------------------------------------------------------------------------------------------------------------------------------------------\n",
		// 	"Table DEPTHS EVICT_SHIFT folded_history shifted_fold incoming_pkt_i padded_incoming expiring_pkts_i padded_expiring aligned_expiring next_folded_history\n",
		// 	"-----------------------------------------------------------------------------------------------------------------------------------------------------------------\n"
		// };

		// output_table = {
		// 	"\n",
		// 	"OUTPUT CHECK\n",
		// 	"---------------------------------------------------------------------------------------------------------------------------------------\n",
		// 	"Table hash_pc_idx_slice hash_pc_tag_slice expected_tagged_index tagged_indices_o expected_tagged_tag tagged_tags_o Result\n",
		// 	"---------------------------------------------------------------------------------------------------------------------------------------\n"
		// };

		history_table = {
			"\n",
			"FOLDED-HISTORY CALCULATION\n",
			"+-------+--------+-------------+----------------+--------------+----------------+-----------------+-----------------+-----------------+------------------+---------------------+\n",
			"| ",
			pad_right("Table",                5), " | ",
			pad_right("DEPTHS",               6), " | ",
			pad_right("EVICT_SHIFT",         11), " | ",
			pad_right("folded_history",      14), " | ",
			pad_right("shifted_fold",        12), " | ",
			pad_right("incoming_pkt_i",      14), " | ",
			pad_right("padded_incoming",     15), " | ",
			pad_right("expiring_pkts_i",     15), " | ",
			pad_right("padded_expiring",     15), " | ",
			pad_right("aligned_expiring",    16), " | ",
			pad_right("next_folded_history", 19), " |\n",
			"+-------+--------+-------------+----------------+--------------+----------------+-----------------+-----------------+-----------------+------------------+---------------------+\n"
		};


		output_table = {
			"\n",
			"OUTPUT CHECK\n",
			"+-------+-------------------+-------------------+-----------------------+------------------+---------------------+---------------+--------+\n",
			"| ",
			pad_right("Table",                  5), " | ",
			pad_right("hash_pc_idx_slice",     17), " | ",
			pad_right("hash_pc_tag_slice",     17), " | ",
			pad_right("expected_tagged_index", 21), " | ",
			pad_right("tagged_indices_o",      16), " | ",
			pad_right("expected_tagged_tag",   19), " | ",
			pad_right("tagged_tags_o",         13), " | ",
			pad_right("Result",                 6), " |\n",
			"+-------+-------------------+-------------------+-----------------------+------------------+---------------------+---------------+--------+\n"
		};

		// check every tagged table
		for (i = 0; i < NUM_TAGGED; i++) begin

			current_folded_history = ref_folded_history[i];
			eviction_shift = DEPTHS[i] % CSR_WIDTH;
			shifted_fold = rotate_left(current_folded_history,1);

			if (active_request) begin
				expiring_pkt_i_gated = {{(CSR_WIDTH-PKT_WIDTH){1'b0}},tr.expiring_pkts[i]};
				padded_expiring = expiring_pkt_i_gated;
				aligned_expiring = rotate_left(padded_expiring,eviction_shift);
				next_folded_history = shifted_fold ^ padded_incoming ^ aligned_expiring;
			end
			else begin
				expiring_pkt_i_gated = '0;
				padded_expiring      = '0;
				aligned_expiring     = '0;
				// The registered folded history holds during inactivity.
				next_folded_history = current_folded_history;
			end

			// expected DUT o/p's
			expected_tagged_index = next_folded_history[CSR_WIDTH-1:T_WIDTH] ^ hash_pc_idx_full[S_WIDTH-1:0];
			expected_tagged_tag = next_folded_history[T_WIDTH-1:0] ^ hash_pc_tag_full[T_WIDTH-1:0];

			table_passed = (tr.observed_indices[i] === expected_tagged_index) && (tr.observed_tags[i]    === expected_tagged_tag);
			total_table_checks++;

			if (table_passed) begin
				passed_table_checks++;
				check_result = "PASS";
			end
			else begin
				failed_table_checks++;
				check_result = "FAIL";
			end

			// history_table = {history_table,
			// $sformatf(
			// 	"%3d %5d %5d   %06h      %06h    %02h    %06h    %02h    %06h     %06h    %06h\n",
			// 	i,
			// 	DEPTHS[i],
			// 	eviction_shift,
			// 	current_folded_history,
			// 	shifted_fold,
			// 	tr.incoming_pkt,
			// 	padded_incoming,
			// 	tr.expiring_pkts[i],
			// 	padded_expiring,
			// 	aligned_expiring,
			// 	next_folded_history
			// )
			// };


			history_table = {
				history_table,

				"| ",
				pad_left($sformatf("%0d", i), 5),

				" | ",
				pad_left($sformatf("%0d", DEPTHS[i]), 6),

				" | ",
				pad_left($sformatf("%0d", eviction_shift), 11),

				" | ",
				pad_left(
					$sformatf("%06h", current_folded_history),
					14
				),

				" | ",
				pad_left(
					$sformatf("%06h", shifted_fold),
					12
				),

				" | ",
				pad_left(
					$sformatf("%02h", tr.incoming_pkt),
					14
				),

				" | ",
				pad_left(
					$sformatf("%06h", padded_incoming),
					15
				),

				" | ",
				pad_left(
					$sformatf("%02h", tr.expiring_pkts[i]),
					15
				),

				" | ",
				pad_left(
					$sformatf("%06h", padded_expiring),
					15
				),

				" | ",
				pad_left(
					$sformatf("%06h", aligned_expiring),
					16
				),

				" | ",
				pad_left(
					$sformatf("%06h", next_folded_history),
					19
				),

				" |\n"
			};


			// output_table = {output_table,
			// $sformatf(
			// 	"%3d  %02h   %04h     %02h       %02h    %04h   %04h  %s\n",
			// 	i,
			// 	hash_pc_idx_full[S_WIDTH-1:0],
			// 	hash_pc_tag_full[T_WIDTH-1:0],
			// 	expected_tagged_index,
			// 	tr.observed_indices[i],
			// 	expected_tagged_tag,
			// 	tr.observed_tags[i],
			// 	check_result
			// )
			// };


			output_table = {
				output_table,

				"| ",
				pad_left($sformatf("%0d", i), 5),

				" | ",
				pad_left(
					$sformatf(
						"%02h",
						hash_pc_idx_full[S_WIDTH-1:0]
					),
					17
				),

				" | ",
				pad_left(
					$sformatf(
						"%04h",
						hash_pc_tag_full[T_WIDTH-1:0]
					),
					17
				),

				" | ",
				pad_left(
					$sformatf("%02h", expected_tagged_index),
					21
				),

				" | ",
				pad_left(
					$sformatf("%02h", tr.observed_indices[i]),
					16
				),

				" | ",
				pad_left(
					$sformatf("%04h", expected_tagged_tag),
					19
				),

				" | ",
				pad_left(
					$sformatf("%04h", tr.observed_tags[i]),
					13
				),

				" | ",
				pad_left(check_result, 6),

				" |\n"
			};




			if (!table_passed) begin

			`uvm_error(
				"HASH_SCB_MISMATCH",
				$sformatf(
				{
					"time=%0t transaction=%0d table=%0d depth=%0d ",
					"folded_history=0x%0h next_folded_history=0x%0h ",
					"expected={index:0x%0h tag:0x%0h} ",
					"observed={index:0x%0h tag:0x%0h}"
				},
				$time,
				total_transactions,
				i,
				DEPTHS[i],
				current_folded_history,
				next_folded_history,
				expected_tagged_index,
				expected_tagged_tag,
				tr.observed_indices[i],
				tr.observed_tags[i]
				)
			)

			end

			ref_folded_history[i] = next_folded_history;

		end

		history_table = {
			history_table,
			"-----------------------------------------------------------------------------------------------------------------------------------------------------------------\n"
		};

		output_table = {
			output_table,
			"---------------------------------------------------------------------------------------------------------------------------------------\n"
		};

		complete_report = $sformatf(
			{
			"\n",
			"=================================================================================================================================================================\n",
			"TAGGED TABLE HASH CHECK\n",
			"=================================================================================================================================================================\n",
			"Simulation time        : %0t\n",
			"Transaction number     : %0d\n",
			"Operation              : %s\n",
			"en_i                   : %0b\n",
			"br_valid_i             : %0b\n",
			"br_valid_i_gated       : %0b\n",
			"incoming_pkt_i         : 0x%0h\n",
			"incoming_pkt_i_gated   : 0x%0h\n",
			"load_pc_i              : 0x%08h\n",
			"load_pc_i_gated        : 0x%08h\n",
			"pc_word                : 0x%0h\n",
			"hash_pc_idx_full       : 0x%0h\n",
			"hash_pc_tag_full       : 0x%0h\n",
			"%s",
			"%s",
			"Cumulative checks     : total=%0d passed=%0d failed=%0d\n",
			"================================================================================================================================================================="
			},
			$time,
			total_transactions,
			transaction_type,
			tr.en,
			tr.br_valid,
			active_request,
			tr.incoming_pkt,
			incoming_pkt_i_gated[PKT_WIDTH-1:0],
			tr.load_pc,
			active_request ? tr.load_pc : 32'b0,
			pc_word,
			hash_pc_idx_full,
			hash_pc_tag_full,
			history_table,
			output_table,
			total_table_checks,
			passed_table_checks,
			failed_table_checks
		);


		`uvm_info(
			"HASH_SCB_CHECK",
			complete_report,
			UVM_LOW
		)

	endfunction


	function void report_phase(uvm_phase phase);

		real pass_percentage;
		super.report_phase(phase);
		if (total_table_checks != 0) begin
			pass_percentage = (100.0 * passed_table_checks) / total_table_checks;
		end
		else begin
			pass_percentage = 0.0;
		end

		`uvm_info("HASH_SCOREBOARD_SUMMARY",
		$sformatf(
			{
			"\n============================================================\n",
			"TAGGED TABLE HASH SCOREBOARD SUMMARY\n",
			"============================================================\n",
			"Final simulation time : %0t\n",
			"Transactions          : %0d\n",
			"Active transactions   : %0d\n",
			"Inactive transactions : %0d\n",
			"Total table checks    : %0d\n",
			"Passed checks         : %0d\n",
			"Failed checks         : %0d\n",
			"Pass percentage       : %0.2f%%\n",
			"============================================================"
			},
			$time,
			total_transactions,
			active_transactions,
			inactive_transactions,
			total_table_checks,
			passed_table_checks,
			failed_table_checks,
			pass_percentage
		),
		UVM_NONE
		)

		if ((failed_table_checks == 0) && (total_table_checks != 0)) begin
			`uvm_info(
				"HASH_TEST_RESULT",
				"TEST RESULT: PASS — all expected indices and tags matched",
				UVM_NONE
			)
		end
		else if (total_table_checks == 0) begin
			`uvm_error(
				"HASH_TEST_RESULT",
				"TEST RESULT: FAIL — scoreboard performed no checks"
			)
		end
		else begin
			`uvm_error(
				"HASH_TEST_RESULT",
				$sformatf(
				"TEST RESULT: FAIL — %0d of %0d table checks mismatched",
				failed_table_checks,
				total_table_checks
				)
		)
		end
	endfunction

endclass



/// coverage
class tagged_table_hash_coverage extends uvm_subscriber #(tagged_table_hash_item);

	`uvm_component_utils(tagged_table_hash_coverage)

	localparam int PKT_WIDTH  = 7;
	localparam int NUM_TAGGED = 7;
	localparam int S_WIDTH    = 7;
	localparam int T_WIDTH    = 16;

	covergroup hash_cg with function sample(
		bit                 sample_en,
		bit                 sample_br_valid,
		bit [PKT_WIDTH-1:0] sample_incoming_pkt,
		bit [31:0]          sample_load_pc
	);

		option.per_instance = 1;

		en_cp: coverpoint sample_en {
			bins disabled = {0};
			bins enabled  = {1};
		}

		br_valid_cp: coverpoint sample_br_valid {
			bins invalid = {0};
			bins valid   = {1};
		}

		request_type_cp: coverpoint {sample_en, sample_br_valid} {
			bins block_disabled = {2'b00, 2'b01};
			bins no_valid_branch = {2'b10};
			bins active_request  = {2'b11};
		}


		incoming_pkt_cp: coverpoint sample_incoming_pkt
		iff (sample_en && sample_br_valid) {
			bins zero = {'0};
			bins low = {[1:(2**(PKT_WIDTH-1))-1]
		};

			bins high = {
				[(2**(PKT_WIDTH-1)):
				(2**PKT_WIDTH)-2]
			};

			bins maximum = {
				(2**PKT_WIDTH)-1
			};
		}

		pc_alignment_cp: coverpoint sample_load_pc[1:0]
			iff (sample_en && sample_br_valid) {

				bins aligned = {2'b00};
				bins unaligned[] = {
					2'b01,
					2'b10,
					2'b11
				};
		}

		pc_region_cp: coverpoint sample_load_pc[31:28]
			iff (sample_en && sample_br_valid) {
				bins regions[16] = {[4'h0:4'hF]};
		}

		request_transition_cp: coverpoint {sample_en, sample_br_valid} {
			bins inactive_to_active = (2'b00, 2'b01, 2'b10 => 2'b11);
			bins active_to_active = (2'b11 => 2'b11);
			bins active_to_inactive = (2'b11 => 2'b00, 2'b01, 2'b10);
		}

		control_cross: cross en_cp, br_valid_cp;

		packet_pc_alignment_cross: cross incoming_pkt_cp, pc_alignment_cp
			iff (sample_en && sample_br_valid);

	endgroup

	covergroup table_cg with function sample(
		int unsigned           table_number,
		bit                    active_request,
		bit [PKT_WIDTH-1:0]    sample_expiring_pkt,
		logic [S_WIDTH-1:0]    sample_index,
		logic [T_WIDTH-1:0]    sample_tag
	);

		option.per_instance = 1;

		table_number_cp: coverpoint table_number {
			bins table_bins[NUM_TAGGED] = {[0:NUM_TAGGED-1]};
			illegal_bins invalid_table = default;
		}

		expiring_pkt_cp: coverpoint sample_expiring_pkt
		iff (active_request) {
			bins zero = {'0};
			bins low = {[1:(2**(PKT_WIDTH-1))-1]};
			bins high = {[(2**(PKT_WIDTH-1)):(2**PKT_WIDTH)-2]};
			bins maximum = {(2**PKT_WIDTH)-1};
		}

		index_cp: coverpoint sample_index
		iff (active_request) {
			bins zero = {'0};
			bins low = {[1:(2**(S_WIDTH-1))-1]};
			bins high = {[(2**(S_WIDTH-1)):(2**S_WIDTH)-2]};
			bins maximum = {(2**S_WIDTH)-1};
		}


		tag_cp: coverpoint sample_tag
		iff (active_request) {
			bins zero = {'0};
			bins low = {[1:(2**(T_WIDTH-1))-1]};
			bins high = {[(2**(T_WIDTH-1)):(2**T_WIDTH)-2]};
			bins maximum = {(2**T_WIDTH)-1};
		}

		table_expiring_cross: cross table_number_cp, expiring_pkt_cp;
		table_index_cross: cross table_number_cp, index_cp;
		table_tag_cross: cross table_number_cp, tag_cp;

	endgroup


	function new(string name = "tagged_table_hash_coverage",uvm_component parent = null);
		super.new(name, parent);
		hash_cg  = new();
		table_cg = new();
	endfunction


	function void write(tagged_table_hash_item tr);

		bit active_request;
		active_request = tr.en && tr.br_valid;

		hash_cg.sample(
			tr.en,
			tr.br_valid,
			tr.incoming_pkt,
			tr.load_pc
		);

		foreach (tr.expiring_pkts[i]) begin

			table_cg.sample(
				i,
				active_request,
				tr.expiring_pkts[i],
				tr.observed_indices[i],
				tr.observed_tags[i]
			);
		end
	endfunction


	function void report_phase(uvm_phase phase);

		super.report_phase(phase);
		`uvm_info("HASH_COVERAGE_SUMMARY",
			$sformatf(
				{
				"\n----------------------------------------\n",
				"TAGGED TABLE HASH COVERAGE SUMMARY\n",
				"----------------------------------------\n",
				"Transaction coverage : %0.2f%%\n",
				"Per-table coverage   : %0.2f%%\n",
				"----------------------------------------"
				},
				hash_cg.get_coverage(),
				table_cg.get_coverage()
			),
			UVM_NONE
		)
	endfunction

endclass


// agent
class tagged_table_hash_agent extends uvm_agent;

		`uvm_component_utils(tagged_table_hash_agent)

		tagged_table_hash_sequencer sequencer;
		tagged_table_hash_driver    driver;
		tagged_table_hash_monitor   monitor;

		function new(string name = "tagged_table_hash_agent",uvm_component parent = null);
			super.new(name, parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			monitor = tagged_table_hash_monitor::type_id::create("monitor",this);
			if (get_is_active() == UVM_ACTIVE) begin
				sequencer = tagged_table_hash_sequencer::type_id::create("sequencer",this);
				driver = tagged_table_hash_driver::type_id::create("driver",this);
			end
		endfunction

		function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
			if (get_is_active() == UVM_ACTIVE) begin
				driver.seq_item_port.connect(sequencer.seq_item_export);
			end
		endfunction

endclass


/// environment
class tagged_table_hash_env extends uvm_env;

	`uvm_component_utils(tagged_table_hash_env)

	tagged_table_hash_agent      agent;
	tagged_table_hash_scoreboard scoreboard;
	tagged_table_hash_coverage   coverage;

	function new(string name = "tagged_table_hash_env",uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		agent = tagged_table_hash_agent::type_id::create("agent",this);
		scoreboard = tagged_table_hash_scoreboard::type_id::create("scoreboard",this);
		coverage = tagged_table_hash_coverage::type_id::create("coverage",this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		agent.monitor.monitor_port.connect(scoreboard.analysis_export);
		agent.monitor.monitor_port.connect(coverage.analysis_export);
	endfunction

endclass


// base test
class tagged_table_hash_base_test extends uvm_test;

	`uvm_component_utils(tagged_table_hash_base_test)

	tagged_table_hash_env env;

	function new(string name = "tagged_table_hash_base_test",uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		uvm_config_db#(uvm_active_passive_enum)::set(this,"env.agent","is_active",UVM_ACTIVE);
		env = tagged_table_hash_env::type_id::create("env",this);
	endfunction

	task run_phase(uvm_phase phase);
		tagged_table_hash_smoke_seq smoke_seq;
		tagged_table_hash_gating_seq gating_seq;
		tagged_table_hash_back_to_back_seq back2back_active;
		tagged_table_hash_hold_resume_seq hash_hold_resume;
		tagged_table_hash_incoming_only_seq only_incoming_pkt;
		tagged_table_hash_expiring_only_seq only_expiring_pkt;
		tagged_table_hash_depth_rotation_seq table_depth_rotate;
		tagged_table_hash_only_pc_seq pc_only_seq;
		tagged_table_hash_pc_alignment_seq pc_aligned_seq;
		tagged_table_hash_boundary_seq boundary_sequences;
		tagged_table_hash_fold_wrap_seq fold_wrap_seq;
		tagged_table_hash_random_seq constrained_random;

		phase.raise_objection(this);
			// `uvm_info("HASH_BASE_TEST","Starting tagged-table hash base test",UVM_LOW)
			// smoke_seq = tagged_table_hash_smoke_seq::type_id::create("smoke_seq");
			// smoke_seq.start(env.agent.sequencer);
			// `uvm_info("HASH_BASE_TEST","Tagged-table hash base test completed",UVM_LOW)

			// gating_seq = tagged_table_hash_gating_seq::type_id::create("gating_seq");
			// gating_seq.start(env.agent.sequencer);
			
			// back2back_active = tagged_table_hash_back_to_back_seq::type_id::create("back2back_active");
			// back2back_active.start(env.agent.sequencer);
			
			// hash_hold_resume = tagged_table_hash_hold_resume_seq::type_id::create("hash_hold_resume");
			// hash_hold_resume.start(env.agent.sequencer);
			
			// only_incoming_pkt = tagged_table_hash_incoming_only_seq::type_id::create("only_incoming_pkt");
			// only_incoming_pkt.start(env.agent.sequencer);
			
			// only_expiring_pkt = tagged_table_hash_expiring_only_seq::type_id::create("only_expiring_pkt");
			// only_expiring_pkt.start(env.agent.sequencer);
			
			// table_depth_rotate = tagged_table_hash_depth_rotation_seq::type_id::create("table_depth_rotate");
			// table_depth_rotate.start(env.agent.sequencer);
				
			// pc_only_seq = tagged_table_hash_only_pc_seq::type_id::create("pc_only_seq");
			// pc_only_seq.start(env.agent.sequencer);

			// pc_aligned_seq = tagged_table_hash_pc_alignment_seq::type_id::create("pc_aligned_seq");
			// pc_aligned_seq.start(env.agent.sequencer);
				
			// boundary_sequences = tagged_table_hash_boundary_seq::type_id::create("boundary_sequences");
			// boundary_sequences.start(env.agent.sequencer);

			// fold_wrap_seq = tagged_table_hash_fold_wrap_seq::type_id::create("fold_wrap_seq");
			// fold_wrap_seq.start(env.agent.sequencer);

			constrained_random = tagged_table_hash_random_seq::type_id::create("constrained_random");
			constrained_random.start(env.agent.sequencer);
			
		phase.phase_done.set_drain_time(this, 20ns);
		phase.drop_objection(this);

	endtask
endclass



// tb top
module tb_top;

	import uvm_pkg::*;
	`include "uvm_macros.svh"

	localparam int PKT_WIDTH  = 7;
	localparam int NUM_TAGGED = 7;
	localparam int S_WIDTH    = 7;
	localparam int T_WIDTH    = 16;

	localparam int DEPTHS [0:NUM_TAGGED-1] = '{2, 4, 6, 8, 12, 16, 32};

	logic clk;

	initial begin
		clk = 1'b0;

		forever begin
			#5ns clk = ~clk;
		end
	end

	tagged_table_hash_if #(
		.PKT_WIDTH  (PKT_WIDTH),
		.NUM_TAGGED (NUM_TAGGED),
		.S_WIDTH    (S_WIDTH),
		.T_WIDTH    (T_WIDTH)
	) hash_if (
		.clk (clk)
	);

	phast_tagged_table_hash #(
		.PKT_WIDTH  (PKT_WIDTH),
		.NUM_TAGGED (NUM_TAGGED),
		.S_WIDTH    (S_WIDTH),
		.T_WIDTH    (T_WIDTH),
		.DEPTHS     (DEPTHS)
	) dut (
		.clk              (clk),
		.rst_n            (hash_if.rst_n),
		.en_i             (hash_if.en_i),
		.br_valid_i       (hash_if.br_valid_i),
		.incoming_pkt_i   (hash_if.incoming_pkt_i),
		.expiring_pkts_i  (hash_if.expiring_pkts_i),
		.load_pc_i        (hash_if.load_pc_i),
		.tagged_indices_o (hash_if.tagged_indices_o),
		.tagged_tags_o    (hash_if.tagged_tags_o)
	);

	initial begin
		hash_if.rst_n          = 1'b0;
		hash_if.en_i           = 1'b0;
		hash_if.br_valid_i     = 1'b0;
		hash_if.incoming_pkt_i = '0;
		hash_if.load_pc_i      = '0;

		foreach (hash_if.expiring_pkts_i[i]) begin
			hash_if.expiring_pkts_i[i] = '0;
		end
	end

	initial begin
		hash_if.rst_n = 1'b0;
		repeat (3) begin
		@(posedge clk);
		end

		@(negedge clk);
		hash_if.rst_n = 1'b1;
	end

	initial begin

		uvm_config_db#(virtual tagged_table_hash_if #(
			.PKT_WIDTH  (PKT_WIDTH),
			.NUM_TAGGED (NUM_TAGGED),
			.S_WIDTH    (S_WIDTH),
			.T_WIDTH    (T_WIDTH)
		)
		)::set(null,"*","vif",hash_if);

		run_test("tagged_table_hash_base_test");

	end

	initial begin
		#100us;
		`uvm_fatal("TB_TIMEOUT","Simulation reached the timeout limit")
	end

endmodule