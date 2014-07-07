`timescale 1ns/1ps

module tb;
//---------------------------------------------
// Wires and Regs
//---------------------------------------------
	reg clk_in_p;
	reg clk_in_n;
	//wire b0_sys_clk_p;
	//wire b0_sys_clk_n;
	wire b0_nand_clk0;
	//wire b0_nand_clk1;
	//wire b0_nand_clk2;
	//wire b0_nand_clk3;
	
	wire [7:0] b0_dq;
	wire b0_dqs;
	wire b0_cle;
	wire b0_ale;
	wire b0_wrn;
	wire b0_wpn;
	wire [7:0] b0_cen;
	wire  [3:0] b0_rb;
	wire [7:0] b0_debug0;
	wire [7:0] b0_debug1;
	reg sys_resetn;
	
	//debug
	//wire debug_ctrl;	
	 

//---------------------------------------------
// Module instantiation
//---------------------------------------------
nand_model nand_model (
	//clocks
	.Clk_We_n(b0_nand_clk0),
	.Clk_We2_n(/*b0_nand_clk0*/),
	
	//CE
	.Ce_n(b0_cen[0]),
	.Ce2_n(/*b0_cen[1]*/),
	.Ce3_n(b0_cen[1]),
	.Ce4_n(/*b0_cen[3]*/),
	
	//Ready/busy
	.Rb_n(b0_rb[0]),
	.Rb2_n(b0_rb[1]),
	.Rb3_n(b0_rb[2]),
	.Rb4_n(b0_rb[3]),
	 
	//DQ DQS
	.Dqs(b0_dqs), 
	.Dq_Io(b0_dq[7:0]), 
	.Dqs2(/*b0_dqs[1]*/),
	.Dq_Io2(/*b0_dq[15:8]*/),
	 
	//ALE CLE WR WP
	.Cle(b0_cle), 
	.Cle2(/*b0_cle[1]*/),
   .Ale(b0_ale), 
	.Ale2(/*b0_ale[1]*/),
	.Wr_Re_n(b0_wrn), 
	.Wr_Re2_n(/*b0_wrn[1]*/),
	.Wp_n(b0_wpn), 
	.Wp2_n(/*b0_wpn[1]*/)
);

mkFlashController u_flash_controller(
		.CLK_sysClkP(clk_in_p),
		 .CLK_sysClkN(clk_in_n),
		 .RST_N_sysRstn(sys_resetn),

		 .DQ(b0_dq),
		 .DQS(b0_dqs),

		 .NAND_CLK(b0_nand_clk0),

		 .CLE(b0_cle),

		 .ALE(b0_ale),

		 .WRN(b0_wrn),

		 .WPN(b0_wpn),

		 .CEN(b0_cen),
		 .DEBUG0(b0_debug0),
		 .DEBUG1(b0_debug1)
	 );


//---------------------------------------------
// Simulation clock and reset
//---------------------------------------------

initial begin
	clk_in_p = 0;
	clk_in_n = 1;
	
	//reset for a bit
	//sys_resetn = 0;
	//#200
	sys_resetn = 1;
	
end

//100MHz differential clock
//can probably just assign clk_in_n=~clk_in_p ?
always begin
	#5 clk_in_p=~clk_in_p;
end
always begin
	#5 clk_in_n=~clk_in_n;
end


endmodule
