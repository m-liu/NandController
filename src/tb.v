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
	wire [1:0] b0_cen;
	//wire  [3:0] b0_rb;
	
	reg sys_resetn;
	
	//debug
	//wire debug_ctrl;	
	 

//---------------------------------------------
// Module instantiation
//---------------------------------------------
/*
nand_model nand_model (
	//clocks
	.Clk_We_n(b0_nand_clk0),
	.Clk_We2_n(b0_nand_clk0),
	
	//CE
	.Ce_n(b0_cen[0]),
	.Ce2_n(b0_cen[1]),
	.Ce3_n(b0_cen[2]),
	.Ce4_n(b0_cen[3]),
	
	//Ready/busy
	.Rb_n(b0_rb[0]),
	.Rb2_n(b0_rb[1]),
	.Rb3_n(b0_rb[2]),
	.Rb4_n(b0_rb[3]),
	 
	//DQ DQS
	.Dqs(b0_dqs[0]), 
	.Dq_Io(b0_dq[7:0]), 
	.Dqs2(b0_dqs[1]),
	.Dq_Io2(b0_dq[15:8]),
	 
	//ALE CLE WR WP
	.Cle(b0_cle[0]), 
	.Cle2(b0_cle[1]),
   .Ale(b0_ale[0]), 
	.Ale2(b0_ale[1]),
	.Wr_Re_n(b0_wrn[0]), 
	.Wr_Re2_n(b0_wrn[1]),
	.Wp_n(b0_wpn[0]), 
	.Wp2_n(b0_wpn[1])
);
*/

mkNandPhy u_nand_phy(
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

		 .CEN(b0_cen)
	 );
	 /*
		.sys_resetn(sys_resetn), //from FMC
		
		.sys_clk_p(clk_in_p),
		.sys_clk_n(clk_in_n),
		.nand_clk(b0_nand_clk0),
		
		.dq(b0_dq),
		.dqs(b0_dqs),
		.cle(b0_cle),
		.ale(b0_ale),
		.wrn(b0_wrn),
		.wpn(b0_wpn),
		.cen(b0_cen),
		.rb(b0_rb)
		
); 
*/
//---------------------------------------------
// Simulation
//---------------------------------------------

initial begin
	clk_in_p = 0;
	clk_in_n = 1;
	
	//reset for a bit
	sys_resetn = 0;
	#20
	sys_resetn = 1;
	
	//for now just wait a long time before ending simulation
	#100000
	$finish;
end

//100MHz differential clock
//can probably just assign clk_in_n=~clk_in_p ?
always begin
	#5 clk_in_p=~clk_in_p;
end
always begin
	#5 clk_in_n=~clk_in_n;
end

reg [7:0] b0_dq_out;
reg b0_dqs_out;

assign b0_dq = (b0_ale==0) ? b0_dq_out : 8'hZZ;
assign b0_dqs = (b0_ale==0) ? b0_dqs_out : 1'bZ;

always begin
		#5
		b0_dq_out = 8'hDE;
		b0_dqs_out = 1'b1;
		#5
		b0_dq_out = 8'hAD;
		b0_dqs_out = 1'b0;
		#5
		b0_dq_out = 8'hBE;
		b0_dqs_out = 1'b1;
		#5
		b0_dq_out = 8'hEF;
		b0_dqs_out = 1'b0;
		end



/*


always @ (*)
begin
	if (debug_ctrl==0) begin
		#5
		b0_dq = 16'hDEAD;
		b0_dqs = 2'b11;
		#5
		b0_dq = 16'hBEEF;
		b0_dqs = 2'b11;
		
	end
	else begin
		b0_dq = 16'hZZZZ;
		b0_dqs = 2'bZZ;
	end
end

*/

endmodule
