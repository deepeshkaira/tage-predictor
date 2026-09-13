package base_update_cntrl_params_pkg;

    parameter int INDEX_WIDTH      = 10;
    parameter int DISTANCE_WIDTH   = 7;
    parameter int CONFIDENCE_WIDTH = 3;

endpackage

import uvm_pkg::*;
`include "uvm_macros.svh";
import base_update_cntrl_params_pkg::*;

/// interface
interface base_update_cntrl_if;

		// DUT inputs
		logic                         en_i;
		logic                         commit_mispredicted_i;
		logic [INDEX_WIDTH-1:0]       base_index_i;
		logic [DISTANCE_WIDTH-1:0]    true_distance_i;
		logic [DISTANCE_WIDTH-1:0]    commit_old_dist_i;
		logic [CONFIDENCE_WIDTH-1:0]  commit_old_conf_i;

		// DUT outputs
		logic                         base_we_o;
		logic [INDEX_WIDTH-1:0]       base_addr_o;
		logic [DISTANCE_WIDTH-1:0]    base_wdata_dist_o;
		logic [CONFIDENCE_WIDTH-1:0]  base_wdata_conf_o;

		// Verification-only event. It is not connected to the DUT.
		event stimulus_applied;

		initial begin
			en_i                  = 1'b0;
			commit_mispredicted_i = 1'b0;
			base_index_i          = '0;
			true_distance_i       = '0;
			commit_old_dist_i     = '0;
			commit_old_conf_i     = '0;
		end

		modport DRIVER (
			output en_i,
			output commit_mispredicted_i,
			output base_index_i,
			output true_distance_i,
			output commit_old_dist_i,
			output commit_old_conf_i
		);

		modport MONITOR (
			input en_i,
			input commit_mispredicted_i,
			input base_index_i,
			input true_distance_i,
			input commit_old_dist_i,
			input commit_old_conf_i,
			input base_we_o,
			input base_addr_o,
			input base_wdata_dist_o,
			input base_wdata_conf_o
		);

endinterface



/// sequence item
class base_update_cntrl_transaction extends uvm_sequence_item;

		// stimuli to the DUT
		rand logic                         en_i;
		rand logic                         commit_mispredicted_i;
		rand logic [INDEX_WIDTH-1:0]       base_index_i;
		rand logic [DISTANCE_WIDTH-1:0]    true_distance_i;
		rand logic [DISTANCE_WIDTH-1:0]    commit_old_dist_i;
		rand logic [CONFIDENCE_WIDTH-1:0]  commit_old_conf_i;

		// Response signals to be sampled from the DUT
		logic                              base_we_o;
		logic [INDEX_WIDTH-1:0]            base_addr_o;
		logic [DISTANCE_WIDTH-1:0]         base_wdata_dist_o;
		logic [CONFIDENCE_WIDTH-1:0]       base_wdata_conf_o;

		`uvm_object_param_utils_begin(base_update_cntrl_transaction #(INDEX_WIDTH,DISTANCE_WIDTH,CONFIDENCE_WIDTH))
			`uvm_field_int(en_i,                    UVM_DEFAULT)
			`uvm_field_int(commit_mispredicted_i,   UVM_DEFAULT)
			`uvm_field_int(base_index_i,            UVM_DEFAULT)
			`uvm_field_int(true_distance_i,         UVM_DEFAULT)
			`uvm_field_int(commit_old_dist_i,       UVM_DEFAULT)
			`uvm_field_int(commit_old_conf_i,       UVM_DEFAULT)

			`uvm_field_int(base_we_o,                UVM_DEFAULT)
			`uvm_field_int(base_addr_o,              UVM_DEFAULT)
			`uvm_field_int(base_wdata_dist_o,        UVM_DEFAULT)
			`uvm_field_int(base_wdata_conf_o,        UVM_DEFAULT)
		`uvm_object_utils_end

		function new(string name = "base_update_cntrl_transaction");
			super.new(name);
		endfunction

endclass


/// basic smoke sequence for the design
class base_update_cntrl_smoke_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE  = '0;
    localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE  = {CONFIDENCE_WIDTH{1'b1}};
    localparam logic [CONFIDENCE_WIDTH-1:0] WEAK_CONFIDENCE = 3'b100;

    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[10:20]};}

    `uvm_object_utils(base_update_cntrl_smoke_sequence)

    function new(string name = "base_update_cntrl_smoke_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;
        bit           randomization_ok;
        string        scenario_name;

        // Randomize the number of transactions in this sequence run.
        if (!this.randomize()) begin
            `uvm_fatal(get_type_name(),"Failed to randomize the number of smoke transactions")
        end

        `uvm_info(get_type_name(),$sformatf("Starting smoke sequence with %0d transactions",nbr_txn),UVM_LOW)

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("transaction_%0d", txn_num + 1));

            start_item(transaction);

            case (txn_num)

                // Misprediction with zero confidence: replace old distance with true distance and set thr confidence to WEAK_CONFIDENCE.
                0: begin
                    scenario_name = "Misprediction: zero-confidence replacement";

                    randomization_ok = transaction.randomize() with {
											en_i == 1'b1;
											commit_mispredicted_i == 1'b1;
											commit_old_conf_i == local::MIN_CONFIDENCE;

											// replacement visible in the log.
											true_distance_i != commit_old_dist_i;
                        };
                end

                // Misprediction with middle confidence:
                // preserve old distance and decrement confidence.
                1: begin
                    scenario_name = "Misprediction: middle-confidence decrement";

                    randomization_ok = transaction.randomize() with {
											en_i == 1'b1;
											commit_mispredicted_i == 1'b1;
											commit_old_conf_i == local::WEAK_CONFIDENCE;

											true_distance_i != commit_old_dist_i;
                        };
                end

                // Misprediction with maximum confidence:
                // preserve old distance and decrement from maximum.
                2: begin
                    scenario_name = "Misprediction: maximum-confidence decrement";

                    randomization_ok = transaction.randomize() with {
											en_i == 1'b1;
											commit_mispredicted_i == 1'b1;
											commit_old_conf_i == local::MAX_CONFIDENCE;

											true_distance_i != commit_old_dist_i;
                        };
                end

                // Correct prediction with middle confidence:
                // preserve old distance and increment confidence.
                3: begin
                    scenario_name = "Correct prediction: middle-confidence increment";

                    randomization_ok = transaction.randomize() with {
											en_i == 1'b1;
											commit_mispredicted_i == 1'b0;
											commit_old_conf_i == local::WEAK_CONFIDENCE;

											true_distance_i != commit_old_dist_i;
                        };
                end

                // Correct prediction with maximum confidence:
                // preserve old distance and keep confidence saturated.
                4: begin
                    scenario_name = "Correct prediction: maximum-confidence saturation";

                    randomization_ok = transaction.randomize() with {
											en_i == 1'b1;
											commit_mispredicted_i == 1'b0;
											commit_old_conf_i  == local::MAX_CONFIDENCE;

											true_distance_i != commit_old_dist_i;
                        };
                end

                // Remaining transactions are randomized while the DUT
                // remains enabled.
                default: begin
                    scenario_name = "Unconstrained enabled random transaction";

                    randomization_ok = transaction.randomize() with {
                            				en_i == 1'b1;
                        };
                end

            endcase

            if (!randomization_ok) begin
                `uvm_fatal(get_type_name(),
                    $sformatf(
                        "Failed to randomize transaction #%0d",
                        txn_num + 1
                    )
                )
            end

            `uvm_info("SMOKE_SCENARIO",
                $sformatf(
                    "Transaction #%0d: %s",
                    txn_num + 1,
                    scenario_name
                ),
                UVM_LOW
            )

            finish_item(transaction);
        end

        `uvm_info(get_type_name(),
            $sformatf(
                "Completed %0d smoke transactions",
                nbr_txn
            ),
            UVM_LOW
        )
    endtask

endclass


/// sequence with enable pin as zero - all outputs and everything must remain zero.
class base_update_cntrl_disabled_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[10:20]};}

    `uvm_object_utils(base_update_cntrl_disabled_sequence)

    function new(string name = "base_update_cntrl_disabled_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;

        if (!this.randomize()) begin
            `uvm_fatal(
                get_type_name(),
                "Failed to randomize the number of disabled transactions"
            )
        end

        `uvm_info(
            get_type_name(),
            $sformatf(
                "Starting disabled sequence with %0d transactions",
                nbr_txn
            ),
            UVM_LOW
        )

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("disabled_transaction_%0d", txn_num + 1));

            start_item(transaction);

            // Keep the block disabled while randomizing every other input.
            if (!transaction.randomize() with {en_i == 1'b0;
            }) begin
                `uvm_fatal(
                    get_type_name(),
                    $sformatf(
                        "Failed to randomize disabled transaction #%0d",
                        txn_num + 1
                    )
                )
            end

            finish_item(transaction);
        end

        `uvm_info(get_type_name(),
            $sformatf(
                "Completed %0d disabled transactions",
                nbr_txn
            ),
            UVM_LOW
        )
    endtask

endclass



//// sequence to verify the correct prediction when the old confidence is not MAXIMUM value
class base_update_cntrl_correct_increment_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};

    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[10:20]};}

    `uvm_object_utils(base_update_cntrl_correct_increment_sequence)

    function new(string name = "base_update_cntrl_correct_increment_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;

        if (!this.randomize()) begin
            `uvm_fatal(get_type_name(),"Failed to randomize the number of increment transactions")
        end

        `uvm_info(get_type_name(),
            $sformatf(
                "Starting correct-increment sequence with %0d transactions",
                nbr_txn
            ),
            UVM_LOW
        )

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("correct_increment_transaction_%0d",txn_num + 1));

            start_item(transaction);

				if (!transaction.randomize() with {
					en_i == 1'b1;		                // Block must be enabled.
					commit_mispredicted_i == 1'b0;				// A correct prediction is being reported.
					commit_old_conf_i < local::MAX_CONFIDENCE;            // Exclude maximum confidence because saturation will be tested in the next sequence.
					true_distance_i != commit_old_dist_i;		// Make distance selection visible in the log.
				}) begin
					`uvm_fatal(get_type_name(),
						$sformatf("Failed to randomize correct-increment transaction #%0d",txn_num + 1))
				end

            finish_item(transaction);
        end

        `uvm_info(
            get_type_name(),
            $sformatf(
                "Completed %0d correct-increment transactions",
                nbr_txn
            ),
            UVM_LOW
        )
    endtask

endclass


//// update control correct saturation sequence
class base_update_cntrl_correct_saturation_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};

    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[10:20]};}

    `uvm_object_utils(base_update_cntrl_correct_saturation_sequence)

    function new(string name = "base_update_cntrl_correct_saturation_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;

        if (!this.randomize()) begin
            `uvm_fatal(get_type_name(),"Failed to randomize the number of saturation transactions")
        end

        `uvm_info(get_type_name(),
            $sformatf("Starting correct-saturation sequence with %0d transactions",nbr_txn),UVM_LOW)

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("correct_saturation_transaction_%0d",txn_num + 1));

            start_item(transaction);

				if (!transaction.randomize() with {
					en_i                  == 1'b1;
					commit_mispredicted_i == 1'b0;
					commit_old_conf_i     == local::MAX_CONFIDENCE;

					true_distance_i != commit_old_dist_i;		// Make distance selection visible in the scoreboard log.
				}) begin
					`uvm_fatal(get_type_name(),
						$sformatf(
							"Failed to randomize saturation transaction #%0d",
							txn_num + 1
						)
					)
				end

            finish_item(transaction);
        end

        `uvm_info(get_type_name(),
            $sformatf("Completed %0d correct-saturation transactions",nbr_txn),UVM_LOW)
    endtask

