`timescale 1ns / 1ps

//`define DQ_WIDTH 8
//`define DQ_PER_DQS 8

module nand_phy #
	(
	parameter DQ_WIDTH = 8,
	parameter DQ_PER_DQS = 8
	)
		(
		//****************************
		//NAND and FPGA I/O interface
		//****************************
		//input sys_resetn, //from FMC
		
		//input sys_clk_p,
		//input sys_clk_n,
		output v_nand_clk,
		
		inout [7:0] v_dq,
		inout v_dqs,
		output v_cle,
		output v_ale,
		output v_wrn,
		output v_wpn,
		output [1:0] v_cen,
		//input  [3:0] rb,
		output [7:0] v_debug,
		output [7:0] v_debug90,
		
		//****************************
		//Controller facing interface 
		//****************************
		input v_ctrl_cle,
		input v_ctrl_ale,
		input v_ctrl_wrn,
		input v_ctrl_wpn,
		input [1:0] v_ctrl_cen,
		//output [3:0] ctrl_rb,
		input [7:0] v_ctrl_debug,
		input [7:0] v_ctrl_debug90,
		
		//DQS iob control and data signals
		input v_dlyinc_dqs,
		input v_dlyce_dqs,
		//input dlyrst_dqs,
		input v_dqs_oe_n,
		input v_dqs_rst_n,
		
		//DQ iob control signals
		input [DQ_WIDTH-1:0] v_dlyinc_dq,
		input [DQ_WIDTH-1:0] v_dlyce_dq,
		//input [DQ_WIDTH-1:0] dlyrst_dq,
		input v_dq_oe_n,
		input [DQ_WIDTH-1:0] v_wr_data_rise,
		input [DQ_WIDTH-1:0] v_wr_data_fall,
		output [DQ_WIDTH-1:0] v_rd_data_rise,
		output [DQ_WIDTH-1:0] v_rd_data_fall,
		
		//clocks and resets
		input v_clk0,
		input v_clk90,
		input v_rstn0,
		input v_rstn90
		

		
		
    );

/* Simulation TODO: 
 * both I/Os within a NAND package
 * multiple chips on a bus
 * multiple buses
 * 
 *
 */

localparam IODELAY_GRP = "IODELAY_NAND";
localparam HIGH_PERFORMANCE_MODE = "TRUE";

wire delayed_dqs;

//invert reset. BSV weirdness...
wire v_rst0 = ~v_rstn0;
wire v_rst90 = ~v_rstn90;

assign v_debug = v_ctrl_debug;
assign v_debug90 = v_ctrl_debug90;

/*
//system clock generator
nand_infrastructure #
	(
		.IODELAY_GRP (IODELAY_GRP)
	)	
	u_nand_infrastructure (
   .sys_clk_p(sys_clk_p),
   .sys_clk_n(sys_clk_n),

   .clk0(clk0),
   .clk90(clk90),
	
   .sys_rst_n(sys_resetn),
   
   .rst0(rst0),
   .rst90(rst90)

);
*/

  //***************************************************************************
  // NAND clock generation
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
           .D1  (1'b0),
           .D2  (1'b1),
           .R   (1'b0),
           .S   (1'b0)
           );

 



//DQS tri-state inout buffer
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
		.dlyinc_dqs     (v_dlyinc_dqs),
		.dlyce_dqs      (v_dlyce_dqs),
		.dlyrst_dqs     (), //not sure if this is needed. Seems to only be for pipeline variable mode

		.dqs_oe_n       (v_dqs_oe_n),
		.dqs_rst_n      (v_dqs_rst_n),
		.ddr_dqs        (v_dqs),

		.delayed_dqs    (delayed_dqs)
	);




//DQ I/O buffers
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
           .clk90        (v_clk90),
           .rst90        (v_rst90),
           .dlyinc       (v_dlyinc_dq[dq_i]),
           .dlyce        (v_dlyce_dq[dq_i]),
           .dlyrst       (/*dlyrst_dq[dq_i]*/), //not sure if needed
           .dq_oe_n      (v_dq_oe_n),
           .dqs          (delayed_dqs),
           .wr_data_rise (v_wr_data_rise[dq_i]),
           .wr_data_fall (v_wr_data_fall[dq_i]),
           .rd_data_rise (v_rd_data_rise[dq_i]),
           .rd_data_fall (v_rd_data_fall[dq_i]),
           .ddr_dq       (v_dq[dq_i])
           );
    end
  endgenerate

//Command I/O registers
nand_phy_ctl_io u_io_phy_ctl
	(
	
	//nand interface for half of a NAND package
	//x8 DQ interface
	.cle(v_cle),
	.ale(v_ale),
	.wrn(v_wrn),
	.wpn(v_wpn),
	.cen(v_cen),
	//.rb(rb[3:0]),
		
	//controller facing interface
	.ctrl_cle(v_ctrl_cle),
	.ctrl_ale(v_ctrl_ale),
	.ctrl_wrn(v_ctrl_wrn),
	.ctrl_wpn(v_ctrl_wpn),
	.ctrl_cen(v_ctrl_cen),
	//.ctrl_rb(ctrl_rb),
	
	//clock and reset
	.clk0(v_clk0),
	.rst0(v_rst0)
	
	);



//for debug
/*
always @ (posedge clk0)
begin
	if (rd_data_rise == 8'hFF || rd_data_fall == 8'hFF)
		ale <= 1;
	else
		ale <= 0;
end

(* KEEP = "TRUE" *) reg [DQ_WIDTH-1:0] rd_data_rise_r;
(* KEEP = "TRUE" *) reg [DQ_WIDTH-1:0] rd_data_fall_r;
always @ (posedge clk0)
begin
	rd_data_rise_r <= rd_data_rise;
	rd_data_fall_r <= rd_data_fall;
end

//disable output
assign dqs_oe_n = 1; 
assign dq_oe_n = 1;

//test shifting
reg [31:0] delay_r;
wire trigger;
assign trigger = (delay_r==32'd50);
always @ (posedge clk90)
begin
	if (rst90) begin
		delay_r <= 0;
	end
	else if (delay_r < 50) begin
		delay_r <= delay_r + 1;
	end
	
end


localparam DELAY_TAPS = 20;
assign dlyrst_dqs = rst90;
reg [4:0] tap_cnt;
always @ (posedge clk90)
begin
	if (rst90 || ~trigger) begin
		tap_cnt <= 5'd0;
		dlyinc_dqs <= 1'b0;
		dlyce_dqs <= 1'b0;
	end
	else if (tap_cnt == DELAY_TAPS) begin
		dlyinc_dqs <= 1'b0;
		dlyce_dqs <= 1'b0;
	end
	else if (trigger) begin
		tap_cnt <= tap_cnt + 1;
		dlyinc_dqs <= 1'b1;
		dlyce_dqs <= 1'b1;
	end
end


*/

endmodule

