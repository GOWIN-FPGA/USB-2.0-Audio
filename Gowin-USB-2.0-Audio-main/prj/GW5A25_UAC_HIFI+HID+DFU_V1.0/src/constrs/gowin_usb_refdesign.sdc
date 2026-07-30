//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.12.03 (64-bit) 
//Created Time: 2026-07-23 09:39:51
create_clock -name clk60 -period 16.667 -waveform {0 8.334} [get_pins {pll1/u_pll/PLLA_inst/CLKOUT0}]
create_clock -name clk120 -period 8.333 -waveform {0 4.167} [get_nets {u_USB_SoftPHY_Top/usb2_0_softphy/u_usb_20_phy_utmi/u_usb2_0_softphy/u_usb_phy_hs/sclk}]
create_clock -name clk_49152 -period 20.345 -waveform {0 10.172} [get_pins {iis_pll0/u_pll/PLLA_inst/CLKOUT0}]
create_clock -name fclk -period 10.173 -waveform {0 5.087} [get_pins {iis_pll1/u_pll/PLLA_inst/CLKOUT0}]
create_clock -name clk_45158 -period 22.144 -waveform {0 11.072} [get_pins {iis_pll0/u_pll/PLLA_inst/CLKOUT1}]
set_false_path -from [get_clocks {clk60}] -to [get_clocks {clk120}] 
set_false_path -from [get_clocks {clk120}] -to [get_clocks {clk60}] 
report_timing -setup -max_paths 100 -max_common_paths 1
