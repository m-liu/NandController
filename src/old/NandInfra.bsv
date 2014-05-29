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
	
	interface Reset rstn0;
	interface Reset rstn90;
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
	//Reset sysRst <- mkResetInverter(sysRstn, clocked_by sysClkIn_buf);

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
	clkParams.clkout0n_buffer		= False;
	clkParams.clkout1_buffer		= True;
	clkParams.clkout1n_buffer		= False;
	clkParams.clkout2_buffer		= True;
	clkParams.clkout2n_buffer		= False;
	clkParams.clkout3_buffer		= False;
	clkParams.clkout3n_buffer		= False;
	clkParams.clkout4_buffer		= False;
	clkParams.clkout5_buffer		= False;
	clkParams.clkout6_buffer		= False;
	// Instantiate clock generator
	ClockGenerator7 clkGen <- mkClockGenerator7(clkParams, clocked_by sysClkIn_buf, reset_by sysRstn);


	//**************************************************************
	// Reset synchronization
	// Hold reset until MMCM is locked and IDELAYCTRL is ready 
	//	and external reset is released
	//**************************************************************
	
	Reset sysRstnSync0 <- mkAsyncReset(2, sysRstn, clkGen.clkout0);
	Reset sysRstnSync90 <- mkAsyncReset(2, sysRstn, clkGen.clkout1);
	Reset sysRstnSync200 <- mkAsyncReset(2, sysRstn, clkGen.clkout2);
	MakeResetIfc newRstn0 <- mkReset(3, True, clkGen.clkout0, clocked_by clkGen.clkout0, reset_by sysRstnSync0);
	MakeResetIfc newRstn90 <- mkReset(3, True, clkGen.clkout1, clocked_by clkGen.clkout1, reset_by sysRstnSync90);
	MakeResetIfc newRstn200 <- mkReset(3, True, clkGen.clkout2, clocked_by clkGen.clkout2, reset_by sysRstnSync200);

	Reset rstn0_ = newRstn0.new_rst;
	Reset rstn90_ = newRstn90.new_rst;
	Reset rstn200_ = newRstn200.new_rst;
	

	//**************************************************************
	// Instantiate IDELAYCTRL. Clocked by 200mhz clk
	// MMCM has to lock first, and then this is reset
	//TODO idelaygroup should be specified in constraint file
	//**************************************************************
	IDELAYCTRL idelayCtrl <- mkIDELAYCTRL(3, clocked_by clkGen.clkout2, reset_by rstn200_); //3 stage sync reset
	//need synchronizer for idelayctrlrdy because it doesn't say clocked_by(no_clock)
	// note that clkGen.locked does say that. Therefore no sync regs needed
	SyncBitIfc#(Bool) syncRdy0 <- mkSyncBit(clkGen.clkout2, rstn200_, clkGen.clkout0);
	SyncBitIfc#(Bool) syncRdy90 <- mkSyncBit(clkGen.clkout2, rstn200_, clkGen.clkout1);


	//**************************************************************
	// Reset rules
	//**************************************************************
	rule doRstn0 if ( (!clkGen.locked) ||  (!syncRdy0.read) );
		newRstn0.assertReset;
	endrule

	rule doRstn90 if ( (!clkGen.locked) || (!syncRdy90.read) );
		newRstn90.assertReset;
	endrule

	rule doRstn200 if (!clkGen.locked);
		newRstn200.assertReset;
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
	interface rstn0 = rstn0_;
	interface rstn90 = rstn90_;
	
	

endmodule

