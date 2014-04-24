import FIFO::*;
import FIFOF::*;
import Vector::*;
import DefaultValue::*;
import TriState::*;
import Clocks::*;

//provided by Bluespec
import XilinxCells::*;

//provided by QRC
import XbsvXilinxCells::*;

interface NandDQCtrl;
	
endinterface

interface NandPhyDQIfc;
	Inout#(Bit#(8)) DQ;
	interface NandDQCtrl;
endinterface


//Clocked by clk90 and rst90
(* synthesize *)
module mkNandPhyDQ #(Clock dqsClk)(NandPhyDQIfc);

	//Tri-state IOBUF from Xbsv
	IOBUF iob <- mkIOBUF(iobOE_r, iobIn);
	Reg#(Bit#(1)) iobOE_r <- mkReg(0);

	//ODDR from BSV lib
	ODDRParams#(Bit#(1)) oddrParams = defaultValue(); 
	oddrParams.ddr_clk_edge 	= "SAME_EDGE";
	oddrParams.srtype 			= "SYNC";

	ODDR#(Bit#(1)) oddr <- mkODDR(oddrParams);


	//IDELAYE2 from Xbsv
	Clock defaultClock <- exposeCurrentClock(); // Don't think it's necessary to pass this
	
	IdelayE2 idelaye2 <- mkIDELAYE2(
		IDELAYE2_Config {
			cinvctrl_sel: "FALSE", 
			delay_src: "IDATAIN",
			high_performance_mode: "TRUE",
			idelay_type: "VARIABLE", 
			idelay_value: 0,
			pipe_sel: "FALSE", 
			refclk_frequency: 200, 
			signal_pattern: "DATA"
			},
		defaultClock 
	);

	//Use DQS to clock the ISERDES
	ClockDividerIfc dqsClkInv <- mkClockInverter(clocked_by dqsClk);
	IserdesE2 iserdese2 <- mkISERDESE2( 
		ISERDESE2_Config{
			data_rate: "DDR", 
			data_width: 4,
			dyn_clk_inv_en: "FALSE", 
			dyn_clkdiv_inv_en: "FALSE",
			interface_type: "MEMORY", 
			num_ce: 2, 
			ofb_used: "FALSE",
			init_q1: 0, 
			init_q2: 0, 
			init_q3: 0, 
			init_q4: 0,
			srval_q1: 0, 
			srval_q2: 0, 
			srval_q3: 0, 
			srval_q4: 0,
			serdes_mode: "MASTER", 
			iobdelay: "IFD"
			},
		dqsClk,
		dqsClkInv.slowClock,
		clocked_by defaultClock //CLKDIV. Being explicit here
	);



endmodule



