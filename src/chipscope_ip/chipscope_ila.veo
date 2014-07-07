///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2014 Xilinx, Inc.
// All Rights Reserved
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor     : Xilinx
// \   \   \/     Version    : 14.7
//  \   \         Application: Xilinx CORE Generator
//  /   /         Filename   : chipscope_ila.veo
// /___/   /\     Timestamp  : Mon Jul 07 15:01:51 EDT 2014
// \   \  /  \
//  \___\/\___\
//
// Design Name: ISE Instantiation template
///////////////////////////////////////////////////////////////////////////////

// The following must be inserted into your Verilog file for this
// core to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
chipscope_ila YourInstanceName (
    .CONTROL(CONTROL), // INOUT BUS [35:0]
    .CLK(CLK), // IN
    .TRIG0(TRIG0), // IN BUS [15:0]
    .TRIG1(TRIG1), // IN BUS [15:0]
    .TRIG2(TRIG2), // IN BUS [15:0]
    .TRIG3(TRIG3), // IN BUS [15:0]
    .TRIG4(TRIG4), // IN BUS [15:0]
    .TRIG5(TRIG5), // IN BUS [15:0]
    .TRIG6(TRIG6), // IN BUS [15:0]
    .TRIG7(TRIG7) // IN BUS [15:0]
);

// INST_TAG_END ------ End INSTANTIATION Template ---------

