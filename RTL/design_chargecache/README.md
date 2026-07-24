# ChargeCache RTL — HCRAC Hardware Implementation

Custom RTL implementation of ChargeCache for area/power comparison against Terracotta.
Targets **nangate45** at **4.0 ns** clock period (same as Terracotta).

## Architecture

| Module | Description |
|---|---|
| `cc_types_pkg` | Parameters: field widths, HCRAC geometry, command encodings, timing mask |
| `HCRAC` | Set-associative cache with LRU replacement and round-robin invalidation |
| `ChargeCacheUnit` | Top-level: command decode, tag computation, HCRAC lookup/update, timing mask |

### Dataflow

- **ACT**: Compute tag `{row, ba, bg, rank}` → HCRAC lookup → output hit + hardcoded timing mask
- **PRE / RDA / WRA**: Compute tag from open-row input → HCRAC update (insert/evict)
- **Invalidation**: External trigger drives round-robin pointer that clears one entry per tick

### Configurable Parameters (in `cc_types_pkg`)

| Parameter | Default | Description |
|---|---|---|
| `CC_ROW_W` | 9 | Row address width |
| `CC_BA_W` | 2 | Bank address width |
| `CC_BG_W` | 3 | Bank-group address width |
| `CC_RANK_W` | 1 | Rank address width |
| `CC_NUM_SETS` | 32 | Number of cache sets (power of 2) |
| `CC_NUM_WAYS` | 4 | Set associativity |

## Quick Usage

```bash
# Simulation (e.g., with Verilator or iverilog)
iverilog -g2012 -o tb src/cc_types_pkg.sv src/HCRAC.sv src/ChargeCacheUnit.sv tb/tb_ChargeCacheUnit.sv && vvp tb

# Synthesis via ORFS
make -C ../OpenROAD-flow-scripts/flow \
  DESIGN_CONFIG=../../design_chargecache/nangate45/ChargeCacheUnit/config.mk synth

# Full P&R
make -C ../OpenROAD-flow-scripts/flow \
  DESIGN_CONFIG=../../design_chargecache/nangate45/ChargeCacheUnit/config.mk finish
```
