
module chipscope_debug_viv (
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


	vio_0 vio (
		.clk(v_clk0),
		.probe_in0(v_debug_vin),
		.probe_out0(v_debug_vout)
	);

	
//	(* mark_debug = "true", keep = "true" *) wire [15:0] v_test;
//	assign v_test = v_debug0_0;

	(* mark_debug = "true" *) reg [15:0] v_debug0_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_4_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_4_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_4_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_4_reg;
	always @  (posedge v_clk0)  begin
		v_debug0_0_reg <= v_debug0_0;
		v_debug0_1_reg <= v_debug0_1;
		v_debug0_2_reg <= v_debug0_2;
		v_debug0_3_reg <= v_debug0_3;
		v_debug0_4_reg <= v_debug0_4;
		v_debug1_0_reg <= v_debug1_0;
		v_debug1_1_reg <= v_debug1_1;
		v_debug1_2_reg <= v_debug1_2;
		v_debug1_3_reg <= v_debug1_3;
		v_debug1_4_reg <= v_debug1_4;
		v_debug2_0_reg <= v_debug2_0;
		v_debug2_1_reg <= v_debug2_1;
		v_debug2_2_reg <= v_debug2_2;
		v_debug2_3_reg <= v_debug2_3;
		v_debug2_4_reg <= v_debug2_4;
		v_debug3_0_reg <= v_debug3_0;
		v_debug3_1_reg <= v_debug3_1;
		v_debug3_2_reg <= v_debug3_2;
		v_debug3_3_reg <= v_debug3_3;
		v_debug3_4_reg <= v_debug3_4;
	end



	ila_0 ila0 (
		.clk(v_clk0),
		.probe0(v_debug0_0_reg), // IN BUS [15:0]
		.probe1(v_debug0_1_reg), // IN BUS [15:0]
		.probe2(v_debug0_2_reg), // IN BUS [15:0]
		.probe3(v_debug0_3_reg), // IN BUS [15:0]
		.probe4(v_debug0_4_reg), // IN BUS [15:0]
		.probe5(v_debug1_0_reg), // IN BUS [15:0]
		.probe6(v_debug1_1_reg), // IN BUS [15:0]
		.probe7(v_debug1_2_reg), // IN BUS [15:0]
		.probe8(v_debug1_3_reg), // IN BUS [15:0]
		.probe9(v_debug1_4_reg), // IN BUS [15:0]
		.probe10(v_debug2_0_reg), // IN BUS [15:0]
		.probe11(v_debug2_1_reg), // IN BUS [15:0]
		.probe12(v_debug2_2_reg), // IN BUS [15:0]
		.probe13(v_debug2_3_reg), // IN BUS [15:0]
		.probe14(v_debug2_4_reg), // IN BUS [15:0]
		.probe15(v_debug3_0_reg), // IN BUS [15:0]
		.probe16(v_debug3_1_reg), // IN BUS [15:0]
		.probe17(v_debug3_2_reg), // IN BUS [15:0]
		.probe18(v_debug3_3_reg), // IN BUS [15:0]
		.probe19(v_debug3_4_reg) // IN BUS [15:0]
	);

endmodule
