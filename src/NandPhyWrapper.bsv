import Connectable       ::*;
import Clocks            ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;
import TriState          ::*;
import Vector            ::*;
import Counter           ::*;
import DefaultValue      ::*;


(* always_enabled, always_ready *)
interface NANDPins;
	(* prefix = "", result = "NAND_CLK" *)
	method    Bit#(1)           nand_clk;
	(* prefix = "", result = "CLE" *)
	method    Bit#(1)           cle;
	(* prefix = "", result = "ALE" *)
	method    Bit#(1)           ale;
	(* prefix = "", result = "WRN" *)
	method    Bit#(1)           wrn;
	(* prefix = "", result = "WPN" *)
	method    Bit#(1)           wpn;
	(* prefix = "", result = "CEN" *)
	method    Bit#(2)           cen;
	(* prefix = "DQ" *)
	interface Inout#(Bit#(8))  dq;
	(* prefix = "DQS" *)
	interface Inout#(Bit#(1))   dqs;
	
	(* prefix = "", result = "DEBUG" *)
	method	Bit#(8)				debug;
	(* prefix = "", result = "DEBUG90" *)
	method	Bit#(8)				debug90;
endinterface 

(* always_ready, always_enabled *)
interface VPhyUser;
	method Action setCLE (Bit#(1) i);
	method Action setALE (Bit#(1) i);
	method Action setWRN (Bit#(1) i);
	method Action setWPN (Bit#(1) i);
	method Action setCEN (Bit#(2) i);
	method Action setWEN (Bit#(1) i);
	method Action setWENSel (Bit#(1) i);
	
	//DQS delay control; clk90 domain
	method Action dlyIncDQS (Bit#(1) i);
	method Action dlyCeDQS (Bit#(1) i);

	//DQS output; clk0 domain
	method Action oenDQS (Bit#(1) i);
	method Action rstnDQS (Bit#(1) i);

	//DQ delay control; clk90 domain
	method Action dlyIncDQ (Bit#(8) i);
	method Action dlyCeDQ (Bit#(8) i);
	method Action oenDataDQ (Bit#(1) i);
	
	method Action wrDataRiseDQ (Bit#(8) d);
	method Action wrDataFallDQ (Bit#(8) d);
	method Bit#(8) rdDataRiseDQ();
	method Bit#(8) rdDataFallDQ();
	method Bit#(8) rdDataCombDQ();
	

//	method Action oenCmdDQ (Bit#(1) i);
//	method Action wrCmdDQ (Bit#(8) d);
//	method Action cmdSelDQ (Bit#(1) i);

	method Action setDebug (Bit#(8) i);
	method Action setDebug90 (Bit#(8) i);
endinterface


interface VNANDPhy;
	(* prefix = "" *)
	interface NANDPins   nandPins;
	(* prefix = "" *)
	interface VPhyUser  vphyUser;
endinterface



import "BVI" nand_phy =
module vMkNandPhy#(/*NAND_Phy_Configure cfg,*/Clock clk0, Clock clk90, Reset rstn0, Reset rstn90)(VNANDPhy);

//no default clock and reset
default_clock no_clock; 
default_reset no_reset;

//parameter DQ_WIDTH      = cfg.dq_width;
//parameter DQ_PER_DQS = cfg.dq_per_dqs;

input_clock clk0(v_clk0, (*unused*)vclk0_GATE) = clk0;
input_clock clk90(v_clk90, (*unused*)vclk90_GATE) = clk90;
input_reset rstn0(v_rstn0) clocked_by (clk0) = rstn0;
input_reset rstn90(v_rstn90) clocked_by (clk90) = rstn90;

interface NANDPins nandPins;
	ifc_inout dq(v_dq)             clocked_by(no_clock) reset_by(no_reset);
	ifc_inout dqs(v_dqs)           clocked_by(no_clock) reset_by(no_reset);

	method    v_nand_clk       nand_clk     clocked_by(no_clock) reset_by(no_reset);
	method    v_cle 	cle         clocked_by(no_clock) reset_by(no_reset);
	method    v_ale 	ale         clocked_by(no_clock) reset_by(no_reset);
	method    v_wrn 	wrn         clocked_by(no_clock) reset_by(no_reset);
	method    v_wpn 	wpn         clocked_by(no_clock) reset_by(no_reset);
	method    v_cen 	cen         clocked_by(no_clock) reset_by(no_reset);
	//debug ports are really just old R/B signals
	method	 v_debug debug			clocked_by(no_clock) reset_by(no_reset);
	method	 v_debug90 debug90	clocked_by(no_clock) reset_by(no_reset);
endinterface


interface VPhyUser vphyUser;
	method setCLE (v_ctrl_cle) enable((*inhigh*)en0) clocked_by(clk0) reset_by(rstn0);
	method setALE (v_ctrl_ale) enable((*inhigh*)en1) clocked_by(clk0) reset_by(rstn0);
	method setWRN (v_ctrl_wrn) enable((*inhigh*)en2) clocked_by(clk0) reset_by(rstn0);
	method setWPN (v_ctrl_wpn) enable((*inhigh*)en3) clocked_by(clk0) reset_by(rstn0);
	method setCEN (v_ctrl_cen) enable((*inhigh*)en4) clocked_by(clk0) reset_by(rstn0);
	method setWEN (v_ctrl_wen) enable((*inhigh*)en16) clocked_by(clk0) reset_by(rstn0);
	method setWENSel (v_ctrl_wen_sel) enable((*inhigh*)en17) clocked_by(clk0) reset_by(rstn0);
	
	
	//DQS delay control; clk90 domain
	method dlyIncDQS (v_dlyinc_dqs) enable((*inhigh*) en5) clocked_by(clk90) reset_by(rstn90);
	method dlyCeDQS (v_dlyce_dqs) enable((*inhigh*) en6) clocked_by(clk90) reset_by(rstn90);

	//DQS output; clk0 domain
	method oenDQS (v_dqs_oe_n) enable((*inhigh*) en7) clocked_by(clk0) reset_by(rstn0); //active low
	method rstnDQS (v_dqs_rst_n) enable((*inhigh*) en8) clocked_by(clk0) reset_by(rstn0);

	//DQ delay control; clk90 domain
	method dlyIncDQ (v_dlyinc_dq) enable((*inhigh*) en9) clocked_by(clk90) reset_by(rstn90);
	method dlyCeDQ (v_dlyce_dq) enable((*inhigh*) en10) clocked_by(clk90) reset_by(rstn90);
	
	//DQ data; changed to clk0 too
	method oenDataDQ (v_dq_oe_n) enable((*inhigh*) en11) clocked_by(clk0) reset_by(rstn0);
	method wrDataRiseDQ (v_wr_data_rise) enable((*inhigh*) en12) clocked_by(clk0) reset_by(rstn0);
	method wrDataFallDQ (v_wr_data_fall) enable((*inhigh*) en13) clocked_by(clk0) reset_by(rstn0);
	method v_rd_data_rise rdDataRiseDQ() clocked_by(clk0) reset_by(rstn0);
	method v_rd_data_fall rdDataFallDQ() clocked_by(clk0) reset_by(rstn0);
	//DQ combinational data for async mode; clk0
	method v_rd_data_comb rdDataCombDQ() clocked_by(clk0) reset_by(rstn0);

	//DQ commands; clk0
	// create two path to DQ, one clocked by clk0 and other by clk90
	// feed into mux, then ODDR (clocked by clk90). For commands, we hold DQ
	// for a long time, therefore we don't care of ODDR goes metastable briefly if
	// the clk0 path input violates setup 
	//method oenCmdDQ (v_dq_cmd_oe_n) enable((*inhigh*) en20) clocked_by(clk0) reset_by(rstn0);
	//method wrCmdDQ (v_wr_cmd) enable((*inhigh*) en21) clocked_by(clk0) reset_by(rstn0);
	//method cmdSelDQ (v_dq_cmd_sel) enable((*inhigh*) en22) clocked_by(clk0) reset_by(rstn0);

	//Debug signals
	method setDebug (v_ctrl_debug) enable((*inhigh*)en14) clocked_by(clk0) reset_by(rstn0);
	method setDebug90 (v_ctrl_debug90) enable((*inhigh*)en15) clocked_by(clk0) reset_by(rstn0);

endinterface

//NAND pins are CF
schedule 
(nandPins_nand_clk, nandPins_cle, nandPins_ale, nandPins_wrn, nandPins_wpn, nandPins_cen, nandPins_debug, nandPins_debug90) 
CF
(nandPins_nand_clk, nandPins_cle, nandPins_ale, nandPins_wrn, nandPins_wpn, nandPins_cen, nandPins_debug, nandPins_debug90);

//Just set all other signals as CF
schedule
(vphyUser_dlyIncDQS, vphyUser_dlyCeDQS, vphyUser_dlyIncDQ, vphyUser_dlyCeDQ, 
vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN,
vphyUser_setWEN, vphyUser_setWENSel,
vphyUser_oenDQS, vphyUser_rstnDQS, vphyUser_oenDataDQ,
vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ, vphyUser_rdDataCombDQ, vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ,
//vphyUser_oenCmdDQ, vphyUser_wrCmdDQ, vphyUser_cmdSelDQ,
vphyUser_setDebug, vphyUser_setDebug90)
CF
(vphyUser_dlyIncDQS, vphyUser_dlyCeDQS, vphyUser_dlyIncDQ, vphyUser_dlyCeDQ, 
vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN,
vphyUser_setWEN, vphyUser_setWENSel,
vphyUser_oenDQS, vphyUser_rstnDQS, vphyUser_oenDataDQ,
vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ, vphyUser_rdDataCombDQ, vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ,
//vphyUser_oenCmdDQ, vphyUser_wrCmdDQ, vphyUser_cmdSelDQ,
vphyUser_setDebug, vphyUser_setDebug90);

//
////Delay controls areCF
//schedule
//(vphyUser_dlyIncDQS, vphyUser_dlyCeDQS, vphyUser_dlyIncDQ, vphyUser_dlyCeDQ)
//CF
//(vphyUser_dlyIncDQS, vphyUser_dlyCeDQS, vphyUser_dlyIncDQ, vphyUser_dlyCeDQ);
//
////Control signals are CF
//schedule
//(vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN)
//CF
//(vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN);
//
//schedule
//(vphyUser_oenDQS, vphyUser_rstnDQS) 
//CF 
//(vphyUser_oenDQ, vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN);
//
//schedule
//(vphyUser_oenDQ)
//CF
//(vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN,
//vphyUser_dlyIncDQS,vphyUser_dlyCeDQS,vphyUser_dlyIncDQ,vphyUser_dlyCeDQ,vphyUser_wrDataRiseDQ,vphyUser_wrDataFallDQ);
//
//
//schedule 
//(vphyUser_oenDQ) C (vphyUser_oenDQ);
//
//schedule
//(vphyUser_oenDQS) C (vphyUser_rstnDQS);
//
//schedule
//(vphyUser_rstnDQS) C (vphyUser_rstnDQS);
//
//schedule
//(vphyUser_oenDQS) C (vphyUser_oenDQS);
//
////read and writes are conflicting
//schedule
//(vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ)
//C 
//(vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ, vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ);
//
////unrelated
//schedule
//(vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ, vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ)
//CF
//(vphyUser_dlyIncDQS,vphyUser_dlyCeDQS,vphyUser_dlyIncDQ,vphyUser_dlyCeDQ,vphyUser_oenDQ);
//
////can read CF
//schedule
//(vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ)
//CF
//(vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ);
//
////FIXME testing
//schedule
//(vphyUser_setALE)
//CF
//(vphyUser_dlyIncDQS,vphyUser_dlyCeDQS,vphyUser_dlyIncDQ,vphyUser_dlyCeDQ,vphyUser_oenDQ,vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ, vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ);
//
////TODO: what other schedule constraints?
//

endmodule


