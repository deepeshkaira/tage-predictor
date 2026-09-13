import uvm_pkg::*;
`include "uvm_macros.svh"
import tagged_update_cntrl_params_pkg::*;


class tagged_update_cntrl_smoke_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[10:20]};}

		`uvm_object_utils(tagged_update_cntrl_smoke_sequence)

		function new(string name = "tagged_update_cntrl_smoke_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			bit           randomization_ok;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of smoke transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting smoke sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("transaction_%0d",txn_num + 1));

				start_item(transaction);

					case (txn_num)

						0: begin
							scenario_name = "Allocate into replaceable entry";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_ALLOCATE;
								current_conf_i   == MIN_CONFIDENCE;
								current_useful_i == MIN_USEFUL;
								new_tag_i        != current_tag_i;
								true_distance_i  != current_distance_i;
							};
						end

						1: begin
							scenario_name = "Reward with non-saturated counters";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_REWARD;
								new_tag_i        == current_tag_i;
								true_distance_i  == current_distance_i;
								current_conf_i   < MAX_CONFIDENCE;
								current_useful_i < MAX_USEFUL;
							};
						end

						2: begin
							scenario_name = "Reward with maximum-confidence saturation";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_REWARD;
								new_tag_i        == current_tag_i;
								true_distance_i  == current_distance_i;
								current_conf_i   == MAX_CONFIDENCE;
								current_useful_i < MAX_USEFUL;
							};
						end

						3: begin
							scenario_name = "Reward with maximum-usefulness saturation";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_REWARD;
								new_tag_i        == current_tag_i;
								true_distance_i  == current_distance_i;
								current_conf_i   < MAX_CONFIDENCE;
								current_useful_i == MAX_USEFUL;
							};
						end

						4: begin
							scenario_name = "Penalize with nonzero-confidence decrement";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_PENALIZE;
								current_conf_i  > MIN_CONFIDENCE;
								new_tag_i       != current_tag_i;
								true_distance_i != current_distance_i;
							};
						end

						5: begin
							scenario_name = "Penalize with zero-confidence distance replacement";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_PENALIZE;
								current_conf_i  == MIN_CONFIDENCE;
								new_tag_i       != current_tag_i;
								true_distance_i != current_distance_i;
							};
						end

						6: begin
							scenario_name = "Decay nonzero usefulness";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_DECAY;
								current_useful_i > MIN_USEFUL;
							};
						end

						7: begin
							scenario_name = "Decay usefulness already at zero";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_DECAY;
								current_useful_i == MIN_USEFUL;
							};
						end

						8: begin
							scenario_name = "Disabled DUT";

							randomization_ok = transaction.randomize() with {
								en_i == 1'b0;
							};
						end

						9: begin
							scenario_name = "Reward with both counters saturated";

							randomization_ok = transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_REWARD;
								new_tag_i        == current_tag_i;
								true_distance_i  == current_distance_i;
								current_conf_i   == MAX_CONFIDENCE;
								current_useful_i == MAX_USEFUL;
							};
						end

						default: begin
							scenario_name = "Random valid enabled transaction";

							randomization_ok = transaction.randomize() with {
								en_i == 1'b1;

								(cmd_i == transaction_t::CMD_ALLOCATE) -> {
									current_conf_i   == MIN_CONFIDENCE;
									current_useful_i == MIN_USEFUL;
								}

								(cmd_i == transaction_t::CMD_REWARD) -> {
									new_tag_i       == current_tag_i;
									true_distance_i == current_distance_i;
								}

								(cmd_i == transaction_t::CMD_PENALIZE) -> {
									new_tag_i       == current_tag_i;
									true_distance_i != current_distance_i;
								}
							};
						end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize smoke transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_SMOKE_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d smoke transactions",nbr_txn),UVM_LOW)

		endtask

endclass



//// sequence with enable control disabled fr the design
class tagged_update_cntrl_disabled_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[12:20]};}

		`uvm_object_utils(tagged_update_cntrl_disabled_sequence)

		function new(string name = "tagged_update_cntrl_disabled_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of disabled transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting disabled sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("disabled_transaction_%0d",txn_num + 1));

				start_item(transaction);

				if (!transaction.randomize() with {en_i == 1'b0;}) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize disabled transaction #%0d",txn_num + 1))
				end

				case (txn_num)

					0: begin
						scenario_name = "Disabled with random known inputs";
					end

					1: begin
						scenario_name = "Disabled with X command";
						transaction.cmd_i = transaction_t::tagged_cmd_t'(2'bxx);
					end

					2: begin
						scenario_name = "Disabled with X current confidence";
						transaction.current_conf_i = 'x;
					end

					3: begin
						scenario_name = "Disabled with X current usefulness";
						transaction.current_useful_i = 'x;
					end

					4: begin
						scenario_name = "Disabled with X current tag";
						transaction.current_tag_i = 'x;
					end

					5: begin
						scenario_name = "Disabled with X current distance";
						transaction.current_distance_i = 'x;
					end

					6: begin
						scenario_name = "Disabled with X new tag";
						transaction.new_tag_i = 'x;
					end

					7: begin
						scenario_name = "Disabled with X true distance";
						transaction.true_distance_i = 'x;
					end

					8: begin
						scenario_name = "Disabled with all upstream inputs X";
						transaction.cmd_i              = transaction_t::tagged_cmd_t'(2'bxx);
						transaction.current_conf_i     = 'x;
						transaction.current_useful_i   = 'x;
						transaction.current_tag_i      = 'x;
						transaction.current_distance_i = 'x;
						transaction.new_tag_i          = 'x;
						transaction.true_distance_i    = 'x;
					end

					9: begin
						scenario_name = "Disabled with all upstream inputs Z";
						transaction.cmd_i              = transaction_t::tagged_cmd_t'(2'bzz);
						transaction.current_conf_i     = 'z;
						transaction.current_useful_i   = 'z;
						transaction.current_tag_i      = 'z;
						transaction.current_distance_i = 'z;
						transaction.new_tag_i          = 'z;
						transaction.true_distance_i    = 'z;
					end

					default: begin
						scenario_name = "Disabled with randomized known inputs";
					end

				endcase

				`uvm_info("TAGGED_DISABLED_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d disabled transactions",nbr_txn),UVM_LOW)

		endtask

