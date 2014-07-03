
import GetPut::*;
import Vector       :: *;
import FIFOF        :: *;
import FIFO::*;
import SpecialFIFOs :: *;
import PAClib       :: *;
import FShow        :: *;

import GFArith      :: *;
import GFTypes      :: *;

interface RSEncoderIfc;
	//interface Put#(Byte) rs_t_in;
	//interface Put#(Byte) rs_k_in;
	interface Put#(Byte) rs_enc_in;
	interface Get#(Byte) rs_enc_out;
endinterface

//TODO pad zeros


(* synthesize *)
module mkRSEncoder (RSEncoderIfc);

	FIFO#(Byte) t_in <- mkFIFO();
	FIFO#(Byte) k_in <- mkFIFO();
	FIFO#(Byte) enc_in <- mkFIFO();
	FIFO#(Byte) enc_out <- mkFIFO();

	Vector#(TwoT, Reg#(Byte)) encodeReg <- replicateM(mkReg(0));
	Reg#(Bit#(32)) count <- mkReg(0);


	//Generator polynomial coefficients. Constants.
	//Generated using rsgenpoly(255,243) in Matlab. In order from lowest to highest degree. 
	Byte gen_poly_coeff[valueOf(TwoT)] = {120, 252, 175, 132, 170, 167, 147, 130, 51, 34, 193, 136};

	rule doEncode if (count < fromInteger(valueOf(K)));
		let enc_in_sub = gf_add(enc_in.first(), encodeReg[valueOf(TwoT)-1]);
		//calculation for the first register differs from the rest
		encodeReg[0] <= gf_mult(enc_in_sub, gen_poly_coeff[0]);

		//the rest
		Integer i;
		for (i=1; i<valueOf(TwoT); i=i+1) begin
			let enc_product = gf_mult(enc_in_sub, gen_poly_coeff[i]);
			encodeReg[i] <= gf_add(enc_product, encodeReg[i-1]);
		end
		
		enc_in.deq;
		count <= count + 1;
	endrule

	rule doOutputParity if (count == fromInteger(valueOf(K)));
		//just display for now
		Integer i;
		for (i=0; i<valueOf(TwoT); i=i+1) begin
			$display("Parity [%d] = %d\n", i, encodeReg[i]);
		end
		count <= 0;
	endrule


	interface Put rs_enc_in		= toPut(enc_in);
	interface Get rs_enc_out	= toGet(enc_out);

endmodule


