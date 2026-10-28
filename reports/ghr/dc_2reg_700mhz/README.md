# Design Compiler 700 MHz result summary

The original Design Compiler reports were generated in the server analysis workspace under reports/synthesis_2reg_700mhz. This repository records the key results and report inventory; the matching constraint and run script are versioned under constraints/ghr and scripts/ghr.

## Results

| Metric | Result |
|---|---:|
| Clock period | 1428.571 ps |
| Critical path | head_ptr_reg_1_ to expiring_packet_o_reg_reg_2__6_ |
| Critical-path arrival | 1374.0166 ps |
| Critical-path slack | +42.0078 ps |
| Worst hold slack | +11.9252 ps |
| Logic levels | 30 |
| Leaf cells | 2682 |
| Combinational cells | 2350 |
| Sequential cells | 332 |
| Cell area | 5014.586888 |
| Estimated power | 0.303 mW |
| Setup violations | 0 |
| Hold violations | 0 |
| Direct input-to-output paths | 0 |

The max_leakage_power entry in report_constraint was produced because the required leakage limit was zero; it is not a setup or hold failure.

## Generated report inventory

- LP_ghr_block_2reg_pre_compile_check.rpt
- LP_ghr_block_2reg_post_compile_check.rpt
- LP_ghr_block_2reg_check_timing.rpt
- LP_ghr_block_2reg_all_violators.rpt
- LP_ghr_block_2reg_timing.rpt
- LP_ghr_block_2reg_hold_timing.rpt
- LP_ghr_block_2reg_input_to_register.rpt
- LP_ghr_block_2reg_register_to_register.rpt
- LP_ghr_block_2reg_register_to_output.rpt
- LP_ghr_block_2reg_input_to_output_comb.rpt
- LP_ghr_block_2reg_input_to_output_comb_count.rpt
- LP_ghr_block_2reg_qor.rpt
- LP_ghr_block_2reg_area.rpt
- LP_ghr_block_2reg_power_estimate.rpt
- LP_ghr_block_2reg_references.rpt