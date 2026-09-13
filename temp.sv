class predictor_history_checkpoint_data_ordering_sequence extends predictor_history_base_sequence;

	`uvm_object_utils(predictor_history_checkpoint_data_ordering_sequence)

	function new(string name = "predictor_history_checkpoint_data_ordering_sequence");
		super.new(name);
	endfunction

	virtual task body();
		int unsigned checkpoint_count;
		branch_packet_t packet_value;
		program_counter_t pc_value;

		if (FIFO_DEPTH < 2) begin
			`uvm_fatal(get_type_name(), "This sequence requires FIFO_DEPTH >= 2")
		end

		checkpoint_count = (FIFO_DEPTH < 8) ? FIFO_DEPTH : 8;

		`uvm_info(get_type_name(), "Starting checkpoint-data ordering sequence", UVM_LOW)

		idle_cycle("verify_initial_empty");

		for (int unsigned write_index = 0; write_index < checkpoint_count; write_index++) begin
			packet_value = branch_packet_t'(7'h11 + (write_index * 7));
			pc_value = program_counter_t'((write_index % 8) * 4);
			branch_cycle(packet_value, pc_value, $sformatf("ordered_checkpoint_write_%0d", write_index));
		end

		idle_cycle("hold_before_ordered_reads");

		for (int unsigned read_index = 0; read_index < checkpoint_count; read_index++) begin
			misprediction_cycle(misprediction_depth_t'(1), program_counter_t'(24), $sformatf("ordered_checkpoint_read_%0d", read_index));
			recovery_cycle(program_counter_t'(24), $sformatf("apply_checkpoint_%0d", read_index));
			idle_cycle($sformatf("settle_after_checkpoint_%0d", read_index));
		end

		repeat (3) begin
			idle_cycle("final_empty_hold");
		end

		`uvm_info(get_type_name(), "Completed checkpoint-data ordering stimulus", UVM_LOW)
	endtask

endclass