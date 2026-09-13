import uvm_pkg::*;
`include "uvm_macros.svh"

interface tagged_predictor_if #(
	parameter int NUM_WAYS         = 4,
	parameter int INDEX_WIDTH      = 7,
	parameter int TAG_WIDTH        = 16,
	parameter int DISTANCE_WIDTH   = 7,
	parameter int CONFIDENCE_WIDTH = 4,
	parameter int USEFUL_WIDTH     = 2
)(
  	input logic clk
);

	// Read port signals
	logic fetch_en_i;
	logic [INDEX_WIDTH-1:0] fetch_idx_i;

	logic [TAG_WIDTH-1:0]        read_tags_o   [NUM_WAYS];
	logic [DISTANCE_WIDTH-1:0]   read_dists_o  [NUM_WAYS];
	logic [CONFIDENCE_WIDTH-1:0] read_confs_o  [NUM_WAYS];
	logic [USEFUL_WIDTH-1:0]     read_useful_o [NUM_WAYS];

	// Write/update port signals
	logic tagged_update_en_i;
	logic [NUM_WAYS-1:0] commit_way_id_i;
	logic [INDEX_WIDTH-1:0] commit_idx_i;

	logic [TAG_WIDTH-1:0]        wdata_tag_i;
	logic [DISTANCE_WIDTH-1:0]   wdata_dist_i;
	logic [CONFIDENCE_WIDTH-1:0] wdata_conf_i;
	logic [USEFUL_WIDTH-1:0]     wdata_useful_i;


	// Driver clocking block:

	clocking drv_cb @(negedge clk);
		output fetch_en_i;
		output fetch_idx_i;

		output tagged_update_en_i;
		output commit_way_id_i;
		output commit_idx_i;

		output wdata_tag_i;
		output wdata_dist_i;
		output wdata_conf_i;
		output wdata_useful_i;
	endclocking


	// Monitor clocking block:
	
	clocking mon_cb @(posedge clk);
		input fetch_en_i;
		input fetch_idx_i;

		input tagged_update_en_i;
		input commit_way_id_i;
		input commit_idx_i;

		input wdata_tag_i;
		input wdata_dist_i;
		input wdata_conf_i;
		input wdata_useful_i;
	endclocking


	// Basic known-value checks
	property fetch_controls_known_when_enabled;
		@(posedge clk)
		fetch_en_i |-> !$isunknown(fetch_idx_i);
	endproperty

	assert property (fetch_controls_known_when_enabled)
		else $error("fetch_idx_i is X/Z when fetch_en_i is asserted");


	property update_controls_known_when_enabled;
		@(posedge clk)
		tagged_update_en_i |->
			!$isunknown({
			commit_way_id_i,
			commit_idx_i,
			wdata_tag_i,
			wdata_dist_i,
			wdata_conf_i,
			wdata_useful_i
			});
	endproperty

	assert property (update_controls_known_when_enabled)
		else $error("Tagged update controls/data contain X/Z when tagged_update_en_i is asserted");


	// 4'b1111 means DECAY.
	// Normal updates should be one-hot.
	property normal_update_mask_is_onehot_or_decay;
		@(posedge clk)
		tagged_update_en_i |->
			((commit_way_id_i == '1) || $onehot(commit_way_id_i));
	endproperty

	assert property (normal_update_mask_is_onehot_or_decay)
		else $error("commit_way_id_i must be one-hot for normal update, or all-ones for decay");


	// Read output hold check when fetch remains disabled.
	// Expanded explicitly for 4 ways to avoid unpacked-array assertion issues.
	property read_outputs_hold_when_fetch_disabled;
		@(posedge clk)
		!fetch_en_i &&
		!$past(fetch_en_i) &&
		!$isunknown({
			read_tags_o[0], read_dists_o[0], read_confs_o[0], read_useful_o[0],
			read_tags_o[1], read_dists_o[1], read_confs_o[1], read_useful_o[1],
			read_tags_o[2], read_dists_o[2], read_confs_o[2], read_useful_o[2],
			read_tags_o[3], read_dists_o[3], read_confs_o[3], read_useful_o[3]
		})
		|-> $stable({
			read_tags_o[0], read_dists_o[0], read_confs_o[0], read_useful_o[0],
			read_tags_o[1], read_dists_o[1], read_confs_o[1], read_useful_o[1],
			read_tags_o[2], read_dists_o[2], read_confs_o[2], read_useful_o[2],
			read_tags_o[3], read_dists_o[3], read_confs_o[3], read_useful_o[3]
		});
	endproperty

	assert property (read_outputs_hold_when_fetch_disabled)
		else $error("Tagged predictor read outputs changed while fetch_en_i was low");


endinterface


class tagged_predictor_item extends uvm_sequence_item;

	localparam int NUM_WAYS         = 4;
	localparam int INDEX_WIDTH      = 7;
	localparam int TAG_WIDTH        = 16;
	localparam int DISTANCE_WIDTH   = 7;
	localparam int CONFIDENCE_WIDTH = 4;
	localparam int USEFUL_WIDTH     = 2;

	typedef enum int {
		TAGGED_IDLE,
		TAGGED_READ,
		TAGGED_WRITE,
		TAGGED_READ_WRITE,
		TAGGED_DECAY,
		TAGGED_REWARD,
		TAGGED_PENALIZE
	} tagged_access_e;

	rand tagged_access_e access_type;

	// Read controls
	rand bit fetch_en;
	rand bit [INDEX_WIDTH-1:0] fetch_idx;

	// Write controls
	rand bit tagged_update_en;
	rand bit [NUM_WAYS-1:0] commit_way_id;
	rand bit [INDEX_WIDTH-1:0] commit_idx;

	rand bit [TAG_WIDTH-1:0]        wdata_tag;
	rand bit [DISTANCE_WIDTH-1:0]   wdata_dist;
	rand bit [CONFIDENCE_WIDTH-1:0] wdata_conf;
	rand bit [USEFUL_WIDTH-1:0]     wdata_useful;

	// Observed read outputs from DUT, all ways
	bit [TAG_WIDTH-1:0]        observed_tags   [NUM_WAYS];
	bit [DISTANCE_WIDTH-1:0]   observed_dists  [NUM_WAYS];
	bit [CONFIDENCE_WIDTH-1:0] observed_confs  [NUM_WAYS];
	bit [USEFUL_WIDTH-1:0]     observed_useful [NUM_WAYS];

	// Useful for scoreboard/debug
	// bit expect_check;
	bit is_decay;
	bit is_same_index_rdw;

	constraint access_to_enable_c {
		access_type == TAGGED_IDLE -> {
		fetch_en == 0;
		tagged_update_en == 0;
		}

		access_type == TAGGED_READ -> {
		fetch_en == 1;
		tagged_update_en == 0;
		}

		access_type == TAGGED_WRITE -> {
		fetch_en == 0;
		tagged_update_en == 1;
		}

		access_type == TAGGED_READ_WRITE -> {
		fetch_en == 1;
		tagged_update_en == 1;
		}

		access_type == TAGGED_DECAY -> {
		fetch_en == 0;
		tagged_update_en == 1;
		commit_way_id == '1;
		}

		access_type == TAGGED_REWARD -> {
		tagged_update_en == 1;
		}

		access_type == TAGGED_PENALIZE -> {
		tagged_update_en == 1;
		}
	}

	constraint normal_write_way_mask_c {
		if (access_type inside {TAGGED_WRITE, TAGGED_READ_WRITE, TAGGED_REWARD, TAGGED_PENALIZE}) {
		commit_way_id inside {4'b0001, 4'b0010, 4'b0100, 4'b1000};
		}
	}

	constraint access_distribution_c {
		access_type dist {
		TAGGED_IDLE       := 10,
		TAGGED_READ       := 25,
		TAGGED_WRITE      := 25,
		TAGGED_READ_WRITE := 15,
		TAGGED_DECAY      := 10,
		TAGGED_REWARD     := 8,
		TAGGED_PENALIZE   := 7
		};
	}

	constraint same_index_rdw_c {
		if (access_type == TAGGED_READ_WRITE) {
		is_same_index_rdw dist {
			1 := 50,
			0 := 50
		};

		if (is_same_index_rdw) {
			fetch_idx == commit_idx;
		}
		}
	}

	`uvm_object_utils_begin(tagged_predictor_item)
		`uvm_field_enum(tagged_access_e, access_type, UVM_ALL_ON)

		`uvm_field_int(fetch_en, UVM_ALL_ON)
		`uvm_field_int(fetch_idx, UVM_ALL_ON)

		`uvm_field_int(tagged_update_en, UVM_ALL_ON)
		`uvm_field_int(commit_way_id, UVM_ALL_ON)
		`uvm_field_int(commit_idx, UVM_ALL_ON)

		`uvm_field_int(wdata_tag, UVM_ALL_ON)
		`uvm_field_int(wdata_dist, UVM_ALL_ON)
		`uvm_field_int(wdata_conf, UVM_ALL_ON)
		`uvm_field_int(wdata_useful, UVM_ALL_ON)

		// `uvm_field_int(expect_check, UVM_ALL_ON)
		`uvm_field_int(is_decay, UVM_ALL_ON)
		`uvm_field_int(is_same_index_rdw, UVM_ALL_ON)
	`uvm_object_utils_end

	function new(string name = "tagged_predictor_item");
		super.new(name);
	endfunction

	function void post_randomize();
		is_decay = (commit_way_id == '1);
	endfunction

endclass


class tagged_predictor_base_seq extends uvm_sequence #(tagged_predictor_item);

	`uvm_object_utils(tagged_predictor_base_seq)

	localparam int NUM_WAYS         = 4;
	localparam int INDEX_WIDTH      = 7;
	localparam int TAG_WIDTH        = 16;
	localparam int DISTANCE_WIDTH   = 7;
	localparam int CONFIDENCE_WIDTH = 4;
	localparam int USEFUL_WIDTH     = 2;

	function new(string name = "tagged_predictor_base_seq");
		super.new(name);
	endfunction

	// idle cycle - no write or reads to the table
	task idle_cycle();
		tagged_predictor_item tr;

		tr = tagged_predictor_item::type_id::create("tr");

		start_item(tr);

		tr.access_type       = tagged_predictor_item::TAGGED_IDLE;
		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = '0;

		tr.tagged_update_en  = 1'b0;
		tr.commit_way_id     = '0;
		tr.commit_idx        = '0;

		tr.wdata_tag         = '0;
		tr.wdata_dist        = '0;
		tr.wdata_conf        = '0;
		tr.wdata_useful      = '0;

		// tr.expect_check      = 1'b0;
		tr.is_decay          = 1'b0;
		tr.is_same_index_rdw = 1'b0;

		finish_item(tr);
	endtask

	// only reads from the table with read enable bit high
	task read_cycle(
		input bit [INDEX_WIDTH-1:0] fetch_idx,
		// input bit expect_check = 1'b1
	);
		tagged_predictor_item tr;

		tr = tagged_predictor_item::type_id::create("tr");

		start_item(tr);

		tr.access_type       = tagged_predictor_item::TAGGED_READ;
		tr.fetch_en          = 1'b1;
		tr.fetch_idx         = fetch_idx;

		tr.tagged_update_en  = 1'b0;
		tr.commit_way_id     = '0;
		tr.commit_idx        = '0;

		tr.wdata_tag         = '0;
		tr.wdata_dist        = '0;
		tr.wdata_conf        = '0;
		tr.wdata_useful      = '0;

		// tr.expect_check      = expect_check;
		tr.is_decay          = 1'b0;
		tr.is_same_index_rdw = 1'b0;

		finish_item(tr);
	endtask


	task write_cycle(
		input bit [INDEX_WIDTH-1:0] commit_idx,
		input bit [NUM_WAYS-1:0] commit_way_id,
		input bit [TAG_WIDTH-1:0] wdata_tag,
		input bit [DISTANCE_WIDTH-1:0] wdata_dist,
		input bit [CONFIDENCE_WIDTH-1:0] wdata_conf,
		input bit [USEFUL_WIDTH-1:0] wdata_useful
	);
		tagged_predictor_item tr;

		tr = tagged_predictor_item::type_id::create("tr");

		start_item(tr);

		tr.access_type       = tagged_predictor_item::TAGGED_WRITE;
		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = '0;

		tr.tagged_update_en  = 1'b1;
		tr.commit_way_id     = commit_way_id;
		tr.commit_idx        = commit_idx;

		tr.wdata_tag         = wdata_tag;
		tr.wdata_dist        = wdata_dist;
		tr.wdata_conf        = wdata_conf;
		tr.wdata_useful      = wdata_useful;

		// tr.expect_check      = 1'b0;
		tr.is_decay          = 1'b0;
		tr.is_same_index_rdw = 1'b0;

		finish_item(tr);
	endtask


	task read_write_cycle(
		input bit [INDEX_WIDTH-1:0] fetch_idx,
		input bit [INDEX_WIDTH-1:0] commit_idx,
		input bit [NUM_WAYS-1:0] commit_way_id,
		input bit [TAG_WIDTH-1:0] wdata_tag,
		input bit [DISTANCE_WIDTH-1:0] wdata_dist,
		input bit [CONFIDENCE_WIDTH-1:0] wdata_conf,
		input bit [USEFUL_WIDTH-1:0] wdata_useful,
		// input bit expect_check = 1'b1
	);
		tagged_predictor_item tr;

		tr = tagged_predictor_item::type_id::create("tr");

		start_item(tr);

		tr.access_type       = tagged_predictor_item::TAGGED_READ_WRITE;
		tr.fetch_en          = 1'b1;
		tr.fetch_idx         = fetch_idx;

		tr.tagged_update_en  = 1'b1;
		tr.commit_way_id     = commit_way_id;
		tr.commit_idx        = commit_idx;

		tr.wdata_tag         = wdata_tag;
		tr.wdata_dist        = wdata_dist;
		tr.wdata_conf        = wdata_conf;
		tr.wdata_useful      = wdata_useful;

		// tr.expect_check      = expect_check;
		tr.is_decay          = 1'b0;
		tr.is_same_index_rdw = (fetch_idx == commit_idx);

		finish_item(tr);
	endtask


	task decay_cycle(
		input bit [INDEX_WIDTH-1:0] commit_idx
	);
		tagged_predictor_item tr;

		tr = tagged_predictor_item::type_id::create("tr");

		start_item(tr);

		tr.access_type       = tagged_predictor_item::TAGGED_DECAY;
		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = '0;

		tr.tagged_update_en  = 1'b1;
		tr.commit_way_id     = '1;
		tr.commit_idx        = commit_idx;

		// These should be ignored by DUT during decay.
		tr.wdata_tag         = '0;
		tr.wdata_dist        = '0;
		tr.wdata_conf        = '0;
		tr.wdata_useful      = '0;

		// tr.expect_check      = 1'b0;
		tr.is_decay          = 1'b1;
		tr.is_same_index_rdw = 1'b0;

		finish_item(tr);
	endtask


	task disabled_write_cycle(
		input bit [INDEX_WIDTH-1:0] commit_idx,
		input bit [NUM_WAYS-1:0] commit_way_id,
		input bit [TAG_WIDTH-1:0] wdata_tag,
		input bit [DISTANCE_WIDTH-1:0] wdata_dist,
		input bit [CONFIDENCE_WIDTH-1:0] wdata_conf,
		input bit [USEFUL_WIDTH-1:0] wdata_useful
	);
		tagged_predictor_item tr;

		tr = tagged_predictor_item::type_id::create("tr");

		start_item(tr);

		tr.access_type       = tagged_predictor_item::TAGGED_IDLE;
		tr.fetch_en          = 1'b0;
		tr.fetch_idx         = '0;

		tr.tagged_update_en  = 1'b0;
		tr.commit_way_id     = commit_way_id;
		tr.commit_idx        = commit_idx;

		tr.wdata_tag         = wdata_tag;
		tr.wdata_dist        = wdata_dist;
		tr.wdata_conf        = wdata_conf;
		tr.wdata_useful      = wdata_useful;

		// tr.expect_check      = 1'b0;
		tr.is_decay          = 1'b0;
		tr.is_same_index_rdw = 1'b0;

		finish_item(tr);
	endtask

