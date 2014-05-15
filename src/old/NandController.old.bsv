//TODO: a cleaner implementation:
// each cycle:
// 	1) push a command
//		2) if command numbursts > 0, push data burst (addr, cmd or data, doesn't matter)
//			need to combine addr and data fifos here. May need 2 fifos or double width fifos for DDR?
// separate reads and status
import FIFOF             ::*;
import Vector            ::*;

import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;

typedef enum {
	IDLE,
	BUS_IDLE,
	WAIT_CYCLES,
	POR,
	BUS_IDLE2,
	SEND_STATUS_CMD,
	GET_STATUS_CMD,
	POLL_STATUS,
	ACTIVATE_SYNC,
	ACTIVATE_SYNC_DATA, 
	DESELECT_ALL,
	EN_CLK,
	SYNC_BUS_IDLE,
	SYNC_READ_STATUS_CMD,
	SYNC_GET_STATUS,
	SYNC_POLL_STATUS,

	SYNC_WRITE_CMD,
	SYNC_WRITE_ADDR,
	SYNC_WRITE_DATA,
	SYNC_WRITE_CONFIRM,

	SYNC_READ_CMD,
	SYNC_READ_ADDR,
	SYNC_READ_CONFIRM,
	SYNC_READ_DATA,
	SYNC_READ_GET_DATA,
	SYNC_READ_DONE_READ_MODE



} CtrlState deriving (Bits, Eq);

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
	
	//Timing parameters for timing parameters between different cycle types
	//using SHORT_RESET for simulation. Doens't matter because we poll
	// until status is ready
	Integer t_POR = 1000; //1ms. Power-on Reset time. TODO: reduced
	Integer t_WHR = 13; //120ns. WE# HIGH to RE# LOW
	Integer t_WB = 20; //200ns
	Integer t_ITC = 150; //1us (tITC)
	Integer t_ADL = 25; //200ns
	Integer t_RHW = 25; //200ns

	Integer t_WHR_SYNC = 8; //80ns. WE# HIGH to RE# LOW
	Integer t_ADL_SYNC = 7; //70ns
	Integer t_RHW_SYNC = 10; //100ns
	Integer t_WB_SYNC = 10; //100ns


	//NAND geometry
	Integer pageSize = 8640; //bytes. 8kB + 448B ECC
	Integer pagesPerBlock = 256;
	Integer blocksPerPlane = 2048;
	Integer planesPerLun = 2;
	Integer lunsPerTarget = 1; //1 for SLC, 2 for MLC

	//NandInfraIfc nandInfra <- mkNandInfra(sysClkP, sysClkN, sysRstn);
	VNandInfra nandInfra <- vMkNandInfra(sysClkP, sysClkN, sysRstn);
	NandPhyIfc phy <- mkNandPhy(nandInfra.clk90, nandInfra.rst90, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	Reg#(CtrlState) state <- mkReg(BUS_IDLE, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(CtrlState) returnState <- mkReg(BUS_IDLE, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(CtrlState) pollReturnState <- mkReg(BUS_IDLE, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(32)) waitCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	//wait rule
	rule doWaitCycles if (state==WAIT_CYCLES);
		if (waitCnt>0) begin
			waitCnt <= waitCnt-1;
		end
		else begin
			state <= returnState;
		end
	endrule


	// 1) Go bus idle
	rule doSelectBusAndIdle if (state==BUS_IDLE);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_ASYNC_BUS_IDLE,
							nandCmd: ?,
							numBurst: 0,
					  		postCmdWait: 0	
							} );
		state <= POR;
	endrule

	// 2) Issue power on reset; wait t_POR
	rule doPOR if (state==POR);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_ASYNC_CMD,
							nandCmd: N_RESET,
							numBurst: 0, 
							postCmdWait: fromInteger(t_POR)
							} );
		state <= SEND_STATUS_CMD;
	endrule

	// 3) Send command to get status; wait t_WHR before reading status
	rule doSendStatusCmd if (state==SEND_STATUS_CMD);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_ASYNC_CMD,
							nandCmd: N_READ_STATUS,
							numBurst: 0,
					  		postCmdWait: fromInteger(t_WHR)
							} );
		state <= GET_STATUS_CMD;
	endrule

	// 4) Get status
	rule doGetStatus if (state==GET_STATUS_CMD);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_ASYNC_READ,
							nandCmd: ?,
							numBurst: 1,
					  		postCmdWait: 0
							} );
		state <= POLL_STATUS;
	endrule

	rule doPollStatus if (state==POLL_STATUS);
		let status <- phy.phyUser.asyncRdByte();
		$display("NandCtrl: status=%x", status);
		if (status==8'hE0) begin //ready
			//wait tRHW before sending another command
			waitCnt <= fromInteger(t_RHW);
			state <= WAIT_CYCLES;
			returnState <= ACTIVATE_SYNC;
		end
		else begin
			//wait a while before polling
			waitCnt <= 500;
			state <= WAIT_CYCLES;
			returnState <= GET_STATUS_CMD;
		end
	endrule

	Vector#(5, ControllerCmd) actSync = newVector;
	actSync[0] = ControllerCmd {
							phyCycle: PHY_ASYNC_CMD,
							nandCmd: N_SET_FEATURES,
							numBurst: 0,
					  		postCmdWait: 0 };

	actSync[1] = ControllerCmd {
							phyCycle: PHY_ASYNC_ADDR,
							nandCmd: ?,
							numBurst: 1,
					  		postCmdWait: fromInteger(t_ADL) };
	
	actSync[2] = ControllerCmd {
							phyCycle: PHY_ASYNC_WRITE,
							nandCmd: ?,
							numBurst: 4,
					  		postCmdWait: fromInteger(t_WB) };
	
	Bit#(8) actSyncAddr = 8'h01;
	Bit#(8) actSyncMode = 8'h15; //synchronous mode 5

	Reg#(Bit#(4)) actSyncCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	rule doActivateSyncCmd if (state==ACTIVATE_SYNC);
		if (actSyncCnt < 3) begin
			phy.phyUser.sendCmd(actSync[actSyncCnt]);
			if (actSyncCnt==0) begin
				phy.phyUser.sendAddr(actSyncAddr);
			end
			actSyncCnt <= actSyncCnt+1;
		end
		else begin
			actSyncCnt <= 0;
			state <= ACTIVATE_SYNC_DATA;
		end
	endrule


	rule doActivateSyncData if (state==ACTIVATE_SYNC_DATA);
		if (actSyncCnt==0) begin
			phy.phyUser.asyncWrByte(actSyncMode);
			actSyncCnt <= actSyncCnt + 1;
		end
		else if (actSyncCnt < 4) begin
			phy.phyUser.asyncWrByte(0);
			actSyncCnt <= actSyncCnt + 1;
		end
		else begin
			actSyncCnt <= 0;
			state <= DESELECT_ALL;
		end
	endrule
		

	//Deassert CE#, wait t_ITC + t_WB
	rule doDeselect if (state==DESELECT_ALL);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_DESELECT_ALL,
							nandCmd: ?,
							numBurst: 0,
					  		postCmdWait: fromInteger(t_ITC)
							} );
		state <= EN_CLK;
	endrule
		

	//enable the nand clock, and we're in sync mode 5!
	rule doEnClk if (state==EN_CLK);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_ENABLE_NAND_CLK,
							nandCmd: ?,
							numBurst: 0,
					  		postCmdWait: 1000 //arbitrary
							} );
		state <= SYNC_BUS_IDLE;
	endrule
		

	//**************************
	//SYNC MODE RULES
	//**************************

	rule doSyncBusIdle if (state==SYNC_BUS_IDLE);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_SYNC_BUS_IDLE,
							nandCmd: ?,
							numBurst: 0,
					  		postCmdWait: 0
							} );
		state <= SYNC_READ_STATUS_CMD;
		pollReturnState <= SYNC_WRITE_CMD;
	endrule
	
	//*****************
	// Sync status polling
	//****************
	//send read status cmd
	rule doSyncRdStatusCmd if (state==SYNC_READ_STATUS_CMD);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_SYNC_CMD,
							nandCmd: N_READ_STATUS,
							numBurst: 0,
					  		postCmdWait: fromInteger(t_WHR_SYNC)
							} );
		state <= SYNC_GET_STATUS;
	endrule
	
	rule doSyncRdStatusGet if (state==SYNC_GET_STATUS);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCycle: PHY_SYNC_READ,
							nandCmd: ?,
							numBurst: 1,
					  		postCmdWait: fromInteger(t_RHW_SYNC)
							} );
		state <= SYNC_POLL_STATUS;
	endrule

	Reg#(Bit#(16)) debugR <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	rule doSyncPollStatus if (state==SYNC_POLL_STATUS);
		let status <- phy.phyUser.syncRdWord();
		$display("NandCtrl: sync status=%x", status);
		debugR <= status; //debug

		if (status==16'hE0E0) begin //ready
			state <= pollReturnState;
		end
		else begin
			//wait a while before polling
			waitCnt <= 500;
			state <= WAIT_CYCLES;
			returnState <= SYNC_READ_STATUS_CMD;
		end
	endrule


	//Sync Write

	Reg#(Bit#(8)) addrCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) dataCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	rule doWriteCmd if (state==SYNC_WRITE_CMD);
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_CMD,
						nandCmd: N_PROGRAM_PAGE,
						numBurst: 0, //TESTING
						postCmdWait: 0
					} );
		state <= SYNC_WRITE_ADDR;
		addrCnt <= 0;
		dataCnt <= 0;
	endrule

	rule doWriteAddr if (state==SYNC_WRITE_ADDR); 
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_ADDR,
						nandCmd: ?,
						numBurst: 5,
						postCmdWait: fromInteger(t_ADL)
					} );
		state <= SYNC_WRITE_DATA; 
	endrule

	//send addresses. hacky
	Vector#(5, Bit#(8)) writeAddr = newVector();
	writeAddr[0] = 8'h0; 
	writeAddr[1] = 8'h0; //column addr = 0
	writeAddr[2] = 8'h0; //page addr = 0; must be sequentially programmed
	writeAddr[3] = 8'h4; //Bit 0 is plane select. Plane=0, block addr=2;
	writeAddr[4] = 8'h0;


	rule doWriteSendAddr if ((state==SYNC_WRITE_ADDR || state==SYNC_WRITE_DATA) && addrCnt<5);
		phy.phyUser.sendAddr(writeAddr[addrCnt]);
		addrCnt <= addrCnt + 1;
		$display("NandCtrl: send addr: %x", addrCnt);
	endrule

	//send data. also hacky
	rule doWriteSendData if ((state==SYNC_WRITE_DATA || state==SYNC_WRITE_CONFIRM) && dataCnt < fromInteger(pageSize/2));
		let d = dataCnt + 16'hDEAD;
		phy.phyUser.syncWrWord(d);
		dataCnt <= dataCnt+1;
	endrule


	rule doWriteData if (state==SYNC_WRITE_DATA && addrCnt==5);
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_WRITE,
						nandCmd: ?,
						numBurst: fromInteger(pageSize/2), //TODO testing
						postCmdWait: 0
					} );

		state <= SYNC_WRITE_CONFIRM;
	endrule

	rule doWriteConfirm if (state==SYNC_WRITE_CONFIRM && dataCnt==fromInteger(pageSize/2));
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_CMD,
						nandCmd: N_PROGRAM_PAGE_END,
						numBurst: 0,
						postCmdWait: fromInteger(t_WB_SYNC)
					});
		//wait until ready
		state <= SYNC_READ_STATUS_CMD;
		pollReturnState <= SYNC_READ_CMD;
	endrule


	//Sync read
	rule doSyncReadSendAddr if (state==SYNC_READ_CMD);
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_CMD,
						nandCmd: N_READ_MODE,
						numBurst: 0,
						postCmdWait: 0
					} );
		addrCnt <= 0;
		state <= SYNC_READ_ADDR;
	endrule
	

	rule doReadAddr if (state==SYNC_READ_ADDR); 
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_ADDR,
						nandCmd: ?,
						numBurst: 5,
						postCmdWait: 0
					} );
		state <= SYNC_READ_CONFIRM; 
	endrule

	//send addresses. hacky
	Vector#(5, Bit#(8)) readAddr = newVector();
	readAddr[0] = 8'h0; 
	readAddr[1] = 8'h0; //column addr = 0
	readAddr[2] = 8'h0; //page addr = 0; must be sequentially programmed
	readAddr[3] = 8'h4; //Bit 0 is plane select. Plane=0, block addr=2;
	readAddr[4] = 8'h0;

	rule doReadSendAddr if ((state==SYNC_READ_ADDR || state==SYNC_READ_CONFIRM) && addrCnt<5);
		phy.phyUser.sendAddr(readAddr[addrCnt]);
		addrCnt <= addrCnt + 1;
		$display("NandCtrl: send READ addr: %x", addrCnt);
	endrule


	rule doReadConfirm if (state==SYNC_READ_CONFIRM && addrCnt==5);
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_CMD,
						nandCmd: N_READ_PAGE_END,
						numBurst: 0,
						postCmdWait: fromInteger(t_WB_SYNC)
					});
		//wait until ready
		state <= SYNC_READ_STATUS_CMD;
		pollReturnState <= SYNC_READ_DONE_READ_MODE;
	endrule

	//switch back to read mode (otherwise we'd be reading the status on dq)
	rule doSyncReadReadMode if (state==SYNC_READ_DONE_READ_MODE);
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_CMD,
						nandCmd: N_READ_MODE,
						numBurst: 0,
						postCmdWait: fromInteger(t_WHR_SYNC)
					} );
		state <= SYNC_READ_DATA;
	endrule


	rule doSyncReadData if (state==SYNC_READ_DATA);
		phy.phyUser.sendCmd ( ControllerCmd {
						phyCycle: PHY_SYNC_READ,
						nandCmd: ?,
						numBurst: fromInteger(pageSize/2),
						postCmdWait: 0
					});
		state <= SYNC_READ_GET_DATA;
	endrule
		
	rule doSyncreadGetData if (state==SYNC_READ_GET_DATA);
		let rd <- phy.phyUser.syncRdWord();
		debugR <= rd;
		$display("NandCtrl: read data: %x", rd);
	endrule




	rule debugRzero if (state != SYNC_POLL_STATUS && state != SYNC_READ_GET_DATA);
		debugR <= 0;
	endrule

	rule debugStatus;
		phy.phyUser.setDebug(truncate(debugR));
		phy.phyUser.setDebug90(truncateLSB(debugR));
	endrule

	
	

	interface nandPins = phy.nandPins;

endmodule

