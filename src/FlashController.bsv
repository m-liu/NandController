import FIFOF		::*;
import Vector		::*;

import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;
import BusController::*;

typedef enum {
	INIT = 0,
	IDLE = 1,
	READ = 2,
	READ_DATA = 3,
	WRITE = 4,
	WRITE_DATA = 5,
	ERASE = 6,
	ACT_SYNC = 7,
	DONE = 8,
	ERROR_READBACK = 9
} TbState deriving (Bits, Eq);


interface FlashControllerIfc;
	(* prefix = "B0_0" *)
	interface NANDPins nandPins;
endinterface


//Set of commands to issue
//Vector#(16, BusCmd) testCmds = newVector();
//testCmds[0] = BusCmd{ssdCmd: INIT_BUS, chip: 0, block: 0, page: 0};
//testCmds[1] = BusCmd{ssdCmd: INIT_BUS, chip: 0, block: 0, page: 0};



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
	Reg#(Bit#(64)) vinPrev <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(4)) chip <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) block <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Note: random page programming NOT ALLOWED!! Must program sequentially within a block
	Reg#(Bit#(8)) page <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) dataCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) errCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) berrCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) cmdCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	Vector#(4, Bit#(64)) vinTest = newVector();
	vinTest[0] = 64'h0002000000050000; //wr 5
	vinTest[1] = 64'h0001000000050000; //rd blk 5
	vinTest[2] = 64'h0003000000050000; //er blk 5
	vinTest[3] = 64'h0001000000050000; //rd blk 5

	rule doInit if (state==INIT);
		busCtrl.busIfc.sendCmd(INIT_BUS, 0, 0, 0);
		state <= ACT_SYNC;
	endrule

	rule doActSync if (state==ACT_SYNC);
		busCtrl.busIfc.sendCmd(INIT_SYNC, 0, 0, 0);
		state <= IDLE;
		$display("FlashController TB: Activate Sync interface");
	endrule


	rule doIdleAcceptCmd if (state==IDLE);
		//VIO input command
		//Beware that VIO runs much slower than system clock.
		`ifdef NAND_SIM
			//use fixed test inputs for sim
			Bit#(64) vin = vinTest[cmdCnt]; 
		`else
			Bit#(64) vin = busCtrl.phyDebug.getDebugVout();
		`endif

		if (vin != 0 && vin != vinPrev) begin
			vinPrev <= vin;
			//decode
			let vinCmd = vin[63:48];
			case (vinCmd)
				1: state <= READ;
				2: state <= WRITE;
				3: state <= ERASE;
				default: state <= IDLE;
			endcase
			chip <= truncate(vin[47:32]);
			block <= truncate(vin[31:16]);
			page <= truncate(vin[15:0]);
			dataCnt <= 0;
			errCnt <= 0;
		end
	endrule



	//Basic write/read/erase testing
	rule doWrite if (state==WRITE);
		busCtrl.busIfc.sendCmd(WRITE_PAGE, chip, block, page);
		state <= WRITE_DATA;
	endrule

	rule doWriteData if (state==WRITE_DATA);
		if (dataCnt < fromInteger(pageSize/2)) begin
			//hash block/page. Add 16'hA000 so the first burst isn't 0.
			Bit#(8) dataHi = truncate(dataCnt + 16'h00A0 + zeroExtend(block)*7+ zeroExtend(chip)<<1 );
			Bit#(8) dataLow = truncate( (~dataHi) + truncate(block) );
			//Bit#(8) dataLow = truncate((dataCnt<<2) + 16'h00DE + zeroExtend(pageCnt)*3);
			Bit#(16) wData = {dataHi, dataLow};
			busCtrl.busIfc.writeWord(wData);
			dataCnt <= dataCnt + 1;
		end
		else begin
			state <= IDLE;
			cmdCnt <= cmdCnt + 1;
		end
	endrule

	rule doRead if (state==READ);
		busCtrl.busIfc.sendCmd(READ_PAGE, chip, block, page);
		state <= READ_DATA;
	endrule

	rule doReadData if (state==READ_DATA);
		if (dataCnt < fromInteger(pageSize/2)) begin
			let rdata <- busCtrl.busIfc.readWord();
			Bit#(8) dataHi = truncate(dataCnt + 16'h00A0 + zeroExtend(block)*7+ zeroExtend(chip)<<1 );
			Bit#(8) dataLow = truncate( (~dataHi) + truncate(block) );
			//Bit#(8) dataHi = truncate(dataCnt + 16'h00A0 + zeroExtend(pageCnt)*7);
			//Bit#(8) dataLow = truncate((dataCnt<<2) + 16'h00DE + zeroExtend(pageCnt)*3);
			Bit#(16) wData = {dataHi, dataLow};
			dataCnt <= dataCnt + 1;

			//check
			/*
			if (pageValid[pageCnt]==False) begin
				if (rdata != 16'hFFFF) begin
					$display("FlashController TB: readback error on empty page at block=%d, page=%d; got %x", 
									blockCnt, pageCnt, rdata);
					errCnt <= errCnt + 1;
				end
				else begin
					$display("FlashController TB: readback OK! data=%x", rdata);
				end
			end
			else begin
			*/
				if (rdata != wData) begin
					$display("FlashController TB: readback error on block=%d, page=%d; Expected %x, got %x", 
									block, page, wData, rdata);
					errCnt <= errCnt + 1;
					//Bit#(16) diffData = rdata ^ wData;
					/*Bit#(16) diffCnt = diffData[0] + diffData[1] + diffData[2] 
						+ diffData[3] + diffData[4] + diffData[5] + diffData[6]
					  	+ diffData[7] + diffData[8] + diffData[9] + diffData[10]
					  	+ diffData[11] + diffData[12] + diffData[13] 
						+ diffData[14] + diffData[15];*/
					//diffData = diffData - ((diffData >> 1) & 16'h5555);
					//diffData = (diffData & 16'h3333) + ((diffData >> 2) & 16'h3333);
					//diffData = ((diffData + (diffData >> 4)) & 16'h0F0F);
					//let diffCnt = (diffData*(16'h0101))>>8;
					//berrCnt <= truncate(berrCnt + diffCnt);

				end
				else begin
					$display("FlashController TB: readback OK! data=%x", rdata);
				end
			//end
		end
		else begin
			state <= IDLE;
			cmdCnt <= cmdCnt + 1;
		end
	endrule

	//erases the whole block
	rule doErase if (state==ERASE);
		busCtrl.busIfc.sendCmd(ERASE_BLOCK, chip, block, page);
		state <= IDLE;
		cmdCnt <= cmdCnt + 1;
	endrule

	rule debugSet;
		busCtrl.phyDebug.setDebug2(zeroExtend(pack(state)));
		busCtrl.phyDebug.setDebug3(errCnt);
		busCtrl.phyDebug.setDebug4(berrCnt);
		busCtrl.phyDebug.setDebug5(cmdCnt);
		busCtrl.phyDebug.setDebugVin(busCtrl.phyDebug.getDebugVout());
	endrule

	interface nandPins = busCtrl.nandPins;
endmodule
