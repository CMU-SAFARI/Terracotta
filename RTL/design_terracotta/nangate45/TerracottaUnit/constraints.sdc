current_design TerracottaUnit

set clk_name  core_clock
set clk_port_name clk_i
set clk_period 4.0
set clk_io_pct 0.2

set clk_port [get_ports $clk_port_name]

create_clock -name $clk_name -period $clk_period  $clk_port

set non_clock_inputs [lsearch -inline -all -not -exact [all_inputs] $clk_port]

set_input_delay  [expr $clk_period * $clk_io_pct] -clock $clk_name $non_clock_inputs
set_output_delay [expr $clk_period * $clk_io_pct] -clock $clk_name [all_outputs]

# Push buffering and reduce input fanout to improve frequency
set_max_fanout 16 [all_inputs]
set_input_transition 0.05 [all_inputs]
# Model a practical driving cell for inputs to trigger upsizing/buffering
set_driving_cell -lib_cell BUF_X4 -pin Z [all_inputs]
