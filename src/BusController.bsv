import FIFOF             ::*;
import FIFO             ::*;
import Vector            ::*;

import NandPhyWrapper::*;
import NandPhy::*;

typedef enum {
	IDLE,
	WAIT_CYCLES,

	INIT,
	INIT_ACT_SYNC,
	INIT_CALIB,

	SYNC_READ_PAGE_REQ,
	SYNC_READ_DATA,
	SYNC_WRITE_PAGE,
	SYNC_ERASE_BLOCK,
	SYNC_POLL_STATUS,
	SYNC_POLL_STATUS_POLL,

	ASYNC_POLL_STATUS,
	ASYNC_POLL_STATUS_POLL
} CtrlState deriving (Bits, Eq);


typedef enum {
	INIT_BUS,
	READ_PAGE,
	WRITE_PAGE,
	ERASE_BLOCK
} SsdCmd deriving (Bits, Eq);


typedef struct {
	SsdCmd ssdCmd;
	Bit#(4) chip;
	Bit#(16) block;
	Bit#(8) page;
} BusCmd deriving (Bits, Eq);

//NAND geometry
Integer pageSize = 8640; //bytes. 8kB + 448B ECC
Integer pagesPerBlock = 256;
Integer blocksPerPlane = 2048;
Integer planesPerLun = 2;
Integer lunsPerTarget = 1; //1 for SLC, 2 for MLC

