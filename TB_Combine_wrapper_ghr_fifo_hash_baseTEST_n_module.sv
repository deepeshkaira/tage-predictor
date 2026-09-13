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

`include "TB_Combine_wrapper_ghr_fifo_hash_other_components.sv"

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
