always_ff @(posedge clk) begin
    if (we_decode[0][0]) bank_mem[0][0] <= br_packet_i_gated;
end

always_ff @(posedge clk) begin
    if (we_decode[0][1]) bank_mem[0][1] <= br_packet_i_gated;
end

always_ff @(posedge clk) begin
    if (we_decode[0][2]) bank_mem[0][2] <= br_packet_i_gated;
end


//...... and so on .........
// these above blocks trnslate to hardware as follows ---

ICG_CELL icg_inst_0_0 (
    .clk_in(clk),               // The global, always-toggling clock
    .enable(we_decode[0][0]),   // My specific enable bit
    .clk_out(gated_clk_0_0)     // The new gated clock  - especially for row 0 , bank 0
);

always_ff @(posedge gated_clk_0_0) begin
    bank_mem_0_0 <= br_packet_i_gated; 
end

//////////////////////////////

ICG_CELL icg_inst_0_1 (
    .clk_in(clk),               // The global, always-toggling clock
    .enable(we_decode[0][1]),   // My specific enable bit
    .clk_out(gated_clk_0_1)     // The new gated clock  - especially for row 0 , bank 1
);

always_ff @(posedge gated_clk_0_1) begin
    bank_mem_0_1 <= br_packet_i_gated; 
end

//////////////////////////////

ICG_CELL icg_inst_0_2 (
    .clk_in(clk),               // The global, always-toggling clock
    .enable(we_decode[0][2]),   // My specific enable bit
    .clk_out(gated_clk_0_2)     // The new gated clock  - especially for row 0 , bank 2
);

always_ff @(posedge gated_clk_0_2) begin
    bank_mem_0_2 <= br_packet_i_gated; 
end