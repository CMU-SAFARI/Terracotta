export DESIGN_NAME = TerracottaSingleTech
export PLATFORM    = nangate45

# Source files (single-tech: no TriggerArray/UpdateArray/ActionArray)
export VERILOG_FILES = \
	$(abspath $(DESIGN_DIR))/../../src/common/terracotta_types_pkg.sv \
	$(abspath $(DESIGN_DIR))/../../src/common/ConfigTable.sv \
	$(abspath $(DESIGN_DIR))/../../src/sram/fakeram45_64x21.v \
	$(abspath $(DESIGN_DIR))/../../src/sram/fakeram45_64x32.v \
	$(abspath $(DESIGN_DIR))/../../src/metadata/MetadataTable.sv \
	$(abspath $(DESIGN_DIR))/../../src/metadata/MetadataTableBank.sv \
	$(abspath $(DESIGN_DIR))/../../src/triggers/TriggerUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/triggers/TriggerBankArray.sv \
	$(abspath $(DESIGN_DIR))/../../src/updates/LfsrRng.sv \
        $(abspath $(DESIGN_DIR))/../../src/updates/UpdateUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/actions/ActionUnit.sv \
	$(abspath $(DESIGN_DIR))/../../src/TerracottaSingleTech.sv
export SDC_FILE      = $(abspath $(DESIGN_DIR))/constraints.sdc

# SRAM macros: Liberty timing + LEF physical
export ADDITIONAL_LIBS = $(PLATFORM_DIR)/lib/fakeram45_64x21.lib \
                         $(PLATFORM_DIR)/lib/fakeram45_64x32.lib
export ADDITIONAL_LEFS = $(PLATFORM_DIR)/lef/fakeram45_64x21.lef \
                         $(PLATFORM_DIR)/lef/fakeram45_64x32.lef

# SystemVerilog frontend
export SYNTH_HDL_FRONTEND = slang
export SYNTH_SLANG_ARGS = --single-unit --top $(DESIGN_NAME)

# Keep ORFS outputs under this design directory
export WORK_HOME = $(abspath $(DESIGN_DIR))

# Do NOT auto-mock memories — we use explicit SRAM instantiation for MetadataTable.
# ConfigTables must remain as register arrays. Set max bits high enough to allow them.
# Largest ConfigTable: Trigger = 128 entries × 84 bits = 10,752 bits
export SYNTH_MOCK_LARGE_MEMORIES = 0
export SYNTH_MEMORY_MAX_BITS = 16384

# Physical design knobs
export CORE_UTILIZATION ?= 35
export PLACE_DENSITY_LB_ADDON ?= 0.20
export TNS_END_PERCENT ?= 100

# Macro halo for SRAM placement
export MACRO_PLACE_HALO = 10 10

# Skip timing-driven global placement to avoid RSZ-1008 overflow
export GPL_TIMING_DRIVEN = 0

# Custom PDN with tighter metal4 pitch for SRAM-dense floorplan
export PDN_TCL = $(abspath $(DESIGN_DIR))/pdn.tcl
