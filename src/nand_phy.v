`timescale 1ns / 1ps

module nand_phy #
	(
	parameter DQ_WIDTH = 8,
	parameter DQ_PER_DQS = 8
	)
		(
		//****************************
		//NAND and FPGA I/O interface
		//****************************
		output v_nand_clk,
		
		inout [7:0] v_dq,
		inout v_dqs,
		output v_cle,
		output v_ale,
		output v_wrn,
		output v_wpn,
		output [7:0] v_cen,

		output [7:0] v_debug0,
		output [7:0] v_debug1,
		
		//****************************
		//Controller facing interface 
		//****************************
		input v_ctrl_cle,
		input v_ctrl_ale,
		input v_ctrl_wrn,
		input v_ctrl_wpn,
		input [7:0] v_ctrl_cen,
		input v_ctrl_wen, 
		input v_ctrl_wen_sel,
		input [15:0] v_ctrl_debug0,
		input [15:0] v_ctrl_debug1,
		input [15:0] v_ctrl_debug2,
		input [15:0] v_ctrl_debug3,
		input [15:0] v_ctrl_debug4,
		input [15:0] v_ctrl_debug5,
		input [15:0] v_ctrl_debug6,
		input [15:0] v_ctrl_debug7,
		
		//DQS iob control and data signals
		//input v_dlyinc_dqs,
		//input v_dlyce_dqs,
		//input dlyrst_dqs,
		input v_dqs_oe_n,
		input v_dqs_rst_n,
		
		//DQ iob control signals
		//input [DQ_WIDTH-1:0] v_dlyinc_dq,
		//input [DQ_WIDTH-1:0] v_dlyce_dq,
		//input [DQ_WIDTH-1:0] dlyrst_dq,
		input v_dq_oe_n,
		input v_dq_iddr_rst,
		input [DQ_WIDTH-1:0] v_wr_data_rise,
		input [DQ_WIDTH-1:0] v_wr_data_fall,
		output [DQ_WIDTH-1:0] v_rd_data_rise,
		output [DQ_WIDTH-1:0] v_rd_data_fall,
		output [DQ_WIDTH-1:0] v_rd_data_comb,
		
		//Calibration DQ and DQ phase selection signals
 		output [DQ_WIDTH-1:0] v_calib_dq_rise_0,
 		output [DQ_WIDTH-1:0] v_calib_dq_rise_90,
 		output [DQ_WIDTH-1:0] v_calib_dq_rise_180,
 		output [DQ_WIDTH-1:0] v_calib_dq_rise_270,
		input v_calib_clk0_sel,
		
		//clocks and resets
		input v_clk0,
		input v_clk90,
		input v_rstn0,
		input v_rstn90
    );

localparam IODELAY_GRP = "IODELAY_NAND";
localparam HIGH_PERFORMANCE_MODE = "TRUE";

wire delayed_dqs;

//invert reset.
wire v_rst0 = ~v_rstn0;
wire v_rst90 = ~v_rstn90;

assign v_debug0 = v_ctrl_debug0[7:0];
assign v_debug1 = v_ctrl_debug1[7:0];

//***************************************************************************
// Mux for NAND_CLK (sync) or WE# (async) 
//***************************************************************************
wire nand_clk_we_d1;
wire nand_clk_we_d2;
assign nand_clk_we_d1 = (v_ctrl_wen_sel) ? (v_ctrl_wen) : (1'b0);
assign nand_clk_we_d2 = (v_ctrl_wen_sel) ? (v_ctrl_wen) : (1'b1);

//***************************************************************************
// NAND CLK ODDR
//***************************************************************************
ODDR #
	(
	.SRTYPE       ("SYNC"),
	.DDR_CLK_EDGE ("OPPOSITE_EDGE")
	)
	u_oddr_ck
	(
		.Q   (v_nand_clk),
		.C   (v_clk0),
		.CE  (1'b1),
		.D1  (nand_clk_we_d1),
		.D2  (nand_clk_we_d2),
		.R   (1'b0),
		.S   (1'b0)
	);


//***************************************************************************
// DQS IO buffer
//***************************************************************************
nand_phy_dqs_iob #
	(
	//.DQS_GATE_EN           (DQS_GATE_EN),
	.HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE),
	.IODELAY_GRP           (IODELAY_GRP)
	)
	u_iob_dqs
	(
		.clk0           (v_clk0),
		.clk90          (v_clk90),
		.rst0           (v_rst0),
		//.dlyinc_dqs     (v_dlyinc_dqs),
		//.dlyce_dqs      (v_dlyce_dqs),
		//.dlyrst_dqs     (), //not sure if this is needed. Seems to only be for pipeline variable mode

		.dqs_oe_n       (v_dqs_oe_n),
		.dqs_rst_n      (v_dqs_rst_n),
		.ddr_dqs        (v_dqs),

		.delayed_dqs    (delayed_dqs)
	);




//***************************************************************************
// DQ IO buffers
//***************************************************************************
genvar dq_i;
generate
 for(dq_i = 0; dq_i < DQ_WIDTH; dq_i = dq_i+1) begin: gen_dq
	nand_phy_dq_iob #
	  (
		.HIGH_PERFORMANCE_MODE (HIGH_PERFORMANCE_MODE),
		.IODELAY_GRP           (IODELAY_GRP)
		)
	  u_iob_dq
		 (
		  .clk0			 (v_clk0),
		  .rst0			 (v_rst0),
		  .clk90        (v_clk90),
		  .rst90        (v_rst90),
		  //.dlyinc       (v_dlyinc_dq[dq_i]),
		  //.dlyce        (v_dlyce_dq[dq_i]),
		  //.dlyrst       (/*dlyrst_dq[dq_i]*/), //not sure if needed
		  .dq_oe_n      (v_dq_oe_n),
		  .dq_iddr_rst	 (v_dq_iddr_rst),
		  .dqs          (delayed_dqs),
		  .wr_data_rise (v_wr_data_rise[dq_i]),
		  .wr_data_fall (v_wr_data_fall[dq_i]),
		  .rd_data_rise (v_rd_data_rise[dq_i]),
		  .rd_data_fall (v_rd_data_fall[dq_i]),
		  .rd_data_comb (v_rd_data_comb[dq_i]),
		  .ddr_dq       (v_dq[dq_i]),
		  .calib_dq_rise_0 (v_calib_dq_rise_0[dq_i]),
		  .calib_dq_rise_90 (v_calib_dq_rise_90[dq_i]),
		  .calib_dq_rise_180 (v_calib_dq_rise_180[dq_i]),
		  .calib_dq_rise_270 (v_calib_dq_rise_270[dq_i]),
		  .calib_clk0_sel (v_calib_clk0_sel)
		  );
 end
endgenerate


//***************************************************************************
// Command I/O registers
//***************************************************************************
nand_phy_ctl_io u_io_phy_ctl
	(
	
	//nand interface for half of a NAND package
	//x8 DQ interface
	.cle(v_cle),
	.ale(v_ale),
	.wrn(v_wrn),
	.wpn(v_wpn),
	.cen(v_cen),
		
	//controller facing interface
	.ctrl_cle(v_ctrl_cle),
	.ctrl_ale(v_ctrl_ale),
	.ctrl_wrn(v_ctrl_wrn),
	.ctrl_wpn(v_ctrl_wpn),
	.ctrl_cen(v_ctrl_cen),
	
	//clock and reset
	.clk0(v_clk0),
	.rst0(v_rst0)
	
	);


 
//***************************************************************************
// Chipscope 
//***************************************************************************
	wire [35:0] dbg_ctrl;

	chipscope_icon icon (
		.CONTROL0(dbg_ctrl) // INOUT BUS [35:0]
	) /* synthesis syn_noprune=1 */;

	chipscope_ila ila (
		.CONTROL(dbg_ctrl), // INOUT BUS [35:0]
		.CLK(v_clk0), // IN
		.TRIG0(v_ctrl_debug0), // IN BUS [15:0]
		.TRIG1(v_ctrl_debug1), // IN BUS [15:0]
		.TRIG2(v_ctrl_debug2), // IN BUS [15:0]
		.TRIG3(v_ctrl_debug3), // IN BUS [15:0]
		.TRIG4(v_ctrl_debug4), // IN BUS [15:0]
		.TRIG5(v_ctrl_debug5), // IN BUS [15:0]
		.TRIG6(v_ctrl_debug6), // IN BUS [15:0]
		.TRIG7(v_ctrl_debug7) // IN BUS [15:0]
	) /* synthesis syn_noprune=1 */;





endmodule

