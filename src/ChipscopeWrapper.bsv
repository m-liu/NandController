
typedef 4 NumDbgIlas;

interface DebugVIO;
	method Action setDebugVin (Bit#(64) i);
	method Bit#(64) getDebugVout();
endinterface

interface DebugILA;
	method Action setDebug0 (Bit#(16) i);
	method Action setDebug1 (Bit#(16) i);
	method Action setDebug2 (Bit#(16) i);
	method Action setDebug3 (Bit#(16) i);
	method Action setDebug4 (Bit#(16) i);
	method Action setDebug5_64 (Bit#(64) i);
	method Action setDebug6_64 (Bit#(64) i);
endinterface


interface CSDebugIfc; 
	interface DebugVIO vio;
	interface DebugILA ila0;
	interface DebugILA ila1;
	interface DebugILA ila2;
	interface DebugILA ila3;
endinterface 

import "BVI" chipscope_debug_viv =  //TODO change for Vivado or ISE IP
module mkChipscopeDebug(CSDebugIfc);
	default_clock clk0;
	default_reset rst0;

	input_clock clk0(v_clk0) <- exposeCurrentClock;
	input_reset rst0(v_rst0) <- exposeCurrentReset;

interface DebugVIO vio;
	method setDebugVin (v_debug_vin) enable((*inhigh*)en38);
	method v_debug_vout getDebugVout;
endinterface 

interface DebugILA ila0;
		method setDebug0 (v_debug0_0) enable((*inhigh*)en0_0);
		method setDebug1 (v_debug0_1) enable((*inhigh*)en0_1);
		method setDebug2 (v_debug0_2) enable((*inhigh*)en0_2);
		method setDebug3 (v_debug0_3) enable((*inhigh*)en0_3);
		method setDebug4 (v_debug0_4) enable((*inhigh*)en0_4);
		method setDebug5_64 (v_debug0_5_64) enable((*inhigh*)en0_5);
		method setDebug6_64 (v_debug0_6_64) enable((*inhigh*)en0_6);
endinterface

interface DebugILA ila1;
		method setDebug0 (v_debug1_0) enable((*inhigh*)en1_0);
		method setDebug1 (v_debug1_1) enable((*inhigh*)en1_1);
		method setDebug2 (v_debug1_2) enable((*inhigh*)en1_2);
		method setDebug3 (v_debug1_3) enable((*inhigh*)en1_3);
		method setDebug4 (v_debug1_4) enable((*inhigh*)en1_4);
		method setDebug5_64 (v_debug1_5_64) enable((*inhigh*)en1_5);
		method setDebug6_64 (v_debug1_6_64) enable((*inhigh*)en1_6);
endinterface

interface DebugILA ila2;
		method setDebug0 (v_debug2_0) enable((*inhigh*)en2_0);
		method setDebug1 (v_debug2_1) enable((*inhigh*)en2_1);
		method setDebug2 (v_debug2_2) enable((*inhigh*)en2_2);
		method setDebug3 (v_debug2_3) enable((*inhigh*)en2_3);
		method setDebug4 (v_debug2_4) enable((*inhigh*)en2_4);
		method setDebug5_64 (v_debug2_5_64) enable((*inhigh*)en2_5);
		method setDebug6_64 (v_debug2_6_64) enable((*inhigh*)en2_6);
endinterface

interface DebugILA ila3;
		method setDebug0 (v_debug3_0) enable((*inhigh*)en3_0);
		method setDebug1 (v_debug3_1) enable((*inhigh*)en3_1);
		method setDebug2 (v_debug3_2) enable((*inhigh*)en3_2);
		method setDebug3 (v_debug3_3) enable((*inhigh*)en3_3);
		method setDebug4 (v_debug3_4) enable((*inhigh*)en3_4);
		method setDebug5_64 (v_debug3_5_64) enable((*inhigh*)en3_5);
		method setDebug6_64 (v_debug3_6_64) enable((*inhigh*)en3_6);
endinterface

schedule 
(
	ila0_setDebug0, ila0_setDebug1, ila0_setDebug2, ila0_setDebug3, ila0_setDebug4, ila0_setDebug5_64, ila0_setDebug6_64,
	ila1_setDebug0, ila1_setDebug1, ila1_setDebug2, ila1_setDebug3, ila1_setDebug4, ila1_setDebug5_64, ila1_setDebug6_64,
	ila2_setDebug0, ila2_setDebug1, ila2_setDebug2, ila2_setDebug3, ila2_setDebug4, ila2_setDebug5_64, ila2_setDebug6_64,
	ila3_setDebug0, ila3_setDebug1, ila3_setDebug2, ila3_setDebug3, ila3_setDebug4, ila3_setDebug5_64, ila3_setDebug6_64,
	vio_setDebugVin, vio_getDebugVout
)
CF
(
	ila0_setDebug0, ila0_setDebug1, ila0_setDebug2, ila0_setDebug3, ila0_setDebug4, ila0_setDebug5_64, ila0_setDebug6_64,
	ila1_setDebug0, ila1_setDebug1, ila1_setDebug2, ila1_setDebug3, ila1_setDebug4, ila1_setDebug5_64, ila1_setDebug6_64,
	ila2_setDebug0, ila2_setDebug1, ila2_setDebug2, ila2_setDebug3, ila2_setDebug4, ila2_setDebug5_64, ila2_setDebug6_64,
	ila3_setDebug0, ila3_setDebug1, ila3_setDebug2, ila3_setDebug3, ila3_setDebug4, ila3_setDebug5_64, ila3_setDebug6_64,
	vio_setDebugVin, vio_getDebugVout
);

endmodule
