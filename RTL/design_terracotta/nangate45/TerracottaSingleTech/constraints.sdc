set clk_period 4.0
create_clock -name clk -period $clk_period [get_ports clk_i]

set_input_delay  [expr $clk_period * 0.20] -clock clk [all_inputs]
set_output_delay [expr $clk_period * 0.20] -clock clk [all_outputs]

set_driving_cell -lib_cell BUF_X4 [all_inputs]
set_max_fanout 16 [current_design]