endclass


//// mispredict and decrement the confidence bits
class base_update_cntrl_mispredict_decrement_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE = '0;

    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[10:20]};}

    `uvm_object_utils(base_update_cntrl_mispredict_decrement_sequence)

    function new(string name = "base_update_cntrl_mispredict_decrement_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;

        if (!this.randomize()) begin
            `uvm_fatal(
                get_type_name(),
                "Failed to randomize the number of decrement transactions"
            )
        end

        `uvm_info(
            get_type_name(),
            $sformatf(
                "Starting mispredict-decrement sequence with %0d transactions",
                nbr_txn
            ),
            UVM_LOW
        )

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create(
                $sformatf("mispredict_decrement_transaction_%0d",txn_num + 1));

            start_item(transaction);

            if (!transaction.randomize() with {
                en_i                  == 1'b1;		                // Block is enabled and a misprediction occurred.
                commit_mispredicted_i == 1'b1;
                commit_old_conf_i > local::MIN_CONFIDENCE;		    // Zero confidence belongs to the replacement sequence.
				true_distance_i != commit_old_dist_i;				// Make distance selection visible in the scoreboard log.
                
            }) begin
                `uvm_fatal(get_type_name(),
                    $sformatf("Failed to randomize decrement transaction #%0d",txn_num + 1))
            end

            finish_item(transaction);
        end

        `uvm_info(
            get_type_name(),
            $sformatf(
                "Completed %0d mispredict-decrement transactions",
                nbr_txn
            ),
            UVM_LOW
        )
    endtask

endclass



//// mispredict with low confidence/0 - replacment
class base_update_cntrl_mispredict_replace_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE = '0;
    localparam logic [CONFIDENCE_WIDTH-1:0] WEAK_CONFIDENCE = 3'b100;

    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[10:20]};}

    `uvm_object_utils(base_update_cntrl_mispredict_replace_sequence)

    function new(string name = "base_update_cntrl_mispredict_replace_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;

        if (!this.randomize()) begin
            `uvm_fatal(get_type_name(),"Failed to randomize the number of replacement transactions")
        end

        `uvm_info(get_type_name(),
            $sformatf("Starting mispredict-replacement sequence with %0d transactions",nbr_txn),UVM_LOW)

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("mispredict_replace_transaction_%0d",txn_num + 1));

            start_item(transaction);

				if (!transaction.randomize() with {
					en_i                  == 1'b1;						// Enable the block and force a misprediction.
					commit_mispredicted_i == 1'b1;
					commit_old_conf_i == local::MIN_CONFIDENCE;			// Zero confidence selects the replacement behavior.
					true_distance_i != commit_old_dist_i;				// Make the distance replacement visible in the log.
				}) begin
					`uvm_fatal(get_type_name(),
						$sformatf("Failed to randomize replacement transaction #%0d",txn_num + 1))
				end

            finish_item(transaction);
        end

        `uvm_info(get_type_name(),
            $sformatf("Completed %0d mispredict-replacement transactions",nbr_txn),UVM_LOW)
    endtask

