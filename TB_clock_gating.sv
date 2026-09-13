import uvm_pkg::*;
`include "uvm_macros.svh"

interface gated_clk_if (
	input logic clk_i
  );
  
	logic en_i;
	logic clk_gated_o;
  
	clocking drv_cb @(negedge clk_i);
	  output en_i;
	endclocking

endinterface

class gated_clk_item extends uvm_sequence_item;

	typedef enum int {
		DRIVE_WHEN_LOW,
		DRIVE_WHEN_HIGH,
		DRIVE_RANDOM_PHASE
	} drive_phase_e;

	rand bit en_value;
	rand drive_phase_e drive_phase;
	rand int unsigned hold_cycles;

	bit obs_clk_i;
	bit obs_en_i;
	bit obs_clk_gated_o;

	constraint hold_cycles_c {
		hold_cycles inside {[1:5]};
	}

	`uvm_object_utils_begin(gated_clk_item)
		`uvm_field_int(en_value, UVM_ALL_ON)
		`uvm_field_enum(drive_phase_e, drive_phase, UVM_ALL_ON)
		`uvm_field_int(hold_cycles, UVM_ALL_ON)

		`uvm_field_int(obs_clk_i, UVM_ALL_ON)
		`uvm_field_int(obs_en_i, UVM_ALL_ON)
		`uvm_field_int(obs_clk_gated_o, UVM_ALL_ON)
	`uvm_object_utils_end

	function new(string name = "gated_clk_item");
		super.new(name);
	endfunction
	
endclass

class gated_clk_base_seq extends uvm_sequence #(gated_clk_item);

	`uvm_object_utils(gated_clk_base_seq)

	function new(string name = "gated_clk_base_seq");
		super.new(name);
	endfunction

	task drive_en(
		input bit en_value,
		input gated_clk_item::drive_phase_e drive_phase,
		input int unsigned hold_cycles
	);
		gated_clk_item tr;

		tr = gated_clk_item::type_id::create("tr");

		start_item(tr);

		tr.en_value    = en_value;
		tr.drive_phase = drive_phase;
		tr.hold_cycles = hold_cycles;

		finish_item(tr);
	endtask

endclass

class gated_clk_basic_enable_seq extends gated_clk_base_seq;

	`uvm_object_utils(gated_clk_basic_enable_seq)

	function new(string name = "gated_clk_basic_enable_seq");
		super.new(name);
	endfunction

	task body();

		`uvm_info("GCLK_BASIC_SEQ",
		"Starting gated clock basic enable sequence",
		UVM_LOW)

		drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 2);
		drive_en(1'b1, gated_clk_item::DRIVE_WHEN_LOW, 4);
		drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 4);
		drive_en(1'b1, gated_clk_item::DRIVE_WHEN_LOW, 3);
		drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 2);

		`uvm_info("GCLK_BASIC_SEQ",
		"Completed gated clock basic enable sequence",
		UVM_LOW)

	endtask

endclass

class gated_clk_high_phase_toggle_seq extends gated_clk_base_seq; 	// checks - en_i changes while clk_i is high

	`uvm_object_utils(gated_clk_high_phase_toggle_seq)

	function new(string name = "gated_clk_high_phase_toggle_seq");
		super.new(name);
	endfunction

	task body();

		`uvm_info("GCLK_HIGH_PHASE_SEQ",
		"Starting gated clock high-phase enable toggle sequence",
		UVM_LOW)

		// start disabled cleanly - then toggle en_i HIGH when clk_i is HIGH
		drive_en(.en_value(1'b0), .drive_phase(gated_clk_item::DRIVE_WHEN_LOW), .hold_cycles(2));
		drive_en(.en_value(1'b1), .drive_phase(gated_clk_item::DRIVE_WHEN_HIGH), .hold_cycles(3));

		// start enabled cleanly - then toggle en_i LOW while clk_i is HIGH
		drive_en(.en_value(1'b1), .drive_phase(gated_clk_item::DRIVE_WHEN_HIGH), .hold_cycles(2));
		drive_en(.en_value(1'b0), .drive_phase(gated_clk_item::DRIVE_WHEN_HIGH), .hold_cycles(3));

		// Repeat with a few more high-phase toggles.
		repeat (3) begin
			drive_en(.en_value(1'b1),.drive_phase(gated_clk_item::DRIVE_WHEN_HIGH),.hold_cycles(2));
			drive_en(.en_value(1'b0),.drive_phase(gated_clk_item::DRIVE_WHEN_HIGH),.hold_cycles(2));
		end

		`uvm_info("GCLK_HIGH_PHASE_SEQ",
		"Completed gated clock high-phase enable toggle sequence",
		UVM_LOW)

	endtask

