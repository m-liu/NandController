import FShow::*;

//**********************************************************
// Type definitions of the flash controller and submodules
//**********************************************************


typedef 1 NUM_CHIPBUSES; //TODO FIXME XXX
typedef 2 BUSES_PER_CHIPBUS;
typedef TMul#(NUM_CHIPBUSES, BUSES_PER_CHIPBUS) NUM_BUSES;

typedef 8 ChipsPerBus;

//NAND geometry
//Actual page size is 8640B, but we don't need the last 40B for ECC
//Valid Data: 2 x (243B x 16 + 208B) = 8192B; 
//With ECC: 2 x (255B x 16 + 220B) = 8600
Integer pageSize = 8600; //bytes
Integer pageSizeUser = 8192; //usable page size is 8k
Integer pageECCBlks = 17; //16 blocks of k=243; 1 block of k=208

//Integer pagesPerBlock = 256;
//Integer blocksPerPlane = 2048;
//Integer planesPerLun = 2;
//Integer lunsPerTarget = 1; //1 for SLC, 2 for MLC

typedef 64 NumTags;
typedef Bit#(TLog#(NumTags)) TagT;
typedef Bit#(TLog#(ChipsPerBus)) ChipT;

//----------------------
//Phy related types
//----------------------
typedef enum {
	PHY_CHIP_SEL,
	PHY_DESELECT_ALL,
	PHY_CMD,
	PHY_READ,
	PHY_WRITE,
	PHY_ADDR,
	PHY_SYNC_CALIB,
	PHY_ENABLE_NAND_CLK
} PhyCycle deriving (Bits, Eq);

typedef enum {
	N_RESET = 8'hFF,
	N_READ_STATUS = 8'h70,
	N_SET_FEATURES = 8'hEF,
	N_PROGRAM_PAGE = 8'h80,
	N_PROGRAM_PAGE_END = 8'h10,
	N_READ_MODE = 8'h00,
	N_READ_PAGE_END = 8'h30,
	N_ERASE_BLOCK = 8'h60,
	N_ERASE_BLOCK_END = 8'hD0,
	N_READ_ID = 8'h90

} ONFICmd deriving (Bits, Eq);

//using tagged union
typedef union tagged {
	ONFICmd OnfiCmd;
	ChipT ChipSel;
} NandCmd deriving (Bits);

typedef struct {
	Bool inSyncMode;
	PhyCycle phyCycle;
	NandCmd nandCmd;
	Bit#(16) numBurst;
	Bit#(32) postCmdWait; //number of cycles to wait after the command
} PhyCmd deriving (Bits);




//---------------------------------
// Bus controller related types
//---------------------------------
typedef enum {
	//INIT_BUS,
	//EN_SYNC,
	//INIT_SYNC,
	//READ_DATA,
	READ_CMD,
	GET_STATUS_READ_DATA,
	WRITE_CMD_DATA,
	ERASE_CMD,
	GET_STATUS, 
	INVALID
} BusOp deriving (Bits, Eq);

typedef struct {
	TagT tag;
	BusOp busOp;
	ChipT chip;
	Bit#(16) block;
	Bit#(8) page;
} BusCmd deriving (Bits, Eq);


//---------------------------------
// Flash controller related types
//---------------------------------

typedef enum {
	INIT_BUS,
	EN_SYNC,
	INIT_SYNC,
	READ_PAGE,
	WRITE_PAGE,
	ERASE_BLOCK
} FlashOp deriving (Bits, Eq);

typedef struct {
	TagT tag;
	FlashOp op;
	ChipT chip;
	Bit#(16) block;
	Bit#(8) page;
} FlashCmd deriving (Bits, Eq);


instance FShow#(BusOp);
	function Fmt fshow (BusOp label);
		case(label)
			READ_CMD: return fshow("BUSOP READ_CMD");
			GET_STATUS_READ_DATA: return fshow("BUSOP GET_STATUS_READ_DATA");
			WRITE_CMD_DATA: return fshow("BUSOP WRITE_CMD_DATA");
			ERASE_CMD: return fshow("BUSOP ERASE_CMD");
			GET_STATUS: return fshow("BUSOP GET_STATUS");
			INVALID: return fshow("BUSOP INVALID");
		endcase
	endfunction
endinstance


