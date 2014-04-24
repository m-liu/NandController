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
endinterface 

(* always_ready, always_enabled *)
interface VPhyUser;
	method Action setCLE (Bit#(1) cleVal);
	method Action setALE (Bit#(1) aleVal);
	method Action setWRN (Bit#(1) wrnVal);
	method Action setWPN (Bit#(1) wpnVal);
	method Action setCEN (Bit#(2) cenVal);
	
	//DQS delay control; clk90 domain
	method Action dlyIncDQS (Bit#(1) i);
	method Action dlyCeDQS (Bit#(1) i);

	//DQS output; clk0 domain
	method Action oenDQS (Bit#(1) i);
	method Action rstnDQS (Bit#(1) i);

	//DQ delay control; clk90 domain
	method Action dlyIncDQ (Bit#(8) i);
	method Action dlyCeDQ (Bit#(8) i);
	method Action oenDQ (Bit#(1) i);
	
	method Action wrDataRiseDQ (Bit#(8) d);
	method Action wrDataFallDQ (Bit#(8) d);
	method Bit#(8) rdDataRiseDQ();
	method Bit#(8) rdDataFallDQ();
endinterface


interface VNANDPhy;
	(* prefix = "" *)
	interface NANDPins   nandPins;
	(* prefix = "" *)
	interface VPhyUser  vphyUser;
endinterface



import "BVI" nand_phy =
module vMkNandPhy#(/*NAND_Phy_Configure cfg,*/Clock clk0, Clock clk90, Reset rst0, Reset rst90)(VNANDPhy);

//no default clock and reset
default_clock no_clock; 
default_reset no_reset;

//parameter DQ_WIDTH      = cfg.dq_width;
//parameter DQ_PER_DQS = cfg.dq_per_dqs;

input_clock clk0(v_clk0, (*unused*)vclk0_GATE) = clk0;
input_clock clk90(v_clk90, (*unused*)vclk90_GATE) = clk90;
input_reset rst0(v_rst0) clocked_by (clk0) = rst0;
input_reset rst90(v_rst90) clocked_by (clk90) = rst90;

interface NANDPins nandPins;
	ifc_inout dq(v_dq)             clocked_by(no_clock) reset_by(no_reset);
	ifc_inout dqs(v_dqs)           clocked_by(no_clock) reset_by(no_reset);

	method    v_nand_clk       nand_clk     clocked_by(no_clock) reset_by(no_reset);
	method    v_cle 	cle         clocked_by(no_clock) reset_by(no_reset);
	method    v_ale 	ale         clocked_by(no_clock) reset_by(no_reset);
	method    v_wrn 	wrn         clocked_by(no_clock) reset_by(no_reset);
	method    v_wpn 	wpn         clocked_by(no_clock) reset_by(no_reset);
	method    v_cen 	cen         clocked_by(no_clock) reset_by(no_reset);
endinterface


interface VPhyUser vphyUser;
	method setCLE (v_ctrl_cle) enable((*inhigh*)en0) clocked_by(clk0) reset_by(rst0);
	method setALE (v_ctrl_ale) enable((*inhigh*)en1) clocked_by(clk0) reset_by(rst0);
	method setWRN (v_ctrl_wrn) enable((*inhigh*)en2) clocked_by(clk0) reset_by(rst0);
	method setWPN (v_ctrl_wpn) enable((*inhigh*)en3) clocked_by(clk0) reset_by(rst0);
	method setCEN (v_ctrl_cen) enable((*inhigh*)en4) clocked_by(clk0) reset_by(rst0);
	
	//DQS delay control; clk90 domain
	method dlyIncDQS (v_dlyinc_dqs) enable((*inhigh*) en5) clocked_by(clk90) reset_by(rst90);
	method dlyCeDQS (v_dlyce_dqs) enable((*inhigh*) en6) clocked_by(clk90) reset_by(rst90);

	//DQS output; clk0 domain
	method oenDQS (v_dqs_oe_n) enable((*inhigh*) en7) clocked_by(clk0) reset_by(rst0); //active low
	method rstnDQS (v_dqs_rst_n) enable((*inhigh*) en8) clocked_by(clk0) reset_by(rst0);

	//DQ delay control; clk90 domain
	method dlyIncDQ (v_dlyinc_dq) enable((*inhigh*) en9) clocked_by(clk90) reset_by(rst90);
	method dlyCeDQ (v_dlyce_dq) enable((*inhigh*) en10) clocked_by(clk90) reset_by(rst90);
	method oenDQ (v_dq_oe_n) enable((*inhigh*) en11) clocked_by(clk90) reset_by(rst90); //active low
	
	method wrDataRiseDQ (v_wr_data_rise) enable((*inhigh*) en12) clocked_by(clk90) reset_by(rst90);
	method wrDataFallDQ (v_wr_data_fall) enable((*inhigh*) en13) clocked_by(clk90) reset_by(rst90);
	method v_rd_data_rise rdDataRiseDQ() clocked_by(clk90) reset_by(rst90);
	method v_rd_data_fall rdDataFallDQ() clocked_by(clk90) reset_by(rst90);
endinterface

//NAND pins are CF
schedule 
(nandPins_nand_clk, nandPins_cle, nandPins_ale, nandPins_wrn, nandPins_wpn, nandPins_cen) 
CF
(nandPins_nand_clk, nandPins_cle, nandPins_ale, nandPins_wrn, nandPins_wpn, nandPins_cen);

//Delay controls areCF
schedule
(vphyUser_dlyIncDQS, vphyUser_dlyCeDQS, vphyUser_dlyIncDQ, vphyUser_dlyCeDQ)
CF
(vphyUser_dlyIncDQS, vphyUser_dlyCeDQS, vphyUser_dlyIncDQ, vphyUser_dlyCeDQ);

//Control signals are CF
schedule
(vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN)
CF
(vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN);


//read and writes are conflicting
/*
schedule
(wrDataRiseDQ, wrDataFallDQ)
C 
(rdDataRiseDQ, rdDataFallDQ);
*/
//TODO: what other schedule constraints?


endmodule


