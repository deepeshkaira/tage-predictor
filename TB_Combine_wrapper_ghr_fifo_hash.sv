`timescale 1ns/1ps

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
    parameter int FOLD_WIDTH = S_WIDTH + T_WIDTH;
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

    import predictor_history_tb_params_pkg::*;

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
        if (observed_item.en_i && observed_item.misprediction_i) rollback_pointer = circular_subtract(ghr_head_model, observed_item.mispredicted_table_depth_i, GHR_MAX_PTR);

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
        if (expected_fifo_read_enable) popped_fifo_data = fifo_memory_model[fifo_read_pointer_model];

        if (observed_item.en_i && previous_recovery_valid) begin
            folded_history_model = recovery_data_model;
        end else if (normal_hash_branch_valid) begin
            padded_incoming_packet = {{(FOLD_WIDTH-PKT_WIDTH){1'b0}}, observed_item.br_packet_i};
            padded_expiring_packet = {{(FOLD_WIDTH-PKT_WIDTH){1'b0}}, selected_expiring_packet};
            folded_history_model = rotate_left(folded_history_before_edge, 1) ^ padded_incoming_packet ^ rotate_left(padded_expiring_packet, SELECTED_HISTORY_DEPTH);
        end

        if (expected_fifo_write_enable) begin
            fifo_memory_model[fifo_write_pointer_model] = folded_history_before_edge;
            fifo_write_pointer_model = (fifo_write_pointer_model + 1) % FIFO_DEPTH;
        end

        if (expected_fifo_read_enable) fifo_read_pointer_model = (fifo_read_pointer_model + 1) % FIFO_DEPTH;

        case ({expected_fifo_write_enable, expected_fifo_read_enable})
            2'b10: fifo_count_model++;
            2'b01: fifo_count_model--;
            default: fifo_count_model = fifo_count_model;
        endcase

        if (normal_ghr_branch_valid) begin
            ghr_write_location = observed_item.misprediction_i ? rollback_pointer : ghr_head_model;
            ghr_memory_model[ghr_write_location] = observed_item.br_packet_i;
        end

        ghr_head_model = next_ghr_head;
        expected_recovery_valid = expected_fifo_read_enable && observed_item.misprediction_i;
        recovery_valid_model = expected_recovery_valid;
        if (expected_recovery_valid) recovery_data_model = popped_fifo_data;

        expected_fifo_empty = (fifo_count_model == 0);
        expected_fifo_full = (fifo_count_model == FIFO_DEPTH);

        check_logic_value("fifo_empty_o", expected_fifo_empty, observed_item.fifo_empty_o);
        check_logic_value("fifo_full_o", expected_fifo_full, observed_item.fifo_full_o);
        check_logic_value("recovery_active_o", expected_recovery_valid, observed_item.recovery_active_o);
        check_vector_value("folded_history_state_o", folded_history_model, observed_item.folded_history_state_o);

        if (expected_recovery_valid) check_vector_value("recovery_folded_history_o", popped_fifo_data, observed_item.recovery_folded_history_o);
        else check_vector_value("recovery_folded_history_o", folded_history_t'('0), observed_item.recovery_folded_history_o);

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
        if (observed_value === expected_value) record_pass(check_name);
        else record_failure(check_name, $sformatf("expected=%b observed=%b", expected_value, observed_value));
    endfunction

    function void check_vector_value(string check_name, folded_history_t expected_value, folded_history_t observed_value);
        if (observed_value === expected_value) record_pass(check_name);
        else record_failure(check_name, $sformatf("expected=0x%0h observed=0x%0h", expected_value, observed_value));
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

    initial begin
        tb_if.rst_n = 1'b0;
        repeat (RESET_ACTIVE_CYCLES) @(posedge clk);
        tb_if.rst_n <= 1'b1;
    end

    initial begin
        uvm_config_db #(virtual predictor_history_if)::set(null, "uvm_test_top.env.agent.*", "vif", tb_if);
        run_test("predictor_history_base_test");
    end

endmodule







