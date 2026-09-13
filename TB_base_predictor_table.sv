import uvm_pkg::*;
`include "uvm_macros.svh"

interface base_predictor_if #(
	parameter INDEX_WIDTH = 10,
    parameter DISTANCE_WIDTH = 7,
    parameter CONFIDENCE_WIDTH = 3
)(
  input logic clk
);

	// reading from memory
  logic fetch_en_i;
  logic [INDEX_WIDTH-1:0] fetch_idx_i;
  logic [DISTANCE_WIDTH-1:0] base_dist_o;
  logic [CONFIDENCE_WIDTH-1:0] base_conf_o;

  // writing to the memory
  logic update_en_i;
  logic [INDEX_WIDTH-1:0] commit_index_i;
  logic [DISTANCE_WIDTH-1:0] commit_distance_i;
  logic [CONFIDENCE_WIDTH-1:0] commit_confidence_i;

  // drivers output serving as input to DUT
  clocking drv_cb @(negedge clk);
    output fetch_en_i;
    output fetch_idx_i;
    output update_en_i;
    output commit_index_i;
    output commit_distance_i;
    output commit_confidence_i;
  endclocking

  // output from DUT as inpput to monitor
  clocking mon_cb @(posedge clk);

  	default input #1step;

    input fetch_en_i;
    input fetch_idx_i;
    input update_en_i;
    input commit_index_i;
    input commit_distance_i;
    input commit_confidence_i;
    input base_dist_o;
    input base_conf_o;
  endclocking

  modport DUT_MP (
    input  clk,
    input  fetch_en_i,
    input  fetch_idx_i,
    input  update_en_i,
    input  commit_index_i,
    input  commit_distance_i,
    input  commit_confidence_i,

	output base_dist_o,
    output base_conf_o
  );

  modport DRV_MP (
    clocking drv_cb,
    input clk
  );

  modport MON_MP (
    clocking mon_cb,
    input clk
  );

  // when outputs are NOT UNDEFINED. Check for situation when fetch_en was 1 earlier and is 0 now - the outputs must hold stable.
  // better version ->  if fetch_en is low now, and was low in the last cycle as well, the outputs are known - then the outputs must be stable
	property read_output_holds_when_fetch_disabled;
		@(posedge clk)
		!fetch_en_i &&
		!$past(fetch_en_i) &&
		!$isunknown({base_dist_o, base_conf_o}) 
		|-> $stable({base_dist_o, base_conf_o});
	endproperty

	assert property (read_output_holds_when_fetch_disabled)
    else $error("Read output changed while fetch_en_i was low");

	// to check when the fetch_en is asserted then the fetch address value is not undefined - it should be correct/valid address.
	property read_controls_known_when_enabled;
		@(posedge clk)
		fetch_en_i |-> !$isunknown(fetch_idx_i);
	endproperty

	assert property (read_controls_known_when_enabled)
	else $error("fetch_idx_i is X/Z while fetch_en_i is active");

	// to check when update_en_i is asserted then the values for commit_index_i, commit_distance_i and commit_confidence_i is not undefined
	property write_controls_known_when_enabled;
	@(posedge clk)
		update_en_i
		|-> !$isunknown({
			commit_index_i,
			commit_distance_i,
			commit_confidence_i
			});
	endproperty
	  
	assert property (write_controls_known_when_enabled)
	else $error("Write address/data contains X/Z while update_en_i is active");

	/// to check if the enables are unknown or known
	// but since the design does not initialize the interface signals at time 0, it may fail immediatly so Keeping checks_en signal here.
	// logic check_en;

	// initial checks_en = 1'b0;

	property enables_are_known;
		@(posedge clk)
		// checks_en |-> !$isunknown({fetch_en_i, update_en_i});
		!$isunknown({fetch_en_i, update_en_i});
	endproperty
	
	assert property (enables_are_known)
	else $error("fetch_en_i or update_en_i is X/Z");


endinterface


// sequence_item
class base_predictor_item extends uvm_sequence_item;

	localparam int INDEX_WIDTH = 10;
	localparam int DISTANCE_WIDTH = 7;
	localparam int CONFIDENCE_WIDTH = 3;

	rand bit fetch_en;
	rand bit [INDEX_WIDTH-1:0] fetch_idx;

	rand bit update_en;
	rand bit [INDEX_WIDTH-1:0] commit_index;
	rand bit [DISTANCE_WIDTH-1:0] commit_distance;
	rand bit [CONFIDENCE_WIDTH-1:0] commit_confidence;

	bit [DISTANCE_WIDTH-1:0] observed_dist;
	bit [CONFIDENCE_WIDTH-1:0] observed_conf;

	// constraints defined for fetch_en and update_en to keep fetch and update modes balanced
	constraint reasonable_enable_distribution_c {
		fetch_en  dist {1 := 45,
						0 := 55};
		update_en dist {1 := 45,
						0 := 55};
	}

	`uvm_object_utils_begin(base_predictor_item)
	`uvm_field_int(fetch_en,UVM_ALL_ON)
	`uvm_field_int(fetch_idx,UVM_ALL_ON)

	`uvm_field_int(update_en,UVM_ALL_ON)
	`uvm_field_int(commit_index,UVM_ALL_ON)
	`uvm_field_int(commit_distance,UVM_ALL_ON)
	`uvm_field_int(commit_confidence,UVM_ALL_ON)

	`uvm_field_int(observed_dist,UVM_ALL_ON)
	`uvm_field_int(observed_conf,UVM_ALL_ON)
	`uvm_object_utils_end

	function new(string name = "base_predictor_item");
		super.new(name);
	endfunction

endclass


// sequence
class base_predictor_base_seq extends uvm_sequence #(base_predictor_item);

	`uvm_object_utils(base_predictor_base_seq)

	function new(string name = "base_predictor_base_seq");
		super.new(name);
	endfunction

	task write_cycle(					/// write to the memory location only - only writing
		input bit [9:0] idx,
		input bit [6:0] distn,
		input bit [2:0] conf
	);
		base_predictor_item tr;

		tr = base_predictor_item::type_id::create("write_tr");

		start_item(tr);
		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = '0;

		tr.update_en         = 1'b1;
		tr.commit_index      = idx;
		tr.commit_distance   = distn;
		tr.commit_confidence = conf;
		finish_item(tr);
	endtask

	task read_cycle(					/// reading from the memory location - only reading
		input bit [9:0] idx
	);
		base_predictor_item tr;

		tr = base_predictor_item::type_id::create("read_tr");

		start_item(tr);
		tr.fetch_en          = 1'b1;
		tr.fetch_idx         = idx;

		tr.update_en         = 1'b0;
		tr.commit_index      = '0;
		tr.commit_distance   = '0;
		tr.commit_confidence = '0;
		finish_item(tr);
	endtask

	task idle_cycle();					/// no reading and writing at the location - SRAM should hold values at the read port
		base_predictor_item tr;

		tr = base_predictor_item::type_id::create("idle_tr");

		start_item(tr);
		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = '0;

		tr.update_en         = 1'b0;
		tr.commit_index      = '0;
		tr.commit_distance   = '0;
		tr.commit_confidence = '0;
		finish_item(tr);
	endtask

	task read_write_cycle(				/// read and write simultaneously from the same location
		input bit [9:0] fetch_idx,
		input bit [9:0] commit_idx,
		input bit [6:0] distn,
		input bit [2:0] conf
	);
		base_predictor_item tr;

		tr = base_predictor_item::type_id::create("read_write_tr");

		start_item(tr);
		tr.fetch_en          = 1'b1;
		tr.fetch_idx         = fetch_idx;

		tr.update_en         = 1'b1;
		tr.commit_index      = commit_idx;
		tr.commit_distance   = distn;
		tr.commit_confidence = conf;
		finish_item(tr);
	endtask

	task idle_with_inputs(
		input bit [9:0] fetch_idx,
		input bit [9:0] commit_idx,
		input bit [6:0] commit_dist,
		input bit [2:0] commit_conf
	);
		base_predictor_item tr;

		tr = base_predictor_item::type_id::create("idle_with_inputs_tr");

		start_item(tr);

		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = fetch_idx;

		tr.update_en         = 1'b0;
		tr.commit_index      = commit_idx;
		tr.commit_distance   = commit_dist;
		tr.commit_confidence = commit_conf;

		finish_item(tr);
	endtask

	task disabled_write_cycle(
		input bit [9:0] commit_idx,
		input bit [6:0] commit_dist,
		input bit [2:0] commit_conf
	);
		base_predictor_item tr;

		tr = base_predictor_item::type_id::create("disabled_write_tr");

		start_item(tr);

		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = '0;

		// Write-side inputs toggle, but update_en is 0.
		tr.update_en         = 1'b0;
		tr.commit_index      = commit_idx;
		tr.commit_distance   = commit_dist;
		tr.commit_confidence = commit_conf;

		finish_item(tr);
		endtask

