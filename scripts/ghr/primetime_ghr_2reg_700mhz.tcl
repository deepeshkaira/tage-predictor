set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ../..]]

puts "PrimeTime project root: $project_root"

set design_name LP_ghr_block_2reg
set netlist_file [file join $project_root netlist LP_ghr_block_2reg_700mhz.v]
set sdc_file [file join $project_root netlist LP_ghr_block_2reg_700mhz.sdc]
set library_dir [file join $project_root lib asap7_db]
set report_dir [file join $project_root reports primetime_2reg_700mhz]

if {![file readable $netlist_file]} {error "Cannot read netlist: $netlist_file"}
if {![file readable $sdc_file]} {error "Cannot read SDC: $sdc_file"}

file mkdir $report_dir

set_app_var search_path [concat $search_path [list \
    $library_dir \
    [file join $project_root netlist] \
]]

set_app_var link_path [list \
    "*" \
    [file join $library_dir asap7sc7p5t_AO_RVT_TT_08302018.db] \
    [file join $library_dir asap7sc7p5t_INVBUF_RVT_TT_08302018.db] \
    [file join $library_dir asap7sc7p5t_OA_RVT_TT_08302018.db] \
    [file join $library_dir asap7sc7p5t_SEQ_RVT_TT_08302018.db] \
    [file join $library_dir asap7sc7p5t_SIMPLE_RVT_TT_08302018.db] \
]

read_verilog $netlist_file
link_design $design_name
current_design $design_name
read_sdc $sdc_file

set clock_count [sizeof_collection [get_clocks -quiet clk]]

if {$clock_count != 1} {
    error "Expected one clock named clk, but found $clock_count"
}

puts "Clock clk successfully created."

redirect -file [file join $report_dir LP_ghr_block_2reg_check_timing.rpt] {check_timing -verbose}
redirect -file [file join $report_dir LP_ghr_block_2reg_units.rpt] {report_units}
redirect -file [file join $report_dir LP_ghr_block_2reg_clocks.rpt] {report_clocks}

update_timing

set reg_start_pins [all_registers -clock_pins]
set reg_end_pins [all_registers -data_pins]

redirect -file [file join $report_dir LP_ghr_block_2reg_all_reg_to_reg.rpt] {
    report_timing -from $reg_start_pins -to $reg_end_pins -delay_type max -path_type full_clock_expanded -start_end_pair -nworst 1 -max_paths 100000 -slack_lesser_than 1000000 -nosplit
}

redirect -file [file join $report_dir LP_ghr_block_2reg_reg_to_reg_summary.rpt] {
    report_timing -from $reg_start_pins -to $reg_end_pins -delay_type max -path_type summary -start_end_pair -nworst 1 -max_paths 100000 -slack_lesser_than 1000000
}

redirect -file [file join $report_dir LP_ghr_block_2reg_untested_checks.rpt] {
    report_analysis_coverage -status_details untested
}

redirect -file [file join $report_dir LP_ghr_block_2reg_disabled_timing.rpt] {
    report_disable_timing
}

redirect -file [file join $report_dir LP_ghr_block_2reg_analysis_coverage.rpt] {
    report_analysis_coverage
}

redirect -file [file join $report_dir LP_ghr_block_2reg_global_timing.rpt] {
    report_global_timing
}

redirect -file [file join $report_dir LP_ghr_block_2reg_all_violators.rpt] {
    report_constraint -all_violators -verbose
}

set functional_inputs [get_ports {
    en_i
    br_valid_i
    br_packet_i[*]
    misprediction_i
    mispredicted_table_depth_i[*]
    recovery_active_i
}]

set functional_outputs [get_ports {
    incoming_packet_o[*]
    expiring_packet_o*
    output_valid_o
}]

redirect -file [file join $report_dir LP_ghr_block_2reg_setup_timing.rpt] {
    report_timing \
        -delay_type max \
        -path_type full_clock_expanded \
        -max_paths 20 \
        -nworst 5 \
        -slack_lesser_than 1000000 \
        -input_pins \
        -nets \
        -transition_time \
        -capacitance \
        -significant_digits 4 \
        -nosplit
}

