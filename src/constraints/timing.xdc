create_clock -period 5.000 -name clk [get_ports clk]
set_input_delay -clock clk 0.000 [get_ports {rst_n irq_in}]
set_output_delay -clock clk 0.000 [get_ports dbg_*]

set_false_path -to [get_ports dbg_*]
set_false_path -from [get_ports rst_n]

create_clock -period 10.000 -name clk [get_ports clk]