endclass


/// alllocation check sequence
class tagged_update_cntrl_allocation_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[10:20]};}

		`uvm_object_utils(tagged_update_cntrl_allocation_sequence)

		function new(string name = "tagged_update_cntrl_allocation_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			bit           randomization_ok;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of allocation transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting allocation sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("allocation_transaction_%0d",txn_num + 1));

				start_item(transaction);

				case (txn_num)

					0: begin
						scenario_name = "Allocate minimum tag and minimum distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == '0;
							true_distance_i  == '0;
							current_tag_i    == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
						};
					end

					1: begin
						scenario_name = "Allocate maximum tag and maximum distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == {TAG_WIDTH{1'b1}};
							true_distance_i  == {DISTANCE_WIDTH{1'b1}};
							current_tag_i    == '0;
							current_distance_i == '0;
						};
					end

					2: begin
						scenario_name = "Allocate minimum tag and maximum distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == '0;
							true_distance_i  == {DISTANCE_WIDTH{1'b1}};
						};
					end

					3: begin
						scenario_name = "Allocate maximum tag and minimum distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == {TAG_WIDTH{1'b1}};
							true_distance_i  == '0;
						};
					end

					4: begin
						scenario_name = "Allocate data different from current entry";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					5: begin
						scenario_name = "Allocate same tag with different distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					6: begin
						scenario_name = "Allocate different tag with same distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					7: begin
						scenario_name = "Allocate data identical to current entry";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					8: begin
						scenario_name = "Allocate tag one and distance one";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == {{(TAG_WIDTH-1){1'b0}},1'b1};
							true_distance_i  == {{(DISTANCE_WIDTH-1){1'b0}},1'b1};
						};
					end

					9: begin
						scenario_name = "Allocate maximum-minus-one tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == ({TAG_WIDTH{1'b1}} - 1'b1);
							true_distance_i  == ({DISTANCE_WIDTH{1'b1}} - 1'b1);
						};
					end

					default: begin
						scenario_name = "Random valid allocation";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
						};
					end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize allocation transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_ALLOCATION_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d allocation transactions",nbr_txn),UVM_LOW)

		endtask

endclass



/// reward sequence
class tagged_update_cntrl_reward_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[10:20]};}

		`uvm_object_utils(tagged_update_cntrl_reward_sequence)

		function new(string name = "tagged_update_cntrl_reward_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			bit           randomization_ok;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of reward transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting reward sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("reward_transaction_%0d",txn_num + 1));

				start_item(transaction);

				case (txn_num)

					0: begin
						scenario_name = "Reward minimum confidence and usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					1: begin
						scenario_name = "Reward non-saturated confidence and usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   > MIN_CONFIDENCE;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i > MIN_USEFUL;
							current_useful_i < MAX_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					2: begin
						scenario_name = "Reward with maximum-confidence saturation";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   == MAX_CONFIDENCE;
							current_useful_i < MAX_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					3: begin
						scenario_name = "Reward with maximum-usefulness saturation";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i == MAX_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					4: begin
						scenario_name = "Reward with both counters saturated";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   == MAX_CONFIDENCE;
							current_useful_i == MAX_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					5: begin
						scenario_name = "Reward confidence from maximum-minus-one to maximum";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   == (MAX_CONFIDENCE - 1'b1);
							current_useful_i < MAX_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					6: begin
						scenario_name = "Reward usefulness from maximum-minus-one to maximum";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i == (MAX_USEFUL - 1'b1);
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					7: begin
						scenario_name = "Reward minimum tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i < MAX_USEFUL;
							current_tag_i      == '0;
							current_distance_i == '0;
							new_tag_i          == current_tag_i;
							true_distance_i    == current_distance_i;
						};
					end

					8: begin
						scenario_name = "Reward maximum tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i < MAX_USEFUL;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							new_tag_i          == current_tag_i;
							true_distance_i    == current_distance_i;
						};
					end

					9: begin
						scenario_name = "Reward random data with both counters below saturation";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i < MAX_USEFUL;
							new_tag_i        == current_tag_i;
							true_distance_i  == current_distance_i;
						};
					end

					default: begin
						scenario_name = "Random valid reward";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							new_tag_i       == current_tag_i;
							true_distance_i == current_distance_i;
						};
					end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize reward transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_REWARD_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d reward transactions",nbr_txn),UVM_LOW)

		endtask

endclass



