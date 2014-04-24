
`timescale 1ns/1ps

module nand_phy_dq_iob #
  (
   // Following parameters are for 32-bit component design (for ML561 Reference
   // board design). Actual values may be different. Actual parameters values
   // are passed from design top module mig_36_1 module. Please refer to
   // the mig_36_1 module for actual values.
   parameter HIGH_PERFORMANCE_MODE = "TRUE",
   parameter IODELAY_GRP           = "IODELAY_NAND"
   )
  (
   input  clk90,
   input  rst90,
   input  dlyinc,
   input  dlyce,
   input  dlyrst,
   input  dq_oe_n,
   input  dqs,
   input  wr_data_rise,
   input  wr_data_fall,
   output rd_data_rise,
   output rd_data_fall,
   inout  ddr_dq
   );

  wire    dq_in;
  wire    dq_oe_n_r;
  wire    dq_out;
  wire    iserdes_clk;
  wire    iserdes_clkb;

  // on a write, rising edge of DQS corresponds to rising edge of CLK180
  // (aka falling edge of CLK0 -> rising edge DQS). We also know:
  //  1. data must be driven 1/4 clk cycle before corresponding DQS edge
  //  2. first rising DQS edge driven on falling edge of CLK0
  //  3. rising data must be driven 1/4 cycle before falling edge of CLK0
  //  4. therefore, rising data driven on rising edge of CLK90
  (* KEEP = "TRUE" *)
  ODDR #
    (
     .SRTYPE("SYNC"),
     .DDR_CLK_EDGE("SAME_EDGE")
     )
    u_oddr_dq
      (
       .Q  (dq_out),
       .C  (clk90),
       .CE (1'b1),
       .D1 (wr_data_rise),
       .D2 (wr_data_fall),
       .R  (1'b0),
       .S  (1'b0)
       );

  // make sure output is tri-state during reset (DQ_OE_N_R = 1)
  (* KEEP = "TRUE" *)
  (* IOB = "FORCE" *) FDPE u_tri_state_dq
    (
     .D    (dq_oe_n),
     .PRE  (rst90),
     .C    (clk90),
     .Q    (dq_oe_n_r),
     .CE   (1'b1)
     ) /* synthesis syn_useioff = 1 */;

	(* KEEP = "TRUE" *)
  IOBUF u_iobuf_dq
    (
     .I  (dq_out),
     .T  (dq_oe_n_r),
     .IO (ddr_dq),
     .O  (dq_in)
     );


(* IODELAY_GROUP = IODELAY_GRP *) IDELAYE2 #(
   .CINVCTRL_SEL("FALSE"),          // Enable dynamic clock inversion (FALSE, TRUE)
   .DELAY_SRC("IDATAIN"),           // Delay input (IDATAIN, DATAIN)
   .HIGH_PERFORMANCE_MODE("TRUE"), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
   .IDELAY_TYPE("VARIABLE"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
   .IDELAY_VALUE(0),                // Input delay tap setting (0-31)
   .PIPE_SEL("FALSE"),              // Select pipelined mode, FALSE, TRUE
   .REFCLK_FREQUENCY(200.0),        // IDELAYCTRL clock input frequency in MHz (190.0-210.0).
   .SIGNAL_PATTERN("CLOCK")          // DATA, CLOCK input signal
)
u_idelay_dq (
   .CNTVALUEOUT(), // 5-bit output: Counter value output
   .DATAOUT(dq_idelay),         // 1-bit output: Delayed data output
   .C(clk90),                     // 1-bit input: Clock input
   .CE(dlyce),                   // 1-bit input: Active high enable increment/decrement input
   .CINVCTRL(),       // 1-bit input: Dynamic clock inversion input
   .CNTVALUEIN(),   // 5-bit input: Counter value input
   .DATAIN(),           // 1-bit input: Internal delay data input
   .IDATAIN(dq_in),         // 1-bit input: Data input from the I/O
   .INC(dlyinc),                 // 1-bit input: Increment / Decrement tap delay input
   .LD(),                   // 1-bit input: Load IDELAY_VALUE input
   .LDPIPEEN(),       // 1-bit input: Enable PIPELINE register to load data input
   .REGRST(dlyrst)            // 1-bit input: Active-high reset tap-delay input
);

/*
  (* IODELAY_GROUP = IODELAY_GRP *) IODELAY #
    (
     .DELAY_SRC("I"),
     .IDELAY_TYPE("VARIABLE"),
     .HIGH_PERFORMANCE_MODE(HIGH_PERFORMANCE_MODE),
     .IDELAY_VALUE(0),
     .ODELAY_VALUE(0)
     )
    u_idelay_dq
      (
       .DATAOUT(dq_idelay),
       .C(clk90),
       .CE(dlyce),
       .DATAIN(),
       .IDATAIN(dq_in),
       .INC(dlyinc),
       .ODATAIN(),
       .RST(dlyrst),
       .T()
       );
*/
  // equalize delays to avoid delta-delay issues
  assign  iserdes_clk  = dqs;
  assign  iserdes_clkb = ~dqs;

(* KEEP = "TRUE" *)
ISERDESE2 #(
   .DATA_RATE("DDR"),           // DDR, SDR
   .DATA_WIDTH(4),              // Parallel data width (2-8,10,14)
   .DYN_CLKDIV_INV_EN("FALSE"), // Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
   .DYN_CLK_INV_EN("FALSE"),    // Enable DYNCLKINVSEL inversion (FALSE, TRUE)
   // INIT_Q1 - INIT_Q4: Initial value on the Q outputs (0/1)
   .INIT_Q1(1'b0),
   .INIT_Q2(1'b0),
   .INIT_Q3(1'b0),
   .INIT_Q4(1'b0),
   .INTERFACE_TYPE("MEMORY"),   // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
   .IOBDELAY("IFD"),           // NONE, BOTH, IBUF, IFD
   .NUM_CE(2),                  // Number of clock enables (1,2)
   .OFB_USED("FALSE"),          // Select OFB path (FALSE, TRUE)
   .SERDES_MODE("MASTER"),      // MASTER, SLAVE
   // SRVAL_Q1 - SRVAL_Q4: Q output values when SR is used (0/1)
   .SRVAL_Q1(1'b0),
   .SRVAL_Q2(1'b0),
   .SRVAL_Q3(1'b0),
   .SRVAL_Q4(1'b0) 
)
ISERDESE2_inst (
   .O(),                       // 1-bit output: Combinatorial output
   // Q1 - Q8: 1-bit (each) output: Registered data outputs
   .Q1(rd_data_fall),
   .Q2(rd_data_rise),
   .Q3(),
   .Q4(),
   .Q5(),
   .Q6(),
   .Q7(),
   .Q8(),
   // SHIFTOUT1-SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
   .SHIFTOUT1(),
   .SHIFTOUT2(),
   .BITSLIP(1'b0),           // 1-bit input: The BITSLIP pin performs a Bitslip operation synchronous to
                                // CLKDIV when asserted (active High). Subsequently, the data seen on the Q1
                                // to Q8 output ports will shift, as in a barrel-shifter operation, one
                                // position every time Bitslip is invoked (DDR operation is different from
                                // SDR).

   // CE1, CE2: 1-bit (each) input: Data register clock enable inputs
   .CE1(1'd1),
   .CE2(1'd1),
   .CLKDIVP(),           // 1-bit input: TBD
   // Clocks: 1-bit (each) input: ISERDESE2 clock input ports
   .CLK(iserdes_clk),                   // 1-bit input: High-speed clock
   .CLKB(iserdes_clkb),                 // 1-bit input: High-speed secondary clock
   .CLKDIV(clk90),             // 1-bit input: Divided clock
   .OCLK(clk90),                 // 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY"
   // Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
   .DYNCLKDIVSEL(), // 1-bit input: Dynamic CLKDIV inversion
   .DYNCLKSEL(),       // 1-bit input: Dynamic CLK/CLKB inversion
   // Input Data: 1-bit (each) input: ISERDESE2 data input ports
   .D(),                       // 1-bit input: Data input
   .DDLY(dq_idelay),                 // 1-bit input: Serial data from IDELAYE2
   .OFB(),                   // 1-bit input: Data feedback from OSERDESE2
   .OCLKB(~clk90),               // 1-bit input: High speed negative edge output clock
   .RST(rst90),                   // 1-bit input: Active high asynchronous reset
   // SHIFTIN1-SHIFTIN2: 1-bit (each) input: Data width expansion input ports
   .SHIFTIN1(),
   .SHIFTIN2() 
);







/*
  ISERDESE2 # //testing FIXME
    (
     //.BITSLIP_ENABLE("FALSE"), //TESTING
     .DATA_RATE("DDR"),
     .DATA_WIDTH(4),
     .INTERFACE_TYPE("MEMORY"),
     .NUM_CE(2),
     .SERDES_MODE("MASTER")
     )
    u_iserdes_dq
      (
       .Q1           (rd_data_fall),
       .Q2           (rd_data_rise),
       .Q3           (),
       .Q4           (),
       .Q5           (),
       .Q6           (),
       .SHIFTOUT1    (),
       .SHIFTOUT2    (),
       .BITSLIP      (),
       .CE1          (1'd1),
       .CE2          (1'd1),
       .CLK          (iserdes_clk),
       .CLKB         (iserdes_clkb),
       .CLKDIV       (clk90),
       //.D            (dq_idelay),
		 .DDLY            (dq_idelay), //TESTING FIXME
       .OCLK         (clk90),
       .RST          (rst90),
       .SHIFTIN1     (),
       .SHIFTIN2     ()
       );
*/
endmodule
