package provider_update_params_pkg;

    parameter int unsigned NUM_TAGGED_TABLES = 7;
	parameter int unsigned NUM_PROVIDERS = NUM_TAGGED_TABLES + 1;
    parameter int unsigned PROVIDER_ID_WIDTH = $clog2(NUM_PROVIDERS);
    parameter int unsigned BASE_S_WIDTH = 10;
    parameter int unsigned S_WIDTH = 7;
    parameter int unsigned T_WIDTH = 16;

    parameter int unsigned TABLE_CMD_WIDTH = 2;

    typedef enum logic [TABLE_CMD_WIDTH-1:0] {
        CMD_ALLOCATE = 2'b00,
        CMD_REWARD   = 2'b01,
        CMD_PENALIZE = 2'b10,
        CMD_DECAY    = 2'b11
    } provider_table_cmd_e;

    typedef logic [PROVIDER_ID_WIDTH-1:0] provider_id_t;

    localparam provider_id_t BASE_PROVIDER_ID = provider_id_t'(0);
    localparam provider_id_t FIRST_TAGGED_PROVIDER_ID = provider_id_t'(1);
    localparam provider_id_t LAST_TAGGED_PROVIDER_ID = provider_id_t'(NUM_TAGGED_TABLES);

    typedef logic [NUM_TAGGED_TABLES-1:0] tagged_table_mask_t;
    typedef logic [BASE_S_WIDTH-1:0] base_index_t;
    typedef logic [S_WIDTH-1:0] tagged_index_t;
    typedef logic [T_WIDTH-1:0] tagged_tag_t;

    typedef tagged_index_t tagged_index_array_t [0:NUM_TAGGED_TABLES-1];
    typedef tagged_tag_t tagged_tag_array_t [0:NUM_TAGGED_TABLES-1];
    typedef provider_table_cmd_e table_cmd_array_t [0:NUM_TAGGED_TABLES-1];

    typedef logic [TABLE_CMD_WIDTH-1:0] raw_table_cmd_array_t [0:NUM_TAGGED_TABLES-1];

    parameter time CLK_PERIOD     = 10ns;
    parameter time CLK_HALF_PERIOD = CLK_PERIOD / 2;

    parameter int unsigned RESET_CYCLES = 5;

endpackage


