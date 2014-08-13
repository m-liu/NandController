
module chipscope_debug (
	input v_clk0,
	input v_rst0,
	input [63:0] v_debug_vin,
	output [63:0] v_debug_vout,
	input [15:0] v_debug0_0,
	input [15:0] v_debug0_1,
	input [15:0] v_debug0_2,
	input [15:0] v_debug0_3,
	input [15:0] v_debug0_4,

	input [15:0] v_debug1_0,
	input [15:0] v_debug1_1,
	input [15:0] v_debug1_2,
	input [15:0] v_debug1_3,
	input [15:0] v_debug1_4,

	input [15:0] v_debug2_0,
	input [15:0] v_debug2_1,
	input [15:0] v_debug2_2,
	input [15:0] v_debug2_3,
	input [15:0] v_debug2_4,

	input [15:0] v_debug3_0,
	input [15:0] v_debug3_1,
	input [15:0] v_debug3_2,
	input [15:0] v_debug3_3,
	input [15:0] v_debug3_4
);


wire [35:0] dbg_ctrl_0;
wire [35:0] dbg_ctrl_1;
wire [35:0] dbg_ctrl_2;
wire [35:0] dbg_ctrl_3;
wire [35:0] dbg_ctrl_4;

//Instantiate chipscope ICON
	chipscope_icon icon_0 (
		.CONTROL0(dbg_ctrl_0), // INOUT BUS [35:0]
		.CONTROL1(dbg_ctrl_1), // INOUT BUS [35:0]
		.CONTROL2(dbg_ctrl_2), // INOUT BUS [35:0]
		.CONTROL3(dbg_ctrl_3), // INOUT BUS [35:0]
		.CONTROL4(dbg_ctrl_4) // INOUT BUS [35:0]
		//.CONTROL5(dbg_ctrl_5), // INOUT BUS [35:0]
		//.CONTROL6(dbg_ctrl_6), // INOUT BUS [35:0]
		//.CONTROL7(dbg_ctrl_7) // INOUT BUS [35:0]
	) /* synthesis syn_noprune=1 */;


	chipscope_vio vio (
		.CONTROL(dbg_ctrl_0),
		.CLK(v_clk0),
		.SYNC_IN(v_debug_vin),
		.SYNC_OUT(v_debug_vout)
	);


	chipscope_ila_2k ila0 (
		.CONTROL(dbg_ctrl_1), // INOUT BUS [35:0]
		.CLK(v_clk0), // IN
		.TRIG0(v_debug0_0), // IN BUS [15:0]
		.TRIG1(v_debug0_1), // IN BUS [15:0]
		.TRIG2(v_debug0_2), // IN BUS [15:0]
		.TRIG3(v_debug0_3), // IN BUS [15:0]
		.TRIG4(v_debug0_4) // IN BUS [15:0]
	);

	chipscope_ila_2k ila1 (
		.CONTROL(dbg_ctrl_2), // INOUT BUS [35:0]
		.CLK(v_clk0), // IN
		.TRIG0(v_debug1_0), // IN BUS [15:0]
		.TRIG1(v_debug1_1), // IN BUS [15:0]
		.TRIG2(v_debug1_2), // IN BUS [15:0]
		.TRIG3(v_debug1_3), // IN BUS [15:0]
		.TRIG4(v_debug1_4) // IN BUS [15:0]
	);

	chipscope_ila_2k ila2 (
		.CONTROL(dbg_ctrl_3), // INOUT BUS [35:0]
		.CLK(v_clk0), // IN
		.TRIG0(v_debug2_0), // IN BUS [15:0]
		.TRIG1(v_debug2_1), // IN BUS [15:0]
		.TRIG2(v_debug2_2), // IN BUS [15:0]
		.TRIG3(v_debug2_3), // IN BUS [15:0]
		.TRIG4(v_debug2_4) // IN BUS [15:0]
	);

	chipscope_ila_2k ila3 (
		.CONTROL(dbg_ctrl_4), // INOUT BUS [35:0]
		.CLK(v_clk0), // IN
		.TRIG0(v_debug3_0), // IN BUS [15:0]
		.TRIG1(v_debug3_1), // IN BUS [15:0]
		.TRIG2(v_debug3_2), // IN BUS [15:0]
		.TRIG3(v_debug3_3), // IN BUS [15:0]
		.TRIG4(v_debug3_4) // IN BUS [15:0]
	);
endmodule
