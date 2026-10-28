set_app_var search_path [concat $search_path [list ./rtl ./constraints ./lib/asap7_db]]

set_app_var target_library [list \
    asap7sc7p5t_AO_RVT_TT_08302018.db \
    asap7sc7p5t_INVBUF_RVT_TT_08302018.db \
    asap7sc7p5t_OA_RVT_TT_08302018.db \
    asap7sc7p5t_SEQ_RVT_TT_08302018.db \
    asap7sc7p5t_SIMPLE_RVT_TT_08302018.db \
]

set_app_var link_library [concat "*" $target_library]

file mkdir netlist
file mkdir reports/synthesis_2reg_700mhz

analyze -format sverilog [list \
    {Verification/Verification Block Level/GHR_2reg/get_bank.sv} \
    {Verification/Verification Block Level/GHR_2reg/get_row.sv} \
    {Verification/Verification Block Level/GHR_2reg/1_LP_Global_Histroy_register_2reg.sv} \
]

elaborate LP_ghr_block_2reg
current_design LP_ghr_block_2reg
link

check_design  > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_pre_compile_check.rpt

read_sdc constraints/ghr/LP_ghr_block_2reg_700mhz.sdc

set_fix_multiple_port_nets -all -buffer_constants

compile_ultra

check_design > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_post_compile_check.rpt

check_timing > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_check_timing.rpt

report_constraint -all_violators > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_all_violators.rpt

change_names -rules verilog -hierarchy

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

report_timing \
    -from $functional_inputs \
    -to $functional_outputs \
    -delay max \
    -path full \
    -start_end_pair \
    -nworst 100 \
    -max_paths 10000 \
    -significant_digits 4 \
    -nosplit \
    > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_input_to_output_comb.rpt

set input_to_output_paths [get_timing_paths \
    -from $functional_inputs \
    -to $functional_outputs \
    -delay_type max \
    -max_paths 10000]

set input_to_output_path_count [sizeof_collection $input_to_output_paths]

redirect reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_input_to_output_comb_count.rpt {
    echo "Pure input-to-output combinational path count = $input_to_output_path_count"
}

# Overall worst timing paths.
report_timing \
    -path full \
    -delay max \
    -nworst 10 \
    -max_paths 50 \
    -nosplit \
    > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_timing.rpt


# Input-to-register timing paths.
# This includes paths ending at the newly inserted target_index registers.
report_timing \
    -from [get_ports {
        en_i
        br_valid_i
        br_packet_i[*]
        misprediction_i
        mispredicted_table_depth_i[*]
        recovery_active_i
    }] \
    -to [all_registers -data_pins] \
    -path full \
    -delay max \
    -nworst 10 \
    -max_paths 100 \
    -nosplit \
    > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_input_to_register.rpt


#reg to reg timing path
report_timing \
    -from [all_registers -output_pins] \
    -to [all_registers -data_pins] \
    -path full \
    -delay max \
    -nworst 10 \
    -max_paths 100 \
    -significant_digits 4 \
    -nosplit \
    > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_register_to_register.rpt


# Register-to-output timing paths.
# This includes target_index register through get_bank/get_row and the bank-memory selection logic to expiring_packet_o.
report_timing \
    -from [all_registers -output_pins] \
    -to [get_ports {
        incoming_packet_o[*]
        expiring_packet_o*
        output_valid_o
    }] \
    -path full \
    -delay max \
    -nworst 10 \
    -max_paths 100 \
    -nosplit \
    > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_register_to_output.rpt


# Direct input-to-output paths.
# The original long misprediction-depth-to-expiring-packet path should no longer exist after the target_index register insertion.
report_timing \
    -from [get_ports {
        en_i
        br_valid_i
        br_packet_i[*]
        misprediction_i
        mispredicted_table_depth_i[*]
        recovery_active_i
    }] \
    -to [get_ports {
        incoming_packet_o[*]
        expiring_packet_o*
        output_valid_o
    }] \
    -path full \
    -delay max \
    -start_end_pair \
    -nworst 17 \
    -max_paths 2000 \
    -nosplit \
    > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_input_to_output_timing.rpt


# hold/min-delay report
report_timing \
    -path full \
    -delay min \
    -nworst 10 \
    -max_paths 50 \
    -significant_digits 4 \
    -nosplit \
    > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_hold_timing.rpt


report_qor > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_qor.rpt

report_area -hierarchy > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_area.rpt

report_power -hierarchy > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_power_estimate.rpt

report_reference -hierarchy > reports/synthesis_2reg_700mhz/LP_ghr_block_2reg_references.rpt


write -format ddc \
    -hierarchy \
    -output netlist/LP_ghr_block_2reg_700mhz.ddc

write -format verilog \
    -hierarchy \
    -output netlist/LP_ghr_block_2reg_700mhz.v

write_sdc netlist/LP_ghr_block_2reg_700mhz.sdc

exit



