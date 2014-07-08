import FIFOF		::*;
import Vector		::*;

import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;
import BusController::*;

typedef enum {
	IDLE,
	INIT,
	READ,
	READ_DATA,
	WRITE,
	WRITE_DATA,
	ERASE,
	ACT_SYNC,
	ERROR_READBACK
} TbState deriving (Bits, Eq);



interface FlashControllerIfc;
	(* prefix = "B0_0" *)
	interface NANDPins nandPins;
endinterface


(* no_default_clock, no_default_reset *)
(*synthesize*)
module mkFlashController#(
	Clock sysClkP,
	Clock sysClkN,
	Reset sysRstn
	)(FlashControllerIfc);

	//Controller Infrastructure (clock, reset)
	VNandInfra nandInfra <- vMkNandInfra(sysClkP, sysClkN, sysRstn);

	//Bus controller
	BusControllerIfc busCtrl <- mkBusController(nandInfra.clk90, nandInfra.rst90, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	Reg#(TbState) state <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(TbState) returnState <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) blockCnt <- mkReg(35, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Note: random page programming NOT ALLOWED!! Must program sequentially within a block
	Reg#(Bit#(8)) pageCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) dataCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bool) hasErr <- mkReg(False, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	Vector#(16, Reg#(Bool)) pageValid <- replicateM(mkReg(False, clocked_by nandInfra.clk0, 
																				reset_by nandInfra.rst0)); //for one block
	//Constant for now
	Bit#(4) chip = 5;

	rule doInit if (state==INIT);
		busCtrl.busIfc.sendCmd(INIT_BUS, chip, 0, 0);
		state <= WRITE;
	endrule

	//Basic write/read/erase testing
	rule doWrite if (state==WRITE);
		busCtrl.busIfc.sendCmd(WRITE_PAGE, chip, blockCnt, pageCnt);
		state <= WRITE_DATA;
	endrule

	rule doWriteData if (state==WRITE_DATA);
		if (dataCnt < fromInteger(pageSize/2)) begin
			//hash block/page. Add 16'hA000 so the first burst isn't 0.
			Bit#(8) dataHi = truncate(dataCnt + 16'h00A0 + zeroExtend(pageCnt)*7);
			Bit#(8) dataLow = truncate((dataCnt<<2) + 16'h00DE + zeroExtend(pageCnt)*3);
			Bit#(16) wData = {dataHi, dataLow};
			busCtrl.busIfc.writeWord(wData);
			dataCnt <= dataCnt + 1;
		end
		else begin
			pageValid[pageCnt] <= True;
			state <= READ;
			returnState <= ERASE;
			dataCnt <= 0;
		end
	endrule

	rule doRead if (state==READ);
		busCtrl.busIfc.sendCmd(READ_PAGE, chip, blockCnt, pageCnt);
		state <= READ_DATA;
	endrule



	rule doReadData if (state==READ_DATA);
		if (dataCnt < fromInteger(pageSize/2)) begin
			let rdata <- busCtrl.busIfc.readWord();
			Bit#(8) dataHi = truncate(dataCnt + 16'h00A0 + zeroExtend(pageCnt)*7);
			Bit#(8) dataLow = truncate((dataCnt<<2) + 16'h00DE + zeroExtend(pageCnt)*3);
			Bit#(16) wData = {dataHi, dataLow};
			dataCnt <= dataCnt + 1;

			//check
			if (pageValid[pageCnt]==False) begin
				if (rdata != 16'hFFFF) begin
					$display("FlashController TB: readback error on empty page at block=%d, page=%d; got %x", 
									blockCnt, pageCnt, rdata);
					hasErr <= True;
				end
				else begin
					$display("FlashController TB: readback OK! data=%x", rdata);
				end
			end
			else begin
				if (rdata != wData) begin
					$display("FlashController TB: readback error on block=%d, page=%d; Expected %x, got %x", 
									blockCnt, pageCnt, wData, rdata);
					hasErr <= True;
				end
				else begin
					$display("FlashController TB: readback OK! data=%x", rdata);
				end
			end
		end
		else begin
			if (hasErr) begin
				state <= ERROR_READBACK;
			end
			else begin
				state <= returnState;
				dataCnt <= 0;
				//pageCnt <= pageCnt + 1;
			end
		end
	endrule

	//erases the whole block
	rule doErase if (state==ERASE);
		busCtrl.busIfc.sendCmd(ERASE_BLOCK, chip, blockCnt, pageCnt);
		for (int i=0; i<16; i=i+1) begin
			pageValid[i] <= False;
		end
		state <= READ;
		returnState <= ACT_SYNC;
	endrule


	rule doActSync if (state==ACT_SYNC);
		busCtrl.busIfc.sendCmd(INIT_SYNC, chip, 0, 0);
		state <= WRITE;
		pageCnt <= pageCnt + 1; //write next page
		$display("FlashController TB: Activate Sync interface");
	endrule

	interface nandPins = busCtrl.nandPins;
endmodule
