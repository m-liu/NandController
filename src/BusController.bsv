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

	READ_PAGE_REQ,
	READ_DATA,
	WRITE_PAGE,
	ERASE_BLOCK,
	POLL_STATUS,
	POLL_STATUS_POLL
} CtrlState deriving (Bits, Eq);


typedef enum {
	INIT_BUS,
	INIT_SYNC,
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
//Integer pagesPerBlock = 256;
//Integer blocksPerPlane = 2048;
//Integer planesPerLun = 2;
//Integer lunsPerTarget = 1; //1 for SLC, 2 for MLC

interface BusIfc;
	method Action sendCmd (SsdCmd cmd, Bit#(4) chip, Bit#(16) block, Bit#(8) page);
	method Action writeWord (Bit#(16) data);
	method ActionValue#(Bit#(16)) readWord (); 
endinterface


interface BusControllerIfc;
	interface BusIfc busIfc;
	//(* prefix = "B0" *)
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
	Integer t_ITC = 150; //1us (tITC)
	Integer t_WHR_ASYNC = 13; //120ns. WE# HIGH to RE# LOW
	Integer t_WB_ASYNC = 20; //200ns
	Integer t_ADL_ASYNC = 25; //200ns
	Integer t_RHW_ASYNC = 25; //200ns
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
	Reg#(Bit#(16)) debugR0 <- mkReg(0);
	Reg#(Bit#(16)) debugR1 <- mkReg(0);
	Reg#(Bit#(16)) debugR2 <- mkReg(0);
	Reg#(Bit#(16)) debugR3 <- mkReg(0);

	//Command/Data FIFOs
	FIFO#(BusCmd) cmdQ <- mkSizedFIFO(64); //TODO adjust
	FIFO#(Bit#(16)) writeQ <- mkSizedFIFO(128); //TODO adjust
	FIFO#(Bit#(16)) readQ <- mkSizedFIFO(128); //TODO adjust
	Reg#(BusCmd) cmdR <- mkRegU();
	Reg#(Bit#(4)) chipR <- mkReg(0);
	Vector#(5, Reg#(Bit#(8))) addrDecoded <- replicateM(mkReg(0));

	//Sync or async mode
	Reg#(Bool) inSyncMode <- mkReg(False);

	//Number of bursts is half the page size in sync mode (DDR)
	Bit#(16) nDataBursts = (inSyncMode) ? fromInteger(pageSize/2) : fromInteger(pageSize);

	//Select between sync mode timing and async mode timing
	Bit#(32) t_WHR = (inSyncMode) ? fromInteger(t_WHR_SYNC) : fromInteger(t_WHR_ASYNC);
	Bit#(32) t_RHW = (inSyncMode) ? fromInteger(t_RHW_SYNC) : fromInteger(t_RHW_ASYNC);
	Bit#(32) t_WB = (inSyncMode) ? fromInteger(t_WB_SYNC) : fromInteger(t_WB_ASYNC);
	Bit#(32) t_ADL = (inSyncMode) ? fromInteger(t_ADL_SYNC) : fromInteger(t_ADL_ASYNC);


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
			INIT_SYNC: state <= INIT_ACT_SYNC;
			READ_PAGE: state <= READ_PAGE_REQ;
			WRITE_PAGE: state <= WRITE_PAGE;
			ERASE_BLOCK: state <= ERASE_BLOCK;
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
	// Read Page (Sync or Async)
	//******************************************************
	Integer nreadReqCmds = 4;
	PhyCmd readReqCmds[nreadReqCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_MODE,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBursts), postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_PAGE_END, 
						numBurst: 0, postCmdWait: t_WB}
			};
	
	Integer nreadDataCmds = 4;
	PhyCmd readDataCmds[nreadDataCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_MODE, 
						numBurst: 0, postCmdWait: t_WHR},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_READ, nandCmd: ?, 
						numBurst: nDataBursts, postCmdWait: t_RHW},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};

	rule doReadPageCmd if (state==READ_PAGE_REQ && cmdCnt < fromInteger(nreadReqCmds));
		phy.phyUser.sendCmd(readReqCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule
		
	rule doReadPageAddr if (state==READ_PAGE_REQ && addrCnt < fromInteger(nAddrBursts));
		phy.phyUser.sendAddr(addrDecoded[addrCnt]);
		addrCnt <= addrCnt + 1;
	endrule

	rule doReadPageWait if (state==READ_PAGE_REQ && 
									addrCnt==fromInteger(nAddrBursts) && 
									cmdCnt==fromInteger(nreadReqCmds));
		state <= POLL_STATUS;
		rdyReturnState <= READ_DATA;
		cmdCnt <= 0;
		addrCnt <= 0;
		dataCnt <= 0;
	endrule

	rule doReadDataCmd if (state==READ_DATA && cmdCnt < fromInteger(nreadDataCmds));
		phy.phyUser.sendCmd(readDataCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	//Sync DDR bursts
	rule doReadDataDDR if (state==READ_DATA && inSyncMode==True && dataCnt < nDataBursts);
		let rd <- phy.phyUser.rdWord();
		readQ.enq(rd);
		debugR0 <= rd;
		dataCnt <= dataCnt + 1;
		$display("NandCtrl: read data: %x", rd);
	endrule

	//Async SDR bursts
	Reg#(Bit#(8)) rdTmp <- mkReg(0);
	rule doReadDataSDR if (state==READ_DATA && inSyncMode==False && dataCnt < nDataBursts);
		Bit#(16) rd <- phy.phyUser.rdWord();
		Bit#(8) rdTrunc = truncate(rd);
		dataCnt <= dataCnt + 1;

		if (dataCnt[0]==0) begin //even bursts
			rdTmp <= rdTrunc;
		end
		else begin //odd burst, enq into fifo
			Bit#(16) rdMerged = {rdTmp, rdTrunc};
			readQ.enq(rdMerged);
			debugR0 <= rdMerged;
			$display("NandCtrl: read data: %x", rdMerged);
		end
	endrule

	rule doReadDataDone if (state==READ_DATA && 
								dataCnt == nDataBursts && 
								cmdCnt==fromInteger(nreadDataCmds));
		state <= IDLE;
	endrule


	//******************************************************
	// Write Page (Sync or Async)
	//******************************************************
	Integer nwriteReqCmds = 6;	
	PhyCmd writeReqCmds[nwriteReqCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_PROGRAM_PAGE, 
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBursts), postCmdWait: t_ADL},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_WRITE, nandCmd: ?, 
						numBurst: nDataBursts, postCmdWait: 0}, 
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_PROGRAM_PAGE_END, 
		 				numBurst: 0, postCmdWait: t_WB},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};


	rule doWritePageCmd if (state==WRITE_PAGE && cmdCnt < fromInteger(nwriteReqCmds));
		phy.phyUser.sendCmd(writeReqCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule
		
	rule doWritePageAddr if (state==WRITE_PAGE && addrCnt < fromInteger(nAddrBursts));
		phy.phyUser.sendAddr(addrDecoded[addrCnt]); 
		addrCnt <= addrCnt + 1;
	endrule

	//TODO we need to make sure the write FIFO always has data, otherwise writes won't work

	//Sync DDR write
	rule doWritePageDataDDR if (state==WRITE_PAGE && inSyncMode && dataCnt < nDataBursts);
		phy.phyUser.wrWord(writeQ.first());
		writeQ.deq();
		dataCnt <= dataCnt + 1;
	endrule

	//Async SDR write
	rule doWritePageDataSDR if (state==WRITE_PAGE && !inSyncMode && dataCnt < nDataBursts);
		if (dataCnt[0]==0) begin
			Bit#(8) wd = truncateLSB(writeQ.first());
			phy.phyUser.wrWord(zeroExtend(wd));
		end
		else begin
			Bit#(8) wd = truncate(writeQ.first());
			phy.phyUser.wrWord(zeroExtend(wd));
			writeQ.deq();
		end
		dataCnt <= dataCnt + 1;
	endrule

		
	rule doWriteDone if (state==WRITE_PAGE && dataCnt==nDataBursts 
								&& cmdCnt==fromInteger(nwriteReqCmds) && 
								addrCnt==fromInteger(nAddrBursts));
		//wait for write to finish
		state <= POLL_STATUS;
		rdyReturnState <= IDLE;
	endrule


		
	//******************************************************
	// Erase Block
	//******************************************************
	Integer neraseCmds = 5;
	PhyCmd eraseCmds[neraseCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_ERASE_BLOCK, 
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBurstsErase), postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_ERASE_BLOCK_END, 
		 				numBurst: 0, postCmdWait: fromInteger(t_BERS)},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};

	rule doEraseBlockCmd if (state==ERASE_BLOCK && cmdCnt < fromInteger(neraseCmds));
		phy.phyUser.sendCmd(eraseCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doEraseBlockAddr if (state==ERASE_BLOCK && 
									addrCnt < fromInteger(nAddrBurstsErase));
		//Write 3 row addresses (page, block) indices 2,3,4.
		//Note: page addr is ignored by the NAND, but still have to send it
		let ind = addrCnt+2;
		phy.phyUser.sendAddr(addrDecoded[ind]);
		addrCnt <= addrCnt + 1;
	endrule

	rule doEraseBlockPoll if (state==ERASE_BLOCK && addrCnt==fromInteger(nAddrBurstsErase) && cmdCnt==fromInteger(neraseCmds));
		//wait for write to finish
		state <= POLL_STATUS;
		rdyReturnState <= IDLE;
	endrule



	//******************************************************
	// Async/Sync Poll Status
	//******************************************************
	Integer nstatusCmds = 4;
	PhyCmd statusCmds[nstatusCmds] = { 
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_STATUS, 
			  			numBurst: 0, postCmdWait: t_WHR},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_READ, nandCmd: ?, 
		 				numBurst: 1, postCmdWait: t_RHW},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
		};
	rule doStatusCntReset if (state==POLL_STATUS);
		cmdCnt <= 0;
		state <= POLL_STATUS_POLL;
	endrule 

	rule doReadStatusCmd if (state==POLL_STATUS_POLL && cmdCnt < fromInteger(nstatusCmds));
		phy.phyUser.sendCmd(statusCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doReadStatusGet if (state==POLL_STATUS_POLL && cmdCnt==fromInteger(nstatusCmds));
		Bit#(16) status <- phy.phyUser.rdWord();
		cmdCnt <= 0;
		$display("NandCtrl: status=%x", status);
		debugR0 <= status; //debug

		//During calibration, get status is used to initialize IDDR regs so that we don't have
		//DON'T CARES
		if (rdyReturnState==INIT_CALIB) begin
			state <= rdyReturnState;
		end
		else begin
			if (status[7:0]==8'hE0) begin 
				state <= rdyReturnState;
			end
			else begin
				//wait a while before polling
				waitCnt <= 100;
				state <= WAIT_CYCLES;
				returnState <= POLL_STATUS_POLL;
			end
		end
	endrule


	//******************************************************
	// Power On Initialization
	// 1) Go bus idle
	// 2) Issue power on reset; wait t_POR
	//******************************************************
	

	Integer ninitCmds = 2;
	PhyCmd initCmds[ninitCmds] = {
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_RESET, 
	 		  				numBurst: 0, postCmdWait: fromInteger(t_POR)}
				};

	rule doInitCmd if (state==INIT && cmdCnt < fromInteger(ninitCmds));
		phy.phyUser.sendCmd(initCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitWait if (state==INIT && cmdCnt==fromInteger(ninitCmds));
		state <= POLL_STATUS;
		rdyReturnState <= IDLE;
	endrule

	//******************************************************
	// Sync Mode 5 activation and calibration
	// 1) poll status until ready
	// 2) activate sync mode 5 interface
	// 3) release CE#, wait t_ITC+t_WB
	// 4) enable nand clock
	// 5) select CE#, go sync bus idle
	// 6) calibrate read timing by issuing READ ID 
	//******************************************************

	Integer nactSyncData = 4;
	Integer nactSyncCmds = 6;
	PhyCmd actSyncCmds[nactSyncCmds] = {
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_SET_FEATURES, 
							numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
							numBurst: 1, postCmdWait: t_ADL},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_WRITE, nandCmd: ?, 
							numBurst: fromInteger(nactSyncData), postCmdWait: t_WB},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
							numBurst: 0, postCmdWait: fromInteger(t_ITC)},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ENABLE_NAND_CLK, nandCmd: ?, 
							numBurst: 0, postCmdWait: fromInteger(t_EN_CLK)}
				};

	Integer nactSyncAddr = 1;
	Bit#(8) actSyncAddr = 8'h01;
	//commands for sync mode 5 (0x15)
	Bit#(8) actSyncData[nactSyncData] = { 8'h15, 8'h00, 8'h00, 8'h00 };
	

	Integer ncalibCmds = 5;
	Integer ncalibIdAddr = 1;
	PhyCmd calibCmds[ncalibCmds] = {
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_ID, 
							numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
							numBurst: 1, postCmdWait: t_WHR},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_SYNC_CALIB, nandCmd: ?, 
							numBurst: 8, postCmdWait: t_RHW},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
							numBurst: 0, postCmdWait: 0}
				};
	Bit#(8) calibIdAddr = 8'h00;


	rule doInitActSync if (state==INIT_ACT_SYNC && cmdCnt < fromInteger(nactSyncCmds));
		phy.phyUser.sendCmd(actSyncCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitActSyncAddr if (state==INIT_ACT_SYNC && addrCnt < fromInteger(nactSyncAddr));
		phy.phyUser.sendAddr(actSyncAddr);
		addrCnt <= addrCnt + 1;
	endrule

	rule doInitActSyncData if (state==INIT_ACT_SYNC && dataCnt < fromInteger(nactSyncData));
		phy.phyUser.wrWord(zeroExtend(actSyncData[dataCnt]));
		dataCnt <= dataCnt + 1;
	endrule

	rule doInitDone if (state==INIT_ACT_SYNC && cmdCnt==fromInteger(nactSyncCmds) && 
								addrCnt==fromInteger(nactSyncAddr) && 
								dataCnt==fromInteger(nactSyncData));

		//Go issue a status poll to initialize IDDR to a defined value (instead of DON'T CARE)
		state <= POLL_STATUS;
		rdyReturnState <= INIT_CALIB;
		cmdCnt <= 0;
		addrCnt <= 0;
		//We have entered Sync Mode 5
		inSyncMode <= True;
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
	// Debug
	//******************************************************
	rule debugStatus;
		phy.phyUser.setDebug0(debugR0);
		phy.phyUser.setDebug1(zeroExtend(pack(state)));
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

