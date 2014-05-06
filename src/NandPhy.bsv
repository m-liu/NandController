//Potential timing problems:
// DQS and clk90 are not aligned on a read. It appears that ISERDESE2 align its output to 
// OCLK (which is clk90), but I cannot be sure. 
// ISERDESE2 is a secureip. Don't know when we violate timing or how much to shift IDELAY by. 
//At power up, default mode is * asynchronous mode 0 *

//TODOOK: initialization: wait at least 100us after power up
//TODO: initial values of CEN, WPN etc. is incorrect for a bit after power up
//			need to set INIT parameter in FDRE reg
//TODO try setting method as clocked_by(no_clock);
//TODOOK change reset routine to use a single state and to use wait rule
//TODOOK go bus idle after each command
//TODO separate CEs!

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
	method Action sendCmd (ControllerCmd cmd);
	method ActionValue#(Bit#(8)) asyncRdByte();
endinterface

interface NandPhyIfc;
	(* prefix = "" *)
	interface NANDPins nandPins;
	interface PhyUser phyUser;
endinterface


typedef enum {
	INIT_WAIT				= 0,
	ADJ_IDELAY_DQ			= 1,
	ADJ_IDELAY_DQS			= 2,
	INIT_NAND_PWR_WAIT	= 3,
	INIT_WP					= 4,
	WAIT_CYCLES				= 5,
	IDLE						= 6,
	ASYNC_BUS_IDLE			= 7,
	ASYNC_CMD_SET_CMD		= 8,
	ASYNC_CMD_LATCH_WE	= 9,
	ASYNC_READ_RE_LOW		= 10,
	ASYNC_READ_CAPTURE	= 11,
	ASYNC_READ_RE_HIGH	= 12,

	SYNC_CMD					= 13,
	SYNC_BUS_IDLE			= 14,
	
	DONE						= 100


} PhyState deriving (Bits, Eq);

typedef enum {
	PHY_ASYNC_BUS_IDLE,
	PHY_ASYNC_SEND_NAND_CMD,
	PHY_ASYNC_READ
} PhyCmd deriving (Bits, Eq);

typedef enum {
	N_RESET = 8'hFF,
	N_READ_STATUS = 8'h70,
	N_SET_FEATURES = 8'hEF
} NandCmd deriving (Bits, Eq);


typedef struct {
	PhyCmd phyCmd;
	NandCmd nandCmd;
	Bit#(16) numBurst;
	Bit#(32) postCmdWait; //number of cycles to wait after the command
} ControllerCmd deriving (Bits, Eq);


