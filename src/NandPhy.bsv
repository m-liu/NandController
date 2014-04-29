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

interface PhyUser;
	method Action incDelayDQS (Bit#(5) val);
endinterface

interface NandPhyIfc;
	(* prefix = "" *)
	interface NANDPins nandPins;
	interface PhyUser phyUser;
endinterface


typedef enum {
	INIT,
	IDLE,
	ADJ_IDELAY_DQ,
	ADJ_IDELAY_DQS
} State deriving (Bits, Eq);


/*
typedef enum {
	
} PhyCommand deriving (Bits, Eq);
*/


//Default clock and resets are: clk0 and rst0
(* synthesize *)
module mkNandPhy#(
	Clock clk90, 
	Reset rst90
	)(NandPhyIfc);

	Clock defaultClk0 <- exposeCurrentClock();
	Reset defaultRst0 <- exposeCurrentReset();

	VNANDPhy vnandPhy <- vMkNandPhy(defaultClk0, clk90, defaultRst0, rst90);
				/*clocked_by nandInfra.clk0, reset_by nandInfra.rstn0*/
	
	Reg#(State) currState <- mkReg(IDLE);

	Reg#(State) state_90 <- mkReg(INIT, clocked_by clk90, reset_by rst90);
	//Reg#(Bool) initDoneSync <- mkSyncRegToCC(False, clk90, rst90);
	Reg#(Bool) initDone_90 <- mkReg(False, clocked_by clk90, reset_by rst90);

	//SyncFIFOIfc#(Bit#(5)) incIdelayDQS_Sync <- mkSyncFIFOFromCC(2, clk90);
	Reg#(Bit#(5)) incIdelayDQS_90 <- mkReg(0, clocked_by clk90, reset_by rst90);

	Reg#(Bit#(1)) dlyIncDQSr <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(1)) dlyCeDQSr <- mkReg(0, clocked_by clk90, reset_by rst90);

	Reg#(Bit#(32)) idleCnt <- mkReg(0, clocked_by clk90, reset_by rst90);
	
	Reg#(Bit#(8)) rdFall <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(8)) rdRise <- mkReg(0, clocked_by clk90, reset_by rst90);

	Reg#(Bit#(8)) debugR90 <- mkReg(0, clocked_by clk90, reset_by rst90);

	rule regBufs;
		vnandPhy.vphyUser.dlyCeDQS(dlyCeDQSr);
		vnandPhy.vphyUser.dlyIncDQS(dlyIncDQSr);

		vnandPhy.vphyUser.setDebug90(debugR90);
	endrule

	rule adjIdelay if (state_90==INIT);
		if (incIdelayDQS_90 != 10) begin
			$display("NandPhy: incremented dqs idelay");
			dlyIncDQSr <= 1;
			dlyCeDQSr <= 1;
			incIdelayDQS_90 <= incIdelayDQS_90 + 1;
		end
		else begin
			dlyIncDQSr <= 0;
			dlyCeDQSr <= 0;
			//incIdelayDQS_90 <= 0;
			//initDoneSync <= True;
			//incIdelayDQS_Sync.deq();
			state_90 <= IDLE;
		end
		
	endrule

	/*
	rule doCnt if (state_90==IDLE);
		idleCnt <= idleCnt+1;
		$display("NandPhy: idle");
	endrule
	*/
	
	/*
	rule syncIdelay if (state_90==INIT);
		if (incIdelayDQS_Sync.first()>0) begin
			state_90 <= ADJ_IDELAY_DQS;
		end
	endrule

	rule doAdjDQS if (state_90==ADJ_IDELAY_DQS);
		if (incIdelayDQS_90 != incIdelayDQS_Sync.first()) begin
			$display("NandPhy: incremented dqs idelay");
			dlyIncDQSr <= 1;
			dlyCeDQSr <= 1;
			incIdelayDQS_90 <= incIdelayDQS_90 + 1;
		end
		else begin
			dlyIncDQSr <= 0;
			dlyCeDQSr <= 0;
			incIdelayDQS_90 <= 0;
			initDoneSync <= True;
			incIdelayDQS_Sync.deq();
		end
	endrule
	

	rule doIdle if (initDoneSync==True && currState==IDLE);
		$display("idle");
	endrule
	*/


	rule doReadData if (state_90==IDLE);
	//hacks...
	//		dlyIncDQSr <= 0;
	//		dlyCeDQSr <= 0;
		rdFall <= vnandPhy.vphyUser.rdDataFallDQ();
		rdRise <= vnandPhy.vphyUser.rdDataRiseDQ();
		$display("rdRise=%x, rdFall=%x", rdRise, rdFall);

		//prevent optimizing everything away
		if (rdFall==rdRise) begin
			debugR90 <= 1;
		end
		else begin
			debugR90 <= 0;
		end
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


	//*****************************************************
	// Interface
	//*****************************************************
	
	interface PhyUser phyUser;
		method Action incDelayDQS (Bit#(5) val);
			//incIdelayDQS_Sync.enq(val);
		endmethod
	endinterface

	interface nandPins = vnandPhy.nandPins;


endmodule

