import FIFOF		::*;
import FIFO		::*;
import Vector		::*;
import Connectable ::*;
import RegFile::*;

import ControllerTypes::*;
import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;
import BusController::*;
import NandPhyWenNclkWrapper::*;
import ChipscopeWrapper::*;

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
	SETUP_TAG_FREE = 10,
	TEST_SUITE = 11,
	TEST_SUITE_DONE = 12,
	ERROR_READBACK = 13
} TbState deriving (Bits, Eq);


interface FlashControllerIfc;
	(* prefix = "B_SHARED" *)
	interface Vector#(NUM_CHIPBUSES, NANDWenNclk) nandBusShared;
	(* prefix = "B" *)
	interface Vector#(NUM_CHIPBUSES, Vector#(BUSES_PER_CHIPBUS, NANDPins)) nandBus;
endinterface

//Create data by hashing the address
function Bit#(16) getDataHash (Bit#(16) dataCnt, Bit#(8) page, Bit#(16) block, ChipT chip, BusT bus);
		Bit#(8) dataCntTrim = truncate(dataCnt);
		Bit#(8) blockTrim = truncate(block);
		Bit#(8) chipTrim = zeroExtend(chip);
		Bit#(8) busTrim = zeroExtend(bus);

		Bit#(8) dataHi = truncate(dataCntTrim + 8'hA0 + (blockTrim<<4)+ (chipTrim<<2) + (busTrim<<6));
		Bit#(8) dataLow = truncate( (~dataHi) + blockTrim );
		Bit#(16) d = {dataHi, dataLow};
		return d;
endfunction

function Tuple2#(BusT, FlashCmd) decodeVin (Bit#(64) vinCmd, TagT tag);
	BusT bus = truncate(vinCmd[47:40]);
	FlashOp flashOp;
	let cmdInOp = vinCmd[55:48];
	case (cmdInOp)
		1: flashOp = READ_PAGE;
		2: flashOp = WRITE_PAGE;
		3: flashOp = ERASE_BLOCK;
		default: flashOp = READ_PAGE;
	endcase
	FlashCmd cmd = FlashCmd { 	tag: tag,
								op: flashOp,
								chip: truncate(vinCmd[39:32]),
								block: truncate(vinCmd[31:16]),
								page: truncate(vinCmd[15:0]) };
	return tuple2(bus, cmd);
endfunction