endclass


class tagged_predictor_sequencer extends uvm_sequencer #(tagged_predictor_item);

	`uvm_component_utils(tagged_predictor_sequencer)

	function new(string name = "tagged_predictor_sequencer", uvm_component parent);
		super.new(name, parent);
	endfunction

endclass


class tagged_predictor_driver extends uvm_driver #(tagged_predictor_item);

	`uvm_component_utils(tagged_predictor_driver)

	virtual tagged_predictor_if vif;

	function new(string name = "tagged_predictor_driver", uvm_component parent);
		super.new(name, parent);
	endfunction


	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual tagged_predictor_if)::get(this, "", "vif", vif)) begin
		`uvm_fatal("NOVIF", "Virtual interface not found for tagged_predictor_driver")
		end
	endfunction


	task run_phase(uvm_phase phase);
		tagged_predictor_item tr;

		drive_idle();

		forever begin
			seq_item_port.get_next_item(tr);
			drive_item(tr);
			seq_item_port.item_done();
		end
	endtask

	
	task drive_idle();

		@(vif.drv_cb);

		vif.drv_cb.fetch_en_i         <= 1'b0;
		vif.drv_cb.fetch_idx_i        <= '0;

		vif.drv_cb.tagged_update_en_i <= 1'b0;
		vif.drv_cb.commit_way_id_i    <= '0;
		vif.drv_cb.commit_idx_i       <= '0;

		vif.drv_cb.wdata_tag_i        <= '0;
		vif.drv_cb.wdata_dist_i       <= '0;
		vif.drv_cb.wdata_conf_i       <= '0;
		vif.drv_cb.wdata_useful_i     <= '0;

	endtask

	task drive_item(tagged_predictor_item tr);

		@(vif.drv_cb);

		vif.drv_cb.fetch_en_i         <= tr.fetch_en;
		vif.drv_cb.fetch_idx_i        <= tr.fetch_idx;

		vif.drv_cb.tagged_update_en_i <= tr.tagged_update_en;
		vif.drv_cb.commit_way_id_i    <= tr.commit_way_id;
		vif.drv_cb.commit_idx_i       <= tr.commit_idx;

		vif.drv_cb.wdata_tag_i        <= tr.wdata_tag;
		vif.drv_cb.wdata_dist_i       <= tr.wdata_dist;
		vif.drv_cb.wdata_conf_i       <= tr.wdata_conf;
		vif.drv_cb.wdata_useful_i     <= tr.wdata_useful;

		`uvm_info("TAGGED_DRV",
		$sformatf("access=%0d fetch_en=%0b fetch_idx=%0d update_en=%0b commit_idx=%0d way_mask=%04b wdata={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
			tr.access_type,
			tr.fetch_en,
			tr.fetch_idx,
			tr.tagged_update_en,
			tr.commit_idx,
			tr.commit_way_id,
			tr.wdata_tag,
			tr.wdata_dist,
			tr.wdata_conf,
			tr.wdata_useful),
		UVM_HIGH)

	endtask

