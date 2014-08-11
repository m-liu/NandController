import FIFOF		::*;
import Vector		::*;
import Connectable ::*;

import ControllerTypes::*;
import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;
import BusController::*;
import NandPhyWenNclkWrapper::*;


typedef enum {
	INIT = 0,
	INIT_WAIT = 1,
	IDLE = 2,
	READ = 3,
	READ_DATA = 4,
	WRITE = 5,
	WRITE_DATA = 6,
	ERASE = 7,
	ACT_SYNC = 8,
	DONE = 9,
	ERROR_READBACK = 10
} TbState deriving (Bits, Eq);


interface FlashControllerIfc;
	(* prefix = "B_SHARED" *)
	interface Vector#(NUM_CHIPBUSES, NANDWenNclk) nandBusShared;
	(* prefix = "B" *)
	interface Vector#(NUM_CHIPBUSES, Vector#(BUSES_PER_CHIPBUS, NANDPins)) nandBus;
endinterface

//Create data by hashing the address
function Bit#(16) getDataHash (Bit#(16) dataCnt, Bit#(8) page, Bit#(16) block, ChipT chip, Bit#(3) bus);
		Bit#(8) dataCntTrim = truncate(dataCnt);
		Bit#(8) blockTrim = truncate(block);
		Bit#(8) chipTrim = zeroExtend(chip);
		Bit#(8) busTrim = zeroExtend(bus);

		Bit#(8) dataHi = truncate(dataCntTrim + 8'hA0 + (blockTrim<<4)+ (chipTrim<<2) + (busTrim<<6));
		Bit#(8) dataLow = truncate( (~dataHi) + blockTrim );
		Bit#(16) d = {dataHi, dataLow};
		return d;
endfunction



(* no_default_clock, no_default_reset *)
(*synthesize*)
module mkFlashController#(
	Clock sysClkP,
	Clock sysClkN,
	Reset sysRstn
	)(FlashControllerIfc);

	//Controller Infrastructure (clock, reset)
	VNandInfra nandInfra <- vMkNandInfra(sysClkP, sysClkN, sysRstn);
	//Vectorize the debug control interfaces so we can use loops later
	Vector#(16, Inout#(Bit#(36))) dbgCtrlIfc = newVector();
	dbgCtrlIfc[0] = nandInfra.dbgCtrl_0;
	dbgCtrlIfc[1] = nandInfra.dbgCtrl_1;
	dbgCtrlIfc[2] = nandInfra.dbgCtrl_2;
	dbgCtrlIfc[3] = nandInfra.dbgCtrl_3;
	dbgCtrlIfc[4] = nandInfra.dbgCtrl_4;
	dbgCtrlIfc[5] = nandInfra.dbgCtrl_5;
	dbgCtrlIfc[6] = nandInfra.dbgCtrl_6;
	dbgCtrlIfc[7] = nandInfra.dbgCtrl_7;