function Bit#(64) getCurrVin(Bit#(64) vio_in);
	Bit#(64) vin;
	`ifdef NAND_SIM
		//use fixed test inputs for sim
		vin = 64'h00010000005a0000; //choose the first set of test inputs for sim
	`else
		vin = vio_in;
	`endif
	return vin;
endfunction

function Tuple2#(Bit#(16), Bit#(64)) getTestSetVin (Bit#(8) testSetSel, Bit#(16) cmdCnt);
	//Mapping: cmd = [63:48], bus = [47:40], chip = [39:32], block = [31:16], tag = [15:0]
	//Vector#(nTestCmds, Bit#(64)) vinTest = newVector();
	Integer nTestCmds1 = 12;
	Bit#(64) testSet1[nTestCmds1] = {
		64'h0102010000050000, //wr blk 5, chip0, bus1, tag 0
		64'h0102010100050001, //wr blk 5, chip1, bus1, tag 1
		64'h0102010200050002, //wr blk 5, chip2, bus1, tag 1
		64'h0102010300050003, //wr blk 5, chip3, bus1, tag 1
		64'h0102010400050004, //wr blk 5, chip4, bus1, tag 1
		64'h0102010500050005, //wr blk 5, chip5, bus1, tag 1
		64'h0101010000050006, //rd blk 5, chip0, bus1, tag 1
		64'h0101010100050007, //rd blk 5, chip1, bus1, tag 1
		64'h0101010200050008, //rd blk 5, chip2, bus1
		64'h0101010300050009, //rd blk 5, chip3, bus1
		64'h010101040005000A, //wr blk 5, chip4, bus1, tag 1
		64'h010101050005000B //wr blk 5, chip5, bus1, tag 1
	};
	Integer nTestCmds2 = 12;
	Bit#(64) testSet2[nTestCmds2] = {
		64'h0201010000050000, //rd blk 0, chip0, bus1, tag 0
		64'h0201010100050001, //rd blk 0, chip1, bus1, tag 1
		64'h0201010200050002, //rd blk 0, chip2, bus1, tag 1
		64'h0201010300050003, //rd blk 0, chip3, bus1, tag 1
		64'h0201010400050004, //rd blk 0, chip4, bus1, tag 1
		64'h0201010500050005, //rd blk 0, chip5, bus1, tag 1
		64'h0201010600050006, //rd blk 0, chip6, bus1, tag 1
		64'h0201010700050007, //rd blk 0, chip7, bus1, tag 1
		64'h0201010000050008, //rd blk 0, chip0, bus1
		64'h0201010100050009, //rd blk 0, chip1, bus1
		64'h020101020005000A, //rd blk 0, chip2, bus1, tag 1
		64'h020101030005000B	 //rd blk 0, chip3, bus1, tag 1
	};
	Integer nTestCmds3 = 6;
	Bit#(64) testSet3[nTestCmds3] = {
		64'h0102010000050000, //wr blk 5, chip0, bus1, tag 0
		64'h0102010100050001, //wr blk 5, chip1, bus1, tag 1
		64'h0102010200050002, //wr blk 5, chip2, bus1, tag 1
		64'h0102010300050003, //wr blk 5, chip3, bus1, tag 1
		64'h0102010400050004, //wr blk 5, chip4, bus1, tag 1
		64'h0102010500050005 //wr blk 5, chip5, bus1, tag 1
	};
	
	Integer nTestCmds4 = 12;
	Bit#(64) testSet4[nTestCmds4] = {
		64'h0101010000050006, //rd blk 5, chip0, bus1, tag 1
		64'h0101010100050007, //rd blk 5, chip1, bus1, tag 1
		64'h0101020200050008, //rd blk 5, chip2, bus1
		64'h0101010300050009, //rd blk 5, chip3, bus1
		64'h010102040005000A, //wr blk 5, chip4, bus1, tag 1
		64'h010101050005000B, //wr blk 5, chip5, bus1, tag 1
		64'h0101020000050006, //rd blk 5, chip0, bus1, tag 1
		64'h0101010100050007, //rd blk 5, chip1, bus1, tag 1
		64'h0101020200050008, //rd blk 5, chip2, bus1
		64'h0101010300050009, //rd blk 5, chip3, bus1
		64'h010102040005000A, //wr blk 5, chip4, bus1, tag 1
		64'h010101050005000B //wr blk 5, chip5, bus1, tag 1
	};

	Integer nTestCmds5 = 1;
	Bit#(64) testSet5[nTestCmds5] = {
		64'h0102010000050000 //wr blk 5, chip0, bus1, tag 0
	};

	Tuple2#(Bit#(16), Bit#(64)) vinRet;
	case (testSetSel)
		1: vinRet = tuple2(fromInteger(nTestCmds1), testSet1[cmdCnt]);
		2: vinRet = tuple2(fromInteger(nTestCmds2), testSet2[cmdCnt]);
		3: vinRet = tuple2(fromInteger(nTestCmds3), testSet3[cmdCnt]);
		4: vinRet = tuple2(fromInteger(nTestCmds4), testSet4[cmdCnt]);
		5: vinRet = tuple2(fromInteger(nTestCmds5), testSet5[cmdCnt]);
		default:	vinRet = tuple2(0,0);
	endcase
	return vinRet;
endfunction

function Tuple2#(BusT, FlashCmd) getNextCmd (TagT tag, Bit#(8) testSetSel, Bit#(16) cmdCnt);
	FlashOp op = INVALID;
	ChipT c = 0;
	BusT bus = 0;
	Bit#(16) blk = 0;
	Integer seqNumBlks = 512;

	//sequential read, same bus
	if (testSetSel == 1) begin
		if (cmdCnt < 1024) begin //issue 10k commands (~80MB)
			bus = 0;
			c = cmdCnt[2:0]; 
			blk = zeroExtend(cmdCnt[15:3]);
			op = READ_PAGE;
		end
	end
	//sequential write, same bus
	else if (testSetSel == 2) begin
		if (cmdCnt < 1024) begin //issue 10k commands (~80MB)
			bus = 0;
			c = cmdCnt[2:0]; 
			blk = zeroExtend(cmdCnt[15:3]);
			op = WRITE_PAGE;
		end
	end

	//sequential erase, same bus
	else if (testSetSel == 3) begin
		if (cmdCnt < 1024) begin //issue 10k commands (~80MB)
			bus = 0;
			c = cmdCnt[2:0]; 
			blk = zeroExtend(cmdCnt[15:3]);
			op = ERASE_BLOCK;
		end
	end

	//sequential read, 2 buses
	else if (testSetSel == 4) begin
		if (cmdCnt < 1024) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[0]); 
			c = cmdCnt[3:1]; 
			blk = zeroExtend(cmdCnt[15:4]);
			op = READ_PAGE;
		end
	end
	//sequential write, 2 buses
	else if (testSetSel == 5) begin
		if (cmdCnt < 1024) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[0]); 
			c = cmdCnt[3:1]; 
			blk = zeroExtend(cmdCnt[15:4]);
			op = WRITE_PAGE;
		end
	end
	//sequential erase, different bus
	else if (testSetSel == 6) begin
		if (cmdCnt < 1024) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[0]); 
			c = cmdCnt[3:1]; 
			blk = zeroExtend(cmdCnt[15:4]);
			op = ERASE_BLOCK;
		end
	end

	FlashCmd cmd =	FlashCmd {	tag: tag,
										op: op,
										chip: c,
										block: blk,
										page: 0 };
	return tuple2(bus, cmd);
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

	//chipscope debug
	CSDebugIfc csDebug <- mkChipscopeDebug(clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Vectorize
	Vector#(4, DebugILA) csDebugIla = newVector();
	csDebugIla[0] = csDebug.ila0;
	csDebugIla[1] = csDebug.ila1;
	csDebugIla[2] = csDebug.ila2;
	csDebugIla[3] = csDebug.ila3;

	rule setILAZero;
		csDebugIla[2].setDebug0(0);
		csDebugIla[2].setDebug1(0);
		csDebugIla[2].setDebug2(0);
		csDebugIla[2].setDebug3(0);
		csDebugIla[2].setDebug4(0);
		csDebugIla[2].setDebug5_64(0);
		csDebugIla[2].setDebug6_64(0);
		csDebugIla[3].setDebug0(0);
		csDebugIla[3].setDebug1(0);
		csDebugIla[3].setDebug2(0);
		csDebugIla[3].setDebug3(0);
		csDebugIla[3].setDebug4(0);
		csDebugIla[3].setDebug5_64(0);
		csDebugIla[3].setDebug6_64(0);
	endrule

	//Nand WEN/NandClk (because of weird organization, this module is
	// shared among half buses)
	Vector#(NUM_CHIPBUSES, VNANDPhyWenNclk) busWenNclk <- replicateM(vMkNandPhyWenNclk(nandInfra.clk0, nandInfra.rst0));

	//Bus controllers.
	Vector#(NUM_BUSES, BusControllerIfc) busCtrl = newVector();
	for (Integer i=0; i<valueOf(NUM_BUSES); i=i+1) begin
		busCtrl[i] <- mkBusController(nandInfra.clk90, nandInfra.rst90, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	end

	//Tag to command mapping table
	//Vector#(NumTags, Reg#(FlashCmd)) tagTable <- replicateM(mkRegU(clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	//Reg#(FlashCmd) tagTable[valueOf(NumTags)];
	//Since the BSV library Regfile only has 5 read ports, we'll just replicate it for each bus
	Vector#(NUM_BUSES, RegFile#(TagT, FlashCmd)) tagTable <- replicateM(mkRegFileFull(clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	FIFO#(TagT) tagFreeList <- mkSizedFIFO(valueOf(NumTags), clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) tagFreeCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	//for (Integer i=0; i<valueOf(NumTags); i=i+1) begin
	//	tagTable[i]	<- mkRegU(clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//end
	//RegFile#(TagT, FlashCmd) tagTable <- mkRegFileFull(clocked_by nandInfra.clk0, reset_by nandInfra.rst0);


	Reg#(TbState) state <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(TbState) returnState <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(64)) vinPrev <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Reg#(ChipT) chip <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(BusT) busInd <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Reg#(Bit#(16)) block <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Note: random page programming NOT ALLOWED!! Must program sequentially within a block
	//Reg#(Bit#(8)) page <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Reg#(Bit#(16)) dataCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Vector#(NUM_BUSES, Reg#(Bit#(2))) wrState <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(FlashCmd)) tagCmd <- replicateM(mkRegU(clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) rdataCnt <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) wdataCnt <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(64))) errCnt <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	//Reg#(Bit#(16)) berrCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) cmdCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Vector#(NUM_BUSES, Reg#(Bit#(16))) rDataDebug <- replicateM(mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0));

	Reg#(Bit#(64)) latencyCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Vector#(NUM_BUSES, FIFO#(Bit#(16))) rdata2check <- replicateM(mkFIFO(clocked_by nandInfra.clk0, reset_by nandInfra.rst0));
	Vector#(NUM_BUSES, FIFO#(FlashCmd)) rcmd2check <- replicateM(mkFIFO(clocked_by nandInfra.clk0, reset_by nandInfra.rst0));




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
					state <= SETUP_TAG_FREE;
				end
			end
		end
	endrule

	//setup tag free list
	rule doSetupTagFreeList if (state==SETUP_TAG_FREE);
		if (tagFreeCnt < fromInteger(valueOf(NumTags))) begin
			tagFreeList.enq(truncate(tagFreeCnt));
			tagFreeCnt <= tagFreeCnt + 1;
		end
		else begin
			state <= IDLE;
			tagFreeCnt <= 0;
		end
	endrule

	//Continuously send commands as fast as possible
	rule doIdleAcceptCmd if (state==IDLE);
		//VIO input command from Bus 0's PHY
		Bit#(64) vin = getCurrVin(csDebug.vio.getDebugVout());

		//select a test set
		Bit#(8) testSetSel = vin[63:56];
		if (testSetSel == 0) begin //use VIO as cmd
			if (vin != 0 && vin != vinPrev) begin
				vinPrev <= vin;
				TagT newTag = tagFreeList.first();
				tagFreeList.deq();
				let dec = decodeVin(vin, newTag);
				let b = tpl_1(dec);
				let cmd = tpl_2(dec);
				busCtrl[b].busIfc.sendCmd(cmd); //send cmd
				for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
					tagTable[i].upd(newTag, cmd);
				end
				//tagTable[cmd.tag] <= cmd;
				//tagTable.upd(cmd.tag, cmd); //insert in tag table
				//errCnt <= 0;
				//cmdCnt <= cmdCnt + 1;
				$display("@%t\t%m: controller sent cmd: %x", $time, vin);
				latencyCnt <= 0; //latency counter
			end
			cmdCnt <= 0;
		end
		else begin //use predefined test set
			state <= TEST_SUITE;
			cmdCnt <= 0;
			latencyCnt <= 0;
			for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
				errCnt[i] <= 0;
			end
		end

//			let ts = getTestSetVin(testSetSel, cmdCnt);
//			Bit#(64) vinTest = tpl_2(ts);
//			FlashCmd cmd = decodeVin(vinTest);
//			Bit#(3) b = truncate(vinTest[47:40]);
//			
//			if (cmdCnt<tpl_1(ts)) begin //intentionally one less command //TODO
//
//				busCtrl[b].busIfc.sendCmd(cmd);
//				//tagTable[cmd.tag] <= cmd;
//				//tagTable.upd(cmd.tag, cmd); //insert in tag table
//				for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
//					tagTable[i].upd(cmd.tag, cmd);
//				end
//				//cmdCnt <= cmdCnt + 1; //FIXME
//				$display("@%t\t%m: controller sent cmd: %x", $time, vinTest);
//			end
//			//else begin
//			//	latencyCnt <= 0; //latency counter
//			//	cmdCnt <= 0;
//			//end
//		end
	endrule


	rule doTestSuite if (state==TEST_SUITE);
		//get a free tag
		TagT newTag = tagFreeList.first();
		tagFreeList.deq();

		//get new command
		Bit#(64) vin = getCurrVin(csDebug.vio.getDebugVout());
		Bit#(8) testSetSel = vin[63:56];
		let busAndCmd = getNextCmd(newTag, testSetSel, cmdCnt);
		let bus = tpl_1(busAndCmd);
		let cmd = tpl_2(busAndCmd);

		//check if done
		if (cmd.op == INVALID) begin
			state <= TEST_SUITE_DONE;
		end
		else begin
			//upate tag table
			for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
				tagTable[i].upd(newTag, cmd);
			end
			//issue command
			busCtrl[bus].busIfc.sendCmd(cmd);
			//increment count, check if done. 
			cmdCnt <= cmdCnt + 1;
			$display("@%t\t%m: controller sent cmd: tag=%x, bus=%d, op=%d, chip=%d, blk=%d", $time,
	  						newTag, bus, cmd.op, cmd.chip, cmd.block);
		end
	endrule

	rule doTestSuiteDone if (state==TEST_SUITE_DONE);
		Bit#(64) vin = getCurrVin(csDebug.vio.getDebugVout());
		if (vin[63:56] == 0) begin
			state <= IDLE;
		end
	endrule

	rule incLatencyCnt;
		latencyCnt <= latencyCnt + 1;
	endrule

	//Handle write data requests from the BusController
	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		rule doEraseAck;
			TagT t <- busCtrl[i].busIfc.ackErase();
			tagFreeList.enq(t);
			$display("@%t\t%m: FlashController erase returned tag=%x", $time, t);
		endrule

		rule doWriteDataReq if (wrState[i] == 0);
			TagT tag <- busCtrl[i].busIfc.writeDataReq();
			tagCmd[i] <= tagTable[i].sub(tag);
			//tagCmd[i] <= tagTable[tag];
			//Return free tag. May create conflicts, but its ok
			tagFreeList.enq(tag); 
			$display("@%t\t%m: FlashController write returned tag=%x", $time, tag);
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
		
		//Pipelined to reduce critical path
		rule doReadData;
			let taggedRData <- busCtrl[i].busIfc.readWord();
			Bit#(16) rdata = tpl_1(taggedRData);
			rDataDebug[i] <= rdata;
			TagT rTag = tpl_2(taggedRData);
			FlashCmd cmd = tagTable[i].sub(rTag);
			//FlashCmd cmd = tagTable[rTag];
			rdata2check[i].enq(rdata);
			rcmd2check[i].enq(cmd);
		endrule

		rule doReadDataCheck;
			FlashCmd cmd = rcmd2check[i].first;
			Bit#(16) rdata = rdata2check[i].first;
			rcmd2check[i].deq();
			rdata2check[i].deq();
			Bit#(16) wData = getDataHash(rdataCnt[i], cmd.page, cmd.block, cmd.chip, fromInteger(i));

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
				//return tag. Again this may conflict, but it should be ok. We have enough buffering
				tagFreeList.enq(cmd.tag);
				$display("@%t\t%m: FlashController read returned tag=%x", $time, cmd.tag);
				rdataCnt[i] <= 0;
			end
		endrule
	end //for each bus


	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		rule debugSet;
			//busCtrl[i].phyDebug.setDebug2(zeroExtend(pack(state)));
			//busCtrl[i].phyDebug.setDebug2(rdataCnt[i]);
			//busCtrl[i].phyDebug.setDebug2(latencyCnt[25:10]); //approximate to 1024 accuracy
			//busCtrl[i].phyDebug.setDebug3(errCnt[i]);
			//busCtrl[i].phyDebug.setDebug4(cmdCnt);
			//busCtrl[i].phyDebug.setDebug4(rDataDebug[i]); //Error corrected data
			//busCtrl[i].phyDebug.setDebugVin(busCtrl[i].phyDebug.getDebugVout());
			csDebugIla[i].setDebug0(busCtrl[i].busIfc.getDebugRawData); 
			csDebugIla[i].setDebug1(busCtrl[i].busIfc.getDebugBusState); 
			csDebugIla[i].setDebug2(busCtrl[i].busIfc.getDebugAddr); 
			csDebugIla[i].setDebug3(rDataDebug[i]); //Error corrected data
			csDebugIla[i].setDebug4(zeroExtend(pack(state)));
			//latencyCnt[25:10]); //approximate to 1024 accuracy
			csDebugIla[i].setDebug5_64(latencyCnt);
			csDebugIla[i].setDebug6_64(errCnt[i]);
		endrule
	end

	rule debugSetVio;
		csDebug.vio.setDebugVin(csDebug.vio.getDebugVout());
	endrule

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