/// penalize sequence
class tagged_update_cntrl_penalize_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[10:20]};}

		`uvm_object_utils(tagged_update_cntrl_penalize_sequence)

		function new(string name = "tagged_update_cntrl_penalize_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			bit           randomization_ok;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of penalize transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting penalize sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("penalize_transaction_%0d",txn_num + 1));

				start_item(transaction);

				case (txn_num)

					0: begin
						scenario_name = "Penalize confidence from one to zero with minimum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   == 1;
							current_useful_i == MIN_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					1: begin
						scenario_name = "Penalize confidence from one to zero with maximum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   == 1;
							current_useful_i == MAX_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					2: begin
						scenario_name = "Penalize middle confidence with minimum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   > 1;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					3: begin
						scenario_name = "Penalize middle confidence with maximum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   > 1;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i == MAX_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					4: begin
						scenario_name = "Penalize maximum confidence with minimum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   == MAX_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					5: begin
						scenario_name = "Penalize maximum confidence with maximum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   == MAX_CONFIDENCE;
							current_useful_i == MAX_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					6: begin
						scenario_name = "Penalize minimum tag and minimum stored distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     > MIN_CONFIDENCE;
							current_tag_i      == '0;
							current_distance_i == '0;
							new_tag_i          != current_tag_i;
							true_distance_i    != current_distance_i;
						};
					end

					7: begin
						scenario_name = "Penalize maximum tag and maximum stored distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     > MIN_CONFIDENCE;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							new_tag_i          != current_tag_i;
							true_distance_i    != current_distance_i;
						};
					end

					8: begin
						scenario_name = "Penalize maximum-minus-one confidence";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i  == (MAX_CONFIDENCE - 1'b1);
							new_tag_i       != current_tag_i;
							true_distance_i != current_distance_i;
						};
					end

					9: begin
						scenario_name = "Penalize weak confidence";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i  == WEAK_CONFIDENCE;
							new_tag_i       != current_tag_i;
							true_distance_i != current_distance_i;
						};
					end

					default: begin
						scenario_name = "Random valid nonzero-confidence penalize";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i  > MIN_CONFIDENCE;
							new_tag_i       != current_tag_i;
							true_distance_i != current_distance_i;
						};
					end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize penalize transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_PENALIZE_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d penalize transactions",nbr_txn),UVM_LOW)

		endtask

endclass



//// zero confidence penalize 
class tagged_update_cntrl_zero_confidence_penalize_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[10:20]};}

		`uvm_object_utils(tagged_update_cntrl_zero_confidence_penalize_sequence)

		function new(string name = "tagged_update_cntrl_zero_confidence_penalize_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			bit           randomization_ok;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of zero-confidence penalize transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting zero-confidence penalize sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("zero_confidence_penalize_transaction_%0d",txn_num + 1));

				start_item(transaction);

				case (txn_num)

					0: begin
						scenario_name = "Zero-confidence penalize with minimum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					1: begin
						scenario_name = "Zero-confidence penalize with maximum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MAX_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					2: begin
						scenario_name = "Zero-confidence penalize with middle usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i > MIN_USEFUL;
							current_useful_i < MAX_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					3: begin
						scenario_name = "Zero-confidence penalize with minimum current tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     == MIN_CONFIDENCE;
							current_tag_i      == '0;
							current_distance_i == '0;
							new_tag_i          != current_tag_i;
							true_distance_i    != current_distance_i;
						};
					end

					4: begin
						scenario_name = "Zero-confidence penalize with maximum current tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     == MIN_CONFIDENCE;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							new_tag_i          != current_tag_i;
							true_distance_i    != current_distance_i;
						};
					end

					5: begin
						scenario_name = "Zero-confidence penalize with minimum new tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i  == MIN_CONFIDENCE;
							new_tag_i       == '0;
							true_distance_i == '0;
							current_tag_i      != new_tag_i;
							current_distance_i != true_distance_i;
						};
					end

					6: begin
						scenario_name = "Zero-confidence penalize with maximum new tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i  == MIN_CONFIDENCE;
							new_tag_i       == {TAG_WIDTH{1'b1}};
							true_distance_i == {DISTANCE_WIDTH{1'b1}};
							current_tag_i      != new_tag_i;
							current_distance_i != true_distance_i;
						};
					end

					7: begin
						scenario_name = "Zero-confidence penalize with minimum current and maximum new data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     == MIN_CONFIDENCE;
							current_tag_i      == '0;
							current_distance_i == '0;
							new_tag_i          == {TAG_WIDTH{1'b1}};
							true_distance_i    == {DISTANCE_WIDTH{1'b1}};
						};
					end

					8: begin
						scenario_name = "Zero-confidence penalize with maximum current and minimum new data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     == MIN_CONFIDENCE;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							new_tag_i          == '0;
							true_distance_i    == '0;
						};
					end

					9: begin
						scenario_name = "Zero-confidence penalize with random data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i  == MIN_CONFIDENCE;
							new_tag_i       != current_tag_i;
							true_distance_i != current_distance_i;
						};
					end

					default: begin
						scenario_name = "Random zero-confidence penalize";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i  == MIN_CONFIDENCE;
							new_tag_i       != current_tag_i;
							true_distance_i != current_distance_i;
						};
					end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize zero-confidence penalize transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_ZERO_CONFIDENCE_PENALIZE_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d zero-confidence penalize transactions",nbr_txn),UVM_LOW)

		endtask

endclass



/// decay sequence
class tagged_update_cntrl_decay_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[10:20]};}

		`uvm_object_utils(tagged_update_cntrl_decay_sequence)

		function new(string name = "tagged_update_cntrl_decay_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			bit           randomization_ok;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of decay transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting decay sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("decay_transaction_%0d",txn_num + 1));

				start_item(transaction);

				case (txn_num)

					0: begin
						scenario_name = "Decay zero usefulness with zero confidence";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
						};
					end

					1: begin
						scenario_name = "Decay zero usefulness with maximum confidence";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_conf_i   == MAX_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
						};
					end

					2: begin
						scenario_name = "Decay usefulness from one to zero";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_useful_i == 1;
						};
					end

					3: begin
						scenario_name = "Decay maximum usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_useful_i == MAX_USEFUL;
						};
					end

					4: begin
						scenario_name = "Decay middle usefulness";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_useful_i > 1;
							current_useful_i < MAX_USEFUL;
						};
					end

					5: begin
						scenario_name = "Decay nonzero usefulness while preserving zero confidence";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i > MIN_USEFUL;
						};
					end

					6: begin
						scenario_name = "Decay nonzero usefulness while preserving maximum confidence";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_conf_i   == MAX_CONFIDENCE;
							current_useful_i > MIN_USEFUL;
						};
					end

					7: begin
						scenario_name = "Decay minimum current tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_tag_i      == '0;
							current_distance_i == '0;
							current_useful_i   > MIN_USEFUL;
							new_tag_i          != current_tag_i;
							true_distance_i    != current_distance_i;
						};
					end

					8: begin
						scenario_name = "Decay maximum current tag and distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							current_useful_i   > MIN_USEFUL;
							new_tag_i          != current_tag_i;
							true_distance_i    != current_distance_i;
						};
					end

					9: begin
						scenario_name = "Decay while ignoring different incoming data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_useful_i > MIN_USEFUL;
							new_tag_i        != current_tag_i;
							true_distance_i  != current_distance_i;
						};
					end

					default: begin
						scenario_name = "Random valid decay";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
						};
					end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize decay transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_DECAY_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d decay transactions",nbr_txn),UVM_LOW)

		endtask

endclass


// counter sweep cases (all mixed) values
class tagged_update_cntrl_counter_sweep_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		`uvm_object_utils(tagged_update_cntrl_counter_sweep_sequence)

		function new(string name = "tagged_update_cntrl_counter_sweep_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			int unsigned  transaction_count;

			transaction_count = 0;

			`uvm_info(get_type_name(),
				$sformatf("Starting counter sweep: confidence values=%0d usefulness values=%0d commands=3",MAX_CONFIDENCE + 1,MAX_USEFUL + 1),UVM_LOW)

			for (int unsigned confidence_value = 0; confidence_value <= MAX_CONFIDENCE; confidence_value++) begin

				for (int unsigned useful_value = 0; useful_value <= MAX_USEFUL; useful_value++) begin

					// REWARD
					transaction_count++;

					transaction = transaction_t::type_id::create($sformatf("reward_conf_%0d_useful_%0d",confidence_value,useful_value));

					start_item(transaction);

					if (!transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							new_tag_i       == current_tag_i;
							true_distance_i == current_distance_i;
					}) begin
						`uvm_fatal(get_type_name(),
							$sformatf("Failed to randomize REWARD for confidence=%0d usefulness=%0d",confidence_value,useful_value))
					end

					transaction.current_conf_i   = confidence_value[CONFIDENCE_WIDTH-1:0];
					transaction.current_useful_i = useful_value[USEFUL_WIDTH-1:0];

					`uvm_info("TAGGED_COUNTER_SWEEP",
						$sformatf("Transaction #%0d: REWARD confidence=%0d usefulness=%0d",transaction_count,confidence_value,useful_value),UVM_MEDIUM)

					finish_item(transaction);

					// PENALIZE
					transaction_count++;

					transaction = transaction_t::type_id::create($sformatf("penalize_conf_%0d_useful_%0d",confidence_value,useful_value));

					start_item(transaction);

					if (!transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_PENALIZE;
								new_tag_i       != current_tag_i;
								true_distance_i != current_distance_i;
					}) begin
						`uvm_fatal(get_type_name(),
							$sformatf("Failed to randomize PENALIZE for confidence=%0d usefulness=%0d",confidence_value,useful_value))
					end

					transaction.current_conf_i   = confidence_value[CONFIDENCE_WIDTH-1:0];
					transaction.current_useful_i = useful_value[USEFUL_WIDTH-1:0];

					`uvm_info("TAGGED_COUNTER_SWEEP",
						$sformatf("Transaction #%0d: PENALIZE confidence=%0d usefulness=%0d",transaction_count,confidence_value,useful_value),UVM_MEDIUM)

					finish_item(transaction);


					// DECAY
					transaction_count++;

					transaction = transaction_t::type_id::create($sformatf("decay_conf_%0d_useful_%0d",confidence_value,useful_value));

					start_item(transaction);

					if (!transaction.randomize() with {
								en_i  == 1'b1;
								cmd_i == transaction_t::CMD_DECAY;
					}) begin
						`uvm_fatal(get_type_name(),
							$sformatf("Failed to randomize DECAY for confidence=%0d usefulness=%0d",confidence_value,useful_value))
					end

					transaction.current_conf_i   = confidence_value[CONFIDENCE_WIDTH-1:0];
					transaction.current_useful_i = useful_value[USEFUL_WIDTH-1:0];

					`uvm_info("TAGGED_COUNTER_SWEEP",
						$sformatf("Transaction #%0d: DECAY confidence=%0d usefulness=%0d",transaction_count,confidence_value,useful_value),UVM_MEDIUM)

					finish_item(transaction);

				end

			end

			`uvm_info(get_type_name(),
				$sformatf("Completed counter sweep with %0d transactions",transaction_count),UVM_LOW)

		endtask

endclass


/// daata boundary sequence
class tagged_update_cntrl_data_boundary_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		`uvm_object_utils(tagged_update_cntrl_data_boundary_sequence)

		function new(string name = "tagged_update_cntrl_data_boundary_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t                  transaction;
			bit                            randomization_ok;
			string                         scenario_name;
			logic [TAG_WIDTH-1:0]          tag_pattern_a;
			logic [TAG_WIDTH-1:0]          tag_pattern_b;
			logic [DISTANCE_WIDTH-1:0]     distance_pattern_a;
			logic [DISTANCE_WIDTH-1:0]     distance_pattern_b;

			for (int unsigned bit_index = 0; bit_index < TAG_WIDTH; bit_index++) begin
				tag_pattern_a[bit_index] = bit_index % 2;
				tag_pattern_b[bit_index] = !(bit_index % 2);
			end

			for (int unsigned bit_index = 0; bit_index < DISTANCE_WIDTH; bit_index++) begin
				distance_pattern_a[bit_index] = bit_index % 2;
				distance_pattern_b[bit_index] = !(bit_index % 2);
			end

			`uvm_info(get_type_name(),"Starting data-boundary sequence with 12 transactions",UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < 12; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("data_boundary_transaction_%0d",txn_num + 1));

				start_item(transaction);

				case (txn_num)

					0: begin
						scenario_name = "Allocate zero tag and zero distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == '0;
							true_distance_i  == '0;
						};
					end

					1: begin
						scenario_name = "Allocate maximum tag and maximum distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
							new_tag_i        == {TAG_WIDTH{1'b1}};
							true_distance_i  == {DISTANCE_WIDTH{1'b1}};
						};
					end

					2: begin
						scenario_name = "Allocate alternating tag and distance patterns";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
						};

						transaction.new_tag_i       = tag_pattern_a;
						transaction.true_distance_i = distance_pattern_a;
					end

					3: begin
						scenario_name = "Reward zero tag and zero distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i < MAX_USEFUL;
							current_tag_i      == '0;
							current_distance_i == '0;
							new_tag_i          == current_tag_i;
							true_distance_i    == current_distance_i;
						};
					end

					4: begin
						scenario_name = "Reward maximum tag and maximum distance";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i < MAX_USEFUL;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							new_tag_i          == current_tag_i;
							true_distance_i    == current_distance_i;
						};
					end

					5: begin
						scenario_name = "Reward alternating tag and distance patterns";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							current_conf_i   < MAX_CONFIDENCE;
							current_useful_i < MAX_USEFUL;
						};

						transaction.current_tag_i      = tag_pattern_a;
						transaction.new_tag_i          = tag_pattern_a;
						transaction.current_distance_i = distance_pattern_a;
						transaction.true_distance_i    = distance_pattern_a;
					end

					6: begin
						scenario_name = "Penalize zero current data with maximum incoming data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     > MIN_CONFIDENCE;
							current_tag_i      == '0;
							current_distance_i == '0;
							new_tag_i          == {TAG_WIDTH{1'b1}};
							true_distance_i    == {DISTANCE_WIDTH{1'b1}};
						};
					end

					7: begin
						scenario_name = "Penalize maximum current data with zero incoming data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i     > MIN_CONFIDENCE;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							new_tag_i          == '0;
							true_distance_i    == '0;
						};
					end

					8: begin
						scenario_name = "Penalize complementary alternating patterns";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							current_conf_i > MIN_CONFIDENCE;
						};

						transaction.current_tag_i      = tag_pattern_a;
						transaction.new_tag_i          = tag_pattern_b;
						transaction.current_distance_i = distance_pattern_a;
						transaction.true_distance_i    = distance_pattern_b;
					end

					9: begin
						scenario_name = "Decay zero current data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_tag_i      == '0;
							current_distance_i == '0;
							new_tag_i          == {TAG_WIDTH{1'b1}};
							true_distance_i    == {DISTANCE_WIDTH{1'b1}};
						};
					end

					10: begin
						scenario_name = "Decay maximum current data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
							current_tag_i      == {TAG_WIDTH{1'b1}};
							current_distance_i == {DISTANCE_WIDTH{1'b1}};
							new_tag_i          == '0;
							true_distance_i    == '0;
						};
					end

					11: begin
						scenario_name = "Decay alternating current data";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
						};

						transaction.current_tag_i      = tag_pattern_a;
						transaction.new_tag_i          = tag_pattern_b;
						transaction.current_distance_i = distance_pattern_a;
						transaction.true_distance_i    = distance_pattern_b;
					end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize data-boundary transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_DATA_BOUNDARY_SCENARIO",$sformatf("Transaction #%0d: %s",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),"Completed 12 data-boundary transactions",UVM_LOW)

		endtask

endclass


/// repeat REWARD opertion to a location
class tagged_update_cntrl_repeated_reward_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		`uvm_object_utils(tagged_update_cntrl_repeated_reward_sequence)

		function new(string name = "tagged_update_cntrl_repeated_reward_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t                  transaction;
			logic [CONFIDENCE_WIDTH-1:0]   current_confidence;
			logic [USEFUL_WIDTH-1:0]       current_usefulness;
			logic [TAG_WIDTH-1:0]          entry_tag;
			logic [DISTANCE_WIDTH-1:0]     entry_distance;
			int unsigned                   increments_needed;
			int unsigned                   nbr_txn;

			current_confidence = MIN_CONFIDENCE;
			current_usefulness = MIN_USEFUL;

			if (!std::randomize(entry_tag,entry_distance)) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the repeated-reward entry data")
			end

			increments_needed = (MAX_CONFIDENCE > MAX_USEFUL) ? MAX_CONFIDENCE : MAX_USEFUL;
			nbr_txn           = increments_needed + 2;

			`uvm_info(get_type_name(),
				$sformatf("Starting repeated reward sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("repeated_reward_transaction_%0d",txn_num + 1));

				start_item(transaction);

				if (!transaction.randomize() with {
					en_i  == 1'b1;
					cmd_i == transaction_t::CMD_REWARD;
				}) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize repeated reward transaction #%0d",txn_num + 1))
				end

				transaction.current_conf_i     = current_confidence;
				transaction.current_useful_i   = current_usefulness;
				transaction.current_tag_i      = entry_tag;
				transaction.new_tag_i          = entry_tag;
				transaction.current_distance_i = entry_distance;
				transaction.true_distance_i    = entry_distance;

				`uvm_info("TAGGED_REPEATED_REWARD",
					$sformatf("Transaction #%0d: current confidence=%0d current usefulness=%0d",txn_num + 1,current_confidence,current_usefulness),UVM_LOW)

				finish_item(transaction);

				if (current_confidence < MAX_CONFIDENCE) begin
					current_confidence++;
				end

				if (current_usefulness < MAX_USEFUL) begin
					current_usefulness++;
				end

			end

			`uvm_info(get_type_name(),
				$sformatf("Completed repeated reward sequence: final confidence=%0d final usefulness=%0d",current_confidence,current_usefulness),UVM_LOW)

		endtask

endclass


///// peanlize repeatdily and then put a replacement option and lets see.
class tagged_update_cntrl_repeated_penalize_n_allocate_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		`uvm_object_utils(tagged_update_cntrl_repeated_penalize_n_allocate_sequence)

		function new(string name = "tagged_update_cntrl_repeated_penalize_n_allocate_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t                  transaction;
			logic [CONFIDENCE_WIDTH-1:0]   current_confidence;
			logic [USEFUL_WIDTH-1:0]       current_usefulness;
			logic [TAG_WIDTH-1:0]          current_tag;
			logic [DISTANCE_WIDTH-1:0]     current_distance;
			logic [TAG_WIDTH-1:0]          replacement_tag;
			logic [DISTANCE_WIDTH-1:0]     replacement_distance;
			int unsigned                   nbr_penalize_txn;
			int unsigned                   transaction_count;

			current_confidence = MAX_CONFIDENCE;
			current_usefulness = MIN_USEFUL;
			transaction_count  = 0;
			nbr_penalize_txn   = MAX_CONFIDENCE + 1;

			if (!std::randomize(current_tag,current_distance,replacement_tag,replacement_distance) with {
				replacement_tag      != current_tag;
				replacement_distance != current_distance;
			}) begin
				`uvm_fatal(get_type_name(),"Failed to randomize repeated-penalize entry data")
			end

			`uvm_info(get_type_name(),
				$sformatf("Starting repeated penalize sequence with %0d penalize transactions followed by replacement",nbr_penalize_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_penalize_txn; txn_num++) begin

				transaction_count++;

				transaction = transaction_t::type_id::create($sformatf("repeated_penalize_transaction_%0d",txn_num + 1));

				start_item(transaction);

				if (!transaction.randomize() with {
					en_i  == 1'b1;
					cmd_i == transaction_t::CMD_PENALIZE;
				}) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize repeated penalize transaction #%0d",txn_num + 1))
				end

				transaction.current_conf_i     = current_confidence;
				transaction.current_useful_i   = current_usefulness;
				transaction.current_tag_i      = current_tag;
				transaction.current_distance_i = current_distance;
				transaction.new_tag_i          = replacement_tag;
				transaction.true_distance_i    = replacement_distance;

				`uvm_info("TAGGED_REPEATED_PENALIZE",
					$sformatf("Transaction #%0d: PENALIZE current confidence=%0d current usefulness=%0d",transaction_count,current_confidence,current_usefulness),UVM_LOW)

				finish_item(transaction);

				if (current_confidence > MIN_CONFIDENCE) begin
					current_confidence--;
				end

			end

			// The target now has zero confidence and zero usefulness.Will do an ALLOCATION on the location.
			transaction_count++;

			transaction = transaction_t::type_id::create("replacement_allocation_transaction");

			start_item(transaction);

			if (!transaction.randomize() with {
				en_i  == 1'b1;
				cmd_i == transaction_t::CMD_ALLOCATE;
			}) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the replacement allocation transaction")
			end

			transaction.current_conf_i     = current_confidence;
			transaction.current_useful_i   = current_usefulness;
			transaction.current_tag_i      = current_tag;
			transaction.current_distance_i = current_distance;
			transaction.new_tag_i          = replacement_tag;
			transaction.true_distance_i    = replacement_distance;

			`uvm_info("TAGGED_REPEATED_PENALIZE",
				$sformatf("Transaction #%0d: ALLOCATE replacement tag=0x%0h replacement distance=0x%0h",transaction_count,replacement_tag,replacement_distance),UVM_LOW)

			finish_item(transaction);

			// Update the local state to represent the newly allocated entry.
			current_confidence = WEAK_CONFIDENCE;
			current_usefulness = INITIAL_USEFUL;
			current_tag        = replacement_tag;
			current_distance   = replacement_distance;

			`uvm_info(get_type_name(),
				$sformatf("Completed repeated penalize sequence: replacement tag=0x%0h distance=0x%0h confidence=%0d usefulness=%0d",current_tag,current_distance,current_confidence,current_usefulness),UVM_LOW)

		endtask

endclass


//// Allocate -> reward --> penalize
class tagged_update_cntrl_allocate_reward_penalize_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		`uvm_object_utils(tagged_update_cntrl_allocate_reward_penalize_sequence)

		function new(string name = "tagged_update_cntrl_allocate_reward_penalize_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t                  transaction;
			logic [CONFIDENCE_WIDTH-1:0]   current_confidence;
			logic [USEFUL_WIDTH-1:0]       current_usefulness;
			logic [TAG_WIDTH-1:0]          current_tag;
			logic [DISTANCE_WIDTH-1:0]     current_distance;
			logic [TAG_WIDTH-1:0]          allocated_tag;
			logic [DISTANCE_WIDTH-1:0]     allocated_distance;
			logic [TAG_WIDTH-1:0]          penalize_new_tag;
			logic [DISTANCE_WIDTH-1:0]     penalize_true_distance;
			int unsigned                   nbr_rewards;
			int unsigned                   transaction_count;

			nbr_rewards       = 10;
			transaction_count = 0;

			if (!std::randomize(current_tag,current_distance,allocated_tag,allocated_distance,
								penalize_new_tag,penalize_true_distance) with {
				allocated_tag          != current_tag;
				allocated_distance     != current_distance;
				penalize_new_tag       != allocated_tag;
				penalize_true_distance != allocated_distance;
			}) begin
				`uvm_fatal(get_type_name(),"Failed to randomize allocate-reward-penalize entry data")
			end

			current_confidence = MIN_CONFIDENCE;
			current_usefulness = MIN_USEFUL;

			`uvm_info(get_type_name(),"Starting ALLOCATE -> REWARD -> PENALIZE sequence",UVM_LOW)


			/// allocate
			transaction = transaction_t::type_id::create("allocate_transaction");

			start_item(transaction);

				if (!transaction.randomize() with {
					en_i  == 1'b1;
					cmd_i == transaction_t::CMD_ALLOCATE;
				}) begin
					`uvm_fatal(get_type_name(),"Failed to randomize ALLOCATE transaction")
				end

				transaction.current_conf_i     = current_confidence;
				transaction.current_useful_i   = current_usefulness;
				transaction.current_tag_i      = current_tag;
				transaction.current_distance_i = current_distance;
				transaction.new_tag_i          = allocated_tag;
				transaction.true_distance_i    = allocated_distance;

				`uvm_info("TAGGED_COMMAND_COMBINATION",
					$sformatf("Transaction #1: ALLOCATE tag=0x%0h distance=0x%0h",allocated_tag,allocated_distance),UVM_LOW)

			finish_item(transaction);

			current_confidence = WEAK_CONFIDENCE;
			current_usefulness = INITIAL_USEFUL;
			current_tag        = allocated_tag;
			current_distance   = allocated_distance;


			/// reward
			for (int unsigned reward_num = 0; reward_num < nbr_rewards; reward_num++) begin
				transaction_count++;
				transaction = transaction_t::type_id::create("reward_transaction");

				start_item(transaction);

					if (!transaction.randomize() with {
						en_i  == 1'b1;
						cmd_i == transaction_t::CMD_REWARD;
					}) begin
						`uvm_fatal(get_type_name(),"Failed to randomize REWARD transaction")
					end

					transaction.current_conf_i     = current_confidence;
					transaction.current_useful_i   = current_usefulness;
					transaction.current_tag_i      = current_tag;
					transaction.current_distance_i = current_distance;
					transaction.new_tag_i          = current_tag;
					transaction.true_distance_i    = current_distance;

					`uvm_info("TAGGED_COMMAND_COMBINATION",
						$sformatf("Transaction #2: REWARD confidence=%0d usefulness=%0d",current_confidence,current_usefulness),UVM_LOW)

				finish_item(transaction);

				if (current_confidence < MAX_CONFIDENCE) begin
					current_confidence++;
				end

				if (current_usefulness < MAX_USEFUL) begin
					current_usefulness++;
				end
			end


			/// penalize
			transaction = transaction_t::type_id::create("penalize_transaction");

			start_item(transaction);

				if (!transaction.randomize() with {
					en_i  == 1'b1;
					cmd_i == transaction_t::CMD_PENALIZE;
				}) begin
					`uvm_fatal(get_type_name(),"Failed to randomize PENALIZE transaction")
				end

				transaction.current_conf_i     = current_confidence;
				transaction.current_useful_i   = current_usefulness;
				transaction.current_tag_i      = current_tag;
				transaction.current_distance_i = current_distance;
				transaction.new_tag_i          = penalize_new_tag;
				transaction.true_distance_i    = penalize_true_distance;

				`uvm_info("TAGGED_COMMAND_COMBINATION",
					$sformatf("Transaction #3: PENALIZE confidence=%0d usefulness=%0d incoming_tag=0x%0h incoming_distance=0x%0h",current_confidence,current_usefulness,penalize_new_tag,penalize_true_distance),UVM_LOW)

			finish_item(transaction);

			if (current_confidence > MIN_CONFIDENCE) begin
				current_confidence--;
			end

			`uvm_info(get_type_name(),
				$sformatf("Completed combination: final tag=0x%0h distance=0x%0h confidence=%0d usefulness=%0d",current_tag,current_distance,current_confidence,current_usefulness),UVM_LOW)

		endtask

endclass



/// random valid transaction
class tagged_update_cntrl_random_valid_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		rand int unsigned nbr_txn;

		constraint nbr_txn_c {nbr_txn inside {[50:100]};}

		`uvm_object_utils(tagged_update_cntrl_random_valid_sequence)

		function new(string name = "tagged_update_cntrl_random_valid_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			bit           randomization_ok;
			string        scenario_name;

			if (!this.randomize()) begin
				`uvm_fatal(get_type_name(),"Failed to randomize the number of random-valid transactions")
			end

			`uvm_info(get_type_name(),$sformatf("Starting random-valid sequence with %0d transactions",nbr_txn),UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < nbr_txn; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("random_valid_transaction_%0d",txn_num + 1));

				start_item(transaction);

				case (txn_num)

					0: begin
						scenario_name = "Guaranteed random allocation";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_ALLOCATE;
							current_conf_i   == MIN_CONFIDENCE;
							current_useful_i == MIN_USEFUL;
						};
					end

					1: begin
						scenario_name = "Guaranteed random reward";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_REWARD;
							new_tag_i       == current_tag_i;
							true_distance_i == current_distance_i;
						};
					end

					2: begin
						scenario_name = "Guaranteed random penalize";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_PENALIZE;
							new_tag_i       != current_tag_i;
							true_distance_i != current_distance_i;
						};
					end

					3: begin
						scenario_name = "Guaranteed random decay";

						randomization_ok = transaction.randomize() with {
							en_i  == 1'b1;
							cmd_i == transaction_t::CMD_DECAY;
						};
					end

					4: begin
						scenario_name = "Guaranteed random disabled transaction";

						randomization_ok = transaction.randomize() with {
							en_i == 1'b0;
						};
					end

					default: begin
						scenario_name = "Random valid transaction";

						randomization_ok = transaction.randomize() with {
							en_i dist {1'b1 := 9,1'b0 := 1};

							((en_i == 1'b1) && (cmd_i == transaction_t::CMD_ALLOCATE)) -> {
								current_conf_i   == MIN_CONFIDENCE;
								current_useful_i == MIN_USEFUL;
							}

							((en_i == 1'b1) && (cmd_i == transaction_t::CMD_REWARD)) -> {
								new_tag_i       == current_tag_i;
								true_distance_i == current_distance_i;
							}

							((en_i == 1'b1) && (cmd_i == transaction_t::CMD_PENALIZE)) -> {
								new_tag_i       != current_tag_i;
								true_distance_i != current_distance_i;
							}
						};
					end

				endcase

				if (!randomization_ok) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize random-valid transaction #%0d",txn_num + 1))
				end

				`uvm_info("TAGGED_RANDOM_VALID_SCENARIO",
					$sformatf("Transaction #%0d: %s en=%0b cmd=%s",
						txn_num + 1,scenario_name,transaction.en_i,transaction.cmd_i.name()),
					UVM_MEDIUM
				)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),$sformatf("Completed %0d random-valid transactions",nbr_txn),UVM_LOW)

		endtask

endclass



/// invalid protocol seqeunce
class tagged_update_cntrl_invalid_protocol_sequence extends uvm_sequence #(tagged_update_cntrl_transaction);

		typedef tagged_update_cntrl_transaction transaction_t;

		`uvm_object_utils(tagged_update_cntrl_invalid_protocol_sequence)

		function new(string name = "tagged_update_cntrl_invalid_protocol_sequence");
			super.new(name);
		endfunction

		virtual task body();

			transaction_t transaction;
			string        scenario_name;

			`uvm_info(get_type_name(),
				"Starting invalid-protocol sequence; scoreboard errors are expected",UVM_LOW)

			for (int unsigned txn_num = 0; txn_num < 15; txn_num++) begin

				transaction = transaction_t::type_id::create($sformatf("invalid_protocol_transaction_%0d",txn_num + 1));

				start_item(transaction);

				if (!transaction.randomize()) begin
					`uvm_fatal(get_type_name(),$sformatf("Failed to randomize invalid-protocol transaction #%0d",txn_num + 1))
				end

				transaction.en_i = 1'b1;

				case (txn_num)

					0: begin
						scenario_name = "ALLOCATE with nonzero confidence";
						transaction.cmd_i            = transaction_t::CMD_ALLOCATE;
						transaction.current_conf_i   = 1;
						transaction.current_useful_i = MIN_USEFUL;
					end

					1: begin
						scenario_name = "ALLOCATE with nonzero usefulness";
						transaction.cmd_i            = transaction_t::CMD_ALLOCATE;
						transaction.current_conf_i   = MIN_CONFIDENCE;
						transaction.current_useful_i = 1;
					end

					2: begin
						scenario_name = "REWARD with different tags";
						transaction.cmd_i             = transaction_t::CMD_REWARD;
						transaction.new_tag_i         = transaction.current_tag_i + 1'b1;
						transaction.true_distance_i   = transaction.current_distance_i;
					end

					3: begin
						scenario_name = "REWARD with different distances";
						transaction.cmd_i             = transaction_t::CMD_REWARD;
						transaction.new_tag_i         = transaction.current_tag_i;
						transaction.true_distance_i   = transaction.current_distance_i + 1'b1;
					end

					4: begin
						scenario_name = "REWARD with different tags and distances";
						transaction.cmd_i             = transaction_t::CMD_REWARD;
						transaction.new_tag_i         = transaction.current_tag_i + 1'b1;
						transaction.true_distance_i   = transaction.current_distance_i + 1'b1;
					end

					5: begin
						scenario_name = "PENALIZE with identical tags";
						transaction.cmd_i             = transaction_t::CMD_PENALIZE;
						transaction.new_tag_i         = transaction.current_tag_i;
						transaction.true_distance_i   = transaction.current_distance_i + 1'b1;
					end

					6: begin
						scenario_name = "PENALIZE with identical distances";
						transaction.cmd_i             = transaction_t::CMD_PENALIZE;
						transaction.new_tag_i         = transaction.current_tag_i + 1'b1;
						transaction.true_distance_i   = transaction.current_distance_i;
					end

					7: begin
						scenario_name = "PENALIZE with identical tags and distances";
						transaction.cmd_i             = transaction_t::CMD_PENALIZE;
						transaction.new_tag_i         = transaction.current_tag_i;
						transaction.true_distance_i   = transaction.current_distance_i;
					end

					8: begin
						scenario_name = "Unknown command while enabled";
						transaction.cmd_i = transaction_t::tagged_cmd_t'(2'bxx);
					end

					9: begin
						scenario_name = "ALLOCATE with unknown new tag";
						transaction.cmd_i            = transaction_t::CMD_ALLOCATE;
						transaction.current_conf_i   = MIN_CONFIDENCE;
						transaction.current_useful_i = MIN_USEFUL;
						transaction.new_tag_i        = 'x;
					end

					10: begin
						scenario_name = "REWARD with unknown current tag";
						transaction.cmd_i             = transaction_t::CMD_REWARD;
						transaction.current_tag_i     = 'x;
						transaction.new_tag_i         = 'x;
						transaction.true_distance_i   = transaction.current_distance_i;
					end

					11: begin
						scenario_name = "PENALIZE with unknown new tag";
						transaction.cmd_i             = transaction_t::CMD_PENALIZE;
						transaction.new_tag_i         = 'x;
						transaction.true_distance_i   = transaction.current_distance_i + 1'b1;
					end

					12: begin
						scenario_name = "DECAY with unknown current usefulness";
						transaction.cmd_i            = transaction_t::CMD_DECAY;
						transaction.current_useful_i = 'x;
					end

					13: begin
						scenario_name = "Unknown enable";
						transaction.en_i = 1'bx;
					end

					14: begin
						scenario_name = "High-impedance enable";
						transaction.en_i = 1'bz;
					end

				endcase

				`uvm_info("TAGGED_INVALID_PROTOCOL_SCENARIO",
					$sformatf("Transaction #%0d: %s; an error is expected",txn_num + 1,scenario_name),UVM_LOW)

				finish_item(transaction);

			end

			`uvm_info(get_type_name(),
				"Completed 15 invalid-protocol transactions; scoreboard errors were expected",UVM_LOW)

		endtask

endclass