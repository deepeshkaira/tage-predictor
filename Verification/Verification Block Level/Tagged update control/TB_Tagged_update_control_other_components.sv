package tagged_update_cntrl_params_pkg;

		parameter int DISTANCE_WIDTH   = 7;
		parameter int TAG_WIDTH        = 16;
		parameter int CONFIDENCE_WIDTH = 4;
		parameter int USEFUL_WIDTH     = 2;

		parameter logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE = '0;
		parameter logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};
		parameter logic [CONFIDENCE_WIDTH-1:0] WEAK_CONFIDENCE = {1'b1,{(CONFIDENCE_WIDTH-1){1'b0}}};

		parameter logic [USEFUL_WIDTH-1:0] MIN_USEFUL = '0;
		parameter logic [USEFUL_WIDTH-1:0] MAX_USEFUL = {USEFUL_WIDTH{1'b1}};
		parameter logic [USEFUL_WIDTH-1:0] INITIAL_USEFUL = {{(USEFUL_WIDTH-1){1'b0}},1'b1};

endpackage


import uvm_pkg::*;
`include "uvm_macros.svh"
import tagged_update_cntrl_params_pkg::*;


interface tagged_update_cntrl_if;

		logic                        en_i;
		logic [1:0]                  cmd_i;
		logic [CONFIDENCE_WIDTH-1:0] current_conf_i;
		logic [USEFUL_WIDTH-1:0]     current_useful_i;
		logic [TAG_WIDTH-1:0]        current_tag_i;
		logic [DISTANCE_WIDTH-1:0]   current_distance_i;
		logic [TAG_WIDTH-1:0]        new_tag_i;
		logic [DISTANCE_WIDTH-1:0]   true_distance_i;

		logic                        sram_we_o;
		logic [CONFIDENCE_WIDTH-1:0] next_confidence_o;
		logic [USEFUL_WIDTH-1:0]     next_useful_o;
		logic [TAG_WIDTH-1:0]        next_tag_o;
		logic [DISTANCE_WIDTH-1:0]   next_distance_o;

		event stimulus_applied;

		initial begin
			en_i               = 1'b0;
			cmd_i              = '0;
			current_conf_i     = '0;
			current_useful_i   = '0;
			current_tag_i      = '0;
			current_distance_i = '0;
			new_tag_i          = '0;
			true_distance_i    = '0;
		end

		modport DRIVER (
			output en_i,
			output cmd_i,
			output current_conf_i,
			output current_useful_i,
			output current_tag_i,
			output current_distance_i,
			output new_tag_i,
			output true_distance_i
		);

		modport MONITOR (
			input en_i,
			input cmd_i,
			input current_conf_i,
			input current_useful_i,
			input current_tag_i,
			input current_distance_i,
			input new_tag_i,
			input true_distance_i,
			input sram_we_o,
			input next_confidence_o,
			input next_useful_o,
			input next_tag_o,
			input next_distance_o
		);

endinterface


class tagged_update_cntrl_transaction extends uvm_sequence_item;

		typedef enum logic [1:0] {
			CMD_ALLOCATE = 2'b00,
			CMD_REWARD   = 2'b01,
			CMD_PENALIZE = 2'b10,
			CMD_DECAY    = 2'b11
		} tagged_cmd_t;

		rand logic                        en_i;
		rand tagged_cmd_t                 cmd_i;
		rand logic [CONFIDENCE_WIDTH-1:0] current_conf_i;
		rand logic [USEFUL_WIDTH-1:0]     current_useful_i;
		rand logic [TAG_WIDTH-1:0]        current_tag_i;
		rand logic [DISTANCE_WIDTH-1:0]   current_distance_i;
		rand logic [TAG_WIDTH-1:0]        new_tag_i;
		rand logic [DISTANCE_WIDTH-1:0]   true_distance_i;

		logic                        sram_we_o;
		logic [CONFIDENCE_WIDTH-1:0] next_confidence_o;
		logic [USEFUL_WIDTH-1:0]     next_useful_o;
		logic [TAG_WIDTH-1:0]        next_tag_o;
		logic [DISTANCE_WIDTH-1:0]   next_distance_o;

		`uvm_object_utils_begin(tagged_update_cntrl_transaction)
			`uvm_field_int(en_i,UVM_DEFAULT)
			`uvm_field_enum(tagged_cmd_t,cmd_i,UVM_DEFAULT)
			`uvm_field_int(current_conf_i,UVM_DEFAULT)
			`uvm_field_int(current_useful_i,UVM_DEFAULT)
			`uvm_field_int(current_tag_i,UVM_DEFAULT)
			`uvm_field_int(current_distance_i,UVM_DEFAULT)
			`uvm_field_int(new_tag_i,UVM_DEFAULT)
			`uvm_field_int(true_distance_i,UVM_DEFAULT)
			`uvm_field_int(sram_we_o,UVM_DEFAULT)
			`uvm_field_int(next_confidence_o,UVM_DEFAULT)
			`uvm_field_int(next_useful_o,UVM_DEFAULT)
			`uvm_field_int(next_tag_o,UVM_DEFAULT)
			`uvm_field_int(next_distance_o,UVM_DEFAULT)
		`uvm_object_utils_end

		function new(string name = "tagged_update_cntrl_transaction");
			super.new(name);
		endfunction

		virtual function string convert2string();

			return $sformatf(
				{"en=%0b cmd=%s current_conf=%0d current_useful=%0d current_tag=0x%0h ",
				 "current_distance=0x%0h new_tag=0x%0h true_distance=0x%0h | ",
				 "sram_we=%0b next_conf=%0d next_useful=%0d next_tag=0x%0h next_distance=0x%0h"},
				en_i,cmd_i.name(),current_conf_i,current_useful_i,current_tag_i,current_distance_i,
				new_tag_i,true_distance_i,sram_we_o,next_confidence_o,next_useful_o,next_tag_o,next_distance_o
			);

		endfunction

endclass


class tagged_update_cntrl_sequencer extends uvm_sequencer #(tagged_update_cntrl_transaction);

		`uvm_component_utils(tagged_update_cntrl_sequencer)

		function new(string name = "tagged_update_cntrl_sequencer",uvm_component parent = null);
			super.new(name,parent);
		endfunction

endclass


class tagged_update_cntrl_driver extends uvm_driver #(tagged_update_cntrl_transaction);

		virtual tagged_update_cntrl_if vif;

		`uvm_component_utils(tagged_update_cntrl_driver)

		function new(string name = "tagged_update_cntrl_driver",uvm_component parent = null);
			super.new(name,parent);
		endfunction

		virtual function void build_phase(uvm_phase phase);

			super.build_phase(phase);

			if (!uvm_config_db #(virtual tagged_update_cntrl_if)::get(this,"","vif",vif)) begin
				`uvm_fatal(get_type_name(),"Failed to get the virtual interface from the configuration database")
			end

		endfunction

		virtual task run_phase(uvm_phase phase);

			tagged_update_cntrl_transaction transaction;

			forever begin
				seq_item_port.get_next_item(transaction);
				drive_transaction(transaction);
				seq_item_port.item_done();
			end

		endtask

		virtual task drive_transaction(tagged_update_cntrl_transaction transaction);

			vif.en_i               = transaction.en_i;
			vif.cmd_i              = transaction.cmd_i;
			vif.current_conf_i     = transaction.current_conf_i;
			vif.current_useful_i   = transaction.current_useful_i;
			vif.current_tag_i      = transaction.current_tag_i;
			vif.current_distance_i = transaction.current_distance_i;
			vif.new_tag_i          = transaction.new_tag_i;
			vif.true_distance_i    = transaction.true_distance_i;

			#1step;
			-> vif.stimulus_applied;
			#1step;

			`uvm_info(get_type_name(),
				$sformatf("Transaction driven: en=%0b cmd=%0b current_conf=%0d current_useful=%0d current_tag=0x%0h current_distance=0x%0h new_tag=0x%0h true_distance=0x%0h",
					transaction.en_i,transaction.cmd_i,transaction.current_conf_i,transaction.current_useful_i,
					transaction.current_tag_i,transaction.current_distance_i,transaction.new_tag_i,transaction.true_distance_i),
				UVM_HIGH
			)

		endtask

endclass


class tagged_update_cntrl_monitor extends uvm_monitor;

		virtual tagged_update_cntrl_if vif;
		uvm_analysis_port #(tagged_update_cntrl_transaction) analysis_port;

		`uvm_component_utils(tagged_update_cntrl_monitor)

		function new(string name = "tagged_update_cntrl_monitor",uvm_component parent = null);
			super.new(name,parent);
			analysis_port = new("analysis_port",this);
		endfunction

		virtual function void build_phase(uvm_phase phase);

			super.build_phase(phase);

			if (!uvm_config_db #(virtual tagged_update_cntrl_if)::get(this,"","vif",vif)) begin
				`uvm_fatal(get_type_name(),"Failed to get the virtual interface from the configuration database")
			end

		endfunction

		virtual task run_phase(uvm_phase phase);

			tagged_update_cntrl_transaction transaction;

			forever begin

				@(vif.stimulus_applied);

				transaction = tagged_update_cntrl_transaction::type_id::create("monitored_transaction");

				transaction.en_i               = vif.en_i;
				transaction.cmd_i              = tagged_update_cntrl_transaction::tagged_cmd_t'(vif.cmd_i);
				transaction.current_conf_i     = vif.current_conf_i;
				transaction.current_useful_i   = vif.current_useful_i;
				transaction.current_tag_i      = vif.current_tag_i;
				transaction.current_distance_i = vif.current_distance_i;
				transaction.new_tag_i          = vif.new_tag_i;
				transaction.true_distance_i    = vif.true_distance_i;

				transaction.sram_we_o         = vif.sram_we_o;
				transaction.next_confidence_o = vif.next_confidence_o;
				transaction.next_useful_o     = vif.next_useful_o;
				transaction.next_tag_o        = vif.next_tag_o;
				transaction.next_distance_o   = vif.next_distance_o;

				`uvm_info(get_type_name(),
					$sformatf("Transaction monitored: en=%0b cmd=%0b current_conf=%0d current_useful=%0d current_tag=0x%0h current_distance=0x%0h new_tag=0x%0h true_distance=0x%0h | sram_we=%0b next_conf=%0d next_useful=%0d next_tag=0x%0h next_distance=0x%0h",
						transaction.en_i,transaction.cmd_i,transaction.current_conf_i,transaction.current_useful_i,
						transaction.current_tag_i,transaction.current_distance_i,transaction.new_tag_i,transaction.true_distance_i,
						transaction.sram_we_o,transaction.next_confidence_o,transaction.next_useful_o,
						transaction.next_tag_o,transaction.next_distance_o),
					UVM_HIGH
				)

				analysis_port.write(transaction);

			end

		endtask

endclass


class tagged_update_cntrl_agent extends uvm_agent;

		tagged_update_cntrl_sequencer sequencer;
		tagged_update_cntrl_driver    driver;
		tagged_update_cntrl_monitor   monitor;

		uvm_analysis_port #(tagged_update_cntrl_transaction) analysis_port;

		`uvm_component_utils(tagged_update_cntrl_agent)

		function new(string name = "tagged_update_cntrl_agent",uvm_component parent = null);
			super.new(name,parent);
			analysis_port = new("analysis_port",this);
		endfunction

		virtual function void build_phase(uvm_phase phase);

			super.build_phase(phase);

			monitor = tagged_update_cntrl_monitor::type_id::create("monitor",this);

			if (get_is_active() == UVM_ACTIVE) begin
				sequencer = tagged_update_cntrl_sequencer::type_id::create("sequencer",this);
				driver    = tagged_update_cntrl_driver::type_id::create("driver",this);
			end

		endfunction

		virtual function void connect_phase(uvm_phase phase);

			super.connect_phase(phase);

			if (get_is_active() == UVM_ACTIVE) begin
				driver.seq_item_port.connect(sequencer.seq_item_export);
			end

			monitor.analysis_port.connect(analysis_port);

		endfunction

endclass


class tagged_update_cntrl_scoreboard extends uvm_scoreboard;

		uvm_analysis_imp #(tagged_update_cntrl_transaction,tagged_update_cntrl_scoreboard) analysis_imp;

		int unsigned transaction_count;
		int unsigned pass_count;
		int unsigned fail_count;

		`uvm_component_utils(tagged_update_cntrl_scoreboard)

		function new(string name = "tagged_update_cntrl_scoreboard",uvm_component parent = null);
			super.new(name,parent);
			analysis_imp = new("analysis_imp",this);
		endfunction

		virtual function void write(tagged_update_cntrl_transaction transaction);

			logic                        expected_sram_we;
			logic [CONFIDENCE_WIDTH-1:0] expected_confidence;
			logic [USEFUL_WIDTH-1:0]     expected_useful;
			logic [TAG_WIDTH-1:0]        expected_tag;
			logic [DISTANCE_WIDTH-1:0]   expected_distance;
			bit                          protocol_error;
			bit                          mismatch;
			string                       protocol_reason;
			string                       result_message;

			transaction_count++;

			protocol_error  = 1'b0;
			protocol_reason = "OK";

			expected_sram_we    = 1'b0;
			expected_confidence = '0;
			expected_useful     = '0;
			expected_tag        = '0;
			expected_distance   = '0;

			if ($isunknown(transaction.en_i)) begin
				fail_count++;
				`uvm_error(get_type_name(),$sformatf("Transaction #%0d cannot be predicted because en_i is X or Z",transaction_count))
				return;
			end

			if (transaction.en_i == 1'b1) begin

				case (transaction.cmd_i)

					tagged_update_cntrl_transaction::CMD_ALLOCATE: begin
						if ($isunknown({transaction.current_conf_i,transaction.current_useful_i,transaction.new_tag_i,transaction.true_distance_i})) begin
							protocol_error  = 1'b1;
							protocol_reason = "ALLOCATE contains unknown required inputs";
						end
						else if ((transaction.current_conf_i != MIN_CONFIDENCE) || (transaction.current_useful_i != MIN_USEFUL)) begin
							protocol_error  = 1'b1;
							protocol_reason = "Invalid ALLOCATE: current confidence and usefulness must both be zero";
						end
					end

					tagged_update_cntrl_transaction::CMD_REWARD: begin
						if ($isunknown({transaction.current_tag_i,transaction.current_distance_i,transaction.new_tag_i,transaction.true_distance_i})) begin
							protocol_error  = 1'b1;
							protocol_reason = "REWARD contains unknown tag or distance inputs";
						end
						else if ((transaction.current_tag_i != transaction.new_tag_i) ||
								 (transaction.current_distance_i != transaction.true_distance_i)) begin
							protocol_error  = 1'b1;
							protocol_reason = "Invalid REWARD: current/new tags and current/true distances must match";
						end
					end

					tagged_update_cntrl_transaction::CMD_PENALIZE: begin
						if ($isunknown({transaction.current_conf_i,transaction.current_useful_i,transaction.current_tag_i,
										transaction.current_distance_i,transaction.new_tag_i,transaction.true_distance_i})) begin
							protocol_error  = 1'b1;
							protocol_reason = "PENALIZE contains unknown required inputs";
						end
						else if (transaction.current_tag_i == transaction.new_tag_i) begin
							protocol_error  = 1'b1;
							protocol_reason = "Invalid PENALIZE scenario: current and new tags must differ";
						end
						else if (transaction.current_distance_i == transaction.true_distance_i) begin
							protocol_error  = 1'b1;
							protocol_reason = "Invalid PENALIZE scenario: current and true distances must differ";
						end
					end

					tagged_update_cntrl_transaction::CMD_DECAY: begin
						if ($isunknown({transaction.current_conf_i,transaction.current_useful_i,
										transaction.current_tag_i,transaction.current_distance_i})) begin
							protocol_error  = 1'b1;
							protocol_reason = "DECAY contains unknown current-entry inputs";
						end
					end

					default: begin
						protocol_error  = 1'b1;
						protocol_reason = "Enabled transaction contains an invalid or unknown command";
					end

				endcase
			end

			if (transaction.en_i == 1'b1) begin

				expected_sram_we = 1'b1;

				case (transaction.cmd_i)

					tagged_update_cntrl_transaction::CMD_ALLOCATE: begin
						expected_tag        = transaction.new_tag_i;
						expected_distance   = transaction.true_distance_i;
						expected_confidence = WEAK_CONFIDENCE;
						expected_useful     = INITIAL_USEFUL;
					end

					tagged_update_cntrl_transaction::CMD_REWARD: begin
						expected_tag        = transaction.current_tag_i;
						expected_distance   = transaction.current_distance_i;
						expected_confidence = (transaction.current_conf_i == MAX_CONFIDENCE) ? MAX_CONFIDENCE : transaction.current_conf_i + 1'b1;
						expected_useful     = (transaction.current_useful_i == MAX_USEFUL) ? MAX_USEFUL : transaction.current_useful_i + 1'b1;
					end

					tagged_update_cntrl_transaction::CMD_PENALIZE: begin
						expected_tag    = transaction.current_tag_i;
						expected_useful = transaction.current_useful_i;

						if (transaction.current_conf_i == MIN_CONFIDENCE) begin
							expected_distance   = transaction.true_distance_i;
							expected_confidence = transaction.current_conf_i;
						end
						else begin
							expected_distance   = transaction.current_distance_i;
							expected_confidence = transaction.current_conf_i - 1'b1;
						end
					end

					tagged_update_cntrl_transaction::CMD_DECAY: begin
						expected_tag        = transaction.current_tag_i;
						expected_distance   = transaction.current_distance_i;
						expected_confidence = transaction.current_conf_i;
						expected_useful     = (transaction.current_useful_i == MIN_USEFUL) ? MIN_USEFUL : transaction.current_useful_i - 1'b1;
					end

					default: begin
						expected_sram_we    = 1'b0;
						expected_confidence = '0;
						expected_useful     = '0;
						expected_tag        = '0;
						expected_distance   = '0;
					end

				endcase
			end

			mismatch = protocol_error ||
					   (transaction.sram_we_o !== expected_sram_we) ||
					   (transaction.next_confidence_o !== expected_confidence) ||
					   (transaction.next_useful_o !== expected_useful) ||
					   (transaction.next_tag_o !== expected_tag) ||
					   (transaction.next_distance_o !== expected_distance);

			result_message = $sformatf(
				{"Transaction #%0d: %s\n",
				 "  Protocol : %s\n",
				 "  Inputs   : en=%0b cmd=%s(%0b) current_confidence=%0d current_useful=%0d current_tag=0x%0h current_distance=0x%0h new_tag=0x%0h true_distance=0x%0h\n",
				 "  Expected : sram_we=%0b next_confidence=%0d next_useful=%0d next_tag=0x%0h next_distance=0x%0h\n",
				 "  Actual   : sram_we=%0b next_confidence=%0d next_useful=%0d next_tag=0x%0h next_distance=0x%0h"},
				transaction_count,mismatch ? "FAIL" : "PASS",protocol_reason,
				transaction.en_i,transaction.cmd_i.name(),transaction.cmd_i,transaction.current_conf_i,
				transaction.current_useful_i,transaction.current_tag_i,transaction.current_distance_i,
				transaction.new_tag_i,transaction.true_distance_i,
				expected_sram_we,expected_confidence,expected_useful,expected_tag,expected_distance,
				transaction.sram_we_o,transaction.next_confidence_o,transaction.next_useful_o,
				transaction.next_tag_o,transaction.next_distance_o
			);

			if (mismatch) begin
				fail_count++;
				`uvm_error("TAGGED_UPDATE_MISMATCH",result_message)
			end
			else begin
				pass_count++;
				`uvm_info("TAGGED_UPDATE_PASS",result_message,UVM_LOW)
			end

		endfunction

		virtual function void report_phase(uvm_phase phase);

			super.report_phase(phase);

			`uvm_info(get_type_name(),
				$sformatf("Scoreboard summary: TOTAL=%0d PASS=%0d FAIL=%0d",transaction_count,pass_count,fail_count),
				UVM_NONE
			)

		endfunction

endclass


class tagged_update_cntrl_env extends uvm_env;

		tagged_update_cntrl_agent      agent;
		tagged_update_cntrl_scoreboard scoreboard;

		`uvm_component_utils(tagged_update_cntrl_env)

		function new(string name = "tagged_update_cntrl_env",uvm_component parent = null);
			super.new(name,parent);
		endfunction

		virtual function void build_phase(uvm_phase phase);

			super.build_phase(phase);

			agent      = tagged_update_cntrl_agent::type_id::create("agent",this);
			scoreboard = tagged_update_cntrl_scoreboard::type_id::create("scoreboard",this);

		endfunction

		virtual function void connect_phase(uvm_phase phase);

			super.connect_phase(phase);
			agent.analysis_port.connect(scoreboard.analysis_imp);

		endfunction

endclass