`timescale 1ns/1ps

/// get bank selection
module get_bank (
	input  logic [5:0] pointer_i,
	output logic [3:0] bank_o
);

	logic [5:0] bank_sel;

	always_comb begin

		case (pointer_i) inside
			
			[6'd0:6'd8]: bank_sel = pointer_i[3:0];
			[6'd9:6'd17]: bank_sel = pointer_i - 6'd9;
			[6'd18:6'd26]: bank_sel = pointer_i - 6'd18;
			[6'd27:6'd35]: bank_sel = pointer_i - 6'd27;

			default: bank_sel = 4'd0;

		endcase

	end

	assign bank_o = bank_sel[3:0];

endmodule
