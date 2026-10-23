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

// Here we are sampling at LEVEL 0 of CLOCK signal because HERE WE HAVE A POSITIVE EDGE CLOCK GATING - means we want the signal to be stable
// before the clock transitions from 0 -> 1. Hence, enable sampling at Level 0

// If this would have been negative edge clock gating design then we would sample the enable signal when clock is HIGH - so that
// the signal settles before there is 1 -> 0 transition.

//   BAD DESIGN - Normal AND with clock signal

//			Cycle 1   Cycle 2   Cycle 3   Cycle 4
//             ___       ___       ___       ___       
// clk_i    __|   |_____|   |_____|   |_____|   |_____
//            |         |         |         |         
//            |   ^     | ^       |   ^     |         
// en_i     __|___|_______|_______|___|_______________
//            |   |       |           |               
//          (en goes HIGH |         (en goes LOW      
//         while clk is HIGH)      while clk is HIGH) 

// ================================================================
// SCENARIO A: The Naive Approach (clk_out = clk_i & en_i)
// ================================================================
//             ___       ___       ___       ___ 
// clk_i    __|   |_____|   |_____|   |_____|   |_____
//            |   |       |           |
// en_i     __|___|_______|_______|___|_______________
//            |   |       |           |
//            |  _!_     _!_          !_
// clk_out  __|___|_____|   |_________|_______________
//                ^                   ^
//            GLITCH!              CUT-OFF!

//		GOOD DESIGN - Latched clock *********************************************************

// 			Cycle 1   Cycle 2   Cycle 3   Cycle 4
//             ___       ___       ___       ___       
// clk_i    __|   |_____|   |_____|   |_____|   |_____
//            |         |         |         |
//            |         |         |         |
// en_i     __|___---------_______|___----____________
//            |         |         |         |
// ================================================================
// SCENARIO B: Latch-Based ICG (The Industry Standard)
// ================================================================
//            |         |         |         |
//            |         |_________|         |
// en_latched |_________|         |_________|_________
//            |         |         |         |
//          (Ignores en |         |       (Ignores en 
//        until clk is LOW)       |     until clk is LOW)
//            |         |         |         |
//            |         | ___     |         | 
// clk_gated_o|_________|    |____|_________|_________
//                      |___|
//                        ^
//                Perfect, clean clock!