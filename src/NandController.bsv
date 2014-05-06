
import FIFOF             ::*;
import Vector            ::*;

import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;

typedef enum {
	BUS_IDLE,
	WAIT_CYCLES,
	POR,
	BUS_IDLE2,
	SEND_STATUS_CMD,
	GET_STATUS_CMD,
	POLL_STATUS

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
		let status = phy.phyUser.asyncRdByte();
		$display("NandCtrl: status=%x", status);
		//wait a while before polling
		waitCnt <= 500;
		state <= WAIT_CYCLES;
		returnState <= GET_STATUS_CMD;
	endrule



	//Device is in async mode on power up
	//Hold reset command for several cycles to satisfy the long setup/hold times
	// (1) transition to bus IDLE 
	//			A target's bus is idle when CE# is LOW, WE# is HIGH, and RE# is HIGH.
	// (2) send reset command 
	//		An asynchronous command is written from DQ[7:0] to the command
	//		register on the rising edge of WE# when CE# is LOW, ALE is LOW, CLE is
	//		HIGH, and RE# is HIGH.  
	// 	Sync to Async mapping: WR# = RE#; WE# = NAND_CLK
	

	
	

	interface nandPins = phy.nandPins;

endmodule

