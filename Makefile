### Makefile for the nand_phy project
### Generated by Bluespec Workstation on Tue Jul 15 01:50:13 EDT 2014

default: full_clean compile

sim: full_clean compile_sim

.PHONY: compile
compile:
	@echo Compiling...
	bsc -u -verilog -elab -vdir verilog -bdir bscOut -info-dir bscOut -keep-fires -aggressive-conditions -p .:%/Prelude:%/Libraries:%/Libraries/BlueNoC:%/BSVSource/Xilinx:./src:./src/ECC/src_bsv -g mkFlashController  src/FlashController.bsv 
	@echo Compilation finished

.PHONY: compile_sim
compile_sim:
	@echo Compiling SIMULATION ONLY...
	bsc -u -verilog -elab -vdir verilog -bdir bscOut -info-dir bscOut -keep-fires -aggressive-conditions -D NAND_SIM -p .:%/Prelude:%/Libraries:%/Libraries/BlueNoC:%/BSVSource/Xilinx:./src:./src/ECC/src_bsv -g mkFlashController  src/FlashController.bsv 
	@echo Compilation SIMULATION ONLY finished

.PHONY: clean
clean:
	exec rm -f bscOut/*

.PHONY: full_clean
full_clean:
	rm -f bscOut/*
	rm -f verilog/*
