// design of linear feedback shift register

// Polynomial that we are going to use is:- x^7 + x^6 + 1

// this is normal block that is already refined as per low power standards.

//  no need to --*** OPERAND ISOLATION HERE, Because we dont have any incoming data ****--
/// and we never clamp the Input control signals.

module phast_lfsr7 (
    input  logic clk,
    input  logic rst_n,   

    /// this enable is different from other enables before.
    /// This block will generate pattern ony when required i.e. during MISPREDICTION/SQUASH
    input  logic en_i,      /// <--- Connect to Misprediction_i flag

    output logic [6:0] lfsr_o  
);

    logic [6:0] lfsr_reg;
    logic feedback;
    logic clk_gated_lfsr;

    gated_clk u_icg (
        .clk_i       (clk),
        .en_i        (en_i),
        .clk_gated_o (clk_gated_lfsr)
    );

    assign feedback = lfsr_reg[6] ^ lfsr_reg[5];

    always_ff @(posedge clk_gated_lfsr or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_reg <= 7'b111_1111;	// this is going to be the reset state of the register 
        end else begin
            lfsr_reg <= {lfsr_reg[5:0], feedback};
        end
    end

    assign lfsr_o = lfsr_reg;

    assert property (@(posedge clk) disable iff (!rst_n)  lfsr_reg != 7'b0);    // assertion to make sure lfsr output is not zero.

endmodule