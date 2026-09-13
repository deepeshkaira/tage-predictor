`timescale 1ns/1ps


module checkpoint_fifo_buffer #(
        parameter int DEPTH      = 16,
        parameter int NUM_FOLDS  = 7,
        parameter int FOLD_WIDTH = 23
    ) (
        input logic clk,
        input logic rst_n,
        input logic en_i,

        /// write signals for the fifo
        input logic wr_en_i,
        input logic [FOLD_WIDTH-1:0] folded_history_i [0:NUM_FOLDS-1],
        input logic misprediction_i,    // Indicates that the popped entry must be sent downstream

        // read enable flag
        input logic rd_en_i,

        output logic fifo_full_o,
        output logic fifo_empty_o,
        output logic recovery_valid_o,
        output logic [FOLD_WIDTH-1:0] recovery_folded_history_o [0:NUM_FOLDS-1]
    );

        // Number of bits required to address the FIFO memory
        localparam int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

        // Pointers contain one additional MSB for wrap detection
        logic [ADDR_WIDTH:0] write_pointer;
        logic [ADDR_WIDTH:0] next_write_pointer;

        logic [ADDR_WIDTH:0] read_pointer;
        logic [ADDR_WIDTH:0] next_read_pointer;

        logic fifo_full_next;
        logic fifo_empty_next;

        logic write_enable;
        logic read_enable;

        logic gated_write_clk;
        logic gated_read_clk;

        logic [FOLD_WIDTH-1:0] fifo_mem [0:DEPTH-1][0:NUM_FOLDS-1];
        logic [FOLD_WIDTH-1:0] read_data_q [0:NUM_FOLDS-1];

        logic recovery_valid_q;

        // INTERNAL READ ENABLE:
        // Read is accepted only when FIFO is not empty.

        assign read_enable = en_i && rd_en_i && !fifo_empty_o;

        // INTERNAL WRITE ENABLE:
        // When full, permit a write if a read is accepted
        // during the same clock cycle.

        assign write_enable = en_i && wr_en_i && (!fifo_full_o || read_enable);

        // FIFO EMPTY FLAG GENERATION - FIFO will be empty after this cycle when the complete next read and write pointers are equal.
        assign fifo_empty_next = (next_read_pointer == next_write_pointer);

        // FIFO FULL FLAG GENERATION - Lower address bits must be equal. Extra pointer MSBs must be different. next_read_pointer is used because this synchronous FIFO permits simultaneous read and write operations.
        assign fifo_full_next = (next_write_pointer[ADDR_WIDTH] != next_read_pointer[ADDR_WIDTH]) && (next_write_pointer[ADDR_WIDTH-1:0] == next_read_pointer[ADDR_WIDTH-1:0]);

        // FIFO FULL AND EMPTY FLAGS
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                fifo_full_o  <= 1'b0;
                fifo_empty_o <= 1'b1;
            end
            else if (en_i) begin
                fifo_full_o  <= fifo_full_next;
                fifo_empty_o <= fifo_empty_next;
            end
        end

        // WRITE CLOCK GATING
        gated_clk u_write_clock_gate (
            .clk_i       (clk),
            .en_i        (write_enable),
            .clk_gated_o (gated_write_clk)
        );

        // READ CLOCK GATING
        gated_clk u_read_clock_gate (
            .clk_i       (clk),
            .en_i        (read_enable),
            .clk_gated_o (gated_read_clk)
        );

        // WRITE POINTER: Advances only when write_enable is asserted.
        always_ff @(posedge gated_write_clk or negedge rst_n) begin
            if (!rst_n)
                write_pointer <= '0;
            else
                write_pointer <= next_write_pointer;
        end

        // NEXT WRITE POINTER: The lower bits address memory. The additional MSB automatically toggles when the lower address portion wraps around.
        assign next_write_pointer = write_pointer + {{ADDR_WIDTH{1'b0}}, write_enable};

        // READ POINTER: Advances only when read_enable is asserted.
        always_ff @(posedge gated_read_clk or negedge rst_n) begin
            if (!rst_n)
                read_pointer <= '0;
            else
                read_pointer <= next_read_pointer;
        end

        // NEXT READ POINTER
        assign next_read_pointer = read_pointer + {{ADDR_WIDTH{1'b0}}, read_enable};

        // FIFO DATA WRITE: The lower write-pointer bits select the memory location.
        always_ff @(posedge gated_write_clk) begin
            for (int i = 0; i < NUM_FOLDS; i++) begin
                fifo_mem[write_pointer[ADDR_WIDTH-1:0]][i] <= folded_history_i[i];
            end
        end

        // SYNCHRONOUS FIFO DATA READ: The current read-pointer location is captured before the read pointer advances.
        always_ff @(posedge gated_read_clk or negedge rst_n) begin
            if (!rst_n) begin
                for (int i = 0; i < NUM_FOLDS; i++) begin
                    read_data_q[i] <= '0;
                end
            end
            else begin
                for (int i = 0; i < NUM_FOLDS; i++) begin
                    read_data_q[i] <= fifo_mem[read_pointer[ADDR_WIDTH-1:0]][i];
                end
            end
        end

        // RECOVERY OUTPUT section.
        /// need to send a valid output only when there is a misprediction in the design.
        /// Also, this FLAG we need to generate because we want the GHR to stop pushing out the Address packets.
        /// until that clock cycle when the Hash address generators have the UNSTALE value of FOLDED HISTORY retained in them.
	logic misprediction_i_gated;
        assign misprediction_i_gated = en_i ? misprediction_i : 1'b0;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                recovery_valid_q <= 1'b0;
            else
                recovery_valid_q <= read_enable && misprediction_i_gated;
        end

        assign recovery_valid_o = recovery_valid_q;

        always_comb begin
            for (int i = 0; i < NUM_FOLDS; i++) begin
                if (recovery_valid_q)
                    recovery_folded_history_o[i] = read_data_q[i];
                else
                    recovery_folded_history_o[i] = '0;
            end
        end

        /// adding an assertion so that the FIFO is always a power of 2.
        // assert

endmodule