endclass

// sanity sequence
class base_predictor_smoke_seq extends base_predictor_base_seq;

  `uvm_object_utils(base_predictor_smoke_seq)

  function new(string name = "base_predictor_smoke_seq");
    super.new(name);
  endfunction

  
  task body();

    idle_cycle();
    idle_cycle();

    write_cycle(10'd5, 7'h2A, 3'h5);
    idle_cycle();

    write_cycle(10'd3, 7'h1B, 3'h6);
    idle_cycle();
	
    write_cycle(10'd7, 7'h12, 3'h4);
    idle_cycle();
	
    write_cycle(10'd8, 7'h13, 3'h2);
    idle_cycle();

    read_cycle(10'd5);
    read_cycle(10'd3);
    read_cycle(10'd7);
    read_cycle(10'd8);

    idle_cycle();
    idle_cycle();

  endtask

endclass

// random sequence write and read cycles.
// but the issue is that it is generating random WRITE REQUESTS and random READ REQUESTS - which may or may not be the same.

class base_predictor_random_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_random_seq)

	rand int unsigned num_transactions;

	constraint num_transactions_c {				/// reached coverage percentage = 99.25%
      num_transactions inside {[3000:4999]};
	}

	function new(string name = "base_predictor_random_seq");
		super.new(name);
	endfunction

	task body();
		base_predictor_item tr;

		if (!randomize()) begin
		`uvm_error("RAND_SEQ", "Failed to randomize num_transactions")
		end

		`uvm_info("RAND_SEQ",$sformatf("Starting random sequence with %0d transactions", num_transactions),UVM_LOW)

		repeat (num_transactions) begin
			tr = base_predictor_item::type_id::create("tr");
			
			start_item(tr);
			if (!tr.randomize()) begin
				`uvm_error("RAND_SEQ", "Failed to randomize transaction")
			end
			finish_item(tr);
		end

		// Add some idle cycles at the end so final read output can settle/check.
		repeat (3) begin
			idle_cycle();
		end

	endtask

endclass

/// random sequences write and read cycles.
/// generate random WRITE ADDRESSES and Store them in a Queue and then use those as read addresses
class base_predictor_random_write_and_same_read_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_random_write_and_same_read_seq)

	rand int unsigned num_writes;

	bit [9:0] written_addr_q[$];

	constraint num_writes_c {
		num_writes inside {[15:20]};
	}

	function new(string name = "base_predictor_random_write_and_same_read_seq");
		super.new(name);
	endfunction

	task body();

		bit [9:0] rand_idx;
		bit [6:0] rand_dist;
		bit [2:0] rand_conf;

		if (!randomize()) begin
			`uvm_error("RAND_WR_RD_SEQ", "Failed to randomize num_writes")
		end

		`uvm_info("RAND_WR_RD_SEQ",
			$sformatf("Starting random write/read sequence with %0d writes", num_writes),
			UVM_LOW)

		idle_cycle();
		idle_cycle();

		// randomly generated write indexes
		repeat (num_writes) begin
			rand_idx  = $urandom_range(0, 1023);
			rand_dist = $urandom_range(0, 127);
			rand_conf = $urandom_range(0, 7);

			write_cycle(rand_idx, rand_dist, rand_conf);

			written_addr_q.push_back(rand_idx);		// store the generated write indexes in a queue to use later fro read
		end

		idle_cycle();
		idle_cycle();

		// read addresses from the queue of stored write addresses
		foreach (written_addr_q[i]) begin
			read_cycle(written_addr_q[i]);
		end

		idle_cycle();
		idle_cycle();

	endtask

endclass

// hazard sequence for writing - reading - writing to same location with no IDLE CYCLES IN MIDDLE of WRITE and READ action

class base_predictor_hazard extends base_predictor_base_seq;
    `uvm_object_utils(base_predictor_hazard)

	// location for scoreboard to 

    function new(string name = "base_predictor_hazard");
        super.new(name);
    endfunction

    virtual task body();
        bit [9:0] target_idx;
        // bit [6:0] rand_dist;
        // bit [2:0] rand_conf;

		// Data variables for (Back2Back)
        bit [6:0] dist_v1;
        bit [2:0] conf_v1;

		// Data variables for (Same-Cycle)
        bit [6:0] dist_v2;
        bit [2:0] conf_v2;

		`uvm_info("RAW_SEQ", "=================================================", UVM_LOW)
        `uvm_info("RAW_SEQ", "Read after write HAZARD seq ", UVM_LOW)
        `uvm_info("RAW_SEQ", "=================================================", UVM_LOW)

        repeat (300) begin					//   able to reach 78.18% total coverage (fetchidx, commitix = 57.14%  ||  sameaddr_cov = 50%)
            target_idx = $urandom_range(0, 1023);
            
			dist_v1    = $urandom_range(0, 127);
            conf_v1    = $urandom_range(0, 7);
            dist_v2    = $urandom;
            conf_v2    = $urandom;

			`uvm_info("RAW_SEQ", $sformatf(" Testing Target Index: %0d ", target_idx), UVM_LOW)

            // Back2back Read After Write (Write at T, Read at T+1) - one clock cycle gap because of the clock in driver
            `uvm_info("RAW_SEQ", $sformatf("[WRITE (1)-READ (0) Cycle T]   WRITE -> Idx: %0d | Data: {Dist: 0x%0h, Conf: 0x%0h}",target_idx, dist_v1, conf_v1), UVM_LOW)
            write_cycle(.idx(target_idx), .distn(dist_v1), .conf(conf_v1));
           
			`uvm_info("RAW_SEQ", $sformatf("[WRITE (0)-READ (1) Cycle T+1] READ  -> Idx: %0d | Expecting: {Dist: 0x%0h, Conf: 0x%0h}",target_idx, dist_v1, conf_v1), UVM_LOW)
            read_cycle(.idx(target_idx));
            idle_cycle();

            // Same-Cycle Read After Write (Parallel Read/Write to matching address)
            `uvm_info("RAW_SEQ",
					$sformatf({
						"[WRITE (1) - READ (1) Cycle T] SAME-CYCLE READ/WRITE -> Idx: %0d\n",
						"  Write new data              : {Dist: 0x%0h, Conf: 0x%0h}\n",
						"  Expected same-cycle read    : {Dist: 0x%0h, Conf: 0x%0h}  // OLD data\n",
						"  Expected next readback      : {Dist: 0x%0h, Conf: 0x%0h}  // NEW data"
					},
						target_idx,
						dist_v2, conf_v2,
						dist_v1, conf_v1,
						dist_v2, conf_v2
					),
					UVM_LOW
					)
            read_write_cycle(
                .fetch_idx(target_idx),
                .commit_idx(target_idx),
                .distn(dist_v2),
                .conf(conf_v2)
            );
            
            // Read again in next cycle to ensure data has committed permanently
			`uvm_info("RAW_SEQ", $sformatf("[CASE 2 - Cycle T_new+1] READ  -> Idx: %0d | Expecting New committed data: {Dist: 0x%0h, Conf: 0x%0h}",target_idx, dist_v2, conf_v2), UVM_LOW)
			read_cycle(.idx(target_idx));
            idle_cycle();
        end

		`uvm_info("RAW_SEQ", "==================================================", UVM_LOW)
        `uvm_info("RAW_SEQ", "RAW HAZARD VERIFICATION SEQUENCE COMPLETED        ", UVM_LOW)
        `uvm_info("RAW_SEQ", "==================================================", UVM_LOW)
    
	endtask
endclass


