# Post-compile cell-sizing ECOs accepted during the 700 MHz GHR timing study.
# Source this file after compile_ultra and before final timing/area reports.

proc require_cell {cell_name} {
    set cell [get_cells -quiet $cell_name]
    if {[sizeof_collection $cell] != 1} {
        error "Expected exactly one mapped cell named $cell_name; the synthesis mapping has changed"
    }
    return $cell
}

proc require_lib_cell {lib_cell_name} {
    set lib_cell [get_lib_cells -quiet $lib_cell_name]
    if {[sizeof_collection $lib_cell] != 1} {
        error "Required library cell is unavailable: $lib_cell_name"
    }
    return $lib_cell
}

proc apply_size_eco {cell_name lib_cell_name} {
    set cell [require_cell $cell_name]
    set lib_cell [require_lib_cell $lib_cell_name]
    size_cell $cell $lib_cell
    puts "CELL_SIZE_ECO: $cell_name -> [get_attribute $cell ref_name]"
}

# High-fanout bank/row decode branch investigated before the U3908 path.
apply_size_eco U4278 asap7sc7p5t_SIMPLE_RVT_TT_08302018/NAND2x1_ASAP7_75t_R

# head_ptr_reg[1] to expiring_packet_o_reg[0][0] path through U3908.
apply_size_eco U3908 asap7sc7p5t_SIMPLE_RVT_TT_08302018/NAND2x1p5_ASAP7_75t_R
apply_size_eco U3733 asap7sc7p5t_SIMPLE_RVT_TT_08302018/NOR2xp67_ASAP7_75t_R
apply_size_eco U3734 asap7sc7p5t_OA_RVT_TT_08302018/OAI21x1_ASAP7_75t_R
apply_size_eco U3726 asap7sc7p5t_SIMPLE_RVT_TT_08302018/NOR2xp67_ASAP7_75t_R
apply_size_eco U2467 asap7sc7p5t_SIMPLE_RVT_TT_08302018/NOR2xp67_ASAP7_75t_R
apply_size_eco U3589 asap7sc7p5t_SIMPLE_RVT_TT_08302018/NAND2xp5_ASAP7_75t_R
apply_size_eco U2373 asap7sc7p5t_SIMPLE_RVT_TT_08302018/NAND2xp5_ASAP7_75t_R

set accepted_sized_cells [get_cells {U4278 U3908 U3733 U3734 U3726 U2467 U3589 U2373}]
set_dont_touch $accepted_sized_cells true
update_timing

