transcript on

vlib work
vmap work work

set UVM_HOME "C:/intelFPGA/20.1/modelsim_ase/verilog_src/uvm-1.2/src"

vlog -sv +incdir+$UVM_HOME $UVM_HOME/uvm_pkg.sv

vlog -sv "E:/MDP TAGE Predictor/Design/gated_clk.sv"
vlog -sv "E:/MDP TAGE Predictor/Design/base_predictor_sram.sv"
vlog -sv +incdir+$UVM_HOME "E:/MDP TAGE Predictor/Design/TB_base_table.sv"

vsim -voptargs=+acc work.tb_top

run -all