//Default clock and resets are: clk0 and rst0
(* synthesize *)
module mkNandPhy#(
	Clock clk90, 
	Reset rst90
	)(NandPhyIfc);

	//Conservative timing parameters. In clock cycles. a
	Integer t_SYS_RESET = 1000; //System reset wait
	Integer t_POWER_UP = 10000; //100us. TODO: Reduced to 1us for sim. 
	Integer t_WW = 20; //100ns. Write protect wait time.
	Integer t_ASYNC_CMD_SETUP = 8; //Async reset setup time before WE# latch
	Integer t_ASYNC_CMD_HOLD = 5; //Async reset hold time after WE# latch
	Integer t_RP = 7; //50ns. Async RE# pulse width. Mode 0.
	Integer t_REH = 5; //30ns. Async RE# High hold time. Note: tRC=tRP+tREH >100ns


	//IDelay Tap value (0 to 31)
	Integer idelayDQS = 10;
	Integer idelayDQ = 0;


	Clock defaultClk0 <- exposeCurrentClock();
	Reset defaultRst0 <- exposeCurrentReset();

	VNANDPhy vnandPhy <- vMkNandPhy(defaultClk0, clk90, defaultRst0, rst90);
				/*clocked_by nandInfra.clk0, reset_by nandInfra.rstn0*/
	

	//State registers
	Reg#(PhyState) currState <- mkReg(INIT_WAIT);
	Reg#(PhyState) returnState <- mkReg(INIT_WAIT);
	Reg#(PhyState) currState90 <- mkSyncRegFromCC(INIT_WAIT, clk90);

	//Timing wait counters
	Reg#(Bit#(32)) waitCnt <- mkReg(0);

	//Registers for command inputs
	Reg#(Bit#(2)) cen <- mkReg(2'b11);
	Reg#(Bit#(1)) cle <- mkReg(0);
	Reg#(Bit#(1)) ale <- mkReg(0);
	Reg#(Bit#(1)) wrn <- mkReg(1);
	Reg#(Bit#(1)) wen <- mkReg(1);
	Reg#(Bit#(1)) wenSel <- mkReg(1); //WE# by default. until sync mode active
	Reg#(Bit#(1)) wpn <- mkReg(0);
	Reg#(Bit#(1)) cmdSelDQ <- mkReg(1);

	//Registers for write data DQ
	Reg#(Bit#(8)) wrDataRise <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(8)) wrDataFall <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(1)) oenDataDQ <- mkReg(1, clocked_by clk90, reset_by rst90);

	//Registers for command DQ. Beware of timing: actually clocked by clk90. 
	Reg#(Bit#(1)) oenCmdDQ <- mkReg(1);
	Reg#(Bit#(8)) wrCmdDQ <- mkReg(0);

	//Delay adjustment registers
	Reg#(Bit#(5)) incIdelayDQS_90 <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(1)) dlyIncDQSr <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(1)) dlyCeDQSr <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bool) initDoneSync <- mkSyncRegToCC(False, clk90, rst90);

	//Debug registers
	Reg#(Bit#(8)) rdFall <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(8)) rdRise <- mkReg(0, clocked_by clk90, reset_by rst90);
	Reg#(Bit#(8)) debugR90 <- mkReg(0, clocked_by clk90, reset_by rst90);

	//Command FIFO
	FIFOF#(ControllerCmd) ctrlCmdQ <- mkFIFOF();
	Reg#(Bit#(16)) numBurstCnt <- mkReg(0);
	Reg#(Bit#(32)) postCmdWaitCnt <- mkReg(0);

	//Read data FIFO
	FIFO#(Bit#(8)) asyncRdQ <- mkSizedFIFO(256); //TODO adjust size

	//**********************************************
	// Buffer phy signals using registers in front
	//**********************************************
	rule regBufs90;
		vnandPhy.vphyUser.dlyCeDQS(dlyCeDQSr);
		vnandPhy.vphyUser.dlyIncDQS(dlyIncDQSr);
		vnandPhy.vphyUser.setDebug90(debugR90);
		vnandPhy.vphyUser.oenDataDQ(oenDataDQ);
		vnandPhy.vphyUser.wrDataRiseDQ(wrDataRise);
		vnandPhy.vphyUser.wrDataFallDQ(wrDataFall);
	endrule

	rule regBufs;
		vnandPhy.vphyUser.setCLE(cle);
		vnandPhy.vphyUser.setALE(ale);
		vnandPhy.vphyUser.setWRN(wrn);
		vnandPhy.vphyUser.setWPN(wpn);
		vnandPhy.vphyUser.setCEN(cen);
		vnandPhy.vphyUser.setWEN(wen);
		vnandPhy.vphyUser.setWENSel(wenSel);
		vnandPhy.vphyUser.oenCmdDQ(oenCmdDQ);
		vnandPhy.vphyUser.wrCmdDQ(wrCmdDQ);
		vnandPhy.vphyUser.cmdSelDQ(cmdSelDQ);
	endrule

	//wait rule
	rule doWaitCycles if (currState==WAIT_CYCLES);
		if (waitCnt>0) begin
			waitCnt <= waitCnt-1;
		end
		else begin
			currState <= returnState;
		end
	endrule
		
	//**********************************************
	// Initialize IDELAY and NAND chip
	//**********************************************

	rule doInitWait if (currState==INIT_WAIT);
		cle <= 0;
		ale <= 0;
		wrn <= 1;
		wpn <= 0;
		cen <= 2'b11;
		wen <= 1;
		wenSel <= 1; //disable nand_clk
		waitCnt <= fromInteger(t_SYS_RESET);
		currState <= WAIT_CYCLES;
		returnState <= ADJ_IDELAY_DQS;
		$display("@%t\t NandPhy: INIT_WAIT", $time);
	endrule

	rule doWaitIdelayDQS if (currState==ADJ_IDELAY_DQS);
		if (initDoneSync==True) begin
			currState <= INIT_NAND_PWR_WAIT;
		end
	endrule

	//power up initialization by the NAND
	rule doInitNandPwrWait if (currState==INIT_NAND_PWR_WAIT);
		waitCnt <= fromInteger(t_POWER_UP);
		currState <= WAIT_CYCLES;
		returnState <= INIT_WP; 
		$display("@%t\t NandPhy: INIT_NAND_PWR_WAIT", $time);
	endrule

	//Turn off Write Protect. Wait tWW (>100ns). WP is always active, thus don't need CE. 
	rule doWP if (currState==INIT_WP);
		wpn <= 1;
		waitCnt <= fromInteger(t_WW);
		currState <= WAIT_CYCLES;
		returnState <= IDLE; 
		$display("@%t\t NandPhy: INIT_WP", $time);
	endrule

	//****************************************
	// Idle and accepting new commands
	//****************************************

	rule doIdle if (currState==IDLE);
		let cmd = ctrlCmdQ.first();
		case(cmd.phyCmd)
			PHY_ASYNC_BUS_IDLE: currState <= ASYNC_BUS_IDLE;
			PHY_ASYNC_SEND_NAND_CMD: currState <= ASYNC_CMD_SET_CMD;
			PHY_ASYNC_READ: currState <= ASYNC_READ_RE_LOW;
			default: currState <= IDLE;
		endcase
		numBurstCnt <= cmd.numBurst;
		postCmdWaitCnt <= cmd.postCmdWait;
		$display("@%t\t NandPhy: New command received: %x", $time, cmd.phyCmd);
	endrule

	//****************************************
	// Async bus idle
	//****************************************
	rule doAsyncCmdBusIdle if (currState==ASYNC_BUS_IDLE);
		cen <= 2'b00; //CE# low
		cle <= 0; //DC
		ale <= 0; //DC
		wrn <= 1; //RE# high
		wen <= 1;//select and set WE# high (NAND_CLK)
		wenSel <= 1; 
		cmdSelDQ <= 1; //default
		oenCmdDQ <= 1; //disable output
		currState <= IDLE;
		ctrlCmdQ.deq();
		$display("@%t\t NandPhy: ASYNC_BUS_IDLE", $time);
	endrule

	//****************************************
	// Async command execution
	//****************************************
	rule doAsyncCmdSetup if (currState==ASYNC_CMD_SET_CMD);
		cen <= 2'b00;
		cle <= 1;
		ale <= 0;
		wen <= 0; 
		wenSel <= 1;
		cmdSelDQ <= 1;
		oenCmdDQ <= 0; //enable cmd output on DQ
		wrCmdDQ <= pack(ctrlCmdQ.first().nandCmd); //set command
		//Wait for setup
		waitCnt <= fromInteger(t_ASYNC_CMD_SETUP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_CMD_LATCH_WE;
		$display("@%t\t NandPhy: ASYNC_CMD_SET_CMD", $time);
	endrule

	rule doAsyncCmdLatch if (currState==ASYNC_CMD_LATCH_WE);
		wen <= 1;
		waitCnt <= fromInteger(t_ASYNC_CMD_HOLD);
		currState <= WAIT_CYCLES;
		returnState <= DONE;
		$display("@%t\t NandPhy: ASYNC_CMD_LATCH_WE", $time);
	endrule

	//****************************************
	// Async read; Assume bus idle
	//****************************************
	rule doAsyncReadReLow if (currState==ASYNC_READ_RE_LOW);
		cle <= 0;
		ale <= 0;
		cmdSelDQ <= 1;
		//TODO this appears to be a hack because we should be using oenDataDQ, 
		// but that's in the clk90 domain
		oenCmdDQ <= 1; //disable output. 
		//toggle RE# to capture data
		wrn <= 0;
		//wait tRP
		waitCnt <= fromInteger(t_RP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_READ_CAPTURE;
		$display("@%t\t NandPhy: ASYNC_READ_RE_LOW", $time);
	endrule

	rule doAsyncReadCapture if (currState==ASYNC_READ_CAPTURE);
		//get data
		let rddata = vnandPhy.vphyUser.rdDataCombDQ();
		asyncRdQ.enq(rddata);
		$display("@%t\t NandPhy: ASYNC_READ_CAPTURE sync read data %x", $time, rddata);
		currState <= ASYNC_READ_RE_HIGH;
	endrule
	

	rule doAsyncReadReHigh if (currState==ASYNC_READ_RE_HIGH);
		wrn <= 1;
		//wait tREH
		waitCnt <= fromInteger(t_REH);
		currState <= WAIT_CYCLES;
		//if done bursting, go idle. otherwise keep toggling RE#
		if (numBurstCnt==0) begin
			returnState <= DONE;
		end
		else begin
			returnState <= ASYNC_READ_RE_LOW;
			numBurstCnt <= numBurstCnt - 1;
		end
		$display("@%t\t NandPhy: ASYNC_READ_RE_HIGH", $time);
	endrule


	//**************************
	// Go bus idle if done
	//**************************
	rule doDone if (currState==DONE);
		cen <= 2'b00; //CE# low
		cle <= 0; //DC
		ale <= 0; //DC
		wrn <= 1; //RE# high
		wen <= 1;//select and set WE# high (NAND_CLK)
		wenSel <= 1; 
		cmdSelDQ <= 1; //default
		oenCmdDQ <= 1; //disable output

		//post command wait
		if (postCmdWaitCnt > 0) begin
			currState <= WAIT_CYCLES;
			waitCnt <= postCmdWaitCnt;
			returnState <= IDLE;
		end
		else begin
			currState <= IDLE;
		end
		ctrlCmdQ.deq();
		$display("@%t\t NandPhy: DONE", $time);
	endrule



	//**************************
	// clk90 domain rules
	//**************************
	//synchronize state to clk90 domain
	rule syncState;
		currState90<=currState;
	endrule

	rule doIdle90 if (currState90==IDLE);
		rdFall <= vnandPhy.vphyUser.rdDataFallDQ();
		rdRise <= vnandPhy.vphyUser.rdDataRiseDQ();
		//$display("rdRise=%x, rdFall=%x", rdRise, rdFall);

		//prevent optimizing everything away
		if (rdFall==rdRise) begin
			debugR90 <= 1;
		end
		else begin
			debugR90 <= 0;
		end
	endrule

	//Init in clk90 domain
	rule doInitWait90 if (currState90==INIT_WAIT);
		initDoneSync <= False;
		dlyIncDQSr <= 0;
		dlyCeDQSr <= 0;
		incIdelayDQS_90 <= 0;
	endrule

	rule doAdjIdelayDQS90 if (currState90==ADJ_IDELAY_DQS);
		if (incIdelayDQS_90 != fromInteger(idelayDQS)) begin
			$display("@%t\t NandPhy: incremented dqs idelay", $time);
			dlyIncDQSr <= 1;
			dlyCeDQSr <= 1;
			incIdelayDQS_90 <= incIdelayDQS_90 + 1;
		end
		else begin
			dlyIncDQSr <= 0;
			dlyCeDQSr <= 0;
			initDoneSync <= True;
		end
	endrule
	




	rule doDisableDQS;
		vnandPhy.vphyUser.oenDQS(1);
	endrule


	//*****************************************************
	// Interface
	//*****************************************************
	
	interface PhyUser phyUser;
		method Action sendCmd (ControllerCmd cmd);
			ctrlCmdQ.enq(cmd);
		endmethod

		method ActionValue#(Bit#(8)) asyncRdByte();
			asyncRdQ.deq();
			return asyncRdQ.first();
		endmethod
	endinterface

	interface nandPins = vnandPhy.nandPins;


endmodule


/*
	rule doNandResetIdle if (currState==INIT_RESET && nandRstSt==BUS_IDLE);
		wen <= 1;//select and set WE# high (NAND_CLK)
		wenSel <= 1;
		cen <= 2'b00; //CE# low
		wrn <= 1; //RE# high
		cle <= 0; //DC
		ale <= 0; //ALE low
		nandRstSt<= SET_RST_CMD;
	endrule

	//setup the command lines for reset command (>5 cycles setup)
	rule doNandResetSetCmd if (currState==INIT_RESET && nandRstSt==SET_RST_CMD);
		cen <= 2'b00; //CE# low, redundant
		ale <= 0;	//ALE low, redundant
		cle <= 1; 	//CLE high
		wrn <= 1; 	//RE# high, redundant
		wen <= 0;	//WE# low
		wenSel <= 1; 
		cmdSelDQ <= 1; //Select and set DQ=8'hFF for reset
		wrCmdDQ <= 8'hFF; 
		oenCmdDQ <= 0; //enable DQ output
		//Wait for setup
		if (waitCnt>=fromInteger(t_ASYNC_CMD_SETUP)) begin
			nandRstSt<=LATCH_WE;
			waitCnt <= 0;
		end
		else begin
			waitCnt <= waitCnt+1;
		end
	endrule
	
	//Latch using WE#
	rule doNandResetLatch if (currState==INIT_RESET && nandRstSt==LATCH_WE);
		wen <= 1; //set WE# high to latch 
		if (waitCnt>=fromInteger(t_ASYNC_CMD_HOLD)) begin
			nandRstSt <= WAIT_POR;
			waitCnt <= 0;
		end
		else begin
			waitCnt <= waitCnt+1;
		end
	endrule

	//Go bus idle. wait for power on reset. 1ms
	rule doNandResetPOR if (currState==INIT_RESET && nandRstSt==WAIT_POR);
		wen <= 1;//select and set WE# high (NAND_CLK)
		wenSel <= 1;
		cen <= 2'b00; //CE# low
		wrn <= 1; //RE# high
		cle <= 0; //DC
		ale <= 0; //ALE low
		oenCmdDQ <= 1; //release bus
		if (waitCnt>=fromInteger(t_POR)) begin
			currState <= IDLE;
			waitCnt <= 0;
		end
		else begin
			waitCnt <= waitCnt+1;
		end
	endrule
*/
