# CGRA Latency Results — Trigger & Update Kernels

## CGRA Configuration

| Parameter | Value |
|-----------|-------|
| Architecture | HyCUBE |
| Grid Size | 6×6 (36 PEs) |
| FU PEs | 30 (non-memory, 1-cycle) |
| FU_MEM PEs | 6 (left column, 2-cycle, supports LOAD/STORE) |
| Register File | 4 registers per PE |
| Datapath | 32-bit |
| Mapping Mode | Light (PartPredLight DFG, no simulation) |

## Trigger Latencies

| Technique | Kernel | II | Latency (cycles) | DFG Nodes | Mem Ops (L+S) | Critical Path Depth |
|-----------|--------|----|-------------------|-----------|---------------|---------------------|
| ChargeCache | v7 (2-way, ACT-gated, packed) | 1 | 8 | 15 | 4L + 1S = 5 | 7 |
| MASA | v6b (override flag) | 1 | 7 | 11 | 3L + 1S = 4 | 6 |
| MoPAC | v2 (PRE-sensitive, per-bank) | 1 | 6 | 6 | 1L + 1S = 2 | 5 |
| PRADA | v2 (LUT, state×request) | 1 | 4 | 7 | 3L + 1S = 4 | 3 + table LOAD |

## Kernel Descriptions

### ChargeCache — `kernels/chargecache/chargecache_trigger_v7_2way.c`

**Function**: On ACT, check if row address is cached in the Hot-Row Charge Cache (HCRAC).

- 2-way set-associative, 32 sets (64 entries total)
- Packed metadata: `entry = (valid << 15) | row_addr[14:0]`
- ACT-gated: result is AND-ed with `cmd == ACT`
- DFG: 4 LOAD + 1 STORE + 3 CMP + 2 AND + 2 LS + 3 OR

### MASA — `kernels/masa/masa_trigger_v6b_override.c`

**Function**: On ACT, check if subarray needs switching. On PRE, signal PRE_SA override.

- Outputs a 1-bit override flag (not the actual command)
- Controller disambiguates: override + original cmd → SEL_SA or PRE_SA
- Eliminates CMERGE/SELECT nodes entirely
- DFG: 3 LOAD + 1 STORE + 3 CMP + 1 XOR + 1 AND + 2 OR

### MoPAC — `kernels/mopac/mopac_trigger_v2_perbank.c`

**Function**: On PRE, check cu_flag and output PREcu or PRE.

- Single metadata read (cu_flag), branchless output
- Uses mask expansion: `-(flag & 1)` → 0 or 0xFFFFFFFF
- XOR-based command selection: `PRE ^ (mask & (PREcu ^ PRE))`
- DFG: 1 LOAD + 1 STORE + 2 AND + 1 SUB + 1 XOR

### PRADA — `kernels/prada/prada_trigger_v2_lut.c`

**Function**: Given (state, request), look up the next command from a precomputed table.

- 32-entry table in SPM: indexed by `(request << 3) | state`
- 5 states × 4 request types, stride-8 for shift addressing
- Pure table lookup, no ALU logic for command selection
- DFG: 3 LOAD + 1 STORE + 2 LS + 1 OR

## Update Latencies

| Technique | Kernel | II | Latency (cycles) | DFG Nodes | Mem Ops (L+S) |
|-----------|--------|----|-------------------|-----------|---------------|
| ChargeCache | HW-managed LRU, 2-way | 1 | 9 | 22 | 3L + 1S = 4 |
| MASA | cmd bit-test, 3-way mux | 1 | 8 | 15 | 3L + 1S = 4 |
| MoPAC | LFSR RNG, p≈1/4 | 1 | 12 | 16 | 1L + 2S = 3 |
| PRADA | LUT state transition | 1 | 4 | 7 | 3L + 1S = 4 |

### ChargeCache — `kernels/chargecache/chargecache_update.c`

**Function**: On PRE, insert row address into the HCRAC (2-way set-associative, 32 sets).

- Hit → re-store same value (SPM marks way as MRU)
- Empty way → insert there
- Conflict → evict LRU way
- SPM hardware tracks LRU: exposes LRU bit in bit 31 of entry0 (read-only)
- CGRA only reads LRU, never writes it — SPM auto-updates on STORE
- Entry format: `(valid << 20) | row_addr[19:0]`, separate `entries_in`/`entries_out` arrays
- Way selection: `select_way1 = hit1 | (!hit0 & (!v1 | lru_is_1))`

### MASA — `kernels/masa/masa_update.c`

**Function**: On PRE_SA, invalidate current SA. On SEL_SA, set target SA.

- Input: `cmd` (ACT/PRE_SA/SEL_SA), `sa_cur`, `target_sa`
- Tests cmd bits: bit 4 → PRE_SA (clear SA), bit 0 → SEL_SA (set target)
- 3-way mux via dual mask+negate: `new_sa = (target & sel_mask) | (sa_cur & ~sel_mask & ~pre_mask)`
- Two parallel SUB paths for negation; no CMERGE/SELECT

### MoPAC — `kernels/mopac/mopac_update.c`

**Function**: On ACT, probabilistically set cu_flag (p ≈ 1/4).

- 16-bit Fibonacci LFSR with taps at bits 16, 14, 13, 11
- Threshold: top 2 bits both zero → fire probability ≈ 1/4
- Separate `lfsr_in`/`lfsr_out` arrays to avoid aliasing RecMinII
- Two STOREs: updated LFSR state + cu_flag

### PRADA — `kernels/prada/prada_update.c`

**Function**: Given (state, cmd_type), look up next state from precomputed transition table.

- Same LUT approach as trigger: `table[(cmd_type << 3) | state]`
- 32-entry table, stride-8 indexing
- Separate `state_in`/`state_out` arrays

## Design Decisions

1. **One CGRA per bank**: All triggers operate on per-bank metadata in on-chip SPM.
2. **6×6 grid**: Minimum size where all 4 techniques achieve II=1. The 4×4 grid has only 4 FU_MEM PEs — insufficient for ChargeCache (5 mem ops) and MASA (4 mem ops with routing pressure).
3. **2-way ChargeCache**: Reduced from 4-way (II=2, 7 mem ops) to 2-way (II=1, 5 mem ops). Sets doubled (16→32) to preserve 64-entry capacity.
4. **MASA override flag**: Outputs boolean instead of command constant to avoid CMERGE/SELECT nodes, saving 2 cycles (9→7).
5. **PRADA LUT**: Table approach avoids state-machine control flow that would fail on CGRA.
6. **Separate in/out arrays**: Morpher infers loop-carried dependency (RecMinII) when same base pointer is both LOADed and STOREd. Using separate arrays eliminates this.
7. **SPM hardware LRU**: ChargeCache update assumes SPM tracks LRU on every STORE, avoiding a dedicated LRU write (saves 1 STORE + ~3 nodes).
