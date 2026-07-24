export DESIGN_NAME = ChargeCacheUnit
export PLATFORM    = nangate45

# Source files (relative to DESIGN_DIR which is this directory)
export VERILOG_FILES = \
	$(abspath $(DESIGN_DIR))/../../src/cc_types_pkg.sv \
	$(abspath $(DESIGN_DIR))/../../src/sram/fakeram45_128x116.v \
	$(abspath $(DESIGN_DIR))/../../src/HCRAC.sv \
	$(abspath $(DESIGN_DIR))/../../src/ChargeCacheUnit.sv
export SDC_FILE      = $(abspath $(DESIGN_DIR))/constraints.sdc

# SystemVerilog frontend
export READ_VERILOG_OPTIONS += -sv
export READ_LANGUAGE = slang

# Keep ORFS outputs under this design directory
export WORK_HOME = $(abspath $(DESIGN_DIR))

# Use slang SystemVerilog frontend for synthesis
export SYNTH_HDL_FRONTEND = slang
export SYNTH_SLANG_ARGS = --single-unit --top $(DESIGN_NAME)

# Explicit SRAM macros — do not mock
export SYNTH_MOCK_LARGE_MEMORIES = 0
export SYNTH_MEMORY_MAX_BITS = 16384

# SRAM macro libraries  (fakeram45_128x116)
export ADDITIONAL_LIBS = $(PLATFORM_DIR)/lib/fakeram45_128x116.lib
export ADDITIONAL_LEFS = $(PLATFORM_DIR)/lef/fakeram45_128x116.lef

# Physical design knobs
export CORE_UTILIZATION ?= 55
export PLACE_DENSITY_LB_ADDON ?= 0.20
export MACRO_PLACE_HALO ?= 5 5
export TNS_END_PERCENT ?= 100

# Custom PDN with wider metal4 pitch for macro clearance
export PDN_TCL ?= $(abspath $(DESIGN_DIR))/pdn.tcl
