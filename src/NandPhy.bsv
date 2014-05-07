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
//TODO separate CEs! For now just select one of the targets

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
	method Action sendAddr (Bit#(8) addr);
	method Action asyncWrByte (Bit#(8) data);
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
	ASYNC_ADDR_WE_LOW		= 13,
	ASYNC_ADDR_WE_HIGH	= 14,
	ASYNC_WRITE_WE_LOW	= 15,
	ASYNC_WRITE_WE_HIGH	= 16,


	SYNC_CMD					= 30,
	SYNC_BUS_IDLE			= 31,
	
	DONE						= 100,
	DESELECT_ALL			= 101,
	ENABLE_NAND_CLK		= 102


} PhyState deriving (Bits, Eq);

typedef enum {
	PHY_ASYNC_BUS_IDLE,
	PHY_ASYNC_SEND_NAND_CMD,
	PHY_ASYNC_READ,
	PHY_ASYNC_WRITE,
	PHY_ASYNC_SEND_ADDR, 
	PHY_DESELECT_ALL,
	PHY_ENABLE_NAND_CLK
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
	Integer t_ASYNC_CMD_SETUP = 8; //Max async cmd/data setup time before WE# latch
	Integer t_ASYNC_CMD_HOLD = 5; //Max async cmd/data hold time after WE# latch
	Integer t_ASYNC_ADDR_SETUP = 8; //Max async addr setup time before WE# latch
	Integer t_ASYNC_ADDR_HOLD = 5; //Max async addr hold time after WE# latch
	Integer t_ASYNC_WRITE_SETUP = 8; //Max async wr data setup time before WE# latch
	Integer t_ASYNC_WRITE_HOLD = 5; //Max async wr data hold time after WE# latch
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

	//Command and address FIFO
	FIFOF#(ControllerCmd) ctrlCmdQ <- mkFIFOF();
	Reg#(Bit#(16)) numBurstCnt <- mkReg(0);
	Reg#(Bit#(32)) postCmdWaitCnt <- mkReg(0);
	FIFO#(Bit#(8)) addrQ <- mkFIFO();

	//Read data FIFO
	FIFO#(Bit#(8)) asyncRdQ <- mkSizedFIFO(256); //TODO adjust size
	FIFO#(Bit#(8)) asyncWrQ <- mkSizedFIFO(256); //TODO adjust size

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
		cen <= 2'b10;
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
			PHY_ASYNC_SEND_ADDR: currState <= ASYNC_ADDR_WE_LOW;
			PHY_ASYNC_WRITE: currState <= ASYNC_WRITE_WE_LOW;
			PHY_DESELECT_ALL: currState <= DESELECT_ALL;
			PHY_ENABLE_NAND_CLK: currState <= ENABLE_NAND_CLK;
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
		cen <= 2'b10; //CE# low
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
	// Async command
	//****************************************
	rule doAsyncCmdSetup if (currState==ASYNC_CMD_SET_CMD);
		cen <= 2'b10;
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
	// Async address cycle; assume bus idle
	//****************************************
	rule doAsyncAddrWeLow if (currState==ASYNC_ADDR_WE_LOW);
		//cen <= 2'b10; //CE# low
		cle <= 0; //Low
		ale <= 1; //High
		//wrn <= 1; //RE# high
		wen <= 0;//select and set WE# low
		wenSel <= 1; 
		cmdSelDQ <= 1; //default
		oenCmdDQ <= 0; //enable output. Note this signal needs 2 cycles to propogate
		wrCmdDQ <= addrQ.first(); //set address output
		addrQ.deq();
		//wait for setup
		waitCnt <= fromInteger(t_ASYNC_ADDR_SETUP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_ADDR_WE_HIGH;
		$display("@%t\t NandPhy: ASYNC_ADDR_WE_LOW set addr: %x", addrQ.first, $time);
	endrule

	rule doAsyncAddrWeHigh if (currState==ASYNC_ADDR_WE_HIGH);
		wen <= 1; //set WE# high to latch addr
		//wait for hold
		waitCnt <= fromInteger(t_ASYNC_ADDR_HOLD);
		currState <= WAIT_CYCLES;
		if (numBurstCnt==1) begin
			returnState <= DONE;
		end
		else begin
			returnState <= ASYNC_ADDR_WE_LOW;
			numBurstCnt <= numBurstCnt - 1;
		end
		$display("@%t\t NandPhy: ASYNC_ADDR_WE_HIGH", $time);
	endrule



	//*************************************************************
	// Async data input cycle (write to NAND); assume bus idle
	//*************************************************************
	rule doAsyncWriteWeLow if (currState==ASYNC_WRITE_WE_LOW);
		//cle <= 0; //Low
		//ale <= 0; //Low
		//wrn <= 1; //RE# high
		wen <= 0;//select and set WE# low
		wenSel <= 1; 
		cmdSelDQ <= 1; 
		oenCmdDQ <= 0; //enable output. Note this signal needs 2 cycles to propogate
		wrCmdDQ <= asyncWrQ.first(); //set data output
		asyncWrQ.deq();
		//wait for setup
		waitCnt <= fromInteger(t_ASYNC_WRITE_SETUP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_WRITE_WE_HIGH;
		$display("@%t\t NandPhy: ASYNC_WRITE_WE_LOW set data: %x", $time, asyncWrQ.first);
	endrule

	rule doAsyncWriteWeHigh if (currState==ASYNC_WRITE_WE_HIGH);
		wen <= 1; //set WE# high to latch write data
		//wait for hold
		waitCnt <= fromInteger(t_ASYNC_WRITE_HOLD);
		currState <= WAIT_CYCLES;
		if (numBurstCnt==1) begin
			returnState <= DONE;
		end
		else if (numBurstCnt>0) begin
			returnState <= ASYNC_WRITE_WE_LOW;
			numBurstCnt <= numBurstCnt - 1;
		end
		else begin
			$display("NandPhy: ERROR: num bursts is incorrect. Must be >1");
		end
		$display("@%t\t NandPhy: ASYNC_WRITE_WE_HIGH", $time);
	endrule


	//*************************************************************
	// Async data output cycle (read from NAND); Assume bus idle
	//*************************************************************
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
		if (numBurstCnt==1) begin
			returnState <= DONE;
		end
		else if (numBurstCnt > 1) begin
			returnState <= ASYNC_READ_RE_LOW;
			numBurstCnt <= numBurstCnt - 1;
		end
		else begin
			$display("NandPhy: ERROR: num bursts is incorrect. Must be >1");
		end
		$display("@%t\t NandPhy: ASYNC_READ_RE_HIGH", $time);
	endrule


	//**************************
	// Go bus idle if done
	//**************************
	rule doDone if (currState==DONE);
		cen <= 2'b10; //CE# low
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

	//TODO: code a bit verbose here
	//******************************************************
	// Deselect all targets. Should be in bus idle already
	//******************************************************
	rule doDeselect if (currState==DESELECT_ALL);
		cen <= 2'b11;
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
		$display("@%t\t NandPhy: DESELECT_ALL", $time);
	endrule


	//******************************************************
	// Enable clock for sync mode
	//******************************************************
	rule doEnNandClock if (currState==ENABLE_NAND_CLK);
		wenSel <= 0;
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
		$display("@%t\t NandPhy: ENABLE_NAND_CLK", $time);
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

		method Action sendAddr (Bit#(8) addr);
			addrQ.enq(addr);
		endmethod

		method Action asyncWrByte (Bit#(8) data);
			asyncWrQ.enq(data);
		endmethod

		method ActionValue#(Bit#(8)) asyncRdByte();
			asyncRdQ.deq();
			return asyncRdQ.first();
		endmethod
	endinterface

	interface nandPins = vnandPhy.nandPins;


endmodule

