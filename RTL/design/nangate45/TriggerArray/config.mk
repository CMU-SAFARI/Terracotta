export DESIGN_NAME = TriggerArray
export PLATFORM    = nangate45

# Out-of-tree config: use DESIGN_DIR (set by ORFS Makefile from DESIGN_CONFIG)
export VERILOG_FILES = \
	$(abspath $(DESIGN_DIR))/../../src/common/terracotta_types_pkg.sv \
	$(abspath $(DESIGN_DIR))/../../src/common/ConfigTable.sv \
	$(abspath $(DESIGN_DIR))/../../src/triggers/TriggerUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/triggers/TriggerArray.sv \
	$(abspath $(DESIGN_DIR))/../../src/updates/UpdateUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/actions/ActionUnit.sv
export SDC_FILE      = $(abspath $(DESIGN_DIR))/constraints.sdc

# Ensure SystemVerilog parsing
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


# Optional knobs for small blocks
export CORE_UTILIZATION ?= 55
export PLACE_DENSITY_LB_ADDON ?= 0.20
export TNS_END_PERCENT ?= 100
