import FIFO::*;
import FIFOF::*;
import Vector::*;
import DefaultValue::*;
import TriState::*;
import Clocks::*;

//provided by Bluespec
import XilinxCells::*;

//provided by QRC
//import XbsvXilinxCells::*;

interface NandInfraIfc;
	interface Clock clk0;
	interface Clock clk90;
	
	interface Reset rst0;
	interface Reset rst90;
endinterface

(* no_default_clock, no_default_reset *)
(* synthesize *)
module mkNandInfra#(	Clock sysClkP, 
							Clock sysClkN,
							Reset sysRstn
						) 
						(NandInfraIfc);

	// Import differential clock using IBUFDS
	Clock sysClkIn <- mkClockIBUFDS(sysClkP, sysClkN);
   Clock sysClkIn_buf <- mkClockBUFG(clocked_by sysClkIn);
	// Invert reset
	Reset sysRst <- mkResetInverter(sysRstn, clocked_by sysClkIn_buf);

	// *************************************************************************
	// Setup and instantiate MMCME2_ADV primitive; Use 7 series clock generator
	// Input: 100MHz system ref clock
	// Output:
	//			(0) 100MHz, 50% duty cycle, no shift
	//			(1) 100MHz, 50% duty cycle, 90 degree shift
	//			(2) 200MHz, 50% duty cycle, no shift 
	// *************************************************************************

	ClockGenerator7Params clkParams = defaultValue();
	// Input clock parameters
	clkParams.clkin1_period			= 10.000;	//100MHz system ref clock
	clkParams.clkin_buffer			= False;		//Buffered already using IFBUGDS
	clkParams.reset_stages			= 3; 			//Default. Async reset sychronization of input clock
	// Setup VCO
	clkParams.clkfbout_mult_f		= 10.000;	//Coregen
	clkParams.clkfbout_phase		= 0.000;		//Coregen
	clkParams.divclk_divide			= 1;
	// Output clock 0: 100MHz, 50% duty, no shift
	clkParams.clkout0_divide_f		= 10.000;
	clkParams.clkout0_duty_cycle	= 0.500;
	clkParams.clkout0_phase			= 0.000;
	// Output clock 1: 100MHz, 50% duty, 90 degree shift
	clkParams.clkout1_divide     	= 10;
	clkParams.clkout1_duty_cycle 	= 0.500;
	clkParams.clkout1_phase      	= 90.000;
	// Output clock 2: 200MHz, 50% duty, no shift
	clkParams.clkout2_divide     = 5;
	clkParams.clkout2_duty_cycle = 0.500;
	clkParams.clkout2_phase      = 0.000;
	// Buffer 3 clocks globally to BUFG; disable other buffers
	clkParams.clkout0_buffer		= True;
	clkParams.clkout1_buffer		= True;
	clkParams.clkout2_buffer		= True;
	clkParams.clkout3_buffer		= False;
	clkParams.clkout4_buffer		= False;
	clkParams.clkout5_buffer		= False;
	clkParams.clkout6_buffer		= False;
	// Instantiate clock generator
	ClockGenerator7 clkGen <- mkClockGenerator7(clkParams, clocked_by sysClkIn_buf, reset_by sysRst);


	//**************************************************************
	// Reset synchronization
	// Hold reset until MMCM is locked and IDELAYCTRL is ready 
	//	and external reset is released
	//**************************************************************
	
	Reset sysRstSync0 <- mkAsyncReset(2, sysRst, clkGen.clkout0);
	Reset sysRstSync90 <- mkAsyncReset(2, sysRst, clkGen.clkout1);
	Reset sysRstSync200 <- mkAsyncReset(2, sysRst, clkGen.clkout2);
	MakeResetIfc newRst0 <- mkReset(3, True, clkGen.clkout0, clocked_by clkGen.clkout0, reset_by sysRstSync0);
	MakeResetIfc newRst90 <- mkReset(3, True, clkGen.clkout1, clocked_by clkGen.clkout1, reset_by sysRstSync90);
	MakeResetIfc newRst200 <- mkReset(3, True, clkGen.clkout2, clocked_by clkGen.clkout2, reset_by sysRstSync200);

	Reset rst0_ = newRst0.new_rst;
	Reset rst90_ = newRst90.new_rst;
	Reset rst200_ = newRst200.new_rst;
	

	//**************************************************************
	// Instantiate IDELAYCTRL. Clocked by 200mhz clk
	// MMCM has to lock first, and then this is reset
	//TODO idelaygroup should be specified in constraint file
	//**************************************************************
	IDELAYCTRL idelayCtrl <- mkIDELAYCTRL(3, clocked_by clkGen.clkout2, reset_by rst200_); //3 stage sync reset
	//need synchronizer for idelayctrlrdy because it doesn't say clocked_by(no_clock)
	// note that clkGen.locked does say that. Therefore no sync regs needed
	SyncBitIfc#(Bool) syncRdy0 <- mkSyncBit(clkGen.clkout2, rst200_, clkGen.clkout0);
	SyncBitIfc#(Bool) syncRdy90 <- mkSyncBit(clkGen.clkout2, rst200_, clkGen.clkout1);


	//**************************************************************
	// Reset rules
	//**************************************************************
	rule doRst0 if ( (!clkGen.locked) && (!syncRdy0.read) );
		newRst0.assertReset;
	endrule

	rule doRst90 if ( (!clkGen.locked) && (!syncRdy90.read) );
		newRst90.assertReset;
	endrule

	rule doRst200 if (!clkGen.locked);
		newRst200.assertReset;
	endrule

	//**************************************************************
	// IDELAYCTRL rdy sync rules
	//**************************************************************
	rule doIdelayRdy0;
		syncRdy0.send(idelayCtrl.rdy);
	endrule

	rule doIdelayRdy90;
		syncRdy90.send(idelayCtrl.rdy);
	endrule


	//**************************************************************
	// Interface
	//**************************************************************
	interface clk0 = clkGen.clkout0;
	interface clk90 = clkGen.clkout1;
	interface rst0 = rst0_;
	interface rst90 = rst90_;
	
	

endmodule

