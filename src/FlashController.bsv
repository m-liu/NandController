import FIFOF		::*;
import Vector		::*;
import Connectable ::*;

import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;
import BusController::*;
import NandPhyWenNclkWrapper::*;

typedef 1 NUM_CHIPBUSES; //TODO FIXME XXX
typedef 2 BUSES_PER_CHIPBUS;
typedef TMul#(NUM_CHIPBUSES, BUSES_PER_CHIPBUS) NUM_BUSES;

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
function Bit#(16) getDataHash (Bit#(16) dataCnt, Bit#(8) page, Bit#(16) block, Bit#(4) chip, Bit#(3) bus);
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
	dbgCtrlIfc[8] = nandInfra.dbgCtrl_8;
	dbgCtrlIfc[9] = nandInfra.dbgCtrl_9;
	dbgCtrlIfc[10] = nandInfra.dbgCtrl_10;
	dbgCtrlIfc[11] = nandInfra.dbgCtrl_11;
	dbgCtrlIfc[12] = nandInfra.dbgCtrl_12;
	dbgCtrlIfc[13] = nandInfra.dbgCtrl_13;
	dbgCtrlIfc[14] = nandInfra.dbgCtrl_14;
	dbgCtrlIfc[15] = nandInfra.dbgCtrl_15;

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

	Reg#(TbState) state <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(TbState) returnState <- mkReg(INIT, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(64)) vinPrev <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(4)) chip <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(3)) bus <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) block <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Note: random page programming NOT ALLOWED!! Must program sequentially within a block
	Reg#(Bit#(8)) page <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) dataCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) errCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	//Reg#(Bit#(16)) berrCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);
	Reg#(Bit#(16)) cmdCnt <- mkReg(0, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	Vector#(4, Bit#(64)) vinTest = newVector();
	vinTest[0] = 64'h0002010000050000; //wr blk 5, chip0, bus1
	vinTest[1] = 64'h0001010000050000; //rd blk 5
	vinTest[2] = 64'h0003010000050000; //er blk 5
	vinTest[3] = 64'h0001010000050000; //rd blk 5


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
	Reg#(SsdCmd) initCmd <- mkReg(INIT_BUS, clocked_by nandInfra.clk0, reset_by nandInfra.rst0);

	rule doInit if (state==INIT);
		busCtrl[bus].busIfc.sendCmd(initCmd, 0, 0, 0);
		state <= INIT_WAIT;
	endrule

	rule doInitWait if (state==INIT_WAIT);
		if (busCtrl[bus].busIfc.isIdle) begin
			if (bus < fromInteger(valueOf(NUM_BUSES)-1)) begin
				bus <= bus + 1;
				state <= INIT;
			end
			else begin
				bus <= 0;	
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



	rule doIdleAcceptCmd if (state==IDLE);
		//VIO input command from Bus 0's PHY
		//Beware that VIO runs much slower than system clock.
		`ifdef NAND_SIM
			//use fixed test inputs for sim
			Bit#(64) vin = vinTest[cmdCnt]; 
		`else
			Bit#(64) vin = busCtrl[0].phyDebug.getDebugVout();
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
			bus <= truncate(vin[47:40]);
			chip <= truncate(vin[39:32]);
			block <= truncate(vin[31:16]);
			page <= truncate(vin[15:0]);
			dataCnt <= 0;
			errCnt <= 0;
		end
	endrule



	//Basic write/read/erase testing
	rule doWrite if (state==WRITE);
		busCtrl[bus].busIfc.sendCmd(WRITE_PAGE, chip, block, page);
		state <= WRITE_DATA;
	endrule

	rule doWriteData if (state==WRITE_DATA);
		if (dataCnt < fromInteger(pageSizeUser/2)) begin
			Bit#(16) wData = getDataHash(dataCnt, page, block, chip, bus);
			busCtrl[bus].busIfc.writeWord(wData);
			dataCnt <= dataCnt + 1;
		end
		else begin
			state <= IDLE;
			cmdCnt <= cmdCnt + 1;
		end
	endrule

	rule doRead if (state==READ);
		busCtrl[bus].busIfc.sendCmd(READ_PAGE, chip, block, page);
		state <= READ_DATA;
	endrule

	rule doReadData if (state==READ_DATA);
		if (dataCnt < fromInteger(pageSizeUser/2)) begin
			let rdata <- busCtrl[bus].busIfc.readWord();
			Bit#(16) wData = getDataHash(dataCnt, page, block, chip, bus);
			dataCnt <= dataCnt + 1;

			//check
			if (rdata != wData) begin
				$display("FlashController TB: readback error on block=%d, page=%d; Expected %x, got %x", 
								block, page, wData, rdata);
				errCnt <= errCnt + 1;
			end
			else begin
				$display("FlashController TB: readback OK! data=%x", rdata);
			end
		end
		else begin
			state <= IDLE;
			cmdCnt <= cmdCnt + 1;
		end
	endrule

	//erases the whole block
	rule doErase if (state==ERASE);
		busCtrl[bus].busIfc.sendCmd(ERASE_BLOCK, chip, block, page);
		state <= IDLE;
		cmdCnt <= cmdCnt + 1;
	endrule

	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		rule debugSet;
			busCtrl[i].phyDebug.setDebug2(zeroExtend(pack(state)));
			busCtrl[i].phyDebug.setDebug3(errCnt);
			busCtrl[i].phyDebug.setDebug4(cmdCnt);
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