import uvm_pkg::*;
`include "uvm_macros.svh";
import provider_update_params_pkg::*;


interface provider_update_if (
    input logic clk
    // input logic rst_n
);

	import provider_update_params_pkg::*;	

    logic rst_n;
    logic commit_valid_i;
    logic commit_mispredicted_i;
    provider_id_t provider_id_i;
    tagged_table_mask_t current_LFSR_value_input;
    tagged_table_mask_t table_empty_mask_i;
    base_index_t commit_base_idx_i;
    tagged_index_t commit_tagged_indices_i
					[0:NUM_TAGGED_TABLES-1];
    tagged_tag_t commit_tagged_tags_i 
					[0:NUM_TAGGED_TABLES-1];

	// DUT Output signals
	logic base_update_en_o;
    base_index_t base_update_idx_o;
    tagged_table_mask_t tagged_table_update_en_o;
    logic [TABLE_CMD_WIDTH-1:0] table_cmd_o [0:NUM_TAGGED_TABLES-1];

    tagged_index_t update_tagged_indices_o
			        [0:NUM_TAGGED_TABLES-1];
    tagged_tag_t update_tagged_tags_o
        			[0:NUM_TAGGED_TABLES-1];


    clocking driver_cb @(negedge clk);

        default input #1step output #0;
        output commit_valid_i;
        output commit_mispredicted_i;
        output provider_id_i;
        output current_LFSR_value_input;
        output table_empty_mask_i;
        output commit_base_idx_i;
        output commit_tagged_indices_i;
        output commit_tagged_tags_i;

        input base_update_en_o;
        input base_update_idx_o;
        input tagged_table_update_en_o;
        input table_cmd_o;
        input update_tagged_indices_o;
        input update_tagged_tags_o;

    endclocking

    clocking monitor_cb @(posedge clk);

        default input #0;
        input rst_n;
        input commit_valid_i;
        input commit_mispredicted_i;
        input provider_id_i;
        input current_LFSR_value_input;
        input table_empty_mask_i;
        input commit_base_idx_i;
        input commit_tagged_indices_i;
        input commit_tagged_tags_i;

        input base_update_en_o;
        input base_update_idx_o;
        input tagged_table_update_en_o;
        input table_cmd_o;
        input update_tagged_indices_o;
        input update_tagged_tags_o;

    endclocking


    modport DUT_MP (
        input  clk,
        input  rst_n,

        input  commit_valid_i,
        input  commit_mispredicted_i,
        input  provider_id_i,
        input  current_LFSR_value_input,
        input  table_empty_mask_i,
        input  commit_base_idx_i,
        input  commit_tagged_indices_i,
        input  commit_tagged_tags_i,

        output base_update_en_o,
        output base_update_idx_o,
        output tagged_table_update_en_o,
        output table_cmd_o,
        output update_tagged_indices_o,
        output update_tagged_tags_o
    );

    modport DRIVER_MP (
        clocking driver_cb,
        input clk,
        input rst_n
    );

    modport MONITOR_MP (
        clocking monitor_cb,
        input clk,
        input rst_n
    );

    task automatic initialize_inputs();

        commit_valid_i             = 1'b0;
        commit_mispredicted_i      = 1'b0;
        provider_id_i              = BASE_PROVIDER_ID;
        current_LFSR_value_input   = '0;
        table_empty_mask_i         = '0;
        commit_base_idx_i          = '0;

        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            commit_tagged_indices_i[i] = '0;
            commit_tagged_tags_i[i]    = '0;
        end

    endtask


    /// for running RESET SEQUENCE IN THE DESIGN
    task automatic apply_reset(int unsigned reset_cycle_count);

        rst_n = 1'b0;

        repeat (reset_cycle_count) begin
            @(negedge clk);
        end

        rst_n = 1'b1;

        @(negedge clk);

    endtask

endinterface



/// sequence item
class provider_update_seq_item extends uvm_sequence_item;

    rand logic commit_valid_i;
    rand logic commit_mispredicted_i;
    rand provider_id_t provider_id_i;
    rand tagged_table_mask_t current_LFSR_value_input;
    rand tagged_table_mask_t table_empty_mask_i;
    rand base_index_t commit_base_idx_i;
    rand tagged_index_array_t commit_tagged_indices_i;
    rand tagged_tag_array_t   commit_tagged_tags_i;


    logic base_update_en_o;
    base_index_t base_update_idx_o;
    tagged_table_mask_t tagged_table_update_en_o;
    raw_table_cmd_array_t table_cmd_o;
    tagged_index_array_t update_tagged_indices_o;
    tagged_tag_array_t   update_tagged_tags_o;

    longint unsigned sampled_cycle;
	time sampled_timestamp;

    bit is_observed_transaction;

	// Constraints
    constraint provider_id_c {
        provider_id_i inside {
            [BASE_PROVIDER_ID:LAST_TAGGED_PROVIDER_ID]
        };
    }

    `uvm_object_utils_begin(provider_update_seq_item)

        // inputs
        `uvm_field_int(commit_valid_i,            UVM_DEFAULT)
        `uvm_field_int(commit_mispredicted_i,     UVM_DEFAULT)
        `uvm_field_int(provider_id_i,              UVM_DEFAULT)
        `uvm_field_int(current_LFSR_value_input,   UVM_DEFAULT)
        `uvm_field_int(table_empty_mask_i,         UVM_DEFAULT)
        `uvm_field_int(commit_base_idx_i,          UVM_DEFAULT)
        `uvm_field_sarray_int(commit_tagged_indices_i,UVM_DEFAULT)
        `uvm_field_sarray_int(commit_tagged_tags_i,UVM_DEFAULT)

        // outputs
        `uvm_field_int(base_update_en_o,           UVM_DEFAULT)
        `uvm_field_int(base_update_idx_o,          UVM_DEFAULT)
        `uvm_field_int(tagged_table_update_en_o,   UVM_DEFAULT)
        `uvm_field_sarray_int(table_cmd_o, UVM_DEFAULT)

        `uvm_field_sarray_int(update_tagged_indices_o, UVM_DEFAULT)

        `uvm_field_sarray_int(update_tagged_tags_o,UVM_DEFAULT)

        `uvm_field_int(sampled_cycle, UVM_DEFAULT | UVM_DEC)

        `uvm_field_int(is_observed_transaction,UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "provider_update_seq_item");
        super.new(name);
        clear_inputs();
        clear_outputs();
        sampled_cycle          = 0;
        is_observed_transaction = 1'b0;
    endfunction

    function void clear_inputs();
        commit_valid_i           = 1'b0;
        commit_mispredicted_i    = 1'b0;
        provider_id_i            = BASE_PROVIDER_ID;
        current_LFSR_value_input = '0;
        table_empty_mask_i       = '0;
        commit_base_idx_i        = '0;
        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			commit_tagged_indices_i[i] = '0;
			commit_tagged_tags_i[i]    = '0;
		end
    endfunction

    function void clear_outputs();

        base_update_en_o         = 1'b0;
        base_update_idx_o        = '0;
        tagged_table_update_en_o = '0;
        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
			table_cmd_o[i]             = CMD_ALLOCATE;
			update_tagged_indices_o[i] = '0;
			update_tagged_tags_o[i]    = '0;
		end

    endfunction

    function string get_command_name(int unsigned table_number);

        provider_table_cmd_e command;
        if (table_number >= NUM_TAGGED_TABLES) begin
            return "INVALID_TABLE";
        end
        command = provider_table_cmd_e'(table_cmd_o[table_number]);
        return command.name();
    endfunction


    virtual function string convert2string();

        string result;
        result = $sformatf(
            {
                "valid=%0b mispredicted=%0b provider_id=%0d ",
                "lfsr=0x%0h empty_mask=0x%0h base_idx=0x%0h ",
                "base_en=%0b base_out_idx=0x%0h tagged_en=0x%0h ",
                "sampled_cycle=%0d"
            },
            commit_valid_i,
            commit_mispredicted_i,
            provider_id_i,
            current_LFSR_value_input,
            table_empty_mask_i,
            commit_base_idx_i,
            base_update_en_o,
            base_update_idx_o,
            tagged_table_update_en_o,
            sampled_cycle
        );
        return result;
    endfunction

    function string tagged_tables2string();

        string result;
        result = "";
        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

            result = {result,
                $sformatf(
                    {
                        "\n  T%0d: input_idx=0x%0h input_tag=0x%0h ",
                        "update_en=%0b cmd=%s ",
                        "output_idx=0x%0h output_tag=0x%0h"
                    },
                    i + 1,
                    commit_tagged_indices_i[i],
                    commit_tagged_tags_i[i],
                    tagged_table_update_en_o[i],
                    get_command_name(i),
                    update_tagged_indices_o[i],
                    update_tagged_tags_o[i]
                )
            };

        end
        return result;
    endfunction

endclass