/// write in first cycle only - read after that and check that data is stable after that
class base_predictor_read_stability_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_read_stability_seq)

	function new(string name = "base_predictor_read_stability_seq");
		super.new(name);
	endfunction

	task body();

		bit [9:0] target_idx;
		bit [6:0] target_dist;
		bit [2:0] target_conf;

		target_idx  = $urandom_range(0, 1023);
		target_dist = $urandom_range(0, 127);;
		target_conf = $urandom_range(0, 7);;

		idle_cycle();
		idle_cycle();

		repeat (8) begin
			with_random_inputs(target_idx, target_dist, target_conf);			
		end

	idle_cycle();
	idle_cycle();
	idle_cycle();

	endtask

	task with_random_inputs(target_idx, target_dist, target_conf);

		`uvm_info("READ_STABILITY_SEQ",
		$sformatf("[WRITE] idx=%0d data={dist=0x%0h conf=0x%0h}",
		target_idx, target_dist, target_conf),
		UVM_LOW)

		write_cycle(target_idx, target_dist, target_conf);

		idle_cycle();

		`uvm_info("READ_STABILITY_SEQ",
		$sformatf("[READ] idx=%0d expecting output={dist=0x%0h conf=0x%0h}",
		target_idx, target_dist, target_conf),
		UVM_LOW)

		read_cycle(target_idx);

		// Now fetch_en is low. Output should hold the last read value.
		// These idle cycles keep fetch_en_i low.
		`uvm_info("READ_STABILITY_SEQ",
		"Holding fetch_en_i low. Output should remain stable.",
		UVM_LOW)
	endtask

endclass


// address uniqueness check
class base_predictor_unique_value_at_index_pattern_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_unique_value_at_index_pattern_seq)

	function new(string name = "base_predictor_unique_value_at_index_pattern_seq");
		super.new(name);
	endfunction

	task body();

	bit [9:0] idx;
	bit [6:0] dist_pattern;
	bit [2:0] conf_pattern;

	idle_cycle();
	idle_cycle();

	`uvm_info("ADDR_PATTERN_SEQ",
		"Writing distinct pattern into first 100 memory locations",
		UVM_LOW)

	// Write pattern
	for (int i = 0; i < 32; i++) begin
		idx          = i[9:0];
		dist_pattern = i + 5;
		conf_pattern = i[2:0];

		`uvm_info("ADDR_PATTERN_SEQ",
		$sformatf("[WRITE] idx=%0d data={dist=0x%0h conf=0x%0h}",
			idx, dist_pattern, conf_pattern),
		UVM_HIGH)

		write_cycle(idx, dist_pattern, conf_pattern);
	end

	idle_cycle();
	idle_cycle();

	`uvm_info("ADDR_PATTERN_SEQ",
		"Reading back first 100 memory locations",
		UVM_LOW)


	// Read back pattern
	for (int i = 0; i < 32; i++) begin
		idx = i[9:0];

		`uvm_info("ADDR_PATTERN_SEQ",
		$sformatf("[READ] idx=%0d expecting={dist=0x%0h conf=0x%0h}",
			idx, (i + 5), i[2:0]),
		UVM_HIGH)

		read_cycle(idx);
	end

	idle_cycle();
	idle_cycle();

	endtask

endclass

// access transition coverage sequence
class base_predictor_access_transition_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_access_transition_seq)

	function new(string name = "base_predictor_access_transition_seq");
		super.new(name);
	endfunction

	task body();

		bit [9:0] idx_a;
		bit [9:0] idx_b;

		idx_a = 10'd40;
		idx_b = 10'd41;

		`uvm_info("ACCESS_TRANSITION_SEQ",
			"Starting access transition sequence",
			UVM_LOW)

		idle_cycle();
		idle_cycle();

		// Initialize addresses so reads are valid.
		write_cycle(idx_a, 7'h21, 3'h1);
		write_cycle(idx_b, 7'h32, 3'h2);


		// idle -> read / write / read_write

		idle_cycle();
		read_cycle(idx_a);

		idle_cycle();
		write_cycle(10'd42, 7'h42, 3'h3);

		idle_cycle();
		read_write_cycle(idx_a, 10'd43, 7'h43, 3'h4);

		// write -> read / write / read_write

		write_cycle(10'd44, 7'h44, 3'h4);
		read_cycle(idx_a);

		write_cycle(10'd45, 7'h45, 3'h5);
		write_cycle(10'd46, 7'h46, 3'h6);

		write_cycle(10'd47, 7'h47, 3'h7);
		read_write_cycle(idx_a, 10'd48, 7'h48, 3'h0);

		// read -> read / write / read_write

		read_cycle(idx_a);
		read_cycle(idx_b);

		read_cycle(idx_a);
		write_cycle(10'd49, 7'h49, 3'h1);

		read_cycle(idx_a);
		read_write_cycle(idx_b, 10'd50, 7'h50, 3'h2);

		// read_write -> read / write / read_write

		read_write_cycle(idx_a, 10'd51, 7'h51, 3'h3);
		read_cycle(idx_b);

		read_write_cycle(idx_a, 10'd52, 7'h52, 3'h4);
		write_cycle(10'd53, 7'h53, 3'h5);

		read_write_cycle(idx_a, 10'd54, 7'h54, 3'h6);
		read_write_cycle(idx_b, 10'd55, 7'h55, 3'h7);

		idle_cycle();
		idle_cycle();

		`uvm_info("ACCESS_TRANSITION_SEQ",
			"Completed access transition sequence",
			UVM_LOW)

	endtask

endclass


/// sequence to check the impact when there are multiple writes to an address

class base_predictor_duplicate_write_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_duplicate_write_seq)

	function new(string name = "base_predictor_duplicate_write_seq");
		super.new(name);
	endfunction

	task body();

		bit [9:0] target_idx;

		target_idx = 10'd77;

		`uvm_info("DUP_WRITE_SEQ",
			$sformatf("Starting duplicate write sequence at idx=%0d", target_idx),
			UVM_LOW)

		idle_cycle();
		idle_cycle();

		write_cycle(target_idx, 7'h11, 3'h1);
		write_cycle(target_idx, 7'h22, 3'h2);
		write_cycle(target_idx, 7'h33, 3'h3);

		// Latest write should win: expect 0x33 / 0x3
		read_cycle(target_idx);

		idle_cycle();
		idle_cycle();

		`uvm_info("DUP_WRITE_SEQ",
			"Completed duplicate write sequence",
			UVM_LOW)

	endtask

endclass


/// disables ENABLE for read and write with toggling inputs
class base_predictor_disabled_input_toggle_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_disabled_input_toggle_seq)

	function new(string name = "base_predictor_disabled_input_toggle_seq");
		super.new(name);
	endfunction

	task body();

	`uvm_info("DISABLED_TOGGLE_SEQ",
		"Starting disabled-port input toggle sequence",
		UVM_LOW)

	idle_cycle();

	// Both enables are 0, but inputs toggle every cycle.
	idle_with_inputs(10'd1,   10'd10, 7'h11, 3'h1);
	idle_with_inputs(10'd2,   10'd20, 7'h22, 3'h2);
	idle_with_inputs(10'd3,   10'd30, 7'h33, 3'h3);
	idle_with_inputs(10'd4,   10'd40, 7'h44, 3'h4);
	idle_with_inputs(10'd999, 10'd50, 7'h55, 3'h5);

	idle_cycle();

	`uvm_info("DISABLED_TOGGLE_SEQ",
		"Completed disabled-port input toggle sequence",
		UVM_LOW)

	endtask

endclass


// sequence with distance constant but confidence changes by PLUS ONE or MINUS ONE at an index
class base_predictor_confidence_INCR_DECR_ONLY_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_confidence_INCR_DECR_ONLY_seq)

	function new(string name = "base_predictor_confidence_INCR_DECR_ONLY_seq");
		super.new(name);
	endfunction

	task body();

		bit [9:0] target_idx;
		bit [6:0] base_dist;
		bit [2:0] conf_init;
		bit [2:0] conf_plus;
		bit [2:0] conf_minus;

		target_idx = 10'd88;
		base_dist  = 7'h35;
		conf_init  = 3'd3;

		conf_plus  = conf_init + 1'b1;
		conf_minus = conf_plus - 1'b1;

		`uvm_info("CONF_STEP_SEQ",
			$sformatf("Starting confidence step sequence idx=%0d dist=0x%0h conf_init=0x%0h",
			target_idx, base_dist, conf_init),
			UVM_LOW)

		idle_cycle();
		idle_cycle();

		// Initial write
		write_cycle(target_idx, base_dist, conf_init);
		read_cycle(target_idx);

		// +1 confidence, distance unchanged
		`uvm_info("CONF_STEP_SEQ",
			$sformatf("[PLUS ONE] idx=%0d dist unchanged=0x%0h conf 0x%0h -> 0x%0h",
			target_idx, base_dist, conf_init, conf_plus),
			UVM_LOW)

		write_cycle(target_idx, base_dist, conf_plus);
		read_cycle(target_idx);

		// -1 confidence, distance unchanged
		`uvm_info("CONF_STEP_SEQ",
			$sformatf("[MINUS ONE] idx=%0d dist unchanged=0x%0h conf 0x%0h -> 0x%0h",
			target_idx, base_dist, conf_plus, conf_minus),
			UVM_LOW)

		write_cycle(target_idx, base_dist, conf_minus);
		read_cycle(target_idx);

		idle_cycle();
		idle_cycle();

		`uvm_info("CONF_STEP_SEQ",
			"Completed confidence step sequence",
			UVM_LOW)

	endtask

endclass

// saturating counter check for confidence bits at an index
// confidence 7 + 1 = 7
// confidence 0 - 1 = 0
class base_predictor_confidence_saturation_seq extends base_predictor_base_seq;

		`uvm_object_utils(base_predictor_confidence_saturation_seq)

		function new(string name = "base_predictor_confidence_saturation_seq");
		super.new(name);
		endfunction

		task body();

		bit [9:0] inc_idx;
		bit [9:0] dec_idx;

		bit [6:0] inc_dist;
		bit [6:0] dec_dist;

		bit [2:0] conf_6;
		bit [2:0] conf_7;
		bit [2:0] conf_1;
		bit [2:0] conf_0;

		conf_6 = 3'd6;
		conf_7 = 3'd7;
		conf_1 = 3'd1;
		conf_0 = 3'd0;

		`uvm_info("CONF_SAT_SEQ",
			"Starting confidence saturation sequence: 6->7->7 and 1->0->0",
			UVM_LOW)

		idle_cycle();
		idle_cycle();

		repeat (7) begin

			// Saturation increment path: 6 -> 7 -> 7
			
			inc_idx  = $urandom_range(0, 1023);
			inc_dist = $urandom_range(0, 127);

			`uvm_info("CONF_SAT_SEQ",
			$sformatf("[SAT INC] idx=%0d dist=0x%0h conf 6 -> 7 -> 7",
				inc_idx, inc_dist),
			UVM_LOW)

			// confidence 6
			write_cycle(inc_idx, inc_dist, conf_6);
			read_cycle(inc_idx);

			// Increment to 7
			write_cycle(inc_idx, inc_dist, conf_7);
			read_cycle(inc_idx);

			// Increment again, should reman at 7
			write_cycle(inc_idx, inc_dist, conf_7);
			read_cycle(inc_idx);

			idle_cycle();

			
			// Saturating decrement path: 1 -> 0 -> 0
			dec_idx  = $urandom_range(0, 1023);
			dec_dist = $urandom_range(0, 127);

			`uvm_info("CONF_SAT_SEQ",
			$sformatf("[SAT DEC] idx=%0d dist=0x%0h conf 1 -> 0 -> 0",
				dec_idx, dec_dist),
			UVM_LOW)

			// confidence 1
			write_cycle(dec_idx, dec_dist, conf_1);
			read_cycle(dec_idx);

			// Decrement to 0
			write_cycle(dec_idx, dec_dist, conf_0);
			read_cycle(dec_idx);

			// Decrement again, should remain 0
			write_cycle(dec_idx, dec_dist, conf_0);
			read_cycle(dec_idx);

			idle_cycle();

		end

		idle_cycle();
		idle_cycle();

		`uvm_info("CONF_SAT_SEQ",
			"Completed confidence saturation sequence",
			UVM_LOW)

		endtask

endclass


// disabled write sequence for update port
class base_predictor_disabled_write_protection_seq extends base_predictor_base_seq;

	`uvm_object_utils(base_predictor_disabled_write_protection_seq)

	function new(string name = "base_predictor_disabled_write_protection_seq");
		super.new(name);
	endfunction

	task body();

		bit [9:0] target_idx;
		bit [6:0] original_dist;
		bit [2:0] original_conf;

		bit [6:0] blocked_dist;
		bit [2:0] blocked_conf;

		target_idx    = 10'd123;
		original_dist = 7'h2D;
		original_conf = 3'h5;

		blocked_dist  = 7'h6A;
		blocked_conf  = 3'h1;

		`uvm_info("DISABLED_WRITE_SEQ",
		$sformatf("Starting disabled write protection test at idx=%0d", target_idx),
		UVM_LOW)

		idle_cycle();
		idle_cycle();

		// Write original value.
		write_cycle(target_idx, original_dist, original_conf);

		// Confirm original value was written.
		read_cycle(target_idx);

		idle_cycle();

		// Try to overwrite same index with update_en=0.
		`uvm_info("DISABLED_WRITE_SEQ",
		$sformatf("Attempting disabled write idx=%0d blocked_data={dist=0x%0h conf=0x%0h}; expected memory remains {dist=0x%0h conf=0x%0h}",
			target_idx,
			blocked_dist,
			blocked_conf,
			original_dist,
			original_conf),
		UVM_LOW)

		disabled_write_cycle(target_idx, blocked_dist, blocked_conf);

		// toggle unrelated write-side inputs while disabled.
		disabled_write_cycle(10'd124, 7'h11, 3'h1);
		disabled_write_cycle(10'd125, 7'h22, 3'h2);
		disabled_write_cycle(target_idx, 7'h7F, 3'h7);

		idle_cycle();

		// Read original address again.
		// Scoreboard should still expect original value.
		read_cycle(target_idx);

		idle_cycle();
		idle_cycle();

		`uvm_info("DISABLED_WRITE_SEQ",
		"Completed disabled write protection test",
		UVM_LOW)

	endtask

endclass

	// sequencer
class base_predictor_sequencer extends uvm_sequencer #(base_predictor_item);

`uvm_component_utils(base_predictor_sequencer)

function new(string name = "base_predictor_sequencer", uvm_component parent);
	super.new(name, parent);
endfunction

endclass

// driver
class base_predictor_driver extends uvm_driver #(base_predictor_item);

	`uvm_component_utils(base_predictor_driver)

	virtual base_predictor_if vif;

	function new(string name = "base_predictor_driver", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual base_predictor_if)::get(this,"","vif",vif)) begin
			`uvm_fatal("NOVIF", "Virtual interface not found for base_predictor_driver")
		end
	endfunction

	task run_phase(uvm_phase phase);
		base_predictor_item req;

		drive_idle();

		forever begin
			seq_item_port.get_next_item(req);
			drive_item(req);
			seq_item_port.item_done();
		end
	endtask

	task drive_idle();

		@(vif.drv_cb);
		vif.drv_cb.fetch_en_i          <= 1'b0;
		vif.drv_cb.fetch_idx_i         <= '0;

		vif.drv_cb.update_en_i         <= 1'b0;
		vif.drv_cb.commit_index_i      <= '0;
		vif.drv_cb.commit_distance_i   <= '0;
		vif.drv_cb.commit_confidence_i <= '0;
	endtask

	task drive_item(base_predictor_item tr);

		@(vif.drv_cb);

		vif.drv_cb.fetch_en_i          <= tr.fetch_en;
		vif.drv_cb.fetch_idx_i         <= tr.fetch_idx;

		vif.drv_cb.update_en_i         <= tr.update_en;
		vif.drv_cb.commit_index_i      <= tr.commit_index;
		vif.drv_cb.commit_distance_i   <= tr.commit_distance;
		vif.drv_cb.commit_confidence_i <= tr.commit_confidence;

		`uvm_info("DRV",
			$sformatf("Driving fetch_en=%0b fetch_idx=%0d update_en=%0b commit_idx=%0d dist=0x%0h conf=0x%0h",
			tr.fetch_en,
			tr.fetch_idx,
			tr.update_en,
			tr.commit_index,
			tr.commit_distance,
			tr.commit_confidence),
			UVM_HIGH
		)

	endtask

endclass


class base_predictor_monitor extends uvm_monitor;

`uvm_component_utils(base_predictor_monitor)

virtual base_predictor_if vif;
uvm_analysis_port #(base_predictor_item) monitor_port;

function new(string name = "base_predictor_monitor", uvm_component parent);
	super.new(name,parent);
	monitor_port = new("monitor_port",this);
endfunction

virtual function void build_phase(uvm_phase phase);
	super.build_phase(phase);

	if (!uvm_config_db#(virtual base_predictor_if)::get(this,"","vif",vif)) begin
		`uvm_fatal("NOVIF", "Virtual interface not found for base_predictor_monitor")
	end
endfunction

task run_phase(uvm_phase phase);
	base_predictor_item tr;

	forever begin
		// @(vif.mon_cb);
		// @(vif.mon_cb);
		@(posedge vif.clk);
		#1;

		tr = base_predictor_item::type_id::create("tr", this);

		// tr.fetch_en          = vif.mon_cb.fetch_en_i;
		// tr.fetch_idx         = vif.mon_cb.fetch_idx_i;

		// tr.update_en         = vif.mon_cb.update_en_i;
		// tr.commit_index      = vif.mon_cb.commit_index_i;
		// tr.commit_distance   = vif.mon_cb.commit_distance_i;
		// tr.commit_confidence = vif.mon_cb.commit_confidence_i;

		// tr.observed_dist     = vif.mon_cb.base_dist_o;
		// tr.observed_conf     = vif.mon_cb.base_conf_o;

		tr.fetch_en          = vif.fetch_en_i;
		tr.fetch_idx         = vif.fetch_idx_i;

		tr.update_en         = vif.update_en_i;
		tr.commit_index      = vif.commit_index_i;
		tr.commit_distance   = vif.commit_distance_i;
		tr.commit_confidence = vif.commit_confidence_i;

		tr.observed_dist     = vif.base_dist_o;
		tr.observed_conf     = vif.base_conf_o;

		monitor_port.write(tr);

		`uvm_info("MON",
			$sformatf("fetch_en=%0b fetch_idx=%0d update_en=%0b commit_index=%0d commit_distance=0x%0h commit_confidence=0x%0h observed_dist=0x%0h observed_conf=0x%0h",
			tr.fetch_en,
			tr.fetch_idx,
			tr.update_en,
			tr.commit_index,
			tr.commit_distance,
			tr.commit_confidence,
			tr.observed_dist,
			tr.observed_conf),
			UVM_HIGH
		)
	end
endtask

endclass


// coverage check
class base_predictor_coverage extends uvm_subscriber #(base_predictor_item);

	`uvm_component_utils(base_predictor_coverage)

	base_predictor_item tr;

	// variables to display coverage on eda-playground
	int fetch_off_count;
	int fetch_on_count;

	int update_off_count;
	int update_on_count;

	int idle_count;
	int read_only_count;
	int write_only_count;
	int read_write_count;

	int fetch_low_addr_count;
	int fetch_mid_addr_count;
	int fetch_high_addr_count;
	int fetch_first_addr_count;
	int fetch_second_addr_count;
	int fetch_second_last_count;
	int fetch_last_addr_count;

	int commit_low_addr_count;
	int commit_mid_addr_count;
	int commit_high_addr_count;
	int commit_first_addr_count;
	int commit_second_addr_count;
	int commit_second_last_count;
	int commit_last_addr_count;

	int dist_zero_count;
	int dist_low_count;
	int dist_mid_count;
	int dist_high_count;
	int dist_max_count;

	int conf_count[8];

	int same_addr_count;
	int diff_addr_count;

	//// variables for disabled-port input toggle coverage
	bit prev_toggle_valid;

	bit [9:0] prev_fetch_idx;
	bit [9:0] prev_commit_index;
	bit [6:0] prev_commit_distance;
	bit [2:0] prev_commit_confidence;

	int fetch_disabled_idx_toggle_count;
	int update_disabled_index_toggle_count;
	int update_disabled_distance_toggle_count;
	int update_disabled_confidence_toggle_count;
	int update_disabled_any_input_toggle_count;

	/// variables to check ACCESS-TYPE Transition coverage like :-
	// write -> read
	// write -> write
	// read -> read
	// read -> write
	// read/write -> read
	// read/write -> write
	// write immediately followed by read
	// read immediately followed by write
	// read/write immediately followed by read

	bit [1:0] prev_access_type;
	bit       prev_access_valid;

	int idle_to_read_count;
	int idle_to_write_count;
	int idle_to_read_write_count;

	int write_to_read_count;
	int write_to_write_count;
	int write_to_read_write_count;

	int read_to_read_count;
	int read_to_write_count;
	int read_to_read_write_count;

	int read_write_to_read_count;
	int read_write_to_write_count;
	int read_write_to_read_write_count;

	covergroup base_predictor_cg;

		option.per_instance = 1;

		// Fetch and Update Enable combinations
		fetch_en_cp : coverpoint tr.fetch_en {
			bins fetch_off = {0};
			bins fetch_on  = {1};
		}

		update_en_cp : coverpoint tr.update_en {
			bins update_off = {0};
			bins update_on  = {1};
		}

		access_type_cp : coverpoint {tr.fetch_en, tr.update_en} {
			bins idle       = {2'b00};
			bins read_only  = {2'b10};
			bins write_only = {2'b01};
			bins read_write = {2'b11};
		}

		// Address coverage
		fetch_idx_cp : coverpoint tr.fetch_idx iff (tr.fetch_en) {
			bins low_addr      		= {[0:15]};
			bins mid_addr      		= {[16:1007]};
			bins high_addr     		= {[1008:1023]};
			bins first_addr    		= {0};
			bins second_addr   		= {1};
			bins second_last   		= {1022};
			bins last_addr     		= {1023};
			// bins outside_range_addr 	= {[1024:1030]};
		}

		commit_idx_cp : coverpoint tr.commit_index iff (tr.update_en) {
			bins low_addr      = {[0:15]};
			bins mid_addr      = {[16:1007]};
			bins high_addr     = {[1008:1023]};
			bins first_addr    = {0};
			bins second_addr   = {1};
			bins second_last   = {1022};
			bins last_addr     = {1023};
		}

		// Data values coverage
		commit_dist_cp : coverpoint tr.commit_distance iff (tr.update_en) {
			bins zero      = {0};
			bins low       = {[1:31]};
			bins mid       = {[32:95]};
			bins high      = {[96:126]};
			bins max_value = {127};
		}

		commit_conf_cp : coverpoint tr.commit_confidence iff (tr.update_en) {
			bins conf_values[] = {[0:7]};
		}

		// Same-cycle read/write address relationship
		same_addr_cp : coverpoint (tr.fetch_idx == tr.commit_index)
			iff (tr.fetch_en && tr.update_en) {
			bins same_addr = {1};
			bins diff_addr = {0};
		}


		// Cross coverage
		read_write_addr_cross : cross access_type_cp, same_addr_cp {
			ignore_bins not_read_write =
			binsof(access_type_cp.idle) ||
			binsof(access_type_cp.read_only) ||
			binsof(access_type_cp.write_only);
		}

		write_data_cross : cross commit_dist_cp, commit_conf_cp;

	endgroup

	function new(string name = "base_predictor_coverage", uvm_component parent);
		super.new(name, parent);
		base_predictor_cg = new();
	endfunction

	virtual function void write(base_predictor_item t);
		
		bit [1:0] curr_access_type;	

		tr = t;
		base_predictor_cg.sample();

		curr_access_type = {tr.fetch_en, tr.update_en};

		if (prev_access_valid) begin

		case ({prev_access_type, curr_access_type})

			// idle -> something active
			{2'b00, 2'b10}: idle_to_read_count++;
			{2'b00, 2'b01}: idle_to_write_count++;
			{2'b00, 2'b11}: idle_to_read_write_count++;

			// write-only -> next operation
			{2'b01, 2'b10}: write_to_read_count++;
			{2'b01, 2'b01}: write_to_write_count++;
			{2'b01, 2'b11}: write_to_read_write_count++;

			// read-only -> next operation
			{2'b10, 2'b10}: read_to_read_count++;
			{2'b10, 2'b01}: read_to_write_count++;
			{2'b10, 2'b11}: read_to_read_write_count++;

			// read/write -> next operation
			{2'b11, 2'b10}: read_write_to_read_count++;
			{2'b11, 2'b01}: read_write_to_write_count++;
			{2'b11, 2'b11}: read_write_to_read_write_count++;

		endcase

		end

		prev_access_type  = curr_access_type;
		prev_access_valid = 1'b1;

		/// Updating the write function to display the values on eda playground terminal
		// enable bins
		if (tr.fetch_en)
			fetch_on_count++;
		else
			fetch_off_count++;

		if (tr.update_en)
			update_on_count++;
		else
			update_off_count++;
	
		// access type bins
		case ({tr.fetch_en, tr.update_en})
			2'b00: idle_count++;
			2'b10: read_only_count++;
			2'b01: write_only_count++;
			2'b11: read_write_count++;
		endcase

		// fetch address bins
		if (tr.fetch_en) begin
			if (tr.fetch_idx == 0)
			  fetch_first_addr_count++;
			if (tr.fetch_idx == 1)
			  fetch_second_addr_count++;
			if (tr.fetch_idx == 1022)
			  fetch_second_last_count++;
			if (tr.fetch_idx == 1023)
			  fetch_last_addr_count++;
		
			if (tr.fetch_idx <= 15)
			  fetch_low_addr_count++;
			else if (tr.fetch_idx >= 1008)
			  fetch_high_addr_count++;
			else
			  fetch_mid_addr_count++;
		end

		// commit address bins
		if (tr.update_en) begin
			if (tr.commit_index == 0)
			  commit_first_addr_count++;
			if (tr.commit_index == 1)
			  commit_second_addr_count++;
			if (tr.commit_index == 1022)
			  commit_second_last_count++;
			if (tr.commit_index == 1023)
			  commit_last_addr_count++;
		
			if (tr.commit_index <= 15)
			  commit_low_addr_count++;
			else if (tr.commit_index >= 1008)
			  commit_high_addr_count++;
			else
			  commit_mid_addr_count++;
		end

		// write data bins
		if (tr.update_en) begin
			if (tr.commit_distance == 0)
			  dist_zero_count++;
			else if (tr.commit_distance <= 31)
			  dist_low_count++;
			else if (tr.commit_distance <= 95)
			  dist_mid_count++;
			else if (tr.commit_distance <= 126)
			  dist_high_count++;
			else
			  dist_max_count++;
		
			conf_count[tr.commit_confidence]++;
		end

		// same-cycle read/write address relation
		if (tr.fetch_en && tr.update_en) begin
			if (tr.fetch_idx == tr.commit_index)
			  same_addr_count++;
			else
			  diff_addr_count++;
		end


		// Disabled-port input toggle coverage

		if (prev_toggle_valid) begin

			// KEEP Read port disabled -- CHANGE fetch index
			// Output should hold the value
			if (!tr.fetch_en && (tr.fetch_idx != prev_fetch_idx)) begin
				fetch_disabled_idx_toggle_count++;
			end
		
			// KEEP Write port disabled  --- CHANGE write-side inputs.
			// Memory should not update.

			if (!tr.update_en) begin
		
			if (tr.commit_index != prev_commit_index) begin
				update_disabled_index_toggle_count++;
			end
		
			if (tr.commit_distance != prev_commit_distance) begin
				update_disabled_distance_toggle_count++;
			end
		
			if (tr.commit_confidence != prev_commit_confidence) begin
				update_disabled_confidence_toggle_count++;
			end
		
			if ((tr.commit_index != prev_commit_index) ||
				(tr.commit_distance != prev_commit_distance) ||
				(tr.commit_confidence != prev_commit_confidence)) begin
				update_disabled_any_input_toggle_count++;
			end
		
			end
		
		end
		
		prev_fetch_idx          = tr.fetch_idx;
		prev_commit_index       = tr.commit_index;
		prev_commit_distance    = tr.commit_distance;
		prev_commit_confidence  = tr.commit_confidence;
		prev_toggle_valid       = 1'b1;

		/// end of toggling INPUTS when ENABLE is disabled for Read and Write ports

	endfunction

	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);

		$display("\n\n==================================================");
		$display("BASE PREDICTOR FUNCTIONAL COVERAGE");
		$display("==================================================");
		$display("Overall coverage       : %0.2f%%", base_predictor_cg.get_coverage());
		$display("Fetch enable coverage  : %0.2f%%", base_predictor_cg.fetch_en_cp.get_coverage());
		$display("Update enable coverage : %0.2f%%", base_predictor_cg.update_en_cp.get_coverage());
		$display("Access type coverage   : %0.2f%%", base_predictor_cg.access_type_cp.get_coverage());
		$display("Fetch index coverage   : %0.2f%%", base_predictor_cg.fetch_idx_cp.get_coverage());
		$display("Commit index coverage  : %0.2f%%", base_predictor_cg.commit_idx_cp.get_coverage());
		$display("Distance coverage      : %0.2f%%", base_predictor_cg.commit_dist_cp.get_coverage());
		$display("Confidence coverage    : %0.2f%%", base_predictor_cg.commit_conf_cp.get_coverage());
		$display("Same addr coverage     : %0.2f%%", base_predictor_cg.same_addr_cp.get_coverage());

		$display("\n-------------------- BIN HIT COUNTS --------------------");

		$display("Fetch enable bins:");
		$display("  fetch_off         : %0d", fetch_off_count);
		$display("  fetch_on          : %0d", fetch_on_count);

		$display("Update enable bins:");
		$display("  update_off        : %0d", update_off_count);
		$display("  update_on         : %0d", update_on_count);

		$display("Access type bins:");
		$display("  idle              : %0d", idle_count);
		$display("  read_only         : %0d", read_only_count);
		$display("  write_only        : %0d", write_only_count);
		$display("  read_write        : %0d", read_write_count);

		$display("Fetch index bins:");
		$display("  low_addr [0:15]   : %0d", fetch_low_addr_count);
		$display("  mid_addr          : %0d", fetch_mid_addr_count);
		$display("  high_addr         : %0d", fetch_high_addr_count);
		$display("  first_addr 0      : %0d", fetch_first_addr_count);
		$display("  second_addr 1     : %0d", fetch_second_addr_count);
		$display("  second_last 1022  : %0d", fetch_second_last_count);
		$display("  last_addr 1023    : %0d", fetch_last_addr_count);

		$display("Commit index bins:");
		$display("  low_addr [0:15]   : %0d", commit_low_addr_count);
		$display("  mid_addr          : %0d", commit_mid_addr_count);
		$display("  high_addr         : %0d", commit_high_addr_count);
		$display("  first_addr 0      : %0d", commit_first_addr_count);
		$display("  second_addr 1     : %0d", commit_second_addr_count);
		$display("  second_last 1022  : %0d", commit_second_last_count);
		$display("  last_addr 1023    : %0d", commit_last_addr_count);

		$display("Distance bins:");
		$display("  zero              : %0d", dist_zero_count);
		$display("  low [1:31]        : %0d", dist_low_count);
		$display("  mid [32:95]       : %0d", dist_mid_count);
		$display("  high [96:126]     : %0d", dist_high_count);
		$display("  max 127           : %0d", dist_max_count);

		$display("Confidence bins:");
		
		foreach (conf_count[i]) begin
			$display("  conf[%0d]           : %0d", i, conf_count[i]);
		end

		$display("Same-cycle read/write bins:");
		$display("  same_addr         : %0d", same_addr_count);
		$display("  diff_addr         : %0d", diff_addr_count);

		$display("==================================================\n\n");


		//  access coverage transitions
		$display("\nAccess transition bins:");
		$display("  idle        -> read        : %0d", idle_to_read_count);
		$display("  idle        -> write       : %0d", idle_to_write_count);
		$display("  idle        -> read/write  : %0d", idle_to_read_write_count);

		$display("  write       -> read        : %0d", write_to_read_count);
		$display("  write       -> write       : %0d", write_to_write_count);
		$display("  write       -> read/write  : %0d", write_to_read_write_count);

		$display("  read        -> read        : %0d", read_to_read_count);
		$display("  read        -> write       : %0d", read_to_write_count);
		$display("  read        -> read/write  : %0d", read_to_read_write_count);

		$display("  read/write  -> read        : %0d", read_write_to_read_count);
		$display("  read/write  -> write       : %0d", read_write_to_write_count);
		$display("  read/write  -> read/write  : %0d", read_write_to_read_write_count);

		/// toggle inputs when ports are disabled
		$display("\nDisabled-port input toggle bins:");
		$display("  fetch_en=0, fetch_idx toggled              : %0d", fetch_disabled_idx_toggle_count);
		$display("  update_en=0, commit_index toggled          : %0d", update_disabled_index_toggle_count);
		$display("  update_en=0, commit_distance toggled       : %0d", update_disabled_distance_toggle_count);
		$display("  update_en=0, commit_confidence toggled     : %0d", update_disabled_confidence_toggle_count);
		$display("  update_en=0, any write-side input toggled  : %0d", update_disabled_any_input_toggle_count);

endfunction

endclass

class base_predictor_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(base_predictor_scoreboard)

	uvm_analysis_imp #(base_predictor_item, base_predictor_scoreboard) analysis_export;

	localparam int TABLE_DEPTH = 1024;

	// memory in scoreboard for holding the value.
	bit [6:0] ref_dist [TABLE_DEPTH];
	bit [2:0] ref_conf [TABLE_DEPTH];
	bit ref_valid [TABLE_DEPTH];

	int total_read_checks;
	int passed_read_checks;
	int failed_read_checks;
	int skipped_uninit_reads;
	int total_writes;

	//to check RDW - read/write in same cycle variables
	int rdw_same_addr_total_count;
	int rdw_same_addr_old_data_count;
	int rdw_same_addr_new_data_count;
	int rdw_same_addr_other_data_count;
		
	// variables for duplicated writes
	int duplicate_write_count;
	int read_after_duplicate_write_count;

	int write_count_per_addr[1024];
	bit duplicate_addr_seen[1024];


	function new(string name = "base_predictor_scoreboard", uvm_component parent);
		super.new(name, parent);
		analysis_export = new("analysis_export", this);
	endfunction

	function void display_scoreboard_memory();

		`uvm_info("SCB_MEM_DUMP","Displaying valid scoreboard memory entries",UVM_LOW)

		for (int i = 0; i < TABLE_DEPTH; i++) begin
			if (ref_valid[i]) begin
				`uvm_info("SB_MEM_DUMP",
				$sformatf("idx=%0d dist=0x%0h conf=0x%0h valid=%0b",
					i,
					ref_dist[i],
					ref_conf[i],
					ref_valid[i]),
				UVM_LOW)
			end
		end
	endfunction

	function void write(base_predictor_item tr);

		bit [6:0] expected_dist;
		bit [2:0] expected_conf;

		// Same-cycle read/write same-address observed behavior, this must happen BEFORE updating reference memory 
		// - because ref_dist/ref_conf still hold OLD data.
		
		if (tr.fetch_en && tr.update_en && (tr.fetch_idx == tr.commit_index)) begin

			rdw_same_addr_total_count++;
		
			if (ref_valid[tr.fetch_idx]) begin
		
			if ((tr.observed_dist == ref_dist[tr.fetch_idx]) &&
				(tr.observed_conf == ref_conf[tr.fetch_idx])) begin
		
				rdw_same_addr_old_data_count++;
		
				`uvm_info("RDW_SAME_ADDR_POLICY",
				$sformatf("RDW SAME ADDR idx=%0d returned OLD data observed={dist=0x%0h conf=0x%0h} old={dist=0x%0h conf=0x%0h} new_write={dist=0x%0h conf=0x%0h}",
					tr.fetch_idx,
					tr.observed_dist,
					tr.observed_conf,
					ref_dist[tr.fetch_idx],
					ref_conf[tr.fetch_idx],
					tr.commit_distance,
					tr.commit_confidence),
				UVM_NONE)
		
			end
			else if ((tr.observed_dist == tr.commit_distance) &&
					(tr.observed_conf == tr.commit_confidence)) begin
		
				rdw_same_addr_new_data_count++;
		
				`uvm_info("RDW_SAME_ADDR_POLICY",
				$sformatf("RDW SAME ADDR idx=%0d returned NEW data observed={dist=0x%0h conf=0x%0h} old={dist=0x%0h conf=0x%0h} new_write={dist=0x%0h conf=0x%0h}",
					tr.fetch_idx,
					tr.observed_dist,
					tr.observed_conf,
					ref_dist[tr.fetch_idx],
					ref_conf[tr.fetch_idx],
					tr.commit_distance,
					tr.commit_confidence),
				UVM_NONE)
		
			end
			else begin
		
				rdw_same_addr_other_data_count++;
		
				`uvm_warning("RDW_SAME_ADDR_POLICY",
				$sformatf("RDW SAME ADDR idx=%0d returned OTHER data observed={dist=0x%0h conf=0x%0h} old={dist=0x%0h conf=0x%0h} new_write={dist=0x%0h conf=0x%0h}",
					tr.fetch_idx,
					tr.observed_dist,
					tr.observed_conf,
					ref_dist[tr.fetch_idx],
					ref_conf[tr.fetch_idx],
					tr.commit_distance,
					tr.commit_confidence))
		
			end
		
			end
			else begin
			`uvm_info("RDW_SAME_ADDR_POLICY",
				$sformatf("RDW SAME ADDR idx=%0d occurred before address had valid scoreboard data",
				tr.fetch_idx),
				UVM_MEDIUM)
			end
		
		end

		// This one comment only for the condition of write and read in same cycle from same location.
		if (tr.fetch_en && tr.update_en && (tr.fetch_idx == tr.commit_index)) begin
			`uvm_info("RDW_SAME_ADDR_OBSERVED",
			  $sformatf({
				"Same-cycle READ/WRITE to same idx=%0d\n",
				"  Write data     : {Dist: 0x%0h, Conf: 0x%0h}\n",
				"  Observed read  : {Dist: 0x%0h, Conf: 0x%0h}"
			  },
				tr.fetch_idx,
				tr.commit_distance,
				tr.commit_confidence,
				tr.observed_dist,
				tr.observed_conf
			  ),
			  UVM_NONE)
		  end


		// Check read only when fetch_en is active.
		if (tr.fetch_en) begin

			if (ref_valid[tr.fetch_idx]) begin
				total_read_checks++;

				expected_dist = ref_dist[tr.fetch_idx];
				expected_conf = ref_conf[tr.fetch_idx];

				/// duplicates read block
				if (duplicate_addr_seen[tr.fetch_idx]) begin
					read_after_duplicate_write_count++;
				  end
				///

				if ((tr.observed_dist !== expected_dist) ||	(tr.observed_conf !== expected_conf)) begin

					failed_read_checks++;

					`uvm_error("BASE_PREDICTOR_MISMATCH",
						$sformatf("FAIL check=%0d idx=%0d expected={dist=0x%0h conf=0x%0h} observed={dist=0x%0h conf=0x%0h}",
						total_read_checks,
						tr.fetch_idx,
						expected_dist,
						expected_conf,
						tr.observed_dist,
						tr.observed_conf))

				end
				else begin

					passed_read_checks++;

					// to reduce the lines consumend on EDA Playground terminal
					// `uvm_info("BASE_PREDICTOR_MATCH",
					// $sformatf("PASS check=%0d idx=%0d", total_read_checks, tr.fetch_idx),
					// UVM_HIGH)

					`uvm_info("BASE_PREDICTOR_MATCH",
						$sformatf("PASS check=%0d idx=%0d expected={dist=0x%0h conf=0x%0h} observed={dist=0x%0h conf=0x%0h}",
						total_read_checks,
						tr.fetch_idx,
						expected_dist,
						expected_conf,
						tr.observed_dist,
						tr.observed_conf),
						UVM_NONE)
					end

			end
			else begin
				skipped_uninit_reads++;
			end

		end

		// Update reference memory after read check.
		if (tr.update_en) begin
			total_writes++;

			/// ====== START OF BLOCK for Duplicate write  ======  ///
			/// this block is added to tell if an address is written more than once, 
			/// then a later read must return the latest written value.
			if (write_count_per_addr[tr.commit_index] > 0) begin
				duplicate_write_count++;
				duplicate_addr_seen[tr.commit_index] = 1'b1;
			
				`uvm_info("DUPLICATE_WRITE",
				  $sformatf("Duplicate write detected idx=%0d old_write_count=%0d new_data={dist=0x%0h conf=0x%0h}",
					tr.commit_index,
					write_count_per_addr[tr.commit_index],
					tr.commit_distance,
					tr.commit_confidence),
				  UVM_HIGH)
			  end
			
			write_count_per_addr[tr.commit_index]++;

			/// ====== END OF BLOCK that tells if an address is written more than once ===== ////

			ref_dist[tr.commit_index]  = tr.commit_distance;
			ref_conf[tr.commit_index]  = tr.commit_confidence;
			ref_valid[tr.commit_index] = 1'b1;
		end

	endfunction

	virtual function void report_phase(uvm_phase phase);
		
		super.report_phase(phase);

		`uvm_info("BASE_PREDICTOR_SCOREBOARD_SUMMARY",
		$sformatf("\n----------------------------------------\nBASE PREDICTOR SCOREBOARD SUMMARY\n----------------------------------------\nTotal writes              : %0d\nTotal read checks         : %0d\nPassed read checks        : %0d\nFailed read checks        : %0d\nSkipped uninitialized reads: %0d\n----------------------------------------",
			total_writes,
			total_read_checks,
			passed_read_checks,
			failed_read_checks,
			skipped_uninit_reads),
		UVM_NONE)

		`uvm_info("DUPLICATE_WRITE_SUMMARY",
		$sformatf({
			"\n-----------------------------------\n",
			"Duplicate Write summary \n",
			"----------------------------------------\n",
			"Duplicate write events        : %0d\n",
			"Read after duplicate write    : %0d\n",
			"----------------------------------------"
			},
			duplicate_write_count,
			read_after_duplicate_write_count),
		UVM_NONE)


		// `uvm_info("RDW_SAME_ADDR_SUMMARY",
		// $sformatf({
		// 	"RDW SAME-ADDRESS - read/write\n",
		// 	"----------------------------------------\n",
		// 	"Total same-address RDW events : %0d\n",
		// 	"Returned OLD data             : %0d\n",
		// 	"Returned NEW data             : %0d\n",
		// 	"Returned OTHER data           : %0d\n",
		// 	"----------------------------------------"
		// },
		// 	rdw_same_addr_total_count,
		// 	rdw_same_addr_old_data_count,
		// 	rdw_same_addr_new_data_count,
		// 	rdw_same_addr_other_data_count),
		// UVM_NONE)

		// display_scoreboard_memory();

		if (failed_read_checks == 0) begin
		`uvm_info("BASE_PREDICTOR_RESULT", "TEST RESULT: PASS", UVM_NONE)
		end
		else begin
		`uvm_error("BASE_PREDICTOR_RESULT",
			$sformatf("TEST RESULT: FAIL with %0d failed read checks", failed_read_checks))
		end

  endfunction

endclass



class base_predictor_agent extends uvm_agent;

  `uvm_component_utils(base_predictor_agent)

  base_predictor_sequencer sequencer;
  base_predictor_driver driver;
  base_predictor_monitor monitor;

  function new(string name = "base_predictor_agent", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    monitor = base_predictor_monitor::type_id::create("monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = base_predictor_sequencer::type_id::create("sequencer", this);
      driver = base_predictor_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass

class base_predictor_env extends uvm_env;

	`uvm_component_utils(base_predictor_env)

	base_predictor_agent      agent;
	base_predictor_scoreboard scoreboard;
	base_predictor_coverage coverage;

	function new(string name = "base_predictor_env", uvm_component parent);
	super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
	super.build_phase(phase);

	agent = base_predictor_agent::type_id::create("agent", this);
	scoreboard = base_predictor_scoreboard::type_id::create("scoreboard", this);
	coverage = base_predictor_coverage::type_id::create("coverage", this);
	endfunction

	function void connect_phase(uvm_phase phase);
	super.connect_phase(phase);
	agent.monitor.monitor_port.connect(scoreboard.analysis_export);
	agent.monitor.monitor_port.connect(coverage.analysis_export);
	endfunction

endclass


class base_predictor_base_test extends uvm_test;

	`uvm_component_utils(base_predictor_base_test)

	base_predictor_env env;

	function new(string name = "base_predictor_base_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		env = base_predictor_env::type_id::create("env", this);
	endfunction

	task run_phase(uvm_phase phase);

		base_predictor_smoke_seq smoke_seq;
		base_predictor_random_seq random_seq;
		base_predictor_random_write_and_same_read_seq  random_wr_same_rd_seq;
		base_predictor_hazard hazard_seq;
		base_predictor_read_stability_seq  stable_read_seq;
		base_predictor_unique_value_at_index_pattern_seq   unique_value_index_seq;
		base_predictor_access_transition_seq access_transition_seq;
		base_predictor_duplicate_write_seq duplicate_write_seq;
		base_predictor_disabled_input_toggle_seq disabled_toggle_seq;
		base_predictor_confidence_INCR_DECR_ONLY_seq  INCR_DECR_seq;
		base_predictor_confidence_saturation_seq confidence_saturation_seq;
		base_predictor_disabled_write_protection_seq disabled_write_seq;

		phase.raise_objection(this);

		// access_transition_seq = base_predictor_access_transition_seq::type_id::create("access_transition_seq");
		// access_transition_seq.start(env.agent.sequencer);

		// smoke_seq = base_predictor_smoke_seq::type_id::create("smoke_seq");
		// smoke_seq.start(env.agent.sequencer);

		// random_seq = base_predictor_random_seq::type_id::create("random_seq");
		// random_seq.start(env.agent.sequencer);
		
		// random_wr_same_rd_seq = base_predictor_random_write_and_same_read_seq::type_id::create("random_wr_same_rd_seq");
		// random_wr_same_rd_seq.start(env.agent.sequencer);
		
		// hazard_seq = base_predictor_hazard::type_id::create("random_wr_same_rd_seq");
		// hazard_seq.start(env.agent.sequencer);
		
		// unique_value_index_seq = base_predictor_unique_value_at_index_pattern_seq::type_id::create("unique_value_index_seq");
		// unique_value_index_seq.start(env.agent.sequencer);

		// duplicate_write_seq = base_predictor_duplicate_write_seq::type_id::create("duplicate_write_seq");
		// duplicate_write_seq.start(env.agent.sequencer);

		// disabled_toggle_seq =  base_predictor_disabled_input_toggle_seq::type_id::create("disabled_toggle_seq");
		// disabled_toggle_seq.start(env.agent.sequencer);

		// INCR_DECR_seq = base_predictor_confidence_INCR_DECR_ONLY_seq::type_id::create("INCR_DECR_seq");
		// INCR_DECR_seq.start(env.agent.sequencer);

		// confidence_saturation_seq = base_predictor_confidence_saturation_seq::type_id::create("confidence_saturation_seq");
		// confidence_saturation_seq.start(env.agent.sequencer);

		disabled_write_seq = base_predictor_disabled_write_protection_seq::type_id::create("disabled_write_seq");
		disabled_write_seq.start(env.agent.sequencer);

		phase.drop_objection(this);

	endtask

endclass


module tb_top;		// testbench for base_predictor_table

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int INDEX_WIDTH      = 10;
  localparam int DISTANCE_WIDTH   = 7;
  localparam int CONFIDENCE_WIDTH = 3;

  logic clk;

  initial clk = 1'b0;

  always #5 clk = ~clk;

  base_predictor_if #(
    .INDEX_WIDTH(INDEX_WIDTH),
    .DISTANCE_WIDTH(DISTANCE_WIDTH),
    .CONFIDENCE_WIDTH(CONFIDENCE_WIDTH)
  ) predictor_if (
    .clk(clk)
  );

  // Time-0 initialization to avoid X on controls

  initial begin
    predictor_if.fetch_en_i = 1'b0;
    predictor_if.fetch_idx_i = '0;
    predictor_if.update_en_i = 1'b0;
    predictor_if.commit_index_i = '0;
    predictor_if.commit_distance_i = '0;
    predictor_if.commit_confidence_i = '0;
  end

  // DUT instance
  base_predictor_sram #(
    .INDEX_WIDTH(INDEX_WIDTH),
    .DISTANCE_WIDTH(DISTANCE_WIDTH),
    .CONFIDENCE_WIDTH(CONFIDENCE_WIDTH)
  ) dut (
    .clk(clk),

    .fetch_en_i(predictor_if.fetch_en_i),
    .fetch_idx_i(predictor_if.fetch_idx_i),
    .base_dist_o(predictor_if.base_dist_o),
    .base_conf_o(predictor_if.base_conf_o),

    .update_en_i(predictor_if.update_en_i),
    .commit_index_i(predictor_if.commit_index_i),
    .commit_distance_i(predictor_if.commit_distance_i),
    .commit_confidence_i(predictor_if.commit_confidence_i)
  );


  initial begin
    uvm_config_db#(virtual base_predictor_if)::set(null,"*","vif",predictor_if);

    run_test("base_predictor_base_test");
  end

endmodule