endclass

class gated_clk_low_phase_toggle_seq extends gated_clk_base_seq;	// enable input signal changes when clk_i is low

	`uvm_object_utils(gated_clk_low_phase_toggle_seq)

	function new(string name = "gated_clk_low_phase_toggle_seq");
		super.new(name);
	endfunction

	task body();

		`uvm_info("GCLK_LOW_PHASE_SEQ",
		"Starting gated clock low-phase enable toggle sequence",
		UVM_LOW)

		 // Enable sampled low phase -> gated clock should pass next high phase.
		drive_en(
			.en_value(1'b1),
			.drive_phase(gated_clk_item::DRIVE_WHEN_LOW),
			.hold_cycles(3)
		  );
	  
		  // Disable sampled low phase -> gated clock should block next high phase.
		  drive_en(
			.en_value(1'b0),
			.drive_phase(gated_clk_item::DRIVE_WHEN_LOW),
			.hold_cycles(3)
		  );
	  
		  // Toggle again to confirm repeated low-phase sampling.
		  drive_en(
			.en_value(1'b1),
			.drive_phase(gated_clk_item::DRIVE_WHEN_LOW),
			.hold_cycles(4)
		  );
	  
		  drive_en(
			.en_value(1'b0),
			.drive_phase(gated_clk_item::DRIVE_WHEN_LOW),
			.hold_cycles(4)
		  );
	  
		  // A few shorter windows.
		  drive_en(
			.en_value(1'b1),
			.drive_phase(gated_clk_item::DRIVE_WHEN_LOW),
			.hold_cycles(2)
		  );
	  
		  drive_en(
			.en_value(1'b0),
			.drive_phase(gated_clk_item::DRIVE_WHEN_LOW),
			.hold_cycles(2)
		  );
	  
		  `uvm_info("GCLK_LOW_PHASE_SEQ",
			"Completed gated clock low-phase enable toggle sequence",
			UVM_LOW)

	endtask

endclass


class gated_clk_random_seq extends gated_clk_base_seq;

	`uvm_object_utils(gated_clk_random_seq)

	rand int unsigned num_transactions;

	constraint num_transactions_c {
		num_transactions inside {[20:50]};
	}

	function new(string name = "gated_clk_random_seq");
		super.new(name);
	endfunction

	task body();

		gated_clk_item tr;

		if(!this.randomize()) begin
			`uvm_error("GATED_CLK_RANDOM_SEQ", "Failed to randomize num_transactions variable")
			num_transactions = 30;
		end

		`uvm_info("GCLK_RANDOM_SEQ",
		"Starting gated clock random sequence",
		UVM_LOW)

		repeat (num_transactions) begin

			tr = gated_clk_item::type_id::create("tr");

			start_item(tr);

			if (!tr.randomize() with {
				en_value dist {
				0 := 50,
				1 := 50
				};

				drive_phase dist {
				gated_clk_item::DRIVE_WHEN_LOW    := 40,
				gated_clk_item::DRIVE_WHEN_HIGH   := 40,
				gated_clk_item::DRIVE_RANDOM_PHASE := 20
				};

				hold_cycles inside {[1:6]};
			}) begin
				`uvm_error("GCLK_RANDOM_SEQ", "Randomization failed")
			end

			finish_item(tr);

			`uvm_info("GCLK_RANDOM_SEQ",
				$sformatf("Random item: en_i=%0b drive_phase=%0d hold_cycles=%0d",
				tr.en_value,
				tr.drive_phase,
				tr.hold_cycles),
				UVM_HIGH)

		end

		`uvm_info("GCLK_RANDOM_SEQ",
		"Completed gated clock random sequence",
		UVM_LOW)

	endtask

endclass


class gated_clk_back_to_back_enable_seq extends gated_clk_base_seq;

  `uvm_object_utils(gated_clk_back_to_back_enable_seq)

  function new(string name = "gated_clk_back_to_back_enable_seq");
    super.new(name);
  endfunction

  task body();

    `uvm_info("GCLK_B2B_SEQ",
      "Starting gated clock back-to-back enable pattern sequence",
      UVM_LOW)

    // Alternating enable every cycle, driven during low phase.
    drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 1);
    drive_en(1'b1, gated_clk_item::DRIVE_WHEN_LOW, 1);
    drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 1);
    drive_en(1'b1, gated_clk_item::DRIVE_WHEN_LOW, 1);
    drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 1);
    drive_en(1'b1, gated_clk_item::DRIVE_WHEN_LOW, 1);

    // Short bursts: enabled for two cycles, disabled for two cycles.
    drive_en(1'b1, gated_clk_item::DRIVE_WHEN_LOW, 2);
    drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 2);
    drive_en(1'b1, gated_clk_item::DRIVE_WHEN_LOW, 2);
    drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 2);

    // End in disabled state.
    drive_en(1'b0, gated_clk_item::DRIVE_WHEN_LOW, 3);

    `uvm_info("GCLK_B2B_SEQ",
      "Completed gated clock back-to-back enable pattern sequence",
      UVM_LOW)

  endtask

endclass

class gated_clk_sequencer extends uvm_sequencer #(gated_clk_item);

	`uvm_component_utils(gated_clk_sequencer)

	function new(string name = "gated_clk_sequencer", uvm_component parent);
		super.new(name, parent);
	endfunction

endclass

class gated_clk_driver extends uvm_driver #(gated_clk_item);

	`uvm_component_utils(gated_clk_driver)

	virtual gated_clk_if vif;

	function new(string name = "gated_clk_driver", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual gated_clk_if)::get(this, "", "vif", vif)) begin
			`uvm_fatal("GCLK_DRV_NO_VIF", "Virtual interface not found")
		end
	endfunction

	task run_phase(uvm_phase phase);
		gated_clk_item req;

		vif.en_i = 1'b0;

		forever begin
			seq_item_port.get_next_item(req);
			drive_item(req);
			seq_item_port.item_done();
		end
	endtask

	task drive_item(gated_clk_item tr);

		case (tr.drive_phase)

			gated_clk_item::DRIVE_WHEN_LOW: begin
			@(negedge vif.clk_i);
			vif.en_i <= tr.en_value;
			end

			gated_clk_item::DRIVE_WHEN_HIGH: begin
			@(posedge vif.clk_i);
			#1;
			vif.en_i <= tr.en_value;
			end

			gated_clk_item::DRIVE_RANDOM_PHASE: begin
			#(1 + $urandom_range(0, 7));
			vif.en_i <= tr.en_value;
			end

		endcase

		`uvm_info("GCLK_DRV",
			$sformatf("Driven en=%0b phase=%0d hold_cycles=%0d",
			tr.en_value, tr.drive_phase, tr.hold_cycles),
			UVM_HIGH)

		repeat (tr.hold_cycles) begin
			@(posedge vif.clk_i);
		end

	endtask

endclass


class gated_clk_monitor extends uvm_monitor;

	`uvm_component_utils(gated_clk_monitor)

	virtual gated_clk_if vif;
	uvm_analysis_port #(gated_clk_item) monitor_port;

	function new(string name = "gated_clk_monitor", uvm_component parent);
		super.new(name, parent);
		monitor_port = new("monitor_port", this);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual gated_clk_if)::get(this, "", "vif", vif)) begin
			`uvm_fatal("GCLK_MON_NO_VIF", "Virtual interface not found")
		end
	endfunction

	task run_phase(uvm_phase phase);
	gated_clk_item tr;

	forever begin
		@(posedge vif.clk_i or negedge vif.clk_i or vif.en_i or vif.clk_gated_o);
		#1;

		tr = gated_clk_item::type_id::create("tr", this);

		tr.obs_clk_i       = vif.clk_i;
		tr.obs_en_i        = vif.en_i;
		tr.obs_clk_gated_o = vif.clk_gated_o;

		monitor_port.write(tr);
	end
	endtask

endclass

class gated_clk_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(gated_clk_scoreboard)

	uvm_analysis_imp #(gated_clk_item, gated_clk_scoreboard) analysis_export;

	bit ref_en_latched;
	bit expected_clk_gated;

	int total_observations;
	int pass_count;
	int fail_count;

	int gated_blocked_checks;
	int gated_pass_checks;

	function new(string name = "gated_clk_scoreboard", uvm_component parent);
	super.new(name, parent);
	analysis_export = new("analysis_export", this);
	endfunction

	function void write(gated_clk_item tr);

	total_observations++;

	// Reference latch model:
	// transparent when clk is low.
	if (tr.obs_clk_i == 1'b0) begin
		ref_en_latched = tr.obs_en_i;
	end

	expected_clk_gated = tr.obs_clk_i & ref_en_latched;

	if (tr.obs_clk_gated_o !== expected_clk_gated) begin
		fail_count++;

		`uvm_error("GCLK_MISMATCH",
		$sformatf({
			"GATED CLOCK MISMATCH\n",
			"  clk_i             : %0b\n",
			"  en_i              : %0b\n",
			"  ref_en_latched    : %0b\n",
			"  expected_gated    : %0b\n",
			"  observed_gated    : %0b"
		},
			tr.obs_clk_i,
			tr.obs_en_i,
			ref_en_latched,
			expected_clk_gated,
			tr.obs_clk_gated_o))
	end
	else begin
		pass_count++;
	end

	if (tr.obs_clk_i && ref_en_latched) begin
		gated_pass_checks++;
	end

	if (tr.obs_clk_i && !ref_en_latched) begin
		gated_blocked_checks++;
	end

	endfunction

	function void report_phase(uvm_phase phase);
	super.report_phase(phase);

	`uvm_info("GCLK_SCOREBOARD",
		$sformatf({
		"\n----------------------------------------\n",
		"GATED CLOCK SCOREBOARD SUMMARY\n",
		"----------------------------------------\n",
		"Total observations        : %0d\n",
		"Pass count                : %0d\n",
		"Fail count                : %0d\n",
		"Gated pass checks         : %0d\n",
		"Gated blocked checks      : %0d\n",
		"----------------------------------------"
		},
		total_observations,
		pass_count,
		fail_count,
		gated_pass_checks,
		gated_blocked_checks),
		UVM_NONE)

	if (fail_count == 0) begin
		`uvm_info("GCLK_RESULT", "TEST RESULT: PASS", UVM_NONE)
	end
	else begin
		`uvm_error("GCLK_RESULT",
		$sformatf("TEST RESULT: FAIL with %0d gated-clock mismatches", fail_count))
	end

	endfunction

endclass

class gated_clk_coverage extends uvm_subscriber #(gated_clk_item);

	`uvm_component_utils(gated_clk_coverage)

	gated_clk_item tr;

	covergroup gated_clk_cg;
		option.per_instance = 1;

		en_cp : coverpoint tr.en_value {
			bins en_low  = {0};
			bins en_high = {1};
		}

		phase_cp : coverpoint tr.drive_phase {
			bins low_phase    = {gated_clk_item::DRIVE_WHEN_LOW};
			bins high_phase   = {gated_clk_item::DRIVE_WHEN_HIGH};
			bins random_phase = {gated_clk_item::DRIVE_RANDOM_PHASE};
		}

	endgroup

	function new(string name = "gated_clk_coverage", uvm_component parent);
		super.new(name, parent);
		gated_clk_cg = new();
	endfunction

	function void write(gated_clk_item t);
		tr = t;
		gated_clk_cg.sample();
	endfunction

	function void report_phase(uvm_phase phase);
		super.report_phase(phase);

		`uvm_info("GCLK_COVERAGE",
			$sformatf("Functional coverage = %0.2f%%", gated_clk_cg.get_coverage()),
			UVM_NONE)

	endfunction

endclass

class gated_clk_agent extends uvm_agent;

	`uvm_component_utils(gated_clk_agent)

	gated_clk_sequencer sequencer;
	gated_clk_driver    driver;
	gated_clk_monitor   monitor;

	function new(string name = "gated_clk_agent", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		monitor = gated_clk_monitor::type_id::create("monitor", this);

		if (get_is_active() == UVM_ACTIVE) begin
			sequencer = gated_clk_sequencer::type_id::create("sequencer", this);
			driver    = gated_clk_driver::type_id::create("driver", this);
		end
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		if (get_is_active() == UVM_ACTIVE) begin
			driver.seq_item_port.connect(sequencer.seq_item_export);
		end
	endfunction

endclass

class gated_clk_env extends uvm_env;

	`uvm_component_utils(gated_clk_env)

	gated_clk_agent      agent;
	gated_clk_scoreboard scoreboard;
	gated_clk_coverage   coverage;

	function new(string name = "gated_clk_env", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		agent      = gated_clk_agent::type_id::create("agent", this);
		scoreboard = gated_clk_scoreboard::type_id::create("scoreboard", this);
		coverage   = gated_clk_coverage::type_id::create("coverage", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		agent.monitor.monitor_port.connect(scoreboard.analysis_export);
		agent.monitor.monitor_port.connect(coverage.analysis_export);
	endfunction

endclass

class gated_clk_base_test extends uvm_test;

	`uvm_component_utils(gated_clk_base_test)

	gated_clk_env env;

	function new(string name = "gated_clk_base_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		env = gated_clk_env::type_id::create("env", this);
	endfunction

	task run_phase(uvm_phase phase);

		gated_clk_basic_enable_seq basic_seq;
		gated_clk_high_phase_toggle_seq high_phase_seq;
		gated_clk_low_phase_toggle_seq low_phase_seq;
		gated_clk_random_seq random_seq;
		gated_clk_back_to_back_enable_seq back2back_seq;

		phase.raise_objection(this);

		// basic_seq = gated_clk_basic_enable_seq::type_id::create("basic_seq");
		// basic_seq.start(env.agent.sequencer);

		// high_phase_seq = gated_clk_high_phase_toggle_seq::type_id::create("high_phase_seq");
		// high_phase_seq.start(env.agent.sequencer);

		// low_phase_seq = gated_clk_low_phase_toggle_seq::type_id::create("low_phase_seq");
		// low_phase_seq.start(env.agent.sequencer);

		// random_seq = gated_clk_random_seq::type_id::create("random_seq");
		// random_seq.start(env.agent.sequencer);

		back2back_seq = gated_clk_back_to_back_enable_seq::type_id::create("back2back_seq");
		back2back_seq.start(env.aent.sequencer);

		phase.drop_objection(this);

	endtask

endclass

module tb_top;

	logic clk_i;

	initial clk_i = 1'b0;
	always #5 clk_i = ~clk_i;

	gated_clk_if gclk_if (
	.clk_i(clk_i)
	);

	initial begin
	gclk_if.en_i = 1'b0;
	end

	gated_clk dut (
	.clk_i       (clk_i),
	.en_i        (gclk_if.en_i),
	.clk_gated_o (gclk_if.clk_gated_o)
	);

	initial begin
		uvm_config_db#(virtual gated_clk_if)::set(null, "*", "vif", gclk_if);
		run_test("gated_clk_base_test");
	end

	initial begin
		$dumpfile("dump.vcd");
		$dumpvars(0, tb_top);
  	end


endmodule