redirect -file [file join $report_dir LP_ghr_block_2reg_hold_timing.rpt] {
    report_timing \
        -delay_type min \
        -path_type full_clock_expanded \
        -max_paths 20 \
        -nworst 5 \
        -slack_lesser_than 1000000 \
        -input_pins \
        -nets \
        -transition_time \
        -capacitance \
        -significant_digits 4 \
        -nosplit
}

redirect -file [file join $report_dir LP_ghr_block_2reg_input_to_register.rpt] {
    report_timing \
        -from $functional_inputs \
        -to [all_registers -data_pins] \
        -delay_type max \
        -path_type full_clock_expanded \
        -max_paths 50 \
        -nworst 10 \
        -slack_lesser_than 1000000 \
        -input_pins \
        -nets \
        -transition_time \
        -capacitance \
        -significant_digits 4 \
        -nosplit
}

redirect -file [file join $report_dir LP_ghr_block_2reg_register_to_register.rpt] {
    report_timing \
        -from [all_registers -clock_pins] \
        -to [all_registers -data_pins] \
        -delay_type max \
        -path_type full_clock_expanded \
        -max_paths 50 \
        -nworst 10 \
        -slack_lesser_than 1000000 \
        -input_pins \
        -nets \
        -transition_time \
        -capacitance \
        -significant_digits 4 \
        -nosplit
}

redirect -file [file join $report_dir LP_ghr_block_2reg_register_to_output.rpt] {
    report_timing \
        -from [all_registers -clock_pins] \
        -to $functional_outputs \
        -delay_type max \
        -path_type full_clock_expanded \
        -max_paths 50 \
        -nworst 10 \
        -slack_lesser_than 1000000 \
        -input_pins \
        -nets \
        -transition_time \
        -capacitance \
        -significant_digits 4 \
        -nosplit
}

redirect -file [file join $report_dir LP_ghr_block_2reg_input_to_output_comb.rpt] {
    report_timing \
        -from $functional_inputs \
        -to $functional_outputs \
        -delay_type max \
        -path_type full \
        -max_paths 10000 \
        -nworst 100 \
        -slack_lesser_than 1000000 \
        -significant_digits 4 \
        -nosplit
}

set comb_paths [get_timing_paths \
    -from $functional_inputs \
    -to $functional_outputs \
    -delay_type max \
    -max_paths 10000]

redirect -file [file join $report_dir LP_ghr_block_2reg_input_to_output_comb_count.rpt] {
    echo "Functional input count = [sizeof_collection $functional_inputs]"
    echo "Functional output count = [sizeof_collection $functional_outputs]"
    echo "Direct input-to-output path count = [sizeof_collection $comb_paths]"
}

set head_ptr_launch_pins [filter_collection [all_registers -clock_pins] {full_name =~ *head_ptr_reg*}]
set expiring_capture_pins [filter_collection [all_registers -data_pins] {full_name =~ *expiring_packet_o_reg*}]

set head_ptr_launch_count [sizeof_collection $head_ptr_launch_pins]
set expiring_capture_count [sizeof_collection $expiring_capture_pins]

redirect -file [file join $report_dir LP_ghr_block_2reg_head_ptr_to_expiring_detailed.rpt] {
    echo "Head-pointer launch-pin count = $head_ptr_launch_count"
    echo "Expiring-packet capture-pin count = $expiring_capture_count"

    if {$head_ptr_launch_count > 0 && $expiring_capture_count > 0} {
        report_timing \
            -from $head_ptr_launch_pins \
            -to $expiring_capture_pins \
            -delay_type max \
            -path_type full_clock_expanded \
            -max_paths 50 \
            -nworst 10 \
            -slack_lesser_than 1000000 \
            -input_pins \
            -nets \
            -transition_time \
            -capacitance \
            -significant_digits 4 \
            -nosplit
    } else {
        echo "Critical-path registers were not found. Check synthesized register names."
    }
}

exit

