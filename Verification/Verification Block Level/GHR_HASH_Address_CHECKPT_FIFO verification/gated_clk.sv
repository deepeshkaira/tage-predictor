`timescale 1ns/1ps

module gated_clk (
    input  logic clk_i,
    input  logic en_i,

    output logic clk_gated_o
);

    logic en_latched;

    always_latch begin
        if (!clk_i) begin
            en_latched <= en_i;
        end
    end

	assign clk_gated_o = clk_i & en_latched;

endmodule