//	dbgCtrlIfc[8] = nandInfra.dbgCtrl_8;
//	dbgCtrlIfc[9] = nandInfra.dbgCtrl_9;
//	dbgCtrlIfc[10] = nandInfra.dbgCtrl_10;
//	dbgCtrlIfc[11] = nandInfra.dbgCtrl_11;
//	dbgCtrlIfc[12] = nandInfra.dbgCtrl_12;
//	dbgCtrlIfc[13] = nandInfra.dbgCtrl_13;
//	dbgCtrlIfc[14] = nandInfra.dbgCtrl_14;
//	dbgCtrlIfc[15] = nandInfra.dbgCtrl_15;

	//Nand WEN/NandClk (because of weird organization, this module is
	// shared among half buses)
	Vector#(NUM_CHIPBUSES, VNANDPhyWenNclk) busWenNclk <- replicateM(vMkNandPhyWenNclk(nandInfra.clk0, nandInfra.rst0));

	//Bus controllers.
	Vector#(NUM_BUSES, BusControllerIfc) busCtrl = newVector();
	for (Integer i=0; i<valueOf(NUM_BUSES); i=i+1) begin
		busCtrl[i] <- mkBusController(nandInfra.clk90, nandInfra.rst90, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
		mkConnection(busCtrl[i].phyDebugCtrl.dbgCtrlIla, dbgCtrlIfc[i*2]);
		mkConnection(busCtrl[i].phyDebugCtrl.dbgCtrlVio, dbgCtrlIfc[i*2+1]);
	end

	//Tag to command mapping table
	// TODO maybe use a regfile?
	Vector#(NumTags, Reg#(FlashCmd)) tagTable <- replicateM(mkRegU(clocked_by nandInfra.clk0, reset_by nandInfra.rst0));


	Reg#(TbState) state <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(TbState) returnState <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(64)) vinPrev <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Reg#(ChipT) chip <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(3)) busInd <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Reg#(Bit#(16)) block <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Note: random page programming NOT ALLOWED!! Must program sequentially within a block
	//Reg#(Bit#(8)) page <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Reg#(Bit#(16)) dataCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Vector#(NUM_BUSES, Reg#(Bit#(2))) wrState <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(FlashCmd)) tagCmd <- replicateM(mkRegU(clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) rdataCnt <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) wdataCnt <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) errCnt <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	//Reg#(Bit#(16)) berrCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) cmdCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Vector#(NUM_BUSES, Reg#(Bit#(16))) rDataDebug <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));


	//Mapping: cmd = [63:48], bus = [47:40], chip = [39:32], block = [31:16], tag = [15:0]
	//Vector#(nTestCmds, Bit#(64)) vinTest = newVector();
	Integer nTestCmds = 12;
	Bit#(64) vinTest[nTestCmds] = {
	64'h0002010000050000, //wr blk 5, chip0, bus1, tag 0
	64'h0002010100050001, //wr blk 5, chip1, bus1, tag 1
	64'h0002010200050002, //wr blk 5, chip2, bus1, tag 1
	64'h0002010300050003, //wr blk 5, chip3, bus1, tag 1
	64'h0002010400050004, //wr blk 5, chip4, bus1, tag 1
	64'h0002010500050005, //wr blk 5, chip5, bus1, tag 1
	64'h0001010000050006, //rd blk 5, chip0, bus1, tag 1
	64'h0001010100050007, //rd blk 5, chip1, bus1, tag 1
	64'h0001010200050008, //rd blk 5, chip2, bus1
	64'h0001010300050009, //rd blk 5, chip3, bus1
	64'h000101040005000A, //wr blk 5, chip4, bus1, tag 1
	64'h000101050005000B //wr blk 5, chip5, bus1, tag 1
	};



	//rule for WEN/NCLK; Shared per chipbus
	for (Integer cbi=0; cbi < valueOf(NUM_CHIPBUSES); cbi=cbi+1) begin
		Integer bi = cbi * valueOf(BUSES_PER_CHIPBUS);
		Integer bj = cbi * valueOf(BUSES_PER_CHIPBUS) + 1;
		rule wenNclkConn;
			busWenNclk[cbi].wenNclk0.setWEN(busCtrl[bi].phyWenNclkGet.getWEN);
			busWenNclk[cbi].wenNclk0.setWENSel(busCtrl[bi].phyWenNclkGet.getWENSel);
			busWenNclk[cbi].wenNclk1.setWEN(busCtrl[bj].phyWenNclkGet.getWEN);
			busWenNclk[cbi].wenNclk1.setWENSel(busCtrl[bj].phyWenNclkGet.getWENSel);
		endrule
	end

	//Initialization: must perform each init op one bus at a time 
	// due to shared WEN/NCLK
	//(1) INIT_BUS (2)EN_SYNC (3)INIT_SYNC
	Reg#(FlashOp) initCmd <- mkReg(INIT_BUS, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	rule doInit if (state==INIT);
		busCtrl[busInd].busIfc.sendCmd( FlashCmd {tag: 0, op: initCmd, chip: 0, block: 0, page: 0} );
		state <= INIT_WAIT;
	endrule

	rule doInitWait if (state==INIT_WAIT);
		if (busCtrl[busInd].busIfc.isInitIdle) begin
			if (busInd < fromInteger(valueOf(NUM_BUSES)-1)) begin
				busInd <= busInd + 1;
				state <= INIT;
			end
			else begin
				busInd <= 0;	
				if (initCmd==INIT_BUS) begin
					initCmd <= EN_SYNC;
					state <= INIT;
				end 
				else if (initCmd==EN_SYNC) begin
					initCmd <= INIT_SYNC;
					state <= INIT;
				end
				else begin
					state <= IDLE;
				end
			end
		end
	endrule


	//Continuously send commands as fast as possible
	rule doIdleAcceptCmd if (state==IDLE);
		//VIO input command from Bus 0's PHY
		//Beware that VIO runs much slower than system clock.
		`ifdef NAND_SIM
			//use fixed test inputs for sim
			Bit#(64) vin;
			if (cmdCnt < fromInteger(nTestCmds)) begin
				vin = vinTest[cmdCnt]; 
			end
			else begin
				vin = 0;
			end
		`else
			Bit#(64) vin = busCtrl[0].phyDebug.getDebugVout();
		`endif

		if (vin != 0 && vin != vinPrev) begin
			vinPrev <= vin;
			
			FlashOp flashOp;
			let vinOp = vin[63:48];
			case (vinOp)
				1: flashOp = READ_PAGE;
				2: flashOp = WRITE_PAGE;
				3: flashOp = ERASE_BLOCK;
				default: flashOp = READ_PAGE;
			endcase
			TagT cmdTag = truncate(vin[15:0]);
			FlashCmd vinCmd = FlashCmd { 	tag: cmdTag,
													op: flashOp,
													chip: truncate(vin[39:32]),
													block: truncate(vin[31:16]),
													page: 0 };

			Bit#(3) b = truncate(vin[47:40]);
			busCtrl[b].busIfc.sendCmd(vinCmd); //send cmd
			tagTable[cmdTag] <= vinCmd; //insert in tag table
			//dataCnt <= 0;
			//errCnt <= 0;
			cmdCnt <= cmdCnt + 1;
			$display("@%t\t%m: controller sent cmd: %x", $time, vin);
		end
	endrule

	//Handle write data requests from the BusController

	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		rule doWriteDataReq if (wrState[i] == 0);
			TagT tag <- busCtrl[i].busIfc.writeDataReq();
			tagCmd[i] <= tagTable[tag];
			wdataCnt[i] <= 0;
			wrState[i] <= 1;
		endrule

		rule doWriteDataSend if (wrState[i] ==1);
			if (wdataCnt[i] < fromInteger(pageSizeUser/2)) begin
				Bit#(16) wData = getDataHash(wdataCnt[i], tagCmd[i].page, 
												tagCmd[i].block, tagCmd[i].chip, fromInteger(i));
				busCtrl[i].busIfc.writeWord(wData);
				wdataCnt[i] <= wdataCnt[i] + 1;
				$display("@%t\t%m: controller sent write data [%d]: %x", $time, wdataCnt[i], wData);
			end
			else begin
				wrState[i] <= 0;
			end
		endrule
			
		//TODO may have to pipeline this if too much logic
		rule doReadData;
			let taggedRData <- busCtrl[i].busIfc.readWord();
			Bit#(16) rdata = tpl_1(taggedRData);
			TagT rTag = tpl_2(taggedRData);
			FlashCmd cmd = tagTable[rTag];
			Bit#(16) wData = getDataHash(rdataCnt[i], cmd.page, cmd.block, cmd.chip, fromInteger(i));
			rDataDebug[i] <= rdata;

			//check
			if (rdata != wData) begin
				$display("@%t\t%m: *** FlashController readback error at [%d] tag=%x, bus=%d, chip=%d, block=%d; Expected %x, got %x",
							$time, rdataCnt[i], cmd.tag, i, cmd.chip, cmd.block, wData, rdata);
				errCnt[i] <= errCnt[i] + 1;
			end
			else begin
				$display("@%t\t%m: FlashController readback OK! data[%d]=%x", $time, rdataCnt[i], rdata);
			end
			if (rdataCnt[i] < fromInteger(pageSizeUser/2 - 1)) begin
				rdataCnt[i] <= rdataCnt[i] + 1;
			end
			else begin
				rdataCnt[i] <= 0;
			end
		endrule
	end //for each bus


	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		rule debugSet;
			//busCtrl[i].phyDebug.setDebug2(zeroExtend(pack(state)));
			busCtrl[i].phyDebug.setDebug2(rdataCnt[i]);
			busCtrl[i].phyDebug.setDebug3(errCnt[i]);
			//busCtrl[i].phyDebug.setDebug4(cmdCnt);
			busCtrl[i].phyDebug.setDebug4(rDataDebug[i]); //Error corrected data
			busCtrl[i].phyDebug.setDebugVin(busCtrl[i].phyDebug.getDebugVout());
		endrule
	end

	Vector#(NUM_CHIPBUSES, Vector#(BUSES_PER_CHIPBUS, NANDPins)) nandBusVec = newVector();
	Vector#(NUM_CHIPBUSES, NANDWenNclk) nandBusSharedVec = newVector();

	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		Integer bi = i / valueOf(BUSES_PER_CHIPBUS);
		Integer bj = i % valueOf(BUSES_PER_CHIPBUS);
		nandBusVec[bi][bj] = busCtrl[i].nandPins;
	end

	for (Integer i=0; i < valueOf(NUM_CHIPBUSES); i=i+1) begin
		nandBusSharedVec[i] = busWenNclk[i].nandWenNclk;
	end

	interface nandBus = nandBusVec;
	interface nandBusShared = nandBusSharedVec;
endmodule
