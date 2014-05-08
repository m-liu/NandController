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
	EN_CLK


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
	Integer t_POR = 50000; //1ms. Power-on Reset time. TODO: reduced
	Integer t_WHR = 13; //120ns. WE# HIGH to RE# LOW
	Integer t_WB = 20; //200ns
	Integer t_ITC = 150; //1us (tITC)
	Integer t_ADL = 25; //200ns
	Integer t_RHW = 25; //200ns


	//NandInfraIfc nandInfra <- mkNandInfra(sysClkP, sysClkN, sysRstn);
	VNandInfra nandInfra <- vMkNandInfra(sysClkP, sysClkN, sysRstn);
	NandPhyIfc phy <- mkNandPhy(nandInfra.clk90, nandInfra.rst90, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	Reg#(CtrlState) state <- mkReg(BUS_IDLE, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(CtrlState) returnState <- mkReg(BUS_IDLE, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
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
							phyCmd: PHY_ASYNC_BUS_IDLE,
							nandCmd: ?,
							numBurst: 0,
					  		postCmdWait: 0	
							} );
		state <= POR;
	endrule

	// 2) Issue power on reset; wait t_POR
	rule doPOR if (state==POR);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCmd: PHY_ASYNC_SEND_NAND_CMD,
							nandCmd: N_RESET,
							numBurst: 0, 
							postCmdWait: fromInteger(t_POR)
							} );
		state <= SEND_STATUS_CMD;
	endrule

	// 3) Send command to get status; wait t_WHR before reading status
	rule doSendStatusCmd if (state==SEND_STATUS_CMD);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCmd: PHY_ASYNC_SEND_NAND_CMD,
							nandCmd: N_READ_STATUS,
							numBurst: 0,
					  		postCmdWait: fromInteger(t_WHR)
							} );
		state <= GET_STATUS_CMD;
	endrule

	// 4) Get status
	rule doGetStatus if (state==GET_STATUS_CMD);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCmd: PHY_ASYNC_READ,
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
							phyCmd: PHY_ASYNC_SEND_NAND_CMD,
							nandCmd: N_SET_FEATURES,
							numBurst: 0,
					  		postCmdWait: 0 };

	actSync[1] = ControllerCmd {
							phyCmd: PHY_ASYNC_SEND_ADDR,
							nandCmd: ?,
							numBurst: 1,
					  		postCmdWait: fromInteger(t_ADL) };
	
	actSync[2] = ControllerCmd {
							phyCmd: PHY_ASYNC_WRITE,
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
							phyCmd: PHY_DESELECT_ALL,
							nandCmd: ?,
							numBurst: 0,
					  		postCmdWait: fromInteger(t_ITC)
							} );
		state <= EN_CLK;
	endrule
		

	//enable the nand clock, and we're in sync mode 5!
	rule doEnClk if (state==EN_CLK);
		phy.phyUser.sendCmd( ControllerCmd {
							phyCmd: PHY_ENABLE_NAND_CLK,
							nandCmd: ?,
							numBurst: 0,
					  		postCmdWait: 1000 //arbitrary
							} );
		state <= IDLE;
	endrule
		



	



	
	

	interface nandPins = phy.nandPins;

endmodule

