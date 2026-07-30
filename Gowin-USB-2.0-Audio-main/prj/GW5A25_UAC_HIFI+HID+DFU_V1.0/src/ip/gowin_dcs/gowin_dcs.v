//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.12.03 (64-bit)
//IP Version: 1.0
//Part Number: GW5A-LV25UG324C2/I1
//Device: GW5A-25
//Device Version: A
//Created Time: Thu Jul 23 09:04:59 2026

module Gowin_DCS (clkout, clksel, clkin0, clkin1, clkin2, clkin3);

output clkout;
input [3:0] clksel;
input clkin0;
input clkin1;
input clkin2;
input clkin3;

wire gw_gnd;

assign gw_gnd = 1'b0;

DCS dcs_inst (
    .CLKOUT(clkout),
    .CLKSEL(clksel),
    .CLKIN0(clkin0),
    .CLKIN1(clkin1),
    .CLKIN2(clkin2),
    .CLKIN3(clkin3),
    .SELFORCE(gw_gnd)
);

defparam dcs_inst.DCS_MODE = "RISING";

endmodule //Gowin_DCS
