/////this will have multiple modules in it.


///   1. THis one will be checking the vacancy at the Row level (among ways ina row)
///		Now, why only row level. Because we will already have an address that will be targeted by that instruction
//// 	Only requirement is that we are going to keep that prediction packet in either a table with higher history depth.
////	or we are going to update the same row in that same table by penalizing the Confidence bits.

module row_vacancy_check#(
	parameter int NUM_WAYS = 4,		// nbr of ways in a row
	parameter int LRU_BITS = 2	
		//lru width
)(
	input logic check_en_i,
	input logic [(NUM_WAYS * LRU_BITS)-1:0] active_lru_bus_i,
	output logic has_space_o
);

	logic [NUM_WAYS-1:0] way_empty_vec;

	// this is how we check if all that row has any vacant bits.
	// if there are , then we can send the same LRU bits to NOR gate to a Row priority encoder.
	/// and use that to define which way to use for data
    always_comb
    begin
		way_empty_vec = '0;

		if(check_en_i) begin
			for(int i = 0; i < NUM_WAYS; i++)
            begin
                // get BITWISE OR for each WAY. Calculate for each way. Four bits of way_empty_vec. 
                way_empty_vec[i] = ~(|active_lru_bus_i[ (i * LRU_BITS) +: LRU_BITS ]);
            end			
		end
    end
   

	// even if one of the way has LRU = 00. This will give 1
	assign has_space_o = |way_empty_vec;

endmodule



//// 2. THis second module give us what is the scene for all tables T1 to T7 (wrt row availability)
module phast_candidate_gen#(
	parameter int NUM_TABLES = 7,
	parameter int NUM_WAYS = 4,
	parameter int LRU_BITS = 2
)(
	input en_i,
	input logic [(NUM_WAYS * LRU_BITS)-1 : 0] active_lru_buses_i [0:NUM_TABLES-1],
	output logic [NUM_TABLES-1:0] candidate_vec_o
);

	// generate a 7 bits candidate vector for each table
	// Tells us which table has available space for a particular address
	generate
		for(genvar k = 0; k < NUM_TABLES; k++)
			begin
				row_vacancy_check #(
					.NUM_WAYS(NUM_WAYS),
					.LRU_BITS(LRU_BITS)
				)u_row_checker(
					.check_en_i(en_i),
					.active_lru_bus_i (active_lru_buses_i[k]),
					.has_space_o (candidate_vec_o[k])
				);
			end
	endgenerate

endmodule