`timescale 1ns/1ps

module predictor_history_single_hash_wrapper #(
    parameter int PKT_WIDTH          = 7,
    parameter int NUM_GHR_PACKETS    = 7,
    parameter int S_WIDTH            = 7,
    parameter int T_WIDTH            = 16,
    parameter int FIFO_DEPTH         = 16,

    // Select which of the seven GHR history depths is demonstrated.
    // 0,1,2,3,4,5,6 correspond to depths 2,4,6,8,12,16,32.
    parameter int SELECTED_HASH_TABLE = 0
) (
    input logic clk,
    input logic rst_n,
    input logic en_i,

    // Branch stream entering the GHR.
    input logic                 br_valid_i,
    input logic [PKT_WIDTH-1:0] br_packet_i,
    input logic [31:0]          load_pc_i,

    // Checkpoint/ROB control.
    input logic branch_commit_i,
    input logic misprediction_i,
    input logic [5:0] mispredicted_table_depth_i,

    // Output from the single selected hash-address-generator lane.
    output logic [S_WIDTH-1:0] tagged_index_o,
    output logic [T_WIDTH-1:0] tagged_tag_o,

    // FIFO/recovery status.
    output logic fifo_full_o,
    output logic fifo_empty_o,
    output logic recovery_active_o,

    // All GHR outputs remain observable. Only the selected expiring packet is
    // consumed by the hash block in this wrapper.
    output logic [PKT_WIDTH-1:0] ghr_incoming_packet_o,
    output logic [PKT_WIDTH-1:0] ghr_expiring_packets_o [0:NUM_GHR_PACKETS-1],
    output logic [PKT_WIDTH-1:0] selected_expiring_packet_o,

    // Observability signals for the later cycle-by-cycle testbench.
    output logic [S_WIDTH+T_WIDTH-1:0] folded_history_state_o,
    output logic [S_WIDTH+T_WIDTH-1:0] recovery_folded_history_o
);

    localparam int FOLD_WIDTH = S_WIDTH + T_WIDTH;

    localparam int GHR_DEPTHS [0:NUM_GHR_PACKETS-1] = '{2, 4, 6, 8, 12, 16, 32};

    // phast_tagged_table_hash expects an unpacked DEPTHS parameter array even
    // when NUM_TAGGED is one.
    localparam int SELECTED_DEPTHS [0:0] = '{GHR_DEPTHS[SELECTED_HASH_TABLE]};

	/// fifo read and write enable signals are generated here
	logic chckpt_wr_en_i;
    logic chckpt_rd_en_i;

    logic [PKT_WIDTH-1:0] ghr_incoming_packet;
    logic [PKT_WIDTH-1:0] ghr_expiring_packets [0:NUM_GHR_PACKETS-1];

    // One-element arrays adapt the existing parameterized hash and FIFO ports.
    logic [PKT_WIDTH-1:0] selected_expiring_packet [0:0];
    logic [FOLD_WIDTH-1:0] folded_history_state [0:0];
    logic [FOLD_WIDTH-1:0] recovery_folded_history [0:0];
    logic [S_WIDTH-1:0] selected_index [0:0];
    logic [T_WIDTH-1:0] selected_tag [0:0];

    initial begin
        assert (NUM_GHR_PACKETS == 7)
            else $fatal(1, "The supplied GHR is configured for seven outputs");
        assert (SELECTED_HASH_TABLE inside {[0:NUM_GHR_PACKETS-1]})
            else $fatal(1, "SELECTED_HASH_TABLE must be between 0 and 6");
        assert (FOLD_WIDTH >= PKT_WIDTH)
            else $fatal(1, "Fold width must be at least PKT_WIDTH");
    end


    LP_ghr_block #(
        .PKT_WIDTH       (PKT_WIDTH),
        .NUM_HASH_TABLES (NUM_GHR_PACKETS)
    ) u_ghr (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .en_i                       (en_i),
		.recovery_active_i          (recovery_active_o),
        .br_valid_i                 (br_valid_i),
        .br_packet_i                (br_packet_i),
        .misprediction_i            (misprediction_i),
        .mispredicted_table_depth_i (mispredicted_table_depth_i),

        .incoming_packet_o          (ghr_incoming_packet),
        .expiring_packet_o          (ghr_expiring_packets)
    );

    // Select one of the seven GHR expiring packets. For the default selection,
    // ghr_expiring_packets[0] is the packet at history depth 2.
    assign selected_expiring_packet[0] = ghr_expiring_packets[SELECTED_HASH_TABLE];
	assign chckpt_wr_en_i = en_i && br_valid_i;
	assign chckpt_rd_en_i = branch_commit_i || misprediction_i;
 
    checkpoint_fifo_buffer #(
        .DEPTH      (FIFO_DEPTH),
        .NUM_FOLDS  (1),
        .FOLD_WIDTH (FOLD_WIDTH)
    ) u_checkpoint_fifo (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .en_i                      (en_i),
        .wr_en_i                   (chckpt_wr_en_i),
        .folded_history_i          (folded_history_state),
        .misprediction_i           (misprediction_i),
        .rd_en_i                   (chckpt_rd_en_i),
		
        .fifo_full_o               (fifo_full_o),
        .fifo_empty_o              (fifo_empty_o),
        .recovery_valid_o          (recovery_active_o),
        .recovery_folded_history_o (recovery_folded_history)
    );
 
    phast_tagged_table_hash #(
        .PKT_WIDTH  (PKT_WIDTH),
        .NUM_TAGGED (1),
        .S_WIDTH    (S_WIDTH),
        .T_WIDTH    (T_WIDTH),
        .DEPTHS     (SELECTED_DEPTHS)
    ) u_single_hash_address_generator (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .en_i                      (en_i),
        .br_valid_i                (br_valid_i),
        .incoming_pkt_i            (ghr_incoming_packet),
        .expiring_pkts_i           (selected_expiring_packet),
        .load_pc_i                 (load_pc_i),

        // Required checkpoint ports added to the hash module.
        .recovery_valid_i          (recovery_active_o),
        .recovery_folded_history_i (recovery_folded_history),

		// outputs
        .folded_history_o          (folded_history_state),

        .tagged_indices_o          (selected_index),
        .tagged_tags_o             (selected_tag)
    );

    assign tagged_index_o             = selected_index[0];
    assign tagged_tag_o               = selected_tag[0];
    assign ghr_incoming_packet_o       = ghr_incoming_packet;
    assign selected_expiring_packet_o  = selected_expiring_packet[0];
    assign folded_history_state_o      = folded_history_state[0];
    assign recovery_folded_history_o   = recovery_folded_history[0];

    generate
        for (genvar i = 0; i < NUM_GHR_PACKETS; i++) begin : gen_ghr_outputs
            assign ghr_expiring_packets_o[i] = ghr_expiring_packets[i];
        end
    endgenerate

    property misprediction_generates_fifo_read_p;
        @(posedge clk) disable iff (!rst_n)
        (en_i && misprediction_i) |-> chckpt_rd_en_i;
    endproperty

    misprediction_generates_fifo_read_a:
        assert property (misprediction_generates_fifo_read_p)
        else $error("misprediction_i did not generate chckpt_rd_en_i");

endmodule

