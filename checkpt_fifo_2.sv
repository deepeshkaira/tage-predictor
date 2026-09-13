// ============================================================================
// Module: history_checkpoint_buffer
// Segregated Control Logic for History Checkpointing
// ============================================================================

module history_checkpoint_buffer #(
    parameter int DEPTH       = 8,
    parameter int NUM_FOLDS   = 7,
    parameter int FOLD_WIDTH  = 23
) (
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------------------
    // Write interface
    // ------------------------------------------------------------------------
    input  logic wr_en_i,
    input  logic [FOLD_WIDTH-1:0] folded_history_i [0:NUM_FOLDS-1],
    output logic full_o,
    output logic wr_ready_o,

    // ------------------------------------------------------------------------
    // Read/Retire interface
    // ------------------------------------------------------------------------
    input  logic rd_en_i,
    input  logic mispredict_i, // High for recovery mode
    
    output logic [FOLD_WIDTH-1:0] folded_history_o [0:NUM_FOLDS-1],
    output logic empty_o,
    output logic [$clog2(DEPTH+1)-1:0] occupancy_o
);

    localparam int PTR_WIDTH = $clog2(DEPTH);
    typedef logic [0:NUM_FOLDS-1][FOLD_WIDTH-1:0] payload_t;

    payload_t fifo_mem [0:DEPTH-1];
    logic [PTR_WIDTH-1:0] write_ptr, read_ptr;
    logic [$clog2(DEPTH+1)-1:0] count;

    // ------------------------------------------------------------------------
    // 1. Flags and Pointers
    // ------------------------------------------------------------------------
    assign empty_o     = (count == 0);
    assign full_o      = (count == DEPTH);
    assign occupancy_o = count;
    assign wr_ready_o  = !full_o;

    // ------------------------------------------------------------------------
    // 2. Gated Write Clock & Pointer Increment
    // ------------------------------------------------------------------------
    logic write_clk_en;
    assign write_clk_en = wr_en_i && wr_ready_o;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
        end else if (mispredict_i) begin
            write_ptr <= read_ptr; // Flush on squash
        end else if (write_clk_en) begin
            write_ptr <= (write_ptr == DEPTH-1) ? '0 : write_ptr + 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // 3. Write Data (Put incoming into FIFO)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (write_clk_en) begin
            fifo_mem[write_ptr] <= folded_history_i;
        end
    end

    // ------------------------------------------------------------------------
    // 4. Read Pointer Increment
    // ------------------------------------------------------------------------
    logic read_clk_en;
    assign read_clk_en = rd_en_i && !empty_o;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr <= '0;
        end else if (read_clk_en) begin
            read_ptr <= (read_ptr == DEPTH-1) ? '0 : read_ptr + 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // 5. FIFO Occupancy Count
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
        end else if (mispredict_i) begin
            count <= '0; // Clear on squash
        end else begin
            case ({write_clk_en, read_clk_en})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 6. Recovery Mode (Muxing Output)
    // ------------------------------------------------------------------------
    // If mispredict_i is high, we bypass standard output to dump history
    always_comb begin
        if (mispredict_i) begin
            folded_history_o = fifo_mem[read_ptr];
        end else begin
            folded_history_o = '0; 
        end
    end

endmodule