endclass


class tagged_predictor_monitor extends uvm_monitor;

	`uvm_component_utils(tagged_predictor_monitor)

	virtual tagged_predictor_if vif;
	uvm_analysis_port #(tagged_predictor_item) monitor_port;

	localparam int NUM_WAYS = 4;

	function new(string name = "tagged_predictor_monitor", uvm_component parent);
		super.new(name, parent);
		monitor_port = new("monitor_port", this);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual tagged_predictor_if)::get(this, "", "vif", vif)) begin
			`uvm_fatal("NOVIF", "Virtual interface not found for tagged_predictor_monitor")
		end
	endfunction


	task run_phase(uvm_phase phase);
		tagged_predictor_item tr;

		forever begin
		@(posedge vif.clk);

		// Wait for DUT nonblocking assignments to settle.
		#1;
		tr = tagged_predictor_item::type_id::create("tr", this);

		tr.fetch_en         = vif.fetch_en_i;
		tr.fetch_idx        = vif.fetch_idx_i;

		tr.tagged_update_en = vif.tagged_update_en_i;
		tr.commit_way_id    = vif.commit_way_id_i;
		tr.commit_idx       = vif.commit_idx_i;

		tr.wdata_tag        = vif.wdata_tag_i;
		tr.wdata_dist       = vif.wdata_dist_i;
		tr.wdata_conf       = vif.wdata_conf_i;
		tr.wdata_useful     = vif.wdata_useful_i;

		tr.is_decay         = (vif.commit_way_id_i == '1);
		tr.is_same_index_rdw = (
			vif.fetch_en_i &&
			vif.tagged_update_en_i &&
			(vif.fetch_idx_i == vif.commit_idx_i)
		);

		if (vif.fetch_en_i && vif.tagged_update_en_i) begin
			tr.access_type = tagged_predictor_item::TAGGED_READ_WRITE;
		end
		else if (vif.fetch_en_i) begin
			tr.access_type = tagged_predictor_item::TAGGED_READ;
		end
		else if (vif.tagged_update_en_i && (vif.commit_way_id_i == '1)) begin
			tr.access_type = tagged_predictor_item::TAGGED_DECAY;
		end
		else if (vif.tagged_update_en_i) begin
			tr.access_type = tagged_predictor_item::TAGGED_WRITE;
		end
		else begin
			tr.access_type = tagged_predictor_item::TAGGED_IDLE;
		end

		for (int way = 0; way < NUM_WAYS; way++) begin
			tr.observed_tags[way]   = vif.read_tags_o[way];
			tr.observed_dists[way]  = vif.read_dists_o[way];
			tr.observed_confs[way]  = vif.read_confs_o[way];
			tr.observed_useful[way] = vif.read_useful_o[way];
		end

		monitor_port.write(tr);

		`uvm_info("TAGGED_MON",
			$sformatf("access=%0d fetch_en=%0b fetch_idx=%0d update_en=%0b commit_idx=%0d way_mask=%04b wdata={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
			tr.access_type,
			tr.fetch_en,
			tr.fetch_idx,
			tr.tagged_update_en,
			tr.commit_idx,
			tr.commit_way_id,
			tr.wdata_tag,
			tr.wdata_dist,
			tr.wdata_conf,
			tr.wdata_useful),
			UVM_HIGH)

		if (tr.fetch_en) begin
			for (int way = 0; way < NUM_WAYS; way++) begin
			`uvm_info("TAGGED_MON_RD",
				$sformatf("idx=%0d way=%0d observed={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
				tr.fetch_idx,
				way,
				tr.observed_tags[way],
				tr.observed_dists[way],
				tr.observed_confs[way],
				tr.observed_useful[way]),
				UVM_HIGH)
			end
		end

		end
	endtask

endclass


class tagged_predictor_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(tagged_predictor_scoreboard)

	localparam int NUM_WAYS         = 4;
	localparam int INDEX_WIDTH      = 7;
	localparam int TABLE_DEPTH      = 1 << INDEX_WIDTH;
	localparam int TAG_WIDTH        = 16;
	localparam int DISTANCE_WIDTH   = 7;
	localparam int CONFIDENCE_WIDTH = 4;
	localparam int USEFUL_WIDTH     = 2;

	uvm_analysis_imp #(tagged_predictor_item, tagged_predictor_scoreboard) analysis_export;

	// memory block inside the scoreboard to check with the incoming data
	bit [TAG_WIDTH-1:0]        ref_tag    [NUM_WAYS][TABLE_DEPTH];
	bit [DISTANCE_WIDTH-1:0]   ref_dist   [NUM_WAYS][TABLE_DEPTH];
	bit [CONFIDENCE_WIDTH-1:0] ref_conf   [NUM_WAYS][TABLE_DEPTH];
	bit [USEFUL_WIDTH-1:0]     ref_useful [NUM_WAYS][TABLE_DEPTH];
	bit                        ref_valid  [NUM_WAYS][TABLE_DEPTH];

	int total_writes;
	int total_decays;
	int total_read_checks;
	int passed_read_checks;
	int failed_read_checks;
	int skipped_uninitialized_reads;

	function new(string name = "tagged_predictor_scoreboard", uvm_component parent);
		super.new(name, parent);
		analysis_export = new("analysis_export", this);
	endfunction


	function void write(tagged_predictor_item tr);

		// checking read data against old model.
		if (tr.fetch_en) begin
			check_read(tr);
		end

		// updated model with write/decay.
		if (tr.tagged_update_en) begin
			if (tr.commit_way_id == '1) begin
				apply_decay(tr);
			end
			else begin
				case (tr.access_type)

					tagged_predictor_item::TAGGED_REWARD: begin
						apply_reward(tr);
					end

					tagged_predictor_item::TAGGED_PENALIZE: begin
						apply_penalize(tr);
					end

					default: begin
						apply_write(tr);
					end

				endcase
			end
		end

	endfunction


	function void check_read(tagged_predictor_item tr);

		for (int way = 0; way < NUM_WAYS; way++) begin

		if (!ref_valid[way][tr.fetch_idx]) begin
			skipped_uninitialized_reads++;
			`uvm_info("TAGGED_UNINIT_READ",
				$sformatf("Skipping uninitialized read idx=%0d way=%0d",
				tr.fetch_idx,
				way),
			UVM_HIGH)
		end
		else begin
			total_read_checks++;

			if (
				tr.observed_tags[way]   === ref_tag[way][tr.fetch_idx] &&
				tr.observed_dists[way]  === ref_dist[way][tr.fetch_idx] &&
				tr.observed_confs[way]  === ref_conf[way][tr.fetch_idx] &&
				tr.observed_useful[way] === ref_useful[way][tr.fetch_idx]
			) begin
			passed_read_checks++;

			`uvm_info("TAGGED_MATCH",
				$sformatf("PASS check=%0d idx=%0d way=%0d expected={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h} observed={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
				total_read_checks,
				tr.fetch_idx,
				way,
				ref_tag[way][tr.fetch_idx],
				ref_dist[way][tr.fetch_idx],
				ref_conf[way][tr.fetch_idx],
				ref_useful[way][tr.fetch_idx],
				tr.observed_tags[way],
				tr.observed_dists[way],
				tr.observed_confs[way],
				tr.observed_useful[way]),
				UVM_HIGH)
			end
			else begin
			failed_read_checks++;

			`uvm_error("TAGGED_MISMATCH",
				$sformatf("Read mismatch idx=%0d way=%0d expected={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h} observed={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
				tr.fetch_idx,
				way,
				ref_tag[way][tr.fetch_idx],
				ref_dist[way][tr.fetch_idx],
				ref_conf[way][tr.fetch_idx],
				ref_useful[way][tr.fetch_idx],
				tr.observed_tags[way],
				tr.observed_dists[way],
				tr.observed_confs[way],
				tr.observed_useful[way]))
			end
		end
		end

	endfunction


	function void apply_write(tagged_predictor_item tr);

		for (int way = 0; way < NUM_WAYS; way++) begin
			if (tr.commit_way_id[way]) begin

				ref_tag[way][tr.commit_idx]    = tr.wdata_tag;
				ref_dist[way][tr.commit_idx]   = tr.wdata_dist;
				ref_conf[way][tr.commit_idx]   = tr.wdata_conf;
				ref_useful[way][tr.commit_idx] = tr.wdata_useful;
				ref_valid[way][tr.commit_idx]  = 1'b1;

				total_writes++;

				`uvm_info("TAGGED_REF_WRITE",
				$sformatf("REF WRITE idx=%0d way=%0d data={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
					tr.commit_idx,
					way,
					tr.wdata_tag,
					tr.wdata_dist,
					tr.wdata_conf,
					tr.wdata_useful),
				UVM_HIGH)

			end
		end

	endfunction


	function void apply_decay(tagged_predictor_item tr);

		for (int way = 0; way < NUM_WAYS; way++) begin
		if (ref_valid[way][tr.commit_idx]) begin

			if (ref_useful[way][tr.commit_idx] != '0) begin
				ref_useful[way][tr.commit_idx] = ref_useful[way][tr.commit_idx] - 1'b1;
			end
			else begin
				ref_useful[way][tr.commit_idx] = '0;
			end

		end
		end

		total_decays++;

		`uvm_info("TAGGED_REF_DECAY",
		$sformatf("REF DECAY idx=%0d all ways useful decremented with saturation",
			tr.commit_idx),
		UVM_HIGH)

	endfunction


	function void apply_reward(tagged_predictor_item tr);

		total_rewards++;

		`uvm_info("TAGGED_REF_REWARD",
			$sformatf("REF REWARD idx=%0d way_mask=%04b data={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
			tr.commit_idx,
			tr.commit_way_id,
			tr.wdata_tag,
			tr.wdata_dist,
			tr.wdata_conf,
			tr.wdata_useful),
			UVM_HIGH)

		apply_write(tr);

	endfunction


	function void apply_penalize(tagged_predictor_item tr);

		total_penalizes++;

		`uvm_info("TAGGED_REF_PENALIZE",
			$sformatf("REF PENALIZE idx=%0d way_mask=%04b data={tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h}",
			tr.commit_idx,
			tr.commit_way_id,
			tr.wdata_tag,
			tr.wdata_dist,
			tr.wdata_conf,
			tr.wdata_useful),
			UVM_HIGH)

		apply_write(tr);

	endfunction


	function void display_scoreboard_memory();

		`uvm_info("TAGGED_MEM_DUMP",
		"Displaying valid tagged scoreboard memory entries",
		UVM_LOW)

		for (int idx = 0; idx < TABLE_DEPTH; idx++) begin
		for (int way = 0; way < NUM_WAYS; way++) begin
			if (ref_valid[way][idx]) begin
			`uvm_info("TAGGED_MEM_DUMP",
				$sformatf("idx=%0d way=%0d tag=0x%0h dist=0x%0h conf=0x%0h useful=0x%0h valid=%0b",
				idx,
				way,
				ref_tag[way][idx],
				ref_dist[way][idx],
				ref_conf[way][idx],
				ref_useful[way][idx],
				ref_valid[way][idx]),
				UVM_LOW)
			end
		end
		end

	endfunction


	function void report_phase(uvm_phase phase);
		super.report_phase(phase);

		`uvm_info("TAGGED_SCOREBOARD_SUMMARY",
			$sformatf("\n----------------------------------------\nTAGGED PREDICTOR SCOREBOARD SUMMARY\n----------------------------------------\nTotal writes              : %0d\nTotal rewards             : %0d\nTotal penalizes           : %0d\nTotal decays              : %0d\nTotal read checks         : %0d\nPassed read checks        : %0d\nFailed read checks        : %0d\nSkipped uninitialized reads: %0d\n----------------------------------------",
			total_writes,
			total_rewards,
			total_penalizes,
			total_decays,
			total_read_checks,
			passed_read_checks,
			failed_read_checks,
			skipped_uninitialized_reads),
			UVM_NONE)

		if (failed_read_checks == 0) begin
			`uvm_info("TAGGED_RESULT", "TEST RESULT: PASS", UVM_NONE)
		end
		else begin
			`uvm_error("TAGGED_RESULT",
				$sformatf("TEST RESULT: FAIL with %0d mismatches", failed_read_checks))
		end

	endfunction

endclass


class tagged_predictor_coverage extends uvm_subscriber #(tagged_predictor_item);

	`uvm_component_utils(tagged_predictor_coverage)

	localparam int NUM_WAYS         = 4;
	localparam int INDEX_WIDTH      = 7;
	localparam int TABLE_DEPTH      = 1 << INDEX_WIDTH;
	localparam int TAG_WIDTH        = 16;
	localparam int DISTANCE_WIDTH   = 7;
	localparam int CONFIDENCE_WIDTH = 4;
	localparam int USEFUL_WIDTH     = 2;

	tagged_predictor_item cov_item;

	bit fetch_en_sample;
	bit update_en_sample;
	bit [INDEX_WIDTH-1:0] fetch_idx_sample;
	bit [INDEX_WIDTH-1:0] commit_idx_sample;
	bit [NUM_WAYS-1:0] commit_way_id_sample;
	bit [TAG_WIDTH-1:0] wdata_tag_sample;
	bit [DISTANCE_WIDTH-1:0] wdata_dist_sample;
	bit [CONFIDENCE_WIDTH-1:0] wdata_conf_sample;
	bit [USEFUL_WIDTH-1:0] wdata_useful_sample;
	bit same_index_sample;
	bit is_decay_sample;

	int access_type_sample;

	covergroup tagged_predictor_cg;

		option.per_instance = 1;

		fetch_en_cp: coverpoint fetch_en_sample {
		bins fetch_disabled = {0};
		bins fetch_enabled  = {1};
		}

		update_en_cp: coverpoint update_en_sample {
		bins update_disabled = {0};
		bins update_enabled  = {1};
		}

		access_type_cp: coverpoint access_type_sample {
		bins idle       = {tagged_predictor_item::TAGGED_IDLE};
		bins read       = {tagged_predictor_item::TAGGED_READ};
		bins write      = {tagged_predictor_item::TAGGED_WRITE};
		bins read_write = {tagged_predictor_item::TAGGED_READ_WRITE};
		bins decay      = {tagged_predictor_item::TAGGED_DECAY};
		bins reward     = {tagged_predictor_item::TAGGED_REWARD};
		bins penalize   = {tagged_predictor_item::TAGGED_PENALIZE};
		}

		fetch_idx_cp: coverpoint fetch_idx_sample iff (fetch_en_sample) {
		bins idx_zero = {0};
		bins idx_low  = {[1:31]};
		bins idx_mid  = {[32:95]};
		bins idx_high = {[96:126]};
		bins idx_max  = {127};
		}

		commit_idx_cp: coverpoint commit_idx_sample iff (update_en_sample) {
		bins idx_zero = {0};
		bins idx_low  = {[1:31]};
		bins idx_mid  = {[32:95]};
		bins idx_high = {[96:126]};
		bins idx_max  = {127};
		}

		commit_way_id_cp: coverpoint commit_way_id_sample iff (update_en_sample) {
		bins way0  = {4'b0001};
		bins way1  = {4'b0010};
		bins way2  = {4'b0100};
		bins way3  = {4'b1000};
		bins decay = {4'b1111};
		bins zero_mask = {4'b0000};
		bins multi_way[] = {
			4'b0011, 4'b0101, 4'b1001,
			4'b0110, 4'b1010, 4'b1100,
			4'b0111, 4'b1011, 4'b1101, 4'b1110
		};
		}

		tag_value_cp: coverpoint wdata_tag_sample iff (update_en_sample && !is_decay_sample) {
		bins tag_zero = {16'h0000};
		bins tag_low  = {[16'h0001:16'h3FFF]};
		bins tag_mid  = {[16'h4000:16'hBFFF]};
		bins tag_high = {[16'hC000:16'hFFFE]};
		bins tag_max  = {16'hFFFF};
		}

		dist_value_cp: coverpoint wdata_dist_sample iff (update_en_sample && !is_decay_sample) {
		bins dist_zero = {7'h00};
		bins dist_low  = {[7'h01:7'h1F]};
		bins dist_mid  = {[7'h20:7'h5F]};
		bins dist_high = {[7'h60:7'h7E]};
		bins dist_max  = {7'h7F};
		}

		conf_value_cp: coverpoint wdata_conf_sample iff (update_en_sample && !is_decay_sample) {
		bins conf_zero = {4'h0};
		bins conf_one  = {4'h1};
		bins conf_mid  = {[4'h2:4'hD]};
		bins conf_max_minus_one = {4'hE};
		bins conf_max  = {4'hF};
		}

		useful_value_cp: coverpoint wdata_useful_sample iff (update_en_sample && !is_decay_sample) {
		bins useful_zero = {2'h0};
		bins useful_one  = {2'h1};
		bins useful_two  = {2'h2};
		bins useful_max  = {2'h3};
		}

		same_index_rdw_cp: coverpoint same_index_sample iff (fetch_en_sample && update_en_sample) {
		bins diff_index = {0};
		bins same_index = {1};
		}

		decay_cp: coverpoint is_decay_sample iff (update_en_sample) {
		bins normal_update = {0};
		bins decay_update  = {1};
		}

		access_cross: cross fetch_en_cp, update_en_cp;

		way_x_conf_cross: cross commit_way_id_cp, conf_value_cp
		iff (update_en_sample && !is_decay_sample);

		way_x_useful_cross: cross commit_way_id_cp, useful_value_cp
		iff (update_en_sample && !is_decay_sample);

	endgroup


	function new(string name = "tagged_predictor_coverage", uvm_component parent);
		super.new(name, parent);
		tagged_predictor_cg = new();
	endfunction


	virtual function void write(tagged_predictor_item t);

		cov_item = t;

		fetch_en_sample      = t.fetch_en;
		update_en_sample     = t.tagged_update_en;
		fetch_idx_sample     = t.fetch_idx;
		commit_idx_sample    = t.commit_idx;
		commit_way_id_sample = t.commit_way_id;
		wdata_tag_sample     = t.wdata_tag;
		wdata_dist_sample    = t.wdata_dist;
		wdata_conf_sample    = t.wdata_conf;
		wdata_useful_sample  = t.wdata_useful;
		same_index_sample    = (t.fetch_idx == t.commit_idx);
		is_decay_sample      = (t.commit_way_id == '1);
		access_type_sample   = t.access_type;

		tagged_predictor_cg.sample();

	endfunction


	function void report_phase(uvm_phase phase);
		super.report_phase(phase);

		`uvm_info("TAGGED_COVERAGE",
		$sformatf("Tagged predictor functional coverage = %0.2f%%",
			tagged_predictor_cg.get_inst_coverage()),
		UVM_NONE)

	endfunction

endclass


class tagged_predictor_agent extends uvm_agent;

	`uvm_component_utils(tagged_predictor_agent)

	tagged_predictor_sequencer sequencer;
	tagged_predictor_driver    driver;
	tagged_predictor_monitor   monitor;
	tagged_predictor_coverage  coverage;

	function new(string name = "tagged_predictor_agent", uvm_component parent);
		super.new(name, parent);
	endfunction


	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (get_is_active() == UVM_ACTIVE) begin
		sequencer = tagged_predictor_sequencer::type_id::create("sequencer", this);
		driver    = tagged_predictor_driver::type_id::create("driver", this);
		end

		monitor  = tagged_predictor_monitor::type_id::create("monitor", this);
		coverage = tagged_predictor_coverage::type_id::create("coverage", this);
	endfunction


	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		if (get_is_active() == UVM_ACTIVE) begin
		driver.seq_item_port.connect(sequencer.seq_item_export);
		end

		monitor.monitor_port.connect(coverage.analysis_export);
	endfunction

endclass


class tagged_predictor_env extends uvm_env;

	`uvm_component_utils(tagged_predictor_env)

	tagged_predictor_agent      agent;
	tagged_predictor_scoreboard scoreboard;

	function new(string name = "tagged_predictor_env", uvm_component parent);
		super.new(name, parent);
	endfunction


	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		agent      = tagged_predictor_agent::type_id::create("agent", this);
		scoreboard = tagged_predictor_scoreboard::type_id::create("scoreboard", this);
	endfunction


	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		agent.monitor.monitor_port.connect(scoreboard.analysis_export);
	endfunction

endclass


class tagged_predictor_base_test extends uvm_test;

	`uvm_component_utils(tagged_predictor_base_test)

	tagged_predictor_env env;

	function new(string name = "tagged_predictor_base_test", uvm_component parent);
		super.new(name, parent);
	endfunction


	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		env = tagged_predictor_env::type_id::create("env", this);
	endfunction


	task run_phase(uvm_phase phase);

		// Later we will add:
		//
		// tagged_predictor_smoke_seq smoke_seq;
		// tagged_predictor_all_way_read_seq all_way_seq;
		// tagged_predictor_way_select_seq way_select_seq;
		// tagged_predictor_decay_seq decay_seq;
		// tagged_predictor_random_seq random_seq;

		phase.raise_objection(this);

		`uvm_info("TAGGED_BASE_TEST",
		"Tagged predictor base test started",
		UVM_LOW)

		// Placeholder idle time until sequences are added.
		#100;

		`uvm_info("TAGGED_BASE_TEST",
		"Tagged predictor base test completed",
		UVM_LOW)

		phase.drop_objection(this);

	endtask

endclass


module tb_top;

	localparam int NUM_TAGGED_TABLES = 7;
	localparam int NUM_WAYS          = 4;
	localparam int INDEX_WIDTH       = 7;
	localparam int TAG_WIDTH         = 16;
	localparam int DISTANCE_WIDTH    = 7;
	localparam int CONFIDENCE_WIDTH  = 4;
	localparam int USEFUL_WIDTH      = 2;

	logic clk;

	// Clock generation: 10 ns period
	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end


	tagged_predictor_if #(
		.NUM_WAYS(NUM_WAYS),
		.INDEX_WIDTH(INDEX_WIDTH),
		.TAG_WIDTH(TAG_WIDTH),
		.DISTANCE_WIDTH(DISTANCE_WIDTH),
		.CONFIDENCE_WIDTH(CONFIDENCE_WIDTH),
		.USEFUL_WIDTH(USEFUL_WIDTH)
	) tagged_if (
		.clk(clk)
	);


	tagged_predictor_sram #(
		.NUM_TAGGED_TABLES(NUM_TAGGED_TABLES),
		.INDEX_WIDTH(INDEX_WIDTH),
		.NUM_WAYS(NUM_WAYS),
		.TAG_WIDTH(TAG_WIDTH),
		.DISTANCE_WIDTH(DISTANCE_WIDTH),
		.CONFIDENCE_WIDTH(CONFIDENCE_WIDTH),
		.USEFUL_WIDTH(USEFUL_WIDTH)
	) dut (
		.clk(clk),

		.fetch_en_i(tagged_if.fetch_en_i),
		.fetch_idx_i(tagged_if.fetch_idx_i),

		.read_tags_o(tagged_if.read_tags_o),
		.read_dists_o(tagged_if.read_dists_o),
		.read_confs_o(tagged_if.read_confs_o),
		.read_useful_o(tagged_if.read_useful_o),

		.tagged_update_en_i(tagged_if.tagged_update_en_i),
		.commit_way_id_i(tagged_if.commit_way_id_i),
		.commit_idx_i(tagged_if.commit_idx_i),

		.wdata_tag_i(tagged_if.wdata_tag_i),
		.wdata_dist_i(tagged_if.wdata_dist_i),
		.wdata_conf_i(tagged_if.wdata_conf_i),
		.wdata_useful_i(tagged_if.wdata_useful_i)
	);


	initial begin
		uvm_config_db#(virtual tagged_predictor_if)::set(
		null,
		"*",
		"vif",
		tagged_if
		);

		run_test("tagged_predictor_base_test");
	end


	initial begin
		$dumpfile("dump.vcd");

		// Top-level clock and control signals
		$dumpvars(0, tb_top.clk);
		$dumpvars(0, tb_top.tagged_if.fetch_en_i);
		$dumpvars(0, tb_top.tagged_if.fetch_idx_i);

		$dumpvars(0, tb_top.tagged_if.tagged_update_en_i);
		$dumpvars(0, tb_top.tagged_if.commit_way_id_i);
		$dumpvars(0, tb_top.tagged_if.commit_idx_i);

		$dumpvars(0, tb_top.tagged_if.wdata_tag_i);
		$dumpvars(0, tb_top.tagged_if.wdata_dist_i);
		$dumpvars(0, tb_top.tagged_if.wdata_conf_i);
		$dumpvars(0, tb_top.tagged_if.wdata_useful_i);

		// Read outputs, all ways
		for (int way = 0; way < NUM_WAYS; way++) begin
		$dumpvars(0, tb_top.tagged_if.read_tags_o[way]);
		$dumpvars(0, tb_top.tagged_if.read_dists_o[way]);
		$dumpvars(0, tb_top.tagged_if.read_confs_o[way]);
		$dumpvars(0, tb_top.tagged_if.read_useful_o[way]);
		end

		// Optional gated clocks for debug
		$dumpvars(0, tb_top.dut.clk_gated_read);
		$dumpvars(0, tb_top.dut.clk_gated_write);
	end

endmodule