interface BusIfc;
	method Action sendCmd (SsdCmd cmd, Bit#(4) chip, Bit#(16) block, Bit#(8) page);
	method Action writeWord (Bit#(16) data);
	method ActionValue#(Bit#(16)) readWord (); 
endinterface


interface BusControllerIfc;
	interface BusIfc busIfc;
	(* prefix = "" *)
	interface NANDPins nandPins;
endinterface

//(* no_default_clock, no_default_reset *)
//Default clock and rests are clk0 and rst0
(* synthesize *)
module mkBusController#(
	Clock clk90, 
	Reset rst90
	)(BusControllerIfc);
	
	//Timing parameters for timing parameters between different cycle types
	//using SHORT_RESET for simulation. Doens't matter because we poll
	// until status is ready
	Integer t_POR = 1000; //1ms. Power-on Reset time. TODO: reduced
	Integer t_WHR = 13; //120ns. WE# HIGH to RE# LOW
	Integer t_WB = 20; //200ns
	Integer t_ITC = 150; //1us (tITC)
	Integer t_ADL = 25; //200ns
	Integer t_RHW = 25; //200ns
	Integer t_EN_CLK = 1000; //Delay after enabling NAND CLK. Not in spec. 

	Integer t_WHR_SYNC = 8; //80ns. WE# HIGH to RE# LOW
	Integer t_ADL_SYNC = 7; //70ns
	Integer t_RHW_SYNC = 10; //100ns
	Integer t_WB_SYNC = 10; //100ns
	Integer t_BERS = 20000; //3.8 to 10ms. But start polling earlier.


	Integer nAddrBursts = 5; //5 addr bursts is standard
	Integer nAddrBurstsErase = 3; //3 addr bursts for erase
	
	//Nand PHY instantiation
	NandPhyIfc phy <- mkNandPhy(clk90, rst90);

	//States
	Reg#(CtrlState) state <- mkReg(IDLE);
	Reg#(CtrlState) returnState <- mkReg(IDLE);
	Reg#(CtrlState) rdyReturnState <- mkReg(IDLE);

	//Counters
	Reg#(Bit#(32)) waitCnt <- mkReg(0);
	Reg#(Bit#(8)) addrCnt <- mkReg(0);
	Reg#(Bit#(8)) cmdCnt <- mkReg(0);
	Reg#(Bit#(16)) dataCnt <- mkReg(0);

	//Debug
	Reg#(Bit#(16)) debugR <- mkReg(0);

	//Command/Data FIFOs
	FIFO#(BusCmd) cmdQ <- mkSizedFIFO(64); //TODO adjust
	FIFO#(Bit#(16)) writeQ <- mkSizedFIFO(128); //TODO adjust
	FIFO#(Bit#(16)) readQ <- mkSizedFIFO(128); //TODO adjust
	Reg#(BusCmd) cmdR <- mkRegU();
	Reg#(Bit#(4)) chipR <- mkReg(0);
	Vector#(5, Reg#(Bit#(8))) addrDecoded <- replicateM(mkReg(0));

	//******************************************************
	// Decode command
	//******************************************************
	rule doDecodeCmd if (state==IDLE);
		cmdCnt <= 0;
		addrCnt <= 0;
		dataCnt <= 0;
		let cmd = cmdQ.first();
		cmdQ.deq();
		cmdR <= cmd;
		case(cmd.ssdCmd)
			INIT_BUS: state <= INIT;
			READ_PAGE: state <= SYNC_READ_PAGE_REQ;
			WRITE_PAGE: state <= SYNC_WRITE_PAGE;
			ERASE_BLOCK: state <= SYNC_ERASE_BLOCK;
			default: state <= IDLE;
		endcase
		//decode addr
		chipR <= cmd.chip;
		addrDecoded[0] <= 0; //column addr
		addrDecoded[1] <= 0;
		addrDecoded[2] <= cmd.page;
		addrDecoded[3] <= truncate(cmd.block);
		addrDecoded[4] <= truncateLSB(cmd.block);
		$display("BusController: Executing command=%x", cmd.ssdCmd);
	endrule	



	//******************************************************
	// Wait rule; waits a certain number of cycles
	//******************************************************
	rule doWaitCycles if (state==WAIT_CYCLES);
		if (waitCnt>2) begin
			waitCnt <= waitCnt-1;
		end
		else begin
			state <= returnState;
		end
	endrule


	//******************************************************
	// Sync Read Page
	//******************************************************
	Integer nreadReqCmds = 4;
	PhyCmd readReqCmds[nreadReqCmds] = {
			PhyCmd { phyCycle: PHY_SYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_READ_MODE,
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBursts), postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_READ_PAGE_END, 
						numBurst: 0, postCmdWait: fromInteger(t_WB_SYNC)}
			};
	
	Integer nreadDataCmds = 4;
	PhyCmd readDataCmds[nreadDataCmds] = {
			PhyCmd { phyCycle: PHY_SYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_READ_MODE, 
						numBurst: 0, postCmdWait: fromInteger(t_WHR_SYNC)},
			PhyCmd {	phyCycle: PHY_SYNC_READ, nandCmd: ?, 
						numBurst: fromInteger(pageSize/2), postCmdWait: fromInteger(t_RHW_SYNC)},
			PhyCmd {	phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};

	rule doReadPageCmd if (state==SYNC_READ_PAGE_REQ && cmdCnt < fromInteger(nreadReqCmds));
		phy.phyUser.sendCmd(readReqCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule
		
	rule doReadPageAddr if (state==SYNC_READ_PAGE_REQ && addrCnt < fromInteger(nAddrBursts));
		phy.phyUser.sendAddr(addrDecoded[addrCnt]);
		addrCnt <= addrCnt + 1;
	endrule

	rule doReadPageWait if (state==SYNC_READ_PAGE_REQ && 
									addrCnt==fromInteger(nAddrBursts) && 
									cmdCnt==fromInteger(nreadReqCmds));
		state <= SYNC_POLL_STATUS;
		rdyReturnState <= SYNC_READ_DATA;
		cmdCnt <= 0;
		addrCnt <= 0;
		dataCnt <= 0;
	endrule

	rule doReadDataCmd if (state==SYNC_READ_DATA && cmdCnt < fromInteger(nreadDataCmds));
		phy.phyUser.sendCmd(readDataCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doReadData if (state==SYNC_READ_DATA && dataCnt < fromInteger(pageSize/2));
		let rd <- phy.phyUser.syncRdWord();
		readQ.enq(rd);
		debugR <= rd;
		dataCnt <= dataCnt + 1;
		$display("NandCtrl: read data: %x", rd);
	endrule

	rule doReadDataDone if (state==SYNC_READ_DATA && 
								dataCnt == fromInteger(pageSize/2) && 
								cmdCnt==fromInteger(nreadDataCmds));
		state <= IDLE;
	endrule


	//******************************************************
	// Sync Write Page
	//******************************************************
	Integer nwriteReqCmds = 6;	
	PhyCmd writeReqCmds[nwriteReqCmds] = {
			PhyCmd { phyCycle: PHY_SYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_PROGRAM_PAGE, 
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBursts), postCmdWait: fromInteger(t_ADL_SYNC)},
			PhyCmd {	phyCycle: PHY_SYNC_WRITE, nandCmd: ?, 
						numBurst: fromInteger(pageSize/2), postCmdWait: 0}, 
			PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_PROGRAM_PAGE_END, 
		 				numBurst: 0, postCmdWait: fromInteger(t_WB_SYNC)},
			PhyCmd {	phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};


	rule doWritePageCmd if (state==SYNC_WRITE_PAGE && cmdCnt < fromInteger(nwriteReqCmds));
		phy.phyUser.sendCmd(writeReqCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule
		
	rule doWritePageAddr if (state==SYNC_WRITE_PAGE && addrCnt < fromInteger(nAddrBursts));
		phy.phyUser.sendAddr(addrDecoded[addrCnt]); 
		addrCnt <= addrCnt + 1;
	endrule

	//TODO we need to make sure the write FIFO always has data, otherwise writes won't work
	rule doWritePageData if (state==SYNC_WRITE_PAGE && dataCnt < fromInteger(pageSize/2));
		phy.phyUser.syncWrWord(writeQ.first());
		writeQ.deq();
		dataCnt <= dataCnt + 1;
	endrule
		
	rule doWriteDone if (state==SYNC_WRITE_PAGE && dataCnt==fromInteger(pageSize/2) 
								&& cmdCnt==fromInteger(nwriteReqCmds) && 
								addrCnt==fromInteger(nAddrBursts));
		//wait for write to finish
		state <= SYNC_POLL_STATUS;
		rdyReturnState <= IDLE;
	endrule


		
	//******************************************************
	// Sync Erase Block
	//******************************************************
	Integer neraseCmds = 5;
	PhyCmd eraseCmds[neraseCmds] = {
			PhyCmd { phyCycle: PHY_SYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_ERASE_BLOCK, 
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBurstsErase), postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_ERASE_BLOCK_END, 
		 				numBurst: 0, postCmdWait: fromInteger(t_BERS)},
			PhyCmd {	phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};

	rule doEraseBlockCmd if (state==SYNC_ERASE_BLOCK && cmdCnt < fromInteger(neraseCmds));
		phy.phyUser.sendCmd(eraseCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doEraseBlockAddr if (state==SYNC_ERASE_BLOCK && 
									addrCnt < fromInteger(nAddrBurstsErase));
		//Write 3 row addresses (page, block) indices 2,3,4.
		//Note: page addr is ignored by the NAND, but still have to send it
		let ind = addrCnt+2;
		phy.phyUser.sendAddr(addrDecoded[ind]);
		addrCnt <= addrCnt + 1;
	endrule

	rule doEraseBlockPoll if (state==SYNC_ERASE_BLOCK && addrCnt==fromInteger(nAddrBurstsErase) && cmdCnt==fromInteger(neraseCmds));
		//wait for write to finish
		state <= SYNC_POLL_STATUS;
		rdyReturnState <= IDLE;
	endrule



	//******************************************************
	// Sync Poll Status
	//******************************************************
	Integer nstatusCmds = 4;
	PhyCmd statusCmds[nstatusCmds] = { 
			PhyCmd { phyCycle: PHY_SYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_READ_STATUS, 
			  			numBurst: 0, postCmdWait: fromInteger(t_WHR_SYNC)},
			PhyCmd {	phyCycle: PHY_SYNC_READ, nandCmd: ?, 
		 				numBurst: 1, postCmdWait: fromInteger(t_RHW_SYNC)},
			PhyCmd {	phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
		};
	rule doStatusCntReset if (state==SYNC_POLL_STATUS);
		cmdCnt <= 0;
		state <= SYNC_POLL_STATUS_POLL;
	endrule 

	rule doReadStatusCmd if (state==SYNC_POLL_STATUS_POLL && cmdCnt < fromInteger(nstatusCmds));
		phy.phyUser.sendCmd(statusCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doReadStatusGet if (state==SYNC_POLL_STATUS_POLL && cmdCnt==fromInteger(nstatusCmds));
		let status <- phy.phyUser.syncRdWord();
		cmdCnt <= 0;
		$display("NandCtrl: sync status=%x", status);
		debugR <= status; //debug

		//During calibration, get status is used to initialize IDDR regs so that we don't have
		//DON'T CARES
		if (rdyReturnState==INIT_CALIB) begin
			state <= rdyReturnState;
		end
		else begin
			if (status==16'hE0E0) begin //ready
				state <= rdyReturnState;
			end
			else begin
				//wait a while before polling
				waitCnt <= 100;
				state <= WAIT_CYCLES;
				returnState <= SYNC_POLL_STATUS_POLL;
			end
		end
	endrule


	//******************************************************
	// Initialization
	// 1) Go bus idle
	// 2) Issue power on reset; wait t_POR
	// 3) poll status until ready
	// 4) activate sync mode 5 interface
	// 5) release CE#, wait t_ITC+t_WB
	// 6) enable nand clock
	// 7) select CE#, go sync bus idle
	// 8) calibrate read timing by issuing READ ID 
	//******************************************************
	Integer ninitCmds = 2;
	PhyCmd initCmds[ninitCmds] = {
				PhyCmd {	phyCycle: PHY_ASYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd {	phyCycle: PHY_ASYNC_CMD, nandCmd: tagged OnfiCmd N_RESET, 
	 		  				numBurst: 0, postCmdWait: fromInteger(t_POR)}
				};

	Integer nactSyncData = 4;
	Integer nactSyncCmds = 6;
	PhyCmd actSyncCmds[nactSyncCmds] = {
				PhyCmd {	phyCycle: PHY_ASYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd {	phyCycle: PHY_ASYNC_CMD, nandCmd: tagged OnfiCmd N_SET_FEATURES, 
							numBurst: 0, postCmdWait: 0},
				PhyCmd {	phyCycle: PHY_ASYNC_ADDR, nandCmd: ?, 
							numBurst: 1, postCmdWait: fromInteger(t_ADL)},
				PhyCmd {	phyCycle: PHY_ASYNC_WRITE, nandCmd: ?, 
							numBurst: fromInteger(nactSyncData), postCmdWait: fromInteger(t_WB)},
				PhyCmd {	phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
							numBurst: 0, postCmdWait: fromInteger(t_ITC)},
				PhyCmd {	phyCycle: PHY_ENABLE_NAND_CLK, nandCmd: ?, 
							numBurst: 0, postCmdWait: fromInteger(t_EN_CLK)}
				};

	Integer nactSyncAddr = 1;
	Bit#(8) actSyncAddr = 8'h01;
	//commands for sync mode 5 (0x15)
	Bit#(8) actSyncData[nactSyncData] = { 8'h15, 8'h00, 8'h00, 8'h00 };
	

	Integer ncalibCmds = 5;
	Integer ncalibIdAddr = 1;
	PhyCmd calibCmds[ncalibCmds] = {
				PhyCmd {	phyCycle: PHY_SYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd {	phyCycle: PHY_SYNC_CMD, nandCmd: tagged OnfiCmd N_READ_ID, 
							numBurst: 0, postCmdWait: 0},
				PhyCmd {	phyCycle: PHY_SYNC_ADDR, nandCmd: ?, 
							numBurst: 1, postCmdWait: fromInteger(t_WHR_SYNC)},
				PhyCmd {	phyCycle: PHY_SYNC_CALIB, nandCmd: ?, 
							numBurst: 8, postCmdWait: fromInteger(t_RHW_SYNC)},
				PhyCmd {	phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
							numBurst: 0, postCmdWait: 0}
				};
	Bit#(8) calibIdAddr = 8'h00;

	rule doInitCmd if (state==INIT && cmdCnt < fromInteger(ninitCmds));
		phy.phyUser.sendCmd(initCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitWait if (state==INIT && cmdCnt==fromInteger(ninitCmds));
		state <= ASYNC_POLL_STATUS;
		rdyReturnState <= INIT_ACT_SYNC;
	endrule

	rule doInitActSync if (state==INIT_ACT_SYNC && cmdCnt < fromInteger(nactSyncCmds));
		phy.phyUser.sendCmd(actSyncCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitActSyncAddr if (state==INIT_ACT_SYNC && addrCnt < fromInteger(nactSyncAddr));
		phy.phyUser.sendAddr(actSyncAddr);
		addrCnt <= addrCnt + 1;
	endrule

	rule doInitActSyncData if (state==INIT_ACT_SYNC && dataCnt < fromInteger(nactSyncData));
		phy.phyUser.asyncWrByte(actSyncData[dataCnt]);
		dataCnt <= dataCnt + 1;
	endrule

	rule doInitDone if (state==INIT_ACT_SYNC && cmdCnt==fromInteger(nactSyncCmds) && 
								addrCnt==fromInteger(nactSyncAddr) && 
								dataCnt==fromInteger(nactSyncData));

		//Go issue a status poll to initialize IDDR to a defined value (instead of DON'T CARE)
		state <= SYNC_POLL_STATUS;
		rdyReturnState <= INIT_CALIB;
		cmdCnt <= 0;
		addrCnt <= 0;
	endrule

	//Calibration rules
	rule doInitCalib if (state==INIT_CALIB && cmdCnt < fromInteger(ncalibCmds));
		phy.phyUser.sendCmd(calibCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitCalibIdAddr if (state==INIT_CALIB && addrCnt < fromInteger(ncalibIdAddr));
		phy.phyUser.sendAddr(calibIdAddr);
		addrCnt <= addrCnt+1;
	endrule

	rule doInitCalibDone if (state==INIT_CALIB && cmdCnt==fromInteger(ncalibCmds) &&
										addrCnt==fromInteger(ncalibIdAddr));
		state <= IDLE;
	endrule
	
	//******************************************************
	// Async Poll Status
	//******************************************************
	Integer naStatusCmds = 4;
	PhyCmd aStatusCmds[naStatusCmds] = {
			PhyCmd { phyCycle: PHY_ASYNC_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd {	phyCycle: PHY_ASYNC_CMD, nandCmd: tagged OnfiCmd N_READ_STATUS, 
				 		numBurst: 0, postCmdWait: fromInteger(t_WHR)},
			PhyCmd {	phyCycle: PHY_ASYNC_READ, nandCmd: ?, 
	 		  			numBurst: 1, postCmdWait: fromInteger(t_RHW)},
			PhyCmd {	phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};

	rule doAsyncStatusCntReset if (state==ASYNC_POLL_STATUS);
		cmdCnt <= 0;
		state <= ASYNC_POLL_STATUS_POLL;
	endrule

	rule doAsyncPollStatus if (state==ASYNC_POLL_STATUS_POLL && 
										cmdCnt < fromInteger(naStatusCmds));
		phy.phyUser.sendCmd(aStatusCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doAsyncGetStatus if (state==ASYNC_POLL_STATUS_POLL && 
										cmdCnt==fromInteger(naStatusCmds));
		let status <- phy.phyUser.asyncRdByte();
		cmdCnt <= 0;
		$display("NandCtrl: async status=%x", status);
		debugR <= zeroExtend(status); //debug
		if (status==8'hE0) begin
			state <= rdyReturnState;
		end
		else begin
			//wait a while before polling
			waitCnt <= 100;
			state <= WAIT_CYCLES;
			returnState <= ASYNC_POLL_STATUS_POLL;
		end
	endrule
	
	
	//******************************************************
	// Debug
	//******************************************************
	//rule debugRzero if (state != SYNC_POLL_STATUS && state != SYNC_READ_GET_DATA);
	//	debugR <= 0;
	//endrule

	rule debugStatus;
		phy.phyUser.setDebug(truncate(debugR));
		phy.phyUser.setDebug90(truncateLSB(debugR));
	endrule


	//******************************************************
	// Interfaces
	//******************************************************
	interface nandPins = phy.nandPins;

	interface BusIfc busIfc;
		method Action sendCmd (SsdCmd cmd, Bit#(4) chip, Bit#(16) block, Bit#(8) page);
			cmdQ.enq( BusCmd { ssdCmd: cmd, chip: chip, block: block, page: page } );
		endmethod

		method Action writeWord (Bit#(16) data);
			writeQ.enq(data);
		endmethod 

		method ActionValue#(Bit#(16)) readWord (); 
			readQ.deq();
			return readQ.first();
		endmethod

	endinterface



endmodule

