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
          
          

module phast_tagged_table_hash #(
    parameter int PKT_WIDTH  = 7,
    parameter int NUM_TAGGED = 7,
    parameter int S_WIDTH    = 7,
    parameter int T_WIDTH    = 16,
    
    parameter int DEPTHS [0:NUM_TAGGED-1] = '{2, 4, 6, 8, 12, 16, 32}
)(

    input  logic clk,
    input  logic rst_n,
    input  logic en_i,
    
    input  logic br_valid_i,
    input  logic [PKT_WIDTH-1:0] incoming_pkt_i,                 
    input  logic [PKT_WIDTH-1:0] expiring_pkts_i [0:NUM_TAGGED-1], 
    input  logic [31:0] load_pc_i,                      
    
	// input for the signal to decide whether to take the calculated value of next_folded_history or recovery_history value
	input logic recovery_valid_i,
	input logic [S_WIDTH+T_WIDTH-1:0] recovery_folded_history_i [0:NUM_TAGGED-1],

    output logic [S_WIDTH-1:0] tagged_indices_o [0:NUM_TAGGED-1],
    output logic [T_WIDTH-1:0] tagged_tags_o    [0:NUM_TAGGED-1],

	//output to send out the folded history output to the checkpoint FIFO buffer to think about
	output logic [S_WIDTH+T_WIDTH-1:0] folded_history_o [0:NUM_TAGGED-1]
);

	localparam int CSR_WIDTH = S_WIDTH + T_WIDTH;


	logic recovery_valid_i_gated;		// recovery valid signals
	logic folded_history_clock_en;		/// signal for gating the clock on both conditions:-  VALID BRANCH   &	 ACTIVE RECOVERY

	// variables for gating the incoming signals
	logic br_valid_i_gated;
	logic [PKT_WIDTH-1:0] incoming_pkt_i_gated;                 
    logic [PKT_WIDTH-1:0] expiring_pkts_i_gated [0:NUM_TAGGED-1];
    logic [S_WIDTH+T_WIDTH-1:0] recovery_folded_history_i_gated [0:NUM_TAGGED-1];		// for recovery addresses
    logic [31:0] load_pc_i_gated;

	assign recovery_valid_i_gated = en_i && recovery_valid_i;
	assign br_valid_i_gated = en_i && br_valid_i && !recovery_valid_i_gated;
	assign incoming_pkt_i_gated = br_valid_i_gated ? incoming_pkt_i : '0;		// no need to gate these large bit sized packets. as they will lead to power use in each flips
	
	/// clock gating for the design
	assign folded_history_clock_en = br_valid_i_gated || recovery_valid_i_gated;

	// program counter value is required for both the cases: VALID BRANCH and ACTIVE RECOVERY
	assign load_pc_i_gated = folded_history_clock_en ? load_pc_i : '0;
	
	generate		// gating_input_expiring_packets and folded history incoming from checkpoint buffer
        for (genvar j = 0; j < NUM_TAGGED; j++) begin : gen_expire_clamp
            assign expiring_pkts_i_gated[j] = br_valid_i_gated ? expiring_pkts_i[j] : '0;
			assign recovery_folded_history_i_gated[j] = recovery_valid_i_gated ? recovery_folded_history_i[j] : '0;
        end
    endgenerate

	/// NEED TO THINK about the pulling the values down to ZERO on expiring packets because if I did it like this
	/// and the block gets disabled for just one clock cycle. Then i will have ZERO propagated to 
	/// - incoming_pkt_i_gated  and  expiring_pkts_i_gated   <------ these will be zero NOW, FOR just one clock cycle.
	/// because of this following signals will also go Zero in this clock cycle :-
	/// - padded_expiring     and    padded_incoming.
	/// But, **** NO ISSUES **** - because we will again get these signals next time when ""enable"" goes HIGH. Because we have folded history already protected with us using registered FF.
	/// So, it is alright.

	logic [29:0] pc_word;
	assign pc_word = load_pc_i_gated [31:2];		// ignored 2 LSB bits, word aligned PC

	logic [29:0] hash_pc_idx_full;
	logic [29:0] hash_pc_tag_full;

	// bitwirse XOR of PC for tag and index
	assign hash_pc_idx_full = pc_word ^ (pc_word >> 2) ^ (pc_word >> 5);
	assign hash_pc_tag_full = pc_word ^ (pc_word >> 3) ^ (pc_word >> 7);


	// ICG
	logic clk_gated_csr;

    // One ICG to gate the clock for all 7 CSR engines
    gated_clk u_icg (
        .clk_i       (clk),
        .en_i        (folded_history_clock_en),
        .clk_gated_o (clk_gated_csr)
    );


	//// ASSERTION FOR CHECKING X or Z in enable signals
	property hash_control_inputs_known_p;
        @(posedge clk) disable iff (!rst_n) !$isunknown({en_i, br_valid_i, recovery_valid_i});
    endproperty

    hash_control_inputs_known_a:
        assert property (hash_control_inputs_known_p)
        else $error("Hash control input en_i, br_valid_i, or recovery_valid_i contains X or Z");

    property hash_gated_controls_known_p;
        @(posedge clk) disable iff (!rst_n) !$isunknown({br_valid_i_gated, recovery_valid_i_gated, folded_history_clock_en});
    endproperty

    hash_gated_controls_known_a:
        assert property (hash_gated_controls_known_p)
        else $error("Hash gated control contains X or Z");

	generate

		for(genvar i = 0; i < NUM_TAGGED; i++) begin
			
			localparam int EVICT_SHIFT = DEPTHS[i] % CSR_WIDTH;		// calculate the eviction shift based on the parameterized depth for this specific table
			
			logic [CSR_WIDTH-1:0] folded_history, next_folded_history, shifted_fold, padded_incoming, padded_expiring, aligned_expiring;

			// aligned_expiring = '0;		// need not set this to ZERO because initially it can hold garbage data.
													// it will be assigned some value only when the gate signal "br_valid_i_gated" will be flipped to HIGH

			assign shifted_fold    = {folded_history[CSR_WIDTH-2:0], folded_history[CSR_WIDTH-1]};		// left circular shift of the current history/CSR bits in the hash table by 1 place
			assign padded_incoming = {{(CSR_WIDTH-PKT_WIDTH){1'b0}}, incoming_pkt_i_gated};				// padded the incoming GHR packet
			assign padded_expiring = {{(CSR_WIDTH-PKT_WIDTH){1'b0}}, expiring_pkts_i_gated[i] };			// padded the expiring GHR packet
			assign aligned_expiring = EVICT_SHIFT ? {padded_expiring[CSR_WIDTH - EVICT_SHIFT-1 : 0], padded_expiring[CSR_WIDTH-1 : CSR_WIDTH-EVICT_SHIFT]} : padded_expiring;

			always_ff@(posedge clk_gated_csr or negedge rst_n)
				begin
					if(!rst_n) begin
						folded_history <= '0;
					end else begin
						folded_history <= next_folded_history;
					end
				end
	
			// CSR fold logic
			always_comb
				begin
					next_folded_history = folded_history;
			
					if(br_valid_i_gated && (!recovery_valid_i_gated)) begin
						next_folded_history = shifted_fold ^ padded_incoming ^ aligned_expiring;
					end else if((!br_valid_i_gated) && recovery_valid_i_gated) begin
						next_folded_history = recovery_folded_history_i_gated[i];
					end
				end

			/// assertion to check if the folded history holds whenever  the enable abnd br_valid are down.
			property folded_history_holds_when_inactive_p;
				@(posedge clk) disable iff (!rst_n) !$past(folded_history_clock_en) |-> $stable(folded_history);
			endproperty
			
			folded_history_holds_when_inactive_a:
				assert property (folded_history_holds_when_inactive_p)
				else $error("TABLE %0d: folded_history changed while request was inactive",i);

			// Final Output Mix (Sliced CSR ^ Left shifted PC)
			assign tagged_indices_o[i] = next_folded_history[CSR_WIDTH-1 : T_WIDTH] ^ hash_pc_idx_full[S_WIDTH-1 : 0];
			assign tagged_tags_o[i] = next_folded_history[T_WIDTH-1 : 0] ^ hash_pc_tag_full[T_WIDTH-1 : 0];
			assign folded_history_o[i] = folded_history;

		end
	endgenerate

endmodule
                  
                  
                  
// this block defines the global history buffer which stores the value for the history along with TAGS.
module LP_ghr_block #(
	// give width parameters here
	parameter PKT_WIDTH = 7,	//{type[1],taken[1],target[5]}  /// THE target is the lowest 5 bits of the target addreess.
	parameter NUM_BANKS = 9,
	parameter ENTRIES_PER_BANK = 4,
	parameter MAX_PTR = 36,		/// 36 total entries (0 to 35)
	parameter NUM_HASH_TABLES = 7
)(
	input logic clk,
	input logic rst_n,				// asynchronous reset

	input logic en_i,					// need to include this to gate the D-flops
	
	// these two decodes the branch
	input logic br_valid_i,			// assert 1 when a valid divergent branch is decoded
	input logic [PKT_WIDTH-1:0] br_packet_i,	// incoming branch information {type[1],taken[1],target[5]}
	
	// commit /ROB interface
	input logic misprediction_i,		// assert 1 from ROB when a branch misprediction flush occurs
	input logic [5:0] mispredicted_table_depth_i,	// indicates how many branches deep the misprediction occurred

	/// check for the outputs
	output logic [PKT_WIDTH-1:0] incoming_packet_o,		// forwards the new packet to the folding logic to be XORed into all the tables
	output logic [PKT_WIDTH-1:0] expiring_packet_o [0:NUM_HASH_TABLES-1],	// 2D array containing the 7 specific historical packets each 7 bits wide required for geometric foldingn

	// recovery for folded history in the hash blocks downstream
	// I dont think that we need the recovery valid outputs in here. Because once we are back with our head read pointers --
	// the GHR is going to handle the incoming packets same way as it is suppossed to and we will have the Porgram counter fetching up the instructions from the rolled back PC
	// and hence i think the incmoing packet will be re-fetched. We dont need to restore the incmoing packet in GHR.
	// ONly thing that I need to restore in the design of GHR is HEAD POINTER which will be used to fetch value from checkpoint buffer.
	// and use that Head pointer to pickup the folded_history packet from checkpoint buffer and push it to hash address generator blocks.
	// that is how it is going to work in recovery of pointer and folded history. 

	// ********
	// but there will be a cycle latency from the checkpoint FIFO when it supplies the data (clean folded history) to the Hash generators.
	// and to stop the data movement into the design during that time we need a RECOVERY ACTIVE signal.
	input logic recovery_active_i

	// ******** ------  *******  PROBABLE HISTORY RECOVERY PORTS. CAN BE USED LATER.
	// output logic recovery_valid_o,	// recovery packet outputs are valid
	// output logic [PKT_WIDTH-1:0] recovery_incoming_packet_o,	// next_old GHR packet being replayed
	// output logic [PKT_WIDTH-1:0] recovery_expiring_packet_o [0:NUM_HASH_TABLES-1],	// packet going out from history window during replay
	// output logic recovery_last_o	// last recovey packet 
);


	// STORAGE - We need to define 9 memory banks in here so that we can use them for placing in the 
	// incoming instructions information and do not create Collision. When we calculate modulo using 7 Banks then it creates collision
	// after 5th bank. But if we use 9 banks , then it will not create any collision and will wrap around only after 7th bank.
	// Hence, we have 7 totally different banks to use for entries. (BADGR architecture)
	// ALSO, we will be able to select the row number (address) for each bank like that so that we don't need an 
	// additional counter/pointer for each memory
	logic [PKT_WIDTH-1:0] bank_mem [0:ENTRIES_PER_BANK-1][0:NUM_BANKS-1];

	logic [5:0] head_ptr, next_head_ptr;	// pointers for count
	// logic [5:0] valid_history_count, next_valid_history_count;		// counters for telling recovery wich positions represent genuine history
	logic br_valid_i_gated;
	logic misprediction_i_gated;
	logic [5:0] mispredicted_table_depth_i_gated;
	logic [PKT_WIDTH-1:0] br_packet_i_gated;
	logic recovery_active_i_gated;

	// input operand isolation. AND with "recovery" i.e. stop taking in new instructions for GHR if misprediction recovery of Hash tables is going on
	// assign br_valid_i_gated = (en_i && !recovery_active) ? br_valid_i : 1'b0;
	// assign misprediction_i_gated = (en_i && !recovery_active) ? misprediction_i : 1'b0;
	// assign mispredicted_table_depth_i_gated = (en_i && !recovery_active) ? mispredicted_table_depth_i : '0;
	// assign br_packet_i_gated = (en_i && !recovery_active) ? br_packet_i : '0;

	assign br_valid_i_gated = en_i ? br_valid_i : 1'b0;
	assign misprediction_i_gated = en_i ? misprediction_i : 1'b0;
	assign mispredicted_table_depth_i_gated = en_i ? mispredicted_table_depth_i : '0;
	assign br_packet_i_gated = en_i ? br_packet_i : '0;
	assign recovery_active_i_gated = en_i ? recovery_active_i : 0;

	logic br_valid_and_recovery_not_active;		// this wire is just to say that the branch is valid and recovery is not active

	assign br_valid_and_recovery_not_active = br_valid_i_gated & (!recovery_active_i_gated);

	logic ptr_update_en;
	
	assign ptr_update_en = br_valid_and_recovery_not_active || misprediction_i_gated;	//gate for enabling the pointer only when there is either a "valid_branch" or "misprediction"
	logic clk_gated_ptr;

    gated_clk u_icg (
        .clk_i       (clk),
        .en_i        (ptr_update_en),	// gated clocks to head pointer only when there is br_valid or misprediction
        .clk_gated_o (clk_gated_ptr)
    );

	// pointer varibales for conditions
	logic [5:0] incremented_ptr;
	logic [5:0] rollback_ptr;
	logic [5:0] rollback_incremented_ptr;

	// pointer increment
	always_ff @(posedge clk_gated_ptr or negedge rst_n)
		begin
			if(!rst_n) begin
				head_ptr <= '0;
				// valid_history_count <= '0;		// commenting them as of now because we are not defining the valid histroy depth and depend on ROB to provide the valid depth
				incoming_packet_o <= '0;
			end else begin
				head_ptr <= next_head_ptr;
				// valid_history_count <= next_valid_history_count;
				incoming_packet_o <= br_packet_i_gated;
			end
		end
		
	// calculation of normal increment, rollback and rollback_increment case
	always_comb begin

		// Normal increment
		if (head_ptr == MAX_PTR - 1)
			incremented_ptr = '0;
		else
			incremented_ptr = head_ptr + 1'b1;
	
		// rollback only, no incoming writes
		if (head_ptr >= mispredicted_table_depth_i_gated)
			rollback_ptr = head_ptr - mispredicted_table_depth_i_gated;
		else
			rollback_ptr =	head_ptr + MAX_PTR - mispredicted_table_depth_i_gated;
	
		// rollback with incoming writes
		if (rollback_ptr == MAX_PTR - 1)
			rollback_incremented_ptr = '0;
		else
			rollback_incremented_ptr = rollback_ptr + 1'b1;
	end

	
	// assigning the value to head pointer
	always_comb begin
		next_head_ptr = head_ptr;

		// priority to misprediction to determine the "next_head_ptr"
		case ({misprediction_i_gated, br_valid_and_recovery_not_active})
        	2'b00: begin
				next_head_ptr = head_ptr;
			end

			2'b01: begin				// normal increment
				next_head_ptr = incremented_ptr;
			end

			2'b10: begin	// incase there is a squash/misprediction, so we need to bring back the pointer. No incoming packets at this time
				next_head_ptr = rollback_ptr;
			end

			2'b11: begin	/// incase there is a squash/misprediction, so we need to bring back the pointer. priority given to MISPREDICTION 
							/// to decide the head pointer so that next head pointer can point to next location for incoming write
				next_head_ptr = rollback_incremented_ptr;
			end

			default: begin
				next_head_ptr = head_ptr;
			end
    endcase
	end


	/// combinational block for recovery of history to be pushed into hash block downstream
	// NOT NEED THIS == ROB should provide a valid depth of misprediction
	// always_comb begin
	// 	next_valid_history_count = valid_history_count;
	
	// 	case ({misprediction_i_gated, br_valid_i_gated})
	
	// 		2'b00: begin	// idle position
	// 			next_valid_history_count = valid_history_count;
	// 		end
	
	// 		2'b01: begin	// normal incoming branch, no misprediction
	// 			// Normal branch insertion - max 36
	// 			if (valid_history_count < MAX_PTR)
	// 				next_valid_history_count =	valid_history_count + 1'b1;
	// 		end
	
	// 		2'b10: begin	// no incoming branch , with MISPREDICTION
	// 			// Remove squashed entries
	// 			next_valid_history_count = valid_history_count - mispredicted_table_depth_i_gated;
	// 		end
	
	// 		2'b11: begin	// MISPREDICTION with INCOMING BRANCH
	// 			// Remove squashed entries, and insert recovery branch
	// 			next_valid_history_count = valid_history_count - mispredicted_table_depth_i_gated + 1'b1;
	// 		end
	
	// 		default: begin
	// 			next_valid_history_count = valid_history_count;
	// 		end
	
	// 	endcase
	// end


	// module and SRAM block address generator function
	// function for generating the modulo to get the bank to write on
	// will synthesize with case logic
	function logic [3:0] get_bank(input logic [5:0] ptr); 
			case (ptr) inside
			[0:8]   : return ptr[3:0];
			[9:17]  : return (ptr - 6'd9);
			[18:26] : return (ptr - 6'd18);
			[27:35] : return (ptr - 6'd27);
			default : return '0;
		endcase
	endfunction

	// function to generate the row address of the respective bank
	function logic [1:0] get_row(input logic [5:0] ptr);        
		case (ptr) inside
			[0:8]   : return 2'b00;
			[9:17]  : return 2'b01;
			[18:26] : return 2'b10;
			[27:35] : return 2'b11;
			default : return 2'b00;
		endcase
	endfunction

	// circular subtract function. Moves backwards through circular 36 GHR entry
	function automatic logic [5:0] circular_subtract(
		input logic [5:0] pointer,
		input logic [5:0] distance
	);
		if (pointer >= distance)
			return pointer - distance;
		else
			return pointer + MAX_PTR - distance;
	endfunction

	///WRITE LOGIC
	// here we need to use the generated bank and address to get and write to the physical target

	logic [3:0] write_bank;	// select the bank to write to
	logic [1:0] write_row;	// select the row to write on that bank

	// physical target to write to Bank number and row number
	// correction here for the reset condition where the head pointer will look at table_0_loc_0 and 
	// next_hd_ptr will look at table_1_loc_0. So, inserting the logic to differentiate between rollback and normal writes

	logic [5:0] write_ptr;

	always_comb begin
		write_ptr = head_ptr;		// Normal write occurs at the current free location.

		// After rollback, the recovered head becomes the write location.
		if (misprediction_i_gated)	write_ptr = rollback_ptr;
	end

	assign write_bank = get_bank(write_ptr);
	assign write_row  = get_row(write_ptr);

	// send the write to a specific bank. we don't need to use a reset logic here as it is memory
	// ******Power Gating ****** the banks - select only that bank which is going to take incoming value
	//		FIRSTLY, make a WRITE_ENABLE for that particular bank.
	logic bank_we [0:NUM_BANKS-1];
	
	always_comb begin
		for (int b = 0; b < NUM_BANKS; b++) begin
			bank_we[b] = br_valid_and_recovery_not_active && (write_bank == b);
		end
    end

	// to keep a check that the bank_we is one hot only when br_valid_i_gated is high
	// assert property (@(posedge clk) br_valid_i_gated |-> $onehot(bank_we));

	// ICGs for each of the 9 banks.
	logic gated_bank_clk [0:NUM_BANKS-1];
	
	generate 
			for (genvar b = 0; b < NUM_BANKS; b++) begin 
				
				gated_clk u_icg (
                    .clk_i       (clk),
                    .en_i        (bank_we[b]),
                    .clk_gated_o (gated_bank_clk[b])
                );

				// **** VERY VERY IMPORTANT OBSERVATION *****//
				// could have used always_ff - BUT in this we have multiple instance of always_ff block being generated.
				// and in those multiple instances we are targeting the same memory bank i.e. "bank_mem".
				// But, there is a rule that - A VARIABLE WRITTEN BY AN "always_ff" block must not be written by any other processes.
				// so, here it will feel like there are 7 different processes drive "bank_mem" and hence it is better to use "always@" if we intend to do this.
				always @(posedge gated_bank_clk[b] or negedge rst_n) begin		
					if (!rst_n) begin
						for (int r = 0; r < ENTRIES_PER_BANK; r++) begin
							bank_mem[r][b] <= '0;
						end
					end	else begin
						bank_mem[write_row][b] <= br_packet_i_gated;
					end
				end
			end
	endgenerate

 

	// gate the output - but need to keep it with the clock because it needs to come out with the expiring packet at the output.
	// hence moving it under gated the sequential block of "head_ptr" in the design.
	// assign incoming_packet_o = (br_valid_and_recovery_not_active) ? br_packet_i_gated : '0;		// this is the packet that will directly go to the hash table

	/// READ LOGIC
	localparam int TOTAL_CAPACITY = NUM_BANKS * ENTRIES_PER_BANK;
	localparam logic [5:0] DEPTHS [0:NUM_HASH_TABLES-1] = '{6'd2, 6'd4, 6'd6, 6'd8, 6'd12, 6'd16, 6'd32};

	logic [5:0] target_index [0:NUM_HASH_TABLES-1];
	logic [3:0] read_bank	 [0:NUM_HASH_TABLES-1];
	logic [1:0] read_row	 [0:NUM_HASH_TABLES-1];


	generate
			for(genvar i = 0; i < NUM_HASH_TABLES; i++) begin
				
				// Absolute index calculation. for DEPTH less and greater than head pointer

				assign target_index[i] = (next_head_ptr >= DEPTHS[i]) ? (next_head_ptr - DEPTHS[i]) : ((TOTAL_CAPACITY) - (DEPTHS[i] - next_head_ptr));
				// assign target_index[i] = (head_ptr >= DEPTHS[i]) ? (head_ptr - DEPTHS[i]) : ((TOTAL_CAPACITY) - (DEPTHS[i] - head_ptr));

				// 1D to 2D Hardware translation, getting the bank and the row
				assign read_bank[i] = get_bank(target_index[i]);
				assign read_row[i]  = get_row(target_index[i]);

				/// giving out the expiring packets out from the GHR block
				assign expiring_packet_o[i] = (br_valid_and_recovery_not_active) ? bank_mem[read_row[i]][read_bank[i]] : 0;

			end
	endgenerate

	// assertion added so that the pointer does not rollback into history that never existed
	assert property (@(posedge clk)
		misprediction_i_gated |-> (mispredicted_table_depth_i_gated > 0) && (mispredicted_table_depth_i_gated < MAX_PTR)
	);

endmodule                  
      
      
      
      
      
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