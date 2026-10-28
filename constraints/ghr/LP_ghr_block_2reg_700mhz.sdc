set CLOCK_PERIOD 1428.571
set INPUT_DELAY [expr 0.60 * $CLOCK_PERIOD]
set OUTPUT_DELAY [expr 0.40 * $CLOCK_PERIOD]
set CLOCK_HALF_PERIOD [expr 0.50 * $CLOCK_PERIOD]

create_clock -name clk -period $CLOCK_PERIOD -waveform [list 0 $CLOCK_HALF_PERIOD] [get_ports clk]
set_clock_transition 20.000 [get_clocks clk]

set functional_inputs [get_ports {en_i br_valid_i br_packet_i[*] misprediction_i mispredicted_table_depth_i[*] recovery_active_i}]
set functional_outputs [get_ports {incoming_packet_o[*] expiring_packet_o* output_valid_o}]

set_input_delay -max $INPUT_DELAY -clock [get_clocks clk] $functional_inputs
set_input_delay -min 0.000 -clock [get_clocks clk] $functional_inputs
set_output_delay -max $OUTPUT_DELAY -clock [get_clocks clk] $functional_outputs
set_output_delay -min 0.000 -clock [get_clocks clk] $functional_outputs

set_input_transition 50.000 $functional_inputs
set_load 5.000 $functional_outputs

# rst_n is an asynchronous reset and is excluded from synchronous data-path timing.
set_false_path -from [get_ports rst_n]
