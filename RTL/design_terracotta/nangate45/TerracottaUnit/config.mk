export DESIGN_NAME = TerracottaUnit
export PLATFORM    = nangate45

# Source files
export VERILOG_FILES = \
	$(abspath $(DESIGN_DIR))/../../src/common/terracotta_types_pkg.sv \
	$(abspath $(DESIGN_DIR))/../../src/common/ConfigTable.sv \
	$(abspath $(DESIGN_DIR))/../../src/metadata/MetadataTable.sv \
	$(abspath $(DESIGN_DIR))/../../src/metadata/MetadataTableBank.sv \
	$(abspath $(DESIGN_DIR))/../../src/triggers/TriggerUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/triggers/TriggerBankArray.sv \
	$(abspath $(DESIGN_DIR))/../../src/triggers/TriggerArray.sv \
	$(abspath $(DESIGN_DIR))/../../src/updates/UpdateUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/actions/ActionUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/TerracottaUnit.sv
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
export CORE_UTILIZATION ?= 45
export PLACE_DENSITY_LB_ADDON ?= 0.20
export TNS_END_PERCENT ?= 100

# Skip timing-driven global placement to avoid RSZ-1008 overflow on large designs
export GPL_TIMING_DRIVEN = 0
