import Connectable       ::*;
import Clocks            ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;
import TriState          ::*;
import Vector            ::*;
import Counter           ::*;
import DefaultValue      ::*;

import NandPhyWrapper::*;
import NandInfra::*;

interface NANDPhyIfc;
	(* prefix = "" *)
	interface NANDPins nandPins;
endinterface

(* no_default_clock, no_default_reset *)
(* synthesize *)
module mkNandPhy#(
	Clock sysClkP, 
	Clock sysClkN, 
	Reset sysRstn
	)(NANDPhyIfc);

	NandInfraIfc nandInfra <- mkNandInfra(sysClkP, sysClkN, sysRstn);
	VNANDPhy vnandPhy <- vMkNandPhy(nandInfra.clk0, nandInfra.clk90, nandInfra.rstn0, nandInfra.rstn90
				/*clocked_by nandInfra.clk0, reset_by nandInfra.rstn0*/);

	Reg#(Bit#(8)) rdFall <- mkReg(0, clocked_by nandInfra.clk90, reset_by nandInfra.rstn90);
	Reg#(Bit#(8)) rdRise <- mkReg(0, clocked_by nandInfra.clk90, reset_by nandInfra.rstn90);
	rule doReadData;
		rdFall <= vnandPhy.vphyUser.rdDataFallDQ();
		rdRise <= vnandPhy.vphyUser.rdDataRiseDQ();
		$display("rdRise=%x, rdFall=%x", rdRise, rdFall);
	endrule

	rule doSetCLE;
		vnandPhy.vphyUser.setCLE(0);
		vnandPhy.vphyUser.setALE(0);
		vnandPhy.vphyUser.setWRN(0);
		vnandPhy.vphyUser.setWPN(0);
		vnandPhy.vphyUser.setCEN(0);
	endrule

	rule doDisableDQS;
		vnandPhy.vphyUser.oenDQS(1);
	endrule
	rule doDisableDQDQS;
		vnandPhy.vphyUser.oenDQ(1);
	endrule
		

	interface nandPins = vnandPhy.nandPins;


endmodule

