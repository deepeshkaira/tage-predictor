`timescale 1ns/1ps

/// get row selection in the bank
module get_row (
	input  logic [5:0] pointer_i,
	output logic [1:0] row_o
);

	always_comb begin

		case (pointer_i) inside

			[6'd0:6'd8]: row_o = 2'b00;
			[6'd9:6'd17]: row_o = 2'b01;
			[6'd18:6'd26]: row_o = 2'b10;
			[6'd27:6'd35]: row_o = 2'b11;

			default: row_o = 2'b00;

		endcase

	end

endmodule
