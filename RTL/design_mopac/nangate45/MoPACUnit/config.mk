export DESIGN_NAME = MoPACUnit
export PLATFORM    = nangate45

# Source files (relative to DESIGN_DIR which is this directory)
export VERILOG_FILES = \
	$(abspath $(DESIGN_DIR))/../../src/mopac_types_pkg.sv \
	$(abspath $(DESIGN_DIR))/../../src/LfsrRng.sv \
	$(abspath $(DESIGN_DIR))/../../src/CaBusEncoderMoPAC.sv \
	$(abspath $(DESIGN_DIR))/../../src/MoPACUnit.sv
export SDC_FILE      = $(abspath $(DESIGN_DIR))/constraints.sdc

# SystemVerilog frontend
export READ_VERILOG_OPTIONS += -sv
export READ_LANGUAGE = slang

# Keep ORFS outputs under this design directory
export WORK_HOME = $(abspath $(DESIGN_DIR))

# Use slang SystemVerilog frontend for synthesis
export SYNTH_HDL_FRONTEND = slang
export SYNTH_SLANG_ARGS = --single-unit --top $(DESIGN_NAME)

# Mock large memories to avoid synthesis aborts on array inference
export SYNTH_MOCK_LARGE_MEMORIES = 1
export SYNTH_KEEP_MOCKED_MEMORIES = 1
export SYNTH_MEMORY_MAX_BITS = 1048576

# Physical design knobs
export CORE_UTILIZATION ?= 55
export PLACE_DENSITY_LB_ADDON ?= 0.20
export TNS_END_PERCENT ?= 100
