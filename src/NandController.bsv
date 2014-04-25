
import FIFOF             ::*;
import Vector            ::*;

import NandPhyWrapper::*;
import NandInfra::*;
import NandPhy::*;


interface NandControllerIfc;
	(* prefix = "" *)
	interface NANDPins nandPins;
endinterface


(* no_default_clock, no_default_reset *)
(* synthesize *)
module mkNandController#(
	Clock sysClkP, 
	Clock sysClkN, 
	Reset sysRstn
	)(NandControllerIfc);
	
	NandInfraIfc nandInfra <- mkNandInfra(sysClkP, sysClkN, sysRstn);
	NandPhyIfc phy <- mkNandPhy(nandInfra.clk90, nandInfra.rstn90, clocked_by nandInfra.clk0, reset_by nandInfra.rstn0);

	//testing
	Reg#(Bit#(32)) nCmds <- mkReg(1, clocked_by nandInfra.clk0, reset_by nandInfra.rstn0);

	rule doCmd if (nCmds>0);
		phy.phyUser.incDelayDQS(10);
		nCmds <= nCmds-1;
	endrule

	interface nandPins = phy.nandPins;

endmodule