endclass


//// test every confidence value for both correct and incorrect predictions
class base_update_cntrl_confidence_sweep_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};

    `uvm_object_utils(base_update_cntrl_confidence_sweep_sequence)

    function new(string name = "base_update_cntrl_confidence_sweep_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;
        int unsigned  transaction_number;

        transaction_number = 0;

        `uvm_info(get_type_name(),
            $sformatf("Starting confidence sweep with %0d transactions",2 * (MAX_CONFIDENCE + 1)),UVM_LOW)

        // prediction_case = 0: correct prediction
        // prediction_case = 1: misprediction
        for (int unsigned prediction_case = 0; prediction_case <= 1; prediction_case++) begin

            for (int unsigned confidence_value = 0; confidence_value <= MAX_CONFIDENCE; confidence_value++) begin

                transaction_number++;
                transaction = transaction_t::type_id::create($sformatf("confidence_sweep_transaction_%0d",transaction_number));

                start_item(transaction);

					if (!transaction.randomize() with {en_i == 1'b1;

						commit_mispredicted_i == local::prediction_case;
						commit_old_conf_i == local::confidence_value;
						true_distance_i != commit_old_dist_i;								// Make distance selection visible in the log.
					}) begin
						`uvm_fatal(get_type_name(),
							$sformatf({"Failed to randomize confidence sweep ","transaction #%0d"},transaction_number))
					end

					`uvm_info("CONFIDENCE_SWEEP",
						$sformatf(
							{"Transaction #%0d: mispredicted=%0b ",
							"old_confidence=%0d"},
							transaction_number,
							prediction_case,
							confidence_value
						),
						UVM_LOW
					)

                finish_item(transaction);
            end
        end

        `uvm_info(get_type_name(),
            $sformatf("Completed %0d confidence-sweep transactions",transaction_number),UVM_LOW)
    endtask

endclass


//// boundary values test sequence. Fr ZERO, maximum, alternating and complementary index/distance patterns.
class base_update_cntrl_data_boundary_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};
    localparam logic [CONFIDENCE_WIDTH-1:0] WEAK_CONFIDENCE = 3'b100;

    `uvm_object_utils(base_update_cntrl_data_boundary_sequence)

    function new(string name = "base_update_cntrl_data_boundary_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;
        string        scenario_name;

        logic [INDEX_WIDTH-1:0]    alternating_index;
        logic [INDEX_WIDTH-1:0]    inverted_index;
        logic [DISTANCE_WIDTH-1:0] alternating_distance;
        logic [DISTANCE_WIDTH-1:0] inverted_distance;

        // Create width-independent alternating patterns.
        for (int unsigned bit_number = 0; bit_number < INDEX_WIDTH; bit_number++) begin
            alternating_index[bit_number] = bit_number % 2;
        end

        for (int unsigned bit_number = 0; bit_number < DISTANCE_WIDTH; bit_number++) begin
            alternating_distance[bit_number] = bit_number % 2;
        end

        inverted_index    = ~alternating_index;
        inverted_distance = ~alternating_distance;

        `uvm_info(get_type_name(),
            "Starting data-boundary sequence with 6 transactions",UVM_LOW)

        for (int unsigned txn_num = 0; txn_num < 6; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("data_boundary_transaction_%0d",txn_num + 1));

            start_item(transaction);

				transaction.en_i = 1'b1;

				case (txn_num)

					// All-zero boundary values.
					0: begin
						scenario_name = "All-zero index and distance values";

						transaction.commit_mispredicted_i = 1'b0;
						transaction.base_index_i          = '0;
						transaction.true_distance_i       = '0;
						transaction.commit_old_dist_i     = '0;
						transaction.commit_old_conf_i     = '0;
					end

					// All-maximum boundary values with saturation.
					1: begin
						scenario_name = "All-maximum values with confidence saturation";

						transaction.commit_mispredicted_i = 1'b0;
						transaction.base_index_i          = '1;
						transaction.true_distance_i       = '1;
						transaction.commit_old_dist_i     = '1;
						transaction.commit_old_conf_i     =  MAX_CONFIDENCE;
					end

					// Replace zero old distance with maximum true distance.
					2: begin
						scenario_name = "Maximum true distance replaces zero old distance";

						transaction.commit_mispredicted_i = 1'b1;
						transaction.base_index_i          = '0;
						transaction.true_distance_i       = '1;
						transaction.commit_old_dist_i     = '0;
						transaction.commit_old_conf_i     = '0;
					end

					// Preserve maximum old distance while true distance is zero.
					3: begin
						scenario_name = "Maximum old distance preserved during decrement";

						transaction.commit_mispredicted_i = 1'b1;
						transaction.base_index_i          = '1;
						transaction.true_distance_i       = '0;
						transaction.commit_old_dist_i     = '1;
						transaction.commit_old_conf_i     = WEAK_CONFIDENCE;
					end

					// Alternating address and distance patterns.
					4: begin
						scenario_name = "Alternating index and distance patterns";

						transaction.commit_mispredicted_i = 1'b0;
						transaction.base_index_i          = alternating_index;
						transaction.true_distance_i       = alternating_distance;
						transaction.commit_old_dist_i     = inverted_distance;
						transaction.commit_old_conf_i     = WEAK_CONFIDENCE - 1'b1;
					end

					// Inverted alternating patterns.
					5: begin
						scenario_name = "Inverted alternating index and distance patterns";

						transaction.commit_mispredicted_i = 1'b1;
						transaction.base_index_i          = inverted_index;
						transaction.true_distance_i       = inverted_distance;
						transaction.commit_old_dist_i     = alternating_distance;
						transaction.commit_old_conf_i     = MAX_CONFIDENCE;
					end

				endcase

				`uvm_info("DATA_BOUNDARY",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

            finish_item(transaction);
        end

        `uvm_info(get_type_name(),"Completed 6 data-boundary transactions",UVM_LOW)
    endtask

endclass



//// enable signal toggle with set of inputs
class base_update_cntrl_enable_toggle_sequence extends uvm_sequence #(base_update_cntrl_transaction);

		typedef base_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[10:20]};}

		`uvm_object_utils(base_update_cntrl_enable_toggle_sequence)

		function new(string name = "base_update_cntrl_enable_toggle_sequence");
			super.new(name);
		endfunction

		virtual task body();
			transaction_t transaction;
			bit           enable_value;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of enable-toggle transactions")
			end

			`uvm_info(get_type_name(),
				$sformatf("Starting enable-toggle sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				// Start disabled and alternate on every transaction.
				enable_value = txn_num % 2;

				transaction = transaction_t::type_id::create($sformatf("enable_toggle_transaction_%0d",txn_num + 1));

				start_item(transaction);

					if (!transaction.randomize() with {
							en_i == local::enable_value;				// Make distance selection visible when enabled.
							true_distance_i != commit_old_dist_i;
					}) begin
						`uvm_fatal(get_type_name(),
							$sformatf("Failed to randomize enable-toggle transaction #%0d",txn_num + 1))
					end

					`uvm_info("ENABLE_TOGGLE",
						$sformatf("Transaction #%0d: en_i=%0b",txn_num + 1,enable_value),UVM_LOW)

				finish_item(transaction);
			end

			`uvm_info(get_type_name(),
				$sformatf("Completed %0d enable-toggle transactions",nbr_txn),UVM_LOW)
		endtask

endclass



//// controlled repeated sequence in the design

class base_update_cntrl_repeated_transaction_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[10:20]};}

    `uvm_object_utils(base_update_cntrl_repeated_transaction_sequence)

    function new(string name = "base_update_cntrl_repeated_transaction_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t template_transaction;
        transaction_t transaction;

        if (!this.randomize()) begin
            `uvm_fatal(get_type_name(),
                "Failed to randomize the number of repeated transactions")
        end

        // Generate one transaction that will be repeated.
        template_transaction = transaction_t::type_id::create("template_transaction");

        if (!template_transaction.randomize() with {
            	en_i == 1'b1;
	            true_distance_i != commit_old_dist_i;            // Make selected distance behavior visible.

        }) begin
            `uvm_fatal(get_type_name(),"Failed to randomize the repeated transaction template")
        end

        `uvm_info("REPEATED_TRANSACTION",
            $sformatf(
                {"Repeating one transaction %0d times:\n",
                 "  en=%0b mispredicted=%0b index=0x%0h ",
                 "true_distance=0x%0h old_distance=0x%0h ",
                 "old_confidence=%0d"},
                nbr_txn,
                template_transaction.en_i,
                template_transaction.commit_mispredicted_i,
                template_transaction.base_index_i,
                template_transaction.true_distance_i,
                template_transaction.commit_old_dist_i,
                template_transaction.commit_old_conf_i
            ),
            UVM_LOW
        )

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("repeated_transaction_%0d",txn_num + 1));

            start_item(transaction);
				// Copy only the DUT input values.
				transaction.en_i = template_transaction.en_i;
				transaction.commit_mispredicted_i = template_transaction.commit_mispredicted_i;
				transaction.base_index_i = template_transaction.base_index_i;
				transaction.true_distance_i = template_transaction.true_distance_i;
				transaction.commit_old_dist_i = template_transaction.commit_old_dist_i;
				transaction.commit_old_conf_i = template_transaction.commit_old_conf_i;
            finish_item(transaction);
        end

        `uvm_info(get_type_name(),
            $sformatf("Completed %0d identical transactions",nbr_txn),UVM_LOW)
    endtask

endclass


//// base update control random sequence
class base_update_cntrl_random_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    localparam logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE = '0;
    localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};
    rand int unsigned nbr_txn;

    constraint nbr_txn_c {nbr_txn inside {[100:250]};}

    `uvm_object_utils(base_update_cntrl_random_sequence)

    function new(string name = "base_update_cntrl_random_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;

        if (!this.randomize()) begin
            `uvm_fatal(get_type_name(),"Failed to randomize the number of random transactions")
        end

        `uvm_info(get_type_name(),
            $sformatf("Starting constrained-random sequence with %0d transactions",nbr_txn),UVM_LOW)

        for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

            transaction = transaction_t::type_id::create($sformatf("random_transaction_%0d",txn_num + 1));

            start_item(transaction);

            if (!transaction.randomize() with {

					// Exercise enabled behavior more frequently while still checking disabled behavior.
					en_i dist {
							1'b1 := 80,
							1'b0 := 20
					};

					// Balance correct predictions and mispredictions.
					commit_mispredicted_i dist {
							1'b0 := 50,
							1'b1 := 50
					};

					// Give zero and maximum confidence additional weight.
					commit_old_conf_i dist {
							local::MIN_CONFIDENCE := 20,
							local::MAX_CONFIDENCE := 20,
							[1:(local::MAX_CONFIDENCE - 1'b1)] :/ 60
					};

            }) begin
                `uvm_fatal(get_type_name(),
                    $sformatf("Failed to randomize transaction #%0d",txn_num + 1))
            end

            finish_item(transaction);
        end

        `uvm_info(get_type_name(),
            $sformatf("Completed %0d constrained-random transactions",nbr_txn),UVM_LOW)
    endtask

endclass



/// disabled enable - no propagation of input sequences
class base_update_cntrl_disabled_x_isolation_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    `uvm_object_utils(base_update_cntrl_disabled_x_isolation_sequence)

    function new(string name = "base_update_cntrl_disabled_x_isolation_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;
        string        scenario_name;

        `uvm_info(
            get_type_name(),
            "Starting disabled X-isolation sequence with 6 transactions",
            UVM_LOW
        )

        for (int unsigned txn_num = 0; txn_num < 6; txn_num++) begin

            transaction = transaction_t::type_id::create(
                $sformatf(
                    "disabled_x_transaction_%0d",
                    txn_num + 1
                )
            );

            start_item(transaction);

            // First generate known random values for all inputs.
            if (!transaction.randomize() with {
                en_i == 1'b0;
            }) begin
                `uvm_fatal(
                    get_type_name(),
                    $sformatf(
                        "Failed to randomize X-isolation transaction #%0d",
                        txn_num + 1
                    )
                )
            end

            // Inject X into one input at a time, followed by all inputs.
            case (txn_num)

                0: begin
                    scenario_name = "X on commit_mispredicted_i";
                    transaction.commit_mispredicted_i = 1'bx;
                end

                1: begin
                    scenario_name = "X on base_index_i";
                    transaction.base_index_i = 'x;
                end

                2: begin
                    scenario_name = "X on true_distance_i";
                    transaction.true_distance_i = 'x;
                end

                3: begin
                    scenario_name = "X on commit_old_dist_i";
                    transaction.commit_old_dist_i = 'x;
                end

                4: begin
                    scenario_name = "X on commit_old_conf_i";
                    transaction.commit_old_conf_i = 'x;
                end

                5: begin
                    scenario_name = "X on all upstream inputs";

                    transaction.commit_mispredicted_i = 1'bx;
                    transaction.base_index_i          = 'x;
                    transaction.true_distance_i       = 'x;
                    transaction.commit_old_dist_i     = 'x;
                    transaction.commit_old_conf_i     = 'x;
                end

            endcase

            `uvm_info("DISABLED_X_ISOLATION",
                $sformatf(
                    "Transaction #%0d: %s",
                    txn_num + 1,
                    scenario_name
                ),
                UVM_LOW
            )

            finish_item(transaction);
        end

        `uvm_info(
            get_type_name(),
            "Completed 6 disabled X-isolation transactions",
            UVM_LOW
        )
    endtask

endclass



/// invalid enable sequence to check the outputs and logic misfire
class base_update_cntrl_invalid_enable_sequence extends uvm_sequence #(base_update_cntrl_transaction);

    typedef base_update_cntrl_transaction transaction_t;

    `uvm_object_utils(base_update_cntrl_invalid_enable_sequence)

    function new(string name = "base_update_cntrl_invalid_enable_sequence");
        super.new(name);
    endfunction

    virtual task body();
        transaction_t transaction;

        `uvm_info(
            get_type_name(),
            {"Starting invalid-enable sequence. ",
             "Assertion errors are expected in this sequence."},
            UVM_LOW
        )

        for (int unsigned txn_num = 0;
             txn_num < 2;
             txn_num++) begin

            transaction = transaction_t::type_id::create(
                $sformatf(
                    "invalid_enable_transaction_%0d",
                    txn_num + 1
                )
            );

            start_item(transaction);

            // Randomize the remaining transaction inputs.
            if (!transaction.randomize()) begin
                `uvm_fatal(
                    get_type_name(),
                    $sformatf(
                        "Failed to randomize invalid-enable transaction #%0d",
                        txn_num + 1
                    )
                )
            end

            case (txn_num)

                0: begin
                    transaction.en_i = 1'bx;

                    `uvm_info(
                        "INVALID_ENABLE",
                        "Driving en_i = X; RTL assertion should fire",
                        UVM_LOW
                    )
                end

                1: begin
                    transaction.en_i = 1'bz;

                    `uvm_info(
                        "INVALID_ENABLE",
                        "Driving en_i = Z; RTL assertion should fire",
                        UVM_LOW
                    )
                end

            endcase

            finish_item(transaction);
        end

        `uvm_info(
            get_type_name(),
            {"Completed invalid-enable sequence. ",
             "Two enable-assertion failures were expected."},
            UVM_LOW
        )
    endtask

endclass




// sequencer
class base_update_cntrl_sequencer extends uvm_sequencer #(base_update_cntrl_transaction);

		`uvm_component_utils(base_update_cntrl_sequencer)
		
		function new(string name = "base_update_cntrl_sequencer",uvm_component parent = null);
			super.new(name, parent);
		endfunction

endclass


/// driver class
class base_update_cntrl_driver extends uvm_driver #(base_update_cntrl_transaction);

		typedef base_update_cntrl_transaction transaction_t;
		virtual base_update_cntrl_if vif;
		`uvm_component_utils(base_update_cntrl_driver)

		function new(string name = "base_update_cntrl_driver",uvm_component parent = null);
			super.new(name, parent);
		endfunction

		virtual function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			if (!uvm_config_db #(virtual base_update_cntrl_if)::get(this, "", "vif", vif)) begin
				`uvm_fatal(get_type_name(),"Failed to get virtual interface from configuration database")
			end
		endfunction

		virtual task run_phase(uvm_phase phase);
			transaction_t transaction;

			forever begin
				seq_item_port.get_next_item(transaction);
				drive_transaction(transaction);
				seq_item_port.item_done();
			end
		endtask

		virtual task drive_transaction(transaction_t transaction);

			vif.en_i                  = transaction.en_i;
			vif.commit_mispredicted_i = transaction.commit_mispredicted_i;
			vif.base_index_i          = transaction.base_index_i;
			vif.true_distance_i       = transaction.true_distance_i;
			vif.commit_old_dist_i     = transaction.commit_old_dist_i;
			vif.commit_old_conf_i     = transaction.commit_old_conf_i;

			// Adding a little delay so that the combinational DUT outputs settle.
			#1step;

			// Notifying the monitor that a complete transaction is available.
			-> vif.stimulus_applied;

			/// adding another delay so that there is no overwriting of transactional data
			// Prevent the next transaction from overwriting the interface before the monitor samples the current transaction.
			#1step;

			`uvm_info(get_type_name(),
				$sformatf(
					{"Transaction driven: en=%0b mispredicted=%0b ",
					"index=0x%0h true_distance=0x%0h ",
					"old_distance=0x%0h old_confidence=%0d"},
					transaction.en_i,
					transaction.commit_mispredicted_i,
					transaction.base_index_i,
					transaction.true_distance_i,
					transaction.commit_old_dist_i,
					transaction.commit_old_conf_i
				),
				UVM_HIGH
			)
		endtask

endclass



/// monitor design
class base_update_cntrl_monitor extends uvm_monitor;

		typedef base_update_cntrl_transaction transaction_t;
		virtual base_update_cntrl_if vif;
		uvm_analysis_port #(transaction_t) analysis_port;
		`uvm_component_utils(base_update_cntrl_monitor)

		function new(string name = "base_update_cntrl_monitor",uvm_component parent = null);
			super.new(name, parent);
			analysis_port = new("analysis_port", this);
		endfunction

		virtual function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			if (!uvm_config_db #(virtual base_update_cntrl_if)::get(this, "", "vif", vif))
			begin
				`uvm_fatal(get_type_name(), "Virtual interface not found")
			end
		endfunction

		virtual task run_phase(uvm_phase phase);
			transaction_t transaction;

			forever begin
				@(vif.stimulus_applied);
				transaction = transaction_t::type_id::create("transaction");

				transaction.en_i                  = vif.en_i;
				transaction.commit_mispredicted_i = vif.commit_mispredicted_i;
				transaction.base_index_i          = vif.base_index_i;
				transaction.true_distance_i       = vif.true_distance_i;
				transaction.commit_old_dist_i     = vif.commit_old_dist_i;
				transaction.commit_old_conf_i     = vif.commit_old_conf_i;

				transaction.base_we_o             = vif.base_we_o;
				transaction.base_addr_o           = vif.base_addr_o;
				transaction.base_wdata_dist_o     = vif.base_wdata_dist_o;
				transaction.base_wdata_conf_o     = vif.base_wdata_conf_o;

				analysis_port.write(transaction);
			end
		endtask

endclass


/// agent
class base_update_cntrl_agent extends uvm_agent;

		typedef base_update_cntrl_transaction transaction_t;
		typedef base_update_cntrl_sequencer   sequencer_t;
		typedef base_update_cntrl_driver      driver_t;
		typedef base_update_cntrl_monitor     monitor_t;

		sequencer_t sequencer;
		driver_t    driver;
		monitor_t   monitor;

		// analysis port for providing the results to the env's scoreboard
		uvm_analysis_port #(transaction_t) analysis_port;

		`uvm_component_utils(base_update_cntrl_agent)

		function new(string name = "base_update_cntrl_agent",uvm_component parent = null);
			super.new(name, parent);
			analysis_port = new("analysis_port", this);
		endfunction

		virtual function void build_phase(uvm_phase phase);
			super.build_phase(phase);

			// monitor required for both active and passive agents.
			monitor = monitor_t::type_id::create("monitor", this);

			if (get_is_active() == UVM_ACTIVE) begin
				sequencer = sequencer_t::type_id::create("sequencer", this);
				driver    = driver_t::type_id::create("driver", this);
			end
		endfunction

		virtual function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);

			if (get_is_active() == UVM_ACTIVE) begin
				driver.seq_item_port.connect(sequencer.seq_item_export);
			end

			monitor.analysis_port.connect(analysis_port);
		endfunction

endclass


/// scoreboard
class base_update_cntrl_scoreboard extends uvm_scoreboard;

		typedef base_update_cntrl_transaction transaction_t;

		localparam logic [CONFIDENCE_WIDTH-1:0] MAX_CONFIDENCE = {CONFIDENCE_WIDTH{1'b1}};
		localparam logic [CONFIDENCE_WIDTH-1:0] MIN_CONFIDENCE = '0;
		localparam logic [CONFIDENCE_WIDTH-1:0] WEAK_CONFIDENCE = 3'b100;

		// Analysis implementation for receiving values from the monitor.
		uvm_analysis_imp #(transaction_t, base_update_cntrl_scoreboard) analysis_imp;

		int unsigned transaction_count;
		int unsigned pass_count;
		int unsigned fail_count;

		`uvm_component_utils(base_update_cntrl_scoreboard)

		function new(string name = "base_update_cntrl_scoreboard",uvm_component parent = null);
			super.new(name, parent);
			analysis_imp = new("analysis_imp", this);
		endfunction

		virtual function void write(transaction_t transaction);

			logic                         expected_we;
			logic [INDEX_WIDTH-1:0]       expected_addr;
			logic [DISTANCE_WIDTH-1:0]    expected_dist;
			logic [CONFIDENCE_WIDTH-1:0]  expected_conf;
			transaction_count++;

			// Default behavior when the block is disabled.
			expected_we   = 1'b0;
			expected_addr = '0;
			expected_dist = '0;
			expected_conf = '0;

			if ($isunknown(transaction.en_i)) begin
				fail_count++;
				`uvm_error(get_type_name(),"Cannot predict transaction because en_i is X or Z")
				return;
			end

			if (transaction.en_i == 1'b1) begin

				expected_we   = 1'b1;
				expected_addr = transaction.base_index_i;

				if (transaction.commit_mispredicted_i == 1'b1) begin

					if (transaction.commit_old_conf_i == MIN_CONFIDENCE) begin
						expected_dist = transaction.true_distance_i;
						expected_conf = WEAK_CONFIDENCE;
					end
					else begin
						expected_dist = transaction.commit_old_dist_i;
						expected_conf = transaction.commit_old_conf_i - 1'b1;
					end
				end
				else begin
					expected_dist = transaction.commit_old_dist_i;
					expected_conf = (transaction.commit_old_conf_i == MAX_CONFIDENCE) ? MAX_CONFIDENCE : transaction.commit_old_conf_i + 1'b1;
				end
			end

			if ((transaction.base_we_o !== expected_we) || (transaction.base_addr_o !== expected_addr) || (transaction.base_wdata_dist_o !== expected_dist) || (transaction.base_wdata_conf_o !== expected_conf)) begin
				fail_count++;

				`uvm_error("BASE_UPDATE_MISMATCH",
					$sformatf(
						{"Transaction #%0d: FAIL\n",
						"  Inputs   : en=%0b mispredicted=%0b base_index=0x%0h ",
						"true_distance=0x%0h old_distance=0x%0h ",
						"old_confidence=%0d\n",
						"  Expected : we=%0b addr=0x%0h distance=0x%0h ",
						"confidence=%0d\n",
						"  Actual   : we=%0b addr=0x%0h distance=0x%0h ",
						"confidence=%0d"},
						transaction_count,

						// Inputs
						transaction.en_i,
						transaction.commit_mispredicted_i,
						transaction.base_index_i,
						transaction.true_distance_i,
						transaction.commit_old_dist_i,
						transaction.commit_old_conf_i,

						// Expected outputs
						expected_we,
						expected_addr,
						expected_dist,
						expected_conf,

						// Actual outputs
						transaction.base_we_o,
						transaction.base_addr_o,
						transaction.base_wdata_dist_o,
						transaction.base_wdata_conf_o
					)
				)
			end
			else begin
				pass_count++;

				`uvm_info("BASE_UPDATE_PASS",
					$sformatf(
						{"Transaction #%0d: PASS\n",
						"  Inputs   : en=%0b mispredicted=%0b base_index=0x%0h ",
						"true_distance=0x%0h old_distance=0x%0h ",
						"old_confidence=%0d\n",
						"  Expected : we=%0b addr=0x%0h distance=0x%0h ",
						"confidence=%0d\n",
						"  Actual   : we=%0b addr=0x%0h distance=0x%0h ",
						"confidence=%0d"},
						transaction_count,

						// Inputs
						transaction.en_i,
						transaction.commit_mispredicted_i,
						transaction.base_index_i,
						transaction.true_distance_i,
						transaction.commit_old_dist_i,
						transaction.commit_old_conf_i,

						// Expected outputs
						expected_we,
						expected_addr,
						expected_dist,
						expected_conf,

						// Actual outputs
						transaction.base_we_o,
						transaction.base_addr_o,
						transaction.base_wdata_dist_o,
						transaction.base_wdata_conf_o
					),
					UVM_LOW
				)
			end
		endfunction

		virtual function void report_phase(uvm_phase phase);
			super.report_phase(phase);

			`uvm_info(get_type_name(),
				$sformatf(
					"Scoreboard summary: TOTAL=%0d PASS=%0d FAIL=%0d",
					transaction_count,
					pass_count,
					fail_count
				),
				UVM_NONE
			)
		endfunction
endclass


/// environment
class base_update_cntrl_env extends uvm_env;

		typedef base_update_cntrl_agent  agent_t;
		typedef base_update_cntrl_scoreboard scoreboard_t;
		
		agent_t  agent;
		scoreboard_t scoreboard;

		`uvm_component_utils(base_update_cntrl_env)

		function new(string name = "base_update_cntrl_env",uvm_component parent = null);
			super.new(name, parent);
		endfunction

		virtual function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			agent = agent_t::type_id::create("agent",this);
			scoreboard = scoreboard_t::type_id::create("scoreboard",this);
		endfunction

		virtual function void connect_phase(uvm_phase phase);
			super.connect_phase(phase);
			agent.analysis_port.connect(scoreboard.analysis_imp);
		endfunction

endclass


// test class
class base_update_cntrl_test extends uvm_test;

		typedef base_update_cntrl_env            env_t;
		typedef base_update_cntrl_smoke_sequence smoke_sequence_t;
		base_update_cntrl_disabled_sequence enable_disabled_seq;
		base_update_cntrl_correct_increment_sequence correct_increment_seq;
		base_update_cntrl_correct_saturation_sequence correct_saturation_seq;
		base_update_cntrl_mispredict_decrement_sequence mispredict_decrement_seq;
		base_update_cntrl_mispredict_replace_sequence mispredict_replace_seq;
		base_update_cntrl_confidence_sweep_sequence confidence_valuesfr_crct_n_incrt_seq;
		base_update_cntrl_data_boundary_sequence boundary_values_sequnce;
		base_update_cntrl_enable_toggle_sequence toggle_en_seq;
		base_update_cntrl_repeated_transaction_sequence repeated_txns;
		base_update_cntrl_random_sequence random_seq;
		base_update_cntrl_disabled_x_isolation_sequence disabled_en_x;
		base_update_cntrl_invalid_enable_sequence invalid_enable;


		env_t env;

		`uvm_component_utils(base_update_cntrl_test)

		function new(string name = "base_update_cntrl_test",uvm_component parent = null);
			super.new(name, parent);
		endfunction

		virtual function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			env = env_t::type_id::create("env",this);
		endfunction

		virtual task run_phase(uvm_phase phase);
			smoke_sequence_t smoke_sequence;
			phase.raise_objection(this,"Starting the sequence");
				// smoke_sequence = smoke_sequence_t::type_id::create("smoke_sequence");
				// smoke_sequence.start(env.agent.sequencer);
				
				// enable_disabled_seq = base_update_cntrl_disabled_sequence::type_id::create("enable_disabled_seq");
				// enable_disabled_seq.start(env.agent.sequencer);

				// correct_increment_seq = base_update_cntrl_correct_increment_sequence::type_id::create("correct_increment_seq");
				// correct_increment_seq.start(env.agent.sequencer);

				// correct_saturation_seq = base_update_cntrl_correct_saturation_sequence::type_id::create("correct_saturation_seq");
				// correct_saturation_seq.start(env.agent.sequencer);

				// mispredict_decrement_seq = base_update_cntrl_mispredict_decrement_sequence::type_id::create("mispredict_decrement_seq");
				// mispredict_decrement_seq.start(env.agent.sequencer);

				// mispredict_replace_seq = base_update_cntrl_mispredict_replace_sequence::type_id::create("mispredict_replace_seq");
				// mispredict_replace_seq.start(env.agent.sequencer);

				// confidence_valuesfr_crct_n_incrt_seq = base_update_cntrl_confidence_sweep_sequence::type_id::create("confidence_valuesfr_crct_n_incrt_seq");
				// confidence_valuesfr_crct_n_incrt_seq.start(env.agent.sequencer);
 
				// boundary_values_sequnce = base_update_cntrl_data_boundary_sequence::type_id::create("boundary_values_sequnce");
				// boundary_values_sequnce.start(env.agent.sequencer);
 
				// toggle_en_seq = base_update_cntrl_enable_toggle_sequence::type_id::create("toggle_en_seq");
				// toggle_en_seq.start(env.agent.sequencer);
 
				// repeated_txns = base_update_cntrl_repeated_transaction_sequence::type_id::create("repeated_txns");
				// repeated_txns.start(env.agent.sequencer);

				// random_seq = base_update_cntrl_random_sequence::type_id::create("random_seq");
				// random_seq.start(env.agent.sequencer);
 
				// disabled_en_x = base_update_cntrl_disabled_x_isolation_sequence::type_id::create("disabled_en_x");
				// disabled_en_x.start(env.agent.sequencer);
 
				invalid_enable = base_update_cntrl_invalid_enable_sequence::type_id::create("invalid_enable");
				invalid_enable.start(env.agent.sequencer);
 
			phase.drop_objection(this,"Sequence completed");
		endtask

endclass



/// module tb
module tb_top;

    timeunit 1ns;
    timeprecision 1ps;

    import uvm_pkg::*;
    import base_update_cntrl_params_pkg::*;

    base_update_cntrl_if base_if();

    base_update_cntrl #(
        .INDEX_WIDTH      (INDEX_WIDTH),
        .DISTANCE_WIDTH   (DISTANCE_WIDTH),
        .CONFIDENCE_WIDTH (CONFIDENCE_WIDTH)
    ) dut (
        .en_i                  (base_if.en_i),
        .commit_mispredicted_i (base_if.commit_mispredicted_i),
        .base_index_i          (base_if.base_index_i),
        .true_distance_i       (base_if.true_distance_i),
        .commit_old_dist_i     (base_if.commit_old_dist_i),
        .commit_old_conf_i     (base_if.commit_old_conf_i),

        .base_we_o             (base_if.base_we_o),
        .base_addr_o           (base_if.base_addr_o),
        .base_wdata_dist_o     (base_if.base_wdata_dist_o),
        .base_wdata_conf_o     (base_if.base_wdata_conf_o)
    );

    initial begin
        uvm_config_db #(virtual base_update_cntrl_if)::set(
            null,
            "uvm_test_top.env.agent*",
            "vif",
            base_if
        );

        run_test("base_update_cntrl_test");
    end

endmodule