/// sequencer
class provider_update_sequencer extends uvm_sequencer #(provider_update_seq_item);

    `uvm_component_utils(provider_update_sequencer)

    function new(string name = "provider_update_sequencer",uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass


// driver
class provider_update_driver extends uvm_driver #(provider_update_seq_item);

    `uvm_component_utils(provider_update_driver)

    virtual provider_update_if vif;

    function new(string name = "provider_update_driver",uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual provider_update_if)::get(this,"","vif",vif)) begin
            `uvm_fatal("NO_VIF",
                {
                    "provider_update_driver could not obtain ",
                    "provider_update_if from uvm_config_db"
                }
            )
        end
    endfunction


    virtual task run_phase(uvm_phase phase);

        provider_update_seq_item req;
        forever begin
            @(vif.driver_cb);
            if (vif.rst_n !== 1'b1) begin
                drive_idle();
            end
            else begin
                req = null;
                seq_item_port.try_next_item(req);
                if (req != null) begin
                    drive_request(req);
                    `uvm_info("DRV",$sformatf("Driving transaction: %s",req.convert2string()),UVM_HIGH)
                    seq_item_port.item_done();
                end
                else begin
                    drive_idle();
                end
            end
        end
    endtask


    virtual task drive_request(provider_update_seq_item req);

        vif.driver_cb.commit_valid_i <= req.commit_valid_i;
        vif.driver_cb.commit_mispredicted_i <= req.commit_mispredicted_i;
        vif.driver_cb.provider_id_i <= req.provider_id_i;
        vif.driver_cb.current_LFSR_value_input <= req.current_LFSR_value_input;
        vif.driver_cb.table_empty_mask_i <= req.table_empty_mask_i;
        vif.driver_cb.commit_base_idx_i <= req.commit_base_idx_i;

        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            vif.driver_cb.commit_tagged_indices_i[i] <= req.commit_tagged_indices_i[i];
            vif.driver_cb.commit_tagged_tags_i[i] <= req.commit_tagged_tags_i[i];
        end
    endtask


    virtual task drive_idle();

        vif.driver_cb.commit_valid_i <= 1'b0;
        vif.driver_cb.commit_mispredicted_i <= 1'b0;
        vif.driver_cb.provider_id_i <= BASE_PROVIDER_ID;
        vif.driver_cb.current_LFSR_value_input <= '0;
        vif.driver_cb.table_empty_mask_i <= '0;
        vif.driver_cb.commit_base_idx_i <= '0;

        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

            vif.driver_cb.commit_tagged_indices_i[i] <= '0;
            vif.driver_cb.commit_tagged_tags_i[i] <= '0;
        end
    endtask

endclass



/// monitor
class provider_update_monitor extends uvm_monitor;

    `uvm_component_utils(provider_update_monitor)

    virtual provider_update_if vif;
    uvm_analysis_port #(provider_update_seq_item) analysis_port;
    longint unsigned cycle_count;

    function new(string name = "provider_update_monitor",uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
        cycle_count   = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual provider_update_if)::get(this,"","vif",vif)) begin
            `uvm_fatal("NO_VIF",
                {
                    "provider_update_monitor could not obtain ",
                    "provider_update_if from uvm_config_db"
                }
            )
        end
    endfunction

    virtual task run_phase(uvm_phase phase);

        provider_update_seq_item observed_item;
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.rst_n !== 1'b1) begin
                cycle_count = 0;
            end
            else begin
                observed_item = provider_update_seq_item::type_id::create("observed_item",this);
                sample_inputs(observed_item);
                sample_outputs(observed_item);
                observed_item.sampled_cycle = cycle_count;
				observed_item.sampled_timestamp = $time;
                observed_item.is_observed_transaction = 1'b1;

                `uvm_info("MON",
                    $sformatf(
                        {
                            "Observed transaction at timestamp %0t, cycle %0d: %s%s"
                        },
                        observed_item.sampled_timestamp,
                        observed_item.sampled_cycle,
                        observed_item.convert2string(),
                        observed_item.tagged_tables2string()
                    ),UVM_HIGH)

                analysis_port.write(observed_item);
                cycle_count++;
            end
        end
    endtask


	virtual function void sample_inputs(provider_update_seq_item item);

        item.commit_valid_i = vif.monitor_cb.commit_valid_i;
        item.commit_mispredicted_i = vif.monitor_cb.commit_mispredicted_i;
        item.provider_id_i = vif.monitor_cb.provider_id_i;
        item.current_LFSR_value_input = vif.monitor_cb.current_LFSR_value_input;
        item.table_empty_mask_i = vif.monitor_cb.table_empty_mask_i;
        item.commit_base_idx_i = vif.monitor_cb.commit_base_idx_i;

        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            item.commit_tagged_indices_i[i] = vif.monitor_cb.commit_tagged_indices_i[i];
            item.commit_tagged_tags_i[i] = vif.monitor_cb.commit_tagged_tags_i[i];
        end
    endfunction


    virtual function void sample_outputs(provider_update_seq_item item);

        item.base_update_en_o = vif.monitor_cb.base_update_en_o;
        item.base_update_idx_o = vif.monitor_cb.base_update_idx_o;
        item.tagged_table_update_en_o = vif.monitor_cb.tagged_table_update_en_o;

        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            item.table_cmd_o[i] = vif.monitor_cb.table_cmd_o[i];
            item.update_tagged_indices_o[i] = vif.monitor_cb.update_tagged_indices_o[i];
            item.update_tagged_tags_o[i] = vif.monitor_cb.update_tagged_tags_o[i];
        end
    endfunction
endclass



/// agent
class provider_update_agent extends uvm_agent;

    `uvm_component_utils(provider_update_agent)

    provider_update_sequencer sequencer;
    provider_update_driver    driver;
    provider_update_monitor   monitor;

    uvm_analysis_port #(provider_update_seq_item) analysis_port;

    function new(string name = "provider_update_agent",uvm_component parent = null);
        super.new(name, parent);
        analysis_port = new("analysis_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        monitor = provider_update_monitor::type_id::create("monitor",this);
        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = provider_update_sequencer::type_id::create("sequencer",this);
            driver = provider_update_driver::type_id::create("driver",this);
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



/// scoreboard
class provider_update_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(provider_update_scoreboard)

    uvm_analysis_imp #(provider_update_seq_item,provider_update_scoreboard) analysis_imp;

    provider_update_seq_item previous_item;
    bit previous_item_valid;
	// time previous_input_timestamp;
    int unsigned checked_count;
    int unsigned passed_count;
    int unsigned error_count;

    function new(string name = "provider_update_scoreboard",uvm_component parent = null);

        super.new(name, parent);
        analysis_imp = new("analysis_imp", this);
        previous_item_valid = 1'b0;
        checked_count       = 0;
        passed_count        = 0;
        error_count         = 0;
		// previous_input_timestamp = 0;
    endfunction


	/// analysis write function
    virtual function void write(provider_update_seq_item observed_item);

        int unsigned errors_before_check;
        bit transaction_passed;

		if (observed_item.sampled_cycle == 0) begin
            previous_item_valid = 1'b0;
        end

        if (previous_item_valid) begin

            errors_before_check = error_count;

            check_transaction(previous_item,observed_item);
            checked_count++;

            transaction_passed = (error_count == errors_before_check);

            display_transaction_data(
                previous_item,
                observed_item
                // transaction_passed
            );

            if (transaction_passed) begin
                passed_count++;

                `uvm_info("SCB_PASS",
				    $sformatf(
					    {
						    "Output at timestamp %0t, cycle %0d passed. ",
						    "It corresponds to input timestamp %0t, cycle %0d"
					    },
					    observed_item.sampled_timestamp,
					    observed_item.sampled_cycle,
					    previous_item.sampled_timestamp,
					    previous_item.sampled_cycle
				    ),UVM_LOW)
            end
        end

        save_current_inputs(observed_item);
    endfunction

    // Saving current top-level inputs for checking on the following cycle
    virtual function void save_current_inputs(provider_update_seq_item observed_item);

        previous_item = provider_update_seq_item::type_id::create("previous_item");

        previous_item.commit_valid_i = observed_item.commit_valid_i;
        previous_item.commit_mispredicted_i = observed_item.commit_mispredicted_i;
        previous_item.provider_id_i = observed_item.provider_id_i;
        previous_item.current_LFSR_value_input = observed_item.current_LFSR_value_input;
        previous_item.table_empty_mask_i = observed_item.table_empty_mask_i;
        previous_item.commit_base_idx_i = observed_item.commit_base_idx_i;

        for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
            previous_item.commit_tagged_indices_i[i] = observed_item.commit_tagged_indices_i[i];
            previous_item.commit_tagged_tags_i[i] = observed_item.commit_tagged_tags_i[i];
        end

		/// to see the output pins values at the time of input sampling 
		previous_item.base_update_en_o = observed_item.base_update_en_o;

		previous_item.base_update_idx_o = observed_item.base_update_idx_o;

		previous_item.tagged_table_update_en_o = observed_item.tagged_table_update_en_o;

		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

			previous_item.table_cmd_o[i] = observed_item.table_cmd_o[i];

			previous_item.update_tagged_indices_o[i] = observed_item.update_tagged_indices_o[i];

			previous_item.update_tagged_tags_o[i] = observed_item.update_tagged_tags_o[i];

		end

        previous_item.sampled_cycle = observed_item.sampled_cycle;
		previous_item.sampled_timestamp = observed_item.sampled_timestamp;
        previous_item_valid = 1'b1;
    endfunction

	/// checking function
	virtual function void check_transaction(provider_update_seq_item request_item,provider_update_seq_item actual_item);

		// display_transaction_data(request_item,actual_item);
        check_base_update(request_item,actual_item);

        if (request_item.commit_valid_i !== 1'b1) begin
            check_idle_tagged_outputs(actual_item);
        end
        else if (request_item.commit_mispredicted_i === 1'b0) begin
            check_correct_prediction(request_item,actual_item);
        end
        else if (request_item.commit_mispredicted_i === 1'b1) begin
            check_misprediction(request_item,actual_item);
        end
        else begin
            report_error("MISPREDICT_X",
                $sformatf("commit_mispredicted_i contains X/Z for request cycle %0d",request_item.sampled_cycle));
        end
    endfunction

	// 
	/// displaying the input and output data used by the scoreboard
	virtual function void display_transaction_data(
		provider_update_seq_item request_item,
		provider_update_seq_item actual_item
	);
	
		string display_string;
	
		tagged_table_mask_t eligibility_mask;
	
		tagged_index_t selected_tagged_index;
		tagged_tag_t   selected_tagged_tag;
	
	
		// -------------------------------------------------------------------------
		// Calculate the eligibility mask.
		//
		// Eligibility is generated only during a valid misprediction.
		// -------------------------------------------------------------------------
	
		eligibility_mask = '0;
	
		if ((request_item.commit_valid_i === 1'b1) &&
			(request_item.commit_mispredicted_i === 1'b1)) begin
	
			for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
	
				if ((i + 1) > int'(request_item.provider_id_i)) begin
					eligibility_mask[i] = 1'b1;
				end
	
			end
	
		end
	
	
		// -------------------------------------------------------------------------
		// Select the tagged index and tag belonging to the provider.
		//
		// Provider ID 1 selects array position 0.
		// Provider ID 2 selects array position 1.
		// ...
		// Provider ID 7 selects array position 6.
		//
		// For the base provider, these values remain zero.
		// -------------------------------------------------------------------------
	
		selected_tagged_index = '0;
		selected_tagged_tag   = '0;
	
		if ((request_item.provider_id_i >= FIRST_TAGGED_PROVIDER_ID) &&
			(request_item.provider_id_i <= LAST_TAGGED_PROVIDER_ID)) begin
	
			selected_tagged_index =
				request_item.commit_tagged_indices_i[
					int'(request_item.provider_id_i) - 1
				];
	
			selected_tagged_tag =
				request_item.commit_tagged_tags_i[
					int'(request_item.provider_id_i) - 1
				];
	
		end
	
	
		// -------------------------------------------------------------------------
		// General transaction information
		// -------------------------------------------------------------------------
	
		display_string = $sformatf(
			{
				"\n",
				"\n==========================================================================",
				"\n                         SCOREBOARD TRANSACTION",
				"\n==========================================================================",
				"\n",
				"\nINPUT INFORMATION",
				"\n--------------------------------------------------------------------------",
				"\nInput timestamp                 : %0t",
				"\nInput sampled cycle             : %0d",
				"\ncommit_valid_i                  : %0b",
				"\ncommit_mispredicted_i           : %0b",
				"\nprovider_id_i                   : %0d",
				"\ncurrent_LFSR_value_input        : 0b%0b",
				"\nEligibility mask                : 0b%0b",
				"\ntable_empty_mask_i              : 0b%0b",
				"\ncommit_base_idx_i               : 0x%0h",
				"\ncommit_tagged_indices_i[T%0d]   : 0x%0h",
				"\ncommit_tagged_tags_i[T%0d]      : 0x%0h",
				"\n",
				"\nOUTPUTS VISIBLE AT INPUT SAMPLE TIME",
				"\n--------------------------------------------------------------------------",
				"\ninput_edge_base_update_en_o      : %0b",
				"\ninput_edge_base_update_idx_o     : 0x%0h",
				"\ninput_edge_tagged_update_en_o    : 0b%0b",
				"\n",
				"\nOUTPUT INFORMATION",
				"\n--------------------------------------------------------------------------",
				"\nOutput timestamp                : %0t",
				"\nOutput sampled cycle            : %0d",
				"\nbase_update_en_o                : %0b",
				"\nbase_update_idx_o               : 0x%0h",
				"\ntagged_table_update_en_o        : 0b%0b"
			},
			request_item.sampled_timestamp,
			request_item.sampled_cycle,
			request_item.commit_valid_i,
			request_item.commit_mispredicted_i,
			request_item.provider_id_i,
			request_item.current_LFSR_value_input,
			eligibility_mask,
			request_item.table_empty_mask_i,
			request_item.commit_base_idx_i,
	
			request_item.provider_id_i,
			selected_tagged_index,
	
			request_item.provider_id_i,
			selected_tagged_tag,

			request_item.base_update_en_o,
			request_item.base_update_idx_o,
			request_item.tagged_table_update_en_o,
	
			actual_item.sampled_timestamp,
			actual_item.sampled_cycle,
			actual_item.base_update_en_o,
			actual_item.base_update_idx_o,
			actual_item.tagged_table_update_en_o
		);
	
	
		// -------------------------------------------------------------------------
		// Table inputs
		//
		// T0 is the base table.
		// T1 through T7 are the tagged tables.
		// -------------------------------------------------------------------------
	
		display_string = {
			display_string,
			"\n",
			"\nTABLE INPUTS (T0 - T7)",
			"\n--------------------------------------------------------------------------",
			$sformatf(
				"\nT0 input index                  : 0x%0h",
				request_item.commit_base_idx_i
			)
		};
	
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
	
			display_string = {
				display_string,
				$sformatf(
					{
						"\nT%0d input index                : 0x%0h",
						"\nT%0d input tag                  : 0x%0h"
					},
					i + 1,
					request_item.commit_tagged_indices_i[i],
					i + 1,
					request_item.commit_tagged_tags_i[i]
				)
			};
	
		end
	
	
		// -------------------------------------------------------------------------
		// Table outputs
		//
		// T0 does not have a command or tag output.
		// T1 through T7 have enable, command, index, and tag outputs.
		// -------------------------------------------------------------------------
	
		display_string = {
			display_string,
			"\n",
			"\nTABLE OUTPUTS (T0 - T7)",
			"\n--------------------------------------------------------------------------",
			$sformatf(
				{
					"\nT0 update enable                : %0b",
					"\nT0 output index                 : 0x%0h",
					"\n"
				},
				actual_item.base_update_en_o,
				actual_item.base_update_idx_o
			)
		};
	
		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
	
			display_string = {
				display_string,
				$sformatf(
					{
						"\nT%0d update enable              : %0b",
						"\nT%0d command                    : %s (0x%0h)",
						"\nT%0d output index               : 0x%0h",
						"\nT%0d output tag                 : 0x%0h",
						"\n"
					},
					i + 1,
					actual_item.tagged_table_update_en_o[i],
	
					i + 1,
					actual_item.get_command_name(i),
					actual_item.table_cmd_o[i],
	
					i + 1,
					actual_item.update_tagged_indices_o[i],
	
					i + 1,
					actual_item.update_tagged_tags_o[i]
				)
			};
	
		end
	
	
		// -------------------------------------------------------------------------
		// End of transaction display
		// -------------------------------------------------------------------------
	
		display_string = {
			display_string,
			"\n=========================================================================="
		};
	
		`uvm_info(
			"SCB_DATA",
			display_string,
			UVM_LOW
		)
	
	endfunction




	// checking the base table behavior
	virtual function void check_base_update(
    provider_update_seq_item request_item,
    provider_update_seq_item actual_item
);

    logic expected_base_update_en;

    // The base table is updated only when:
    //   1. The commit is valid.
    //   2. The base table was the prediction provider.
    expected_base_update_en =
        (request_item.commit_valid_i === 1'b1) &&
        (request_item.provider_id_i === BASE_PROVIDER_ID);


    // Check the base-table update enable.
    if (actual_item.base_update_en_o !==
        expected_base_update_en) begin

        report_error(
            "BASE_ENABLE",
            $sformatf(
                {
                    "Cycle %0d: provider_id=%0d, ",
                    "expected base_update_en_o=%0b, actual=%0b"
                },
                actual_item.sampled_cycle,
                request_item.provider_id_i,
                expected_base_update_en,
                actual_item.base_update_en_o
            )
        );

    end


    // Check the base index only when the base table is being updated.
    if (expected_base_update_en === 1'b1) begin

        if (actual_item.base_update_idx_o !==
            request_item.commit_base_idx_i) begin

            report_error(
                "BASE_INDEX",
                $sformatf(
                    {
                        "Cycle %0d: expected base index=0x%0h, ",
                        "actual base index=0x%0h"
                    },
                    actual_item.sampled_cycle,
                    request_item.commit_base_idx_i,
                    actual_item.base_update_idx_o
                )
            );

        end

    end

endfunction


	/// checking the tagged outputs during INVALID/IDLE request
    virtual function void check_idle_tagged_outputs(provider_update_seq_item actual_item);

        if (actual_item.tagged_table_update_en_o !== '0) begin
            report_error("IDLE_TAGGED_ENABLE",
                $sformatf(
                    {
                        "Cycle %0d: expected no tagged-table update ",
                        "during idle, actual mask=0x%0h"
                    },
                    actual_item.sampled_cycle,
                    actual_item.tagged_table_update_en_o
                )
            );
        end
    endfunction


	/// checking the correctly predicted commit
    virtual function void check_correct_prediction(provider_update_seq_item request_item,provider_update_seq_item actual_item);

        tagged_table_mask_t expected_enable_mask;
        int provider_index;

        expected_enable_mask = '0;

        if (request_item.provider_id_i != BASE_PROVIDER_ID) begin
            provider_index = int'(request_item.provider_id_i) - 1;
            expected_enable_mask[provider_index] = 1'b1;
        end

        if (actual_item.tagged_table_update_en_o !== expected_enable_mask) begin

            report_error("REWARD_ENABLE",
                $sformatf(
                    {
                        "Cycle %0d: expected reward enable mask=0x%0h, ",
                        "actual mask=0x%0h"
                    },
                    actual_item.sampled_cycle,
                    expected_enable_mask,
                    actual_item.tagged_table_update_en_o
                )
            );
        end

        if (request_item.provider_id_i != BASE_PROVIDER_ID) begin

            provider_index = int'(request_item.provider_id_i) - 1;

            if (actual_item.table_cmd_o[provider_index] !== CMD_REWARD) begin

                report_error("REWARD_COMMAND",
                    $sformatf(
                        {
                            "Cycle %0d: T%0d expected CMD_REWARD, ",
                            "actual command=0x%0h"
                        },
                        actual_item.sampled_cycle,
                        provider_index + 1,
                        actual_item.table_cmd_o[provider_index]
                    )
                );
            end

            check_table_data(provider_index,request_item,actual_item);
        end
    endfunction


    /// cherck misprediction in the desing
    virtual function void check_misprediction(provider_update_seq_item request_item, provider_update_seq_item actual_item);

            tagged_table_mask_t available_eligible_mask;
            tagged_table_mask_t eligibility_mask;

            tagged_table_mask_t lfsr_candidate_mask;
            tagged_table_mask_t final_lfsr_target_mask;

            tagged_table_mask_t expected_enable_mask;
            tagged_table_mask_t expected_allocate_mask;
            tagged_table_mask_t expected_decay_mask;

            tagged_table_mask_t actual_allocate_mask;
            tagged_table_mask_t actual_decay_mask;

            provider_table_cmd_e expected_command;

            int allocation_target_index;
            logic expected_enable;

            int provider_index;

            lfsr_candidate_mask      = '0;
            final_lfsr_target_mask   = '0;
            expected_enable_mask     = '0;
            expected_allocate_mask   = '0;
            expected_decay_mask      = '0;
            actual_allocate_mask     = '0;
            actual_decay_mask        = '0;

            allocation_target_index = -1;
            provider_index = -1;

            available_eligible_mask = '0;
            eligibility_mask = '0;

            if (request_item.provider_id_i != BASE_PROVIDER_ID) begin
                provider_index = int'(request_item.provider_id_i) - 1;
            end

            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin
                // Only tagged tables above the provider are eligible.
                eligibility_mask[i] = ((i + 1) > int'(request_item.provider_id_i));
                    if ((eligibility_mask[i] === 1'b1) && (request_item.table_empty_mask_i[i] === 1'b1)) begin
                        available_eligible_mask[i] = 1'b1;
                end
            end

            /// incase of no allocation in higher tables during a misprediiction
            if (available_eligible_mask == '0) begin
                check_no_allocation_misprediction(request_item,actual_item,eligibility_mask);   
                return;  
            end


            // Apply the LFSR to the available and eligible allocation candidates.
            lfsr_candidate_mask = available_eligible_mask & request_item.current_LFSR_value_input;

            // If the LFSR removes every candidate, fall back to the original available-eligible mask.
            if (lfsr_candidate_mask != '0) begin
                final_lfsr_target_mask = lfsr_candidate_mask;
            end
            else begin    
                final_lfsr_target_mask = available_eligible_mask;
            end
            
            
            // Select the deepest table - i.e. the highest set bit.       
            allocation_target_index = -1;
            
            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                if (final_lfsr_target_mask[i] === 1'b1) begin
                    allocation_target_index = i;
                end
            end
            
            
            if (allocation_target_index < 0) begin
            
                report_error("NO_ALLOCATION_TARGET",
                    $sformatf(
                        {
                            "Cycle %0d: available mask=0b%0b, LFSR=0b%0b, ",
                            "but no allocation target was found"
                        },
                        actual_item.sampled_cycle,
                        available_eligible_mask,
                        request_item.current_LFSR_value_input
                    )
                );

                return; 
            end


            // The deepest table in final_lfsr_target_mask receives ALLOCATE.
            expected_allocate_mask = '0;
            expected_allocate_mask[allocation_target_index] = 1'b1;

            // Every other table in final_lfsr_target_mask receives DECAY.
            expected_decay_mask = final_lfsr_target_mask;
            expected_decay_mask[allocation_target_index] = 1'b0;


            // Every table in final_lfsr_target_mask is enabled.
            expected_enable_mask = final_lfsr_target_mask;

            // A tagged-table provider is enabled for PENALIZE. The base provider is handled through the base-table interface.
            if (provider_index >= 0) begin
                expected_enable_mask[provider_index] = 1'b1;
            end


            `uvm_info("SCB_LFSR_ALLOC_COMPARE",
                $sformatf(
                    {
                        "Allocation-path misprediction: ",
                        "eligibility_mask=0b%0b ",
                        "available_eligible_mask=0b%0b ",
                        "LFSR=0b%0b ",
                        "LFSR_candidate_mask=0b%0b ",
                        "final_LFSR_target_mask=0b%0b ",
                        "expected_allocate_mask=0b%0b ",
                        "expected_decay_mask=0b%0b ",
                        "expected_enable_mask=0b%0b ",
                        "actual_enable_mask=0b%0b"
                    },
                    eligibility_mask,
                    available_eligible_mask,
                    request_item.current_LFSR_value_input,
                    lfsr_candidate_mask,
                    final_lfsr_target_mask,
                    expected_allocate_mask,
                    expected_decay_mask,
                    expected_enable_mask,
                    actual_item.tagged_table_update_en_o
                ),
                UVM_LOW
            )


            for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

                expected_enable = expected_enable_mask[i];

                if ($isunknown(actual_item.tagged_table_update_en_o[i])) begin

                report_error("TAGGED_ENABLE_X",
                    $sformatf(
                        {
                            "Cycle %0d: update enable for T%0d ",
                            "contains X/Z"
                        },
                        actual_item.sampled_cycle,
                        i + 1
                    )
                );
                end

                // Check update enable.
                else if (actual_item.tagged_table_update_en_o[i] !== expected_enable) begin

                    report_error("LFSR_UPDATE_ENABLE",
                        $sformatf(
                            {
                                "Cycle %0d: T%0d expected update enable=%0b, ",
                                "actual update enable=%0b; ",
                                "available mask=0b%0b LFSR=0b%0b ",
                                "final LFSR target mask=0b%0b"
                            },
                            actual_item.sampled_cycle,
                            i + 1,
                            expected_enable,
                            actual_item.tagged_table_update_en_o[i],
                            available_eligible_mask,
                            request_item.current_LFSR_value_input,
                            final_lfsr_target_mask
                        )
                    );
                end


                if (expected_enable === 1'b1) begin

                    // The mispredicting tagged provider receives PENALIZE.
                    if (i == provider_index) begin
                        expected_command = CMD_PENALIZE;
                    end

                    // The deepest final LFSR candidate receives ALLOCATE.
                    else if (i == allocation_target_index) begin
                        expected_command = CMD_ALLOCATE;
                    end

                    // Every other final LFSR candidate receives DECAY.
                    else begin
                        expected_command = CMD_DECAY;
                    end

                    // Check command.
                    if (actual_item.table_cmd_o[i] !== expected_command) begin

                        report_error("LFSR_UPDATE_COMMAND",
                            $sformatf(
                                {
                                    "Cycle %0d: T%0d expected command=%s (0x%0h), ",
                                    "actual command=%s (0x%0h); ",
                                    "final LFSR target mask=0b%0b"
                                },
                                actual_item.sampled_cycle,
                                i + 1,
                                expected_command.name(),
                                expected_command,
                                actual_item.get_command_name(i),
                                actual_item.table_cmd_o[i],
                                final_lfsr_target_mask
                            )
                        );
                    end

                    // Check the address and tag sent to the downstream table.
                    check_table_data(i,request_item,actual_item);

                end
                // else if (actual_item.tagged_table_update_en_o[i] !== 1'b0) begin

                //     report_error(
                //         "TAGGED_ENABLE_X",
                //         $sformatf(
                //             {
                //                 "Cycle %0d: update enable for T%0d ",
                //                 "contains X/Z"
                //             },
                //             actual_item.sampled_cycle,
                //             i + 1
                //         )
                //     );

                // end

                // Record active ALLOCATE operations
                // A CMD_ALLOCATE value is active only when the corresponding tagged-table update enable is asserted.

                if ((actual_item.tagged_table_update_en_o[i] === 1'b1) && (actual_item.table_cmd_o[i] === CMD_ALLOCATE)) begin
                    actual_allocate_mask[i] = 1'b1;
                end

                // Record active DECAY operations.
                if ((actual_item.tagged_table_update_en_o[i] === 1'b1) && (actual_item.table_cmd_o[i] === CMD_DECAY)) begin
                    actual_decay_mask[i] = 1'b1;
                end

            end


            // Exactly one active allocation must occur.
            if (!$onehot(actual_allocate_mask)) begin

                report_error("ALLOCATE_NOT_ONEHOT",
                    $sformatf(
                        {
                            "Cycle %0d: expected exactly one active allocation, ",
                            "actual allocation mask=0b%0b"
                        },
                        actual_item.sampled_cycle,
                        actual_allocate_mask
                    )
                );
            end


            // Check that allocation was sent to the deepest final candidate.
            if (actual_allocate_mask !== expected_allocate_mask) begin

                report_error("WRONG_ALLOCATION_TARGET",
                    $sformatf(
                        {
                            "Cycle %0d: expected allocation mask=0b%0b, ",
                            "actual allocation mask=0b%0b"
                        },
                        actual_item.sampled_cycle,
                        expected_allocate_mask,
                        actual_allocate_mask
                    )
                );

            end


            // Check that DECAY was generated only from final_lfsr_target_mask.
            if (actual_decay_mask !== expected_decay_mask) begin

                report_error("WRONG_DECAY_MASK",
                    $sformatf(
                        {
                            "Cycle %0d: expected decay mask=0b%0b, ",
                            "actual decay mask=0b%0b; ",
                            "final LFSR target mask=0b%0b"
                        },
                        actual_item.sampled_cycle,
                        expected_decay_mask,
                        actual_decay_mask,
                        final_lfsr_target_mask
                    )
                );

            end


                // When final_lfsr_target_mask is one-hot, allocation is the only
                // operation on the candidate tables. No DECAY is permitted.
                if ($onehot(final_lfsr_target_mask) && (actual_decay_mask != '0)) begin

                report_error("ONE_TARGET_WITH_DECAY",
                    $sformatf(
                        {
                            "Cycle %0d: final LFSR target mask is one-hot ",
                            "(0b%0b), but decay mask is 0b%0b"
                        },
                        actual_item.sampled_cycle,
                        final_lfsr_target_mask,
                        actual_decay_mask
                    )
                );

            end

    endfunction


	/// for cheking the no allocation during a misprediction
	virtual function void check_no_allocation_misprediction(
		provider_update_seq_item request_item,
		provider_update_seq_item actual_item,
		tagged_table_mask_t eligibility_mask
	);

		int provider_index;

		logic expected_enable;

		provider_table_cmd_e expected_command;

		provider_index = -1;

		// A tagged provider must be PENALIZEd.
		// The base provider is handled by the base-update interface.
		if (request_item.provider_id_i != BASE_PROVIDER_ID) begin

			provider_index =
				int'(request_item.provider_id_i) - 1;

		end


		`uvm_info(
			"SCB_NO_ALLOC_COMPARE",
			$sformatf(
				{
					"No-allocation misprediction: ",
					"eligibility_mask=0b%0b ",
					"expected tagged enable mask=0b%0b ",
					"actual tagged enable mask=0b%0b"
				},
				eligibility_mask,
				eligibility_mask |
					((provider_index >= 0)
						? tagged_table_mask_t'(1 << provider_index)
						: '0),
				actual_item.tagged_table_update_en_o
			),
			UVM_LOW
		)


		for (int i = 0; i < NUM_TAGGED_TABLES; i++) begin

			// Enable the mispredicting tagged provider for PENALIZE.
			// Enable every higher eligible table for DECAY.
			expected_enable = (i == provider_index) || (eligibility_mask[i] === 1'b1);

			// -------------------------------------------------------------
			// Check update enable.
			// -------------------------------------------------------------

			if (actual_item.tagged_table_update_en_o[i] !==
				expected_enable) begin

				report_error(
					"NO_ALLOC_ENABLE",
					$sformatf(
						{
							"Cycle %0d: T%0d expected update enable=%0b, ",
							"actual update enable=%0b"
						},
						actual_item.sampled_cycle,
						i + 1,
						expected_enable,
						actual_item.tagged_table_update_en_o[i]
					)
				);

			end


			if (expected_enable === 1'b1) begin

				// The mispredicting tagged provider receives PENALIZE.
				// Every other enabled table receives DECAY.
				if (i == provider_index) begin
					expected_command = CMD_PENALIZE;
				end
				else begin
					expected_command = CMD_DECAY;
				end


				// ---------------------------------------------------------
				// Check command.
				// ---------------------------------------------------------

				if (actual_item.table_cmd_o[i] !==
					expected_command) begin

					report_error(
						"NO_ALLOC_COMMAND",
						$sformatf(
							{
								"Cycle %0d: T%0d expected command=%s (0x%0h), ",
								"actual command=%s (0x%0h)"
							},
							actual_item.sampled_cycle,
							i + 1,
							expected_command.name(),
							expected_command,
							actual_item.get_command_name(i),
							actual_item.table_cmd_o[i]
						)
					);

				end

				// ---------------------------------------------------------
				// Check the address and tag sent to the downstream table.
				// ---------------------------------------------------------

				check_table_data(
					i,
					request_item,
					actual_item
				);

			end

		end

	endfunction



	// check table data for enabled tagged table
    virtual function void check_table_data(int table_index,provider_update_seq_item request_item,provider_update_seq_item actual_item);

        if (actual_item.update_tagged_indices_o[table_index] !== request_item.commit_tagged_indices_i[table_index]) begin

            report_error("TAGGED_INDEX",
                $sformatf(
                    {
                        "Cycle %0d: T%0d expected index=0x%0h, ",
                        "actual index=0x%0h"
                    },
                    actual_item.sampled_cycle,
                    table_index + 1,
                    request_item.commit_tagged_indices_i[table_index],
                    actual_item.update_tagged_indices_o[table_index]
                )
            );
        end

        if (actual_item.update_tagged_tags_o[table_index] !== request_item.commit_tagged_tags_i[table_index]) begin

            report_error("TAGGED_TAG",
                $sformatf(
                    {
                        "Cycle %0d: T%0d expected tag=0x%0h, ",
                        "actual tag=0x%0h"
                    },
                    actual_item.sampled_cycle,
                    table_index + 1,
                    request_item.commit_tagged_tags_i[table_index],
                    actual_item.update_tagged_tags_o[table_index]
                )
            );
        end

    endfunction

    virtual function void report_error(string error_id,string message);
        error_count++;
        `uvm_error(error_id, message)
    endfunction


    virtual function void report_phase(uvm_phase phase);

        super.report_phase(phase);

        `uvm_info("SCB_SUMMARY",
			$sformatf({"Scoreboard summary: checked=%0d ","passed=%0d errors=%0d"},checked_count,passed_count,error_count),UVM_LOW)
    endfunction

endclass



/// environment
class provider_update_env extends uvm_env;

    `uvm_component_utils(provider_update_env)

    provider_update_agent      agent;
    provider_update_scoreboard scoreboard;

    function new(string name = "provider_update_env",uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);

        super.build_phase(phase);
        agent = provider_update_agent::type_id::create("agent",this);
        scoreboard = provider_update_scoreboard::type_id::create("scoreboard",this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.analysis_port.connect(scoreboard.analysis_imp);
    endfunction

endclass


