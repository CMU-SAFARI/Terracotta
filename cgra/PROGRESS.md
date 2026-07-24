# PROGRESS.md — Container Recovery & Progress Tracker

> **Purpose**: If the container is rebuilt, read this file first to resume work.

## Environment Status

| Component | Status | Notes |
|-----------|--------|-------|
| LLVM/Clang 10.0.0 | ✅ Installed | `/usr/bin/clang`, `/usr/bin/opt` |
| g++-7 | ✅ Installed | Ubuntu 7.5.0-6ubuntu2 |
| cmake | ✅ Installed | 3.16.3 |
| Python 3.8 | ✅ Installed | numpy 1.24.4, PyYAML 5.3.1, tqdm 4.67.3 |
| Morpher submodules | ✅ Initialized | All 3 populated (DFG Gen, Mapper, Simulator) |
| Morpher DFG Generator | ✅ Built | `Morpher_DFG_Generator/build/src/libdfggenPass.so` |
| Morpher CGRA Mapper | ✅ Built | `Morpher_CGRA_Mapper/build/src/cgra_xml_mapper` |
| HyCUBE Simulator | ✅ Built | `hycube_simulator/src/build/hycube_simulator` |

## Kernel Status

| Technique | Selected Kernel | Source File | Function | Nodes | Mem Ops |
|-----------|----------------|-------------|----------|-------|---------|
| ChargeCache | v7 (2-way, ACT-gated, packed) | `kernels/chargecache/chargecache_trigger_v7_2way.c` | `chargecache_trigger` | 15 | 4L+1S=5 |
| MASA | v6b (override flag) | `kernels/masa/masa_trigger_v6b_override.c` | `masa_trigger` | 11 | 3L+1S=4 |
| MoPAC | v2 (PRE-sensitive, per-bank) | `kernels/mopac/mopac_trigger_v2_perbank.c` | `mopac_trigger` | 6 | 1L+1S=2 |
| PRADA | v2 (LUT, state×request) | `kernels/prada/prada_trigger_v2_lut.c` | `prada_trigger` | 7 | 3L+1S=4 |

## Final CGRA Trigger Mapping Results (6×6 HyCUBE, all II=1)

| Technique | Kernel | II | Latency (cycles) | Nodes | Mem Ops | Notes |
|-----------|--------|----|-------------------|-------|---------|-------|
| **ChargeCache** | v7 2-way ACT | **1** | **8** | 15 | 5 | 32 sets × 2 ways, packed valid+tag, ACT-gated |
| **MASA** | v6b override | **1** | **7** | 11 | 4 | 1-bit override flag, no CMERGE/SELECT |
| **MoPAC** | v2 per-bank | **1** | **6** | 6 | 2 | PRE-sensitive, cu_flag check |
| **PRADA** | v2 LUT | **1** | **4** | 7 | 4 | (req<<3)\|state index into 32-entry table |

### Historical Results (exploration, superseded)

| Technique | II | Latency | Config | Mapping Success |
|-----------|----|---------|--------------------|-----------------|
| ChargeCache v5 packed (4×4) | 2 | 12 | 4×4 | ✅ |
| ChargeCache v5 packed (6×6) | 2 | 9 | 6×6 | ✅ |
| ChargeCache v6 ACT 4-way (6×6) | 2 | 9 | 6×6 | ✅ (7 mem ops → ResMinII=2) |
| ChargeCache v8 dual-pack (6×6) | 2 | 11 | 6×6 | ✅ (routing fail at II=1, 24 nodes) |
| MASA v4 minimal (4×4) | 1 | 5 | 4×4 | ✅ (no cmd output) |
| MASA v5c cmd output (4×4) | 2 | 10 | 4×4 | ✅ |
| MoPAC v2 per-bank (4×4) | 1 | 6 | 4×4 | ✅ |

## Update Kernel Status

| Technique | Selected Kernel | Source File | Function | Nodes | Mem Ops |
|-----------|----------------|-------------|----------|-------|---------|
| ChargeCache | HW-managed LRU, 2-way | `kernels/chargecache/chargecache_update.c` | `chargecache_update` | 22 | 3L+1S=4 |
| MASA | cmd bit-test, 3-way mux | `kernels/masa/masa_update.c` | `masa_update` | 15 | 3L+1S=4 |
| MoPAC | LFSR RNG, p≈1/4 | `kernels/mopac/mopac_update.c` | `mopac_update` | 16 | 1L+2S=3 |
| PRADA | LUT state transition | `kernels/prada/prada_update.c` | `prada_update` | 7 | 3L+1S=4 |

## Final CGRA Update Mapping Results (6×6 HyCUBE, all II=1)

| Technique | Kernel | II | Latency (cycles) | Nodes | Mem Ops | Notes |
|-----------|--------|----|-------------------|-------|---------|-------|
| **ChargeCache** | HW LRU | **1** | **9** | 22 | 4 | SPM tracks LRU on STORE; 2-way, 32 sets |
| **MASA** | cmd bit-test | **1** | **8** | 15 | 4 | bit4→PRE_SA, bit0→SEL_SA, dual-mask mux |
| **MoPAC** | LFSR RNG | **1** | **12** | 16 | 3 | 16-bit Fibonacci LFSR, threshold top 2 bits |
| **PRADA** | LUT transition | **1** | **4** | 7 | 4 | Same LUT approach as trigger |

## Ramulator2 Integration

- [x] Update kernels written (metadata management behind trigger latency)
- [ ] `results/cgra_latencies.yaml` generated
- [ ] Per-technique speedup CSV generated

---

## Change Log

### 2026-04-03 — Initial Setup
- Verified build environment: LLVM 10.0.0, g++-7, cmake 3.16, Python 3.8 all present
- Confirmed Python packages: numpy, pyyaml, tqdm installed
- Morpher submodules initialized (updated from outside container)
- Built all 3 Morpher components successfully
- Fixed `run_morpher.py` for light mode:
  - Added AGI_REMOVED DFG XML rename (light mode produces `_PartPred_AGI_REMOVED_DFG.xml`)
  - Added dummy `mem_alloc.txt` generation in light mode (instrumentation is skipped)
- **Tested array_add toy example** — mapped successfully: II=1, latency=3, 19ms
- Kernels placed in `morpher/Morpher_DFG_Generator/benchmarks/terracotta_triggers/`
- All 4 trigger kernels written and ready in `kernels/`
- All 3 scripts written: `run_morpher_triggers.sh`, `extract_latencies.py`, `run_colation_per_technique.py`
- Configs ready: `hycube_4x4.yaml` (full) and `hycube_4x4_light.yaml` (fast iteration)
- Created `.github/copilot-instructions.md` workspace instructions
- Created this `PROGRESS.md` file

### Next Steps
1. Map remaining 3 trigger kernels (MoPAC, MASA, PRADA) — may need similar unrolling
2. Consider writing update/action kernels beyond triggers
3. Extract per-technique latencies
4. Feed into Ramulator2 for performance evaluation

### 2026-04-03 — ChargeCache Optimization Sweep
- Resolved design model: **one CGRA per bank**, 16 sets × 4 ways, tag-only lookup
- HCRAC metadata stored in CGRA's on-chip SPM (256-512 bytes depending on packing)
- Created 5 kernel versions exploring different tradeoffs:
  - v1 (nested loop) → fails to map
  - v2 (unrolled `&&`) → 40 nodes, II=4, lat=14
  - v3 (per-bank `&&`) → 44 nodes, II=3, lat=17
  - v4 (branchless AND) → 34 nodes, II=3, lat=10
  - v5 (packed valid+tag) → 20 nodes, II=2, lat=12 (4×4) / lat=9 (6×6)
- **Key finding**: II bottleneck is memory port count, not total PEs
  - 4×4: 4 mem PEs → 6 mem ops at II=2
  - 6×6: 6 mem PEs → ResMinII=1 but routing congestion prevents II=1
- Created per-technique kernel directories with README.md docs
- Added 6×6 and 8×8 configs (8×8 has mapper issues)

### 2026-04-03 — ChargeCache v6-v8 experiments (port model)
- v6 (global scalar for row input) → LLVM generates same LOAD, no benefit
- v7 (induction variable as row) → RecMinII=4, worse than v5
- v7b (manual DFG edit: LOAD→OLOAD) → mapper assertion failure (BasePointerName)
- v8 (accumulator to avoid STORE) → RecMinII=6, accumulator adds heavy control flow
- **Conclusion**: v5 packed is the best result. II=1 on 4×4 not achievable due to PE count
  (18 nodes / 16 PEs = ResMinII=2 even with OLOAD trick)
- **Best ChargeCache result: v5 — II=2, lat=12 (4×4) / II=2, lat=9 (6×6)**

### 2026-04-03 — MASA mapping
- v1 (original multi-bank) → not suitable for per-bank CGRA model
- v2 (per-bank with packed state) → segfault: AGI removal breaks loop-carried state register
- v3 (independent iterations) → **II=1, lat=7 on 4×4** — clean 8-node DFG, 3L+1S, RecMinII=0
- Key insight: pre-stage both current and incoming SA as input arrays → no loop-carried deps
- v4 (no valid bit, minimal): 6 nodes, 2L+1S → **II=1, lat=5**
- v4b (DFG edit: sa_cur LOAD→OLOAD, remove STORE): 4 nodes, 1L only → **II=1, lat=3**
- **DFG editing note**: OLOAD needs BasePointerName + matching entry in mem_alloc.txt
  → update_mem_alloc.py populates DATA_LAYOUT in arch JSON → mapper resolves OLOAD address
- **OLOAD correction**: sa_cur changes every iteration → OLOAD (loop-invariant) is wrong model
  → v4b result invalidated. OLOAD only valid for true constants (config regs, thresholds)
- **Best MASA result: v4 — II=1, lat=5 (4×4)**

### 2026-04-03 — ChargeCache scaling decision
- Row address and hit output must remain regular LOAD/STORE (not OLOAD) — they vary per iteration
- II=1 on 4×4 not achievable with current mem port count; revisit later with larger CGRA

### 2026-04-03 — MASA v5 command output
- v5 (ACT check + SEL_SA + PRE→PRE_SA + passthrough mux): 21 nodes → II=2, lat=13
- v5b (lean, no passthrough): 16 nodes → II=2, lat=10 (routing-limited at II=1)
- v5c (bitwise): 16 nodes → II=2, lat=10 (4×4) / **II=1, lat=9 (6×6)**
- CMERGE/SELECT bloat unavoidable for conditional constant materialisation

### 2026-04-03 — MoPAC mapping
- v1 (multi-bank LFSR + threshold) → not suitable for per-bank model
- v2 (per-bank PRE-sensitive): 6 nodes, 1L+1S, pure bitwise → **II=1, lat=6 (4×4)**
- Logic: on PRE, read cu_flag → if set output PREcu, else output PRE
- Metadata update (ACT sets flag) has hidden latency, not modeled

### 2026-04-03 — PRADA mapping
- v2 (lookup table): 7 nodes, 3L+1S, pure LUT approach → **II=1, lat=4 (6×6)**
- Table in SPM: 4 requests × 8 slots = 32 entries (stride 8 for shift addressing)
- States: closed/opened/two-opened/three-opened/not; Requests: RowClone/NOT/AND-OR/NANDNOR
- All 4 techniques now mapped on 6×6

### 2026-04-03 — ChargeCache ACT-gated + II=1 push
- v6 (4-way, ACT-gated): 23 nodes, 7 mem ops → ResMinII=2 → II=2, lat=9 (6×6)
- v7 (2-way, ACT-gated): 15 nodes, 5 mem ops → **II=1, lat=8 (6×6)** ← selected
  - 32 sets × 2 ways = 64 entries (same capacity as 16×4)
  - DFG: 4L+1S + 3 CMP + 2 AND + 2 LS + 3 OR = 15 nodes
- v8 (dual-pack 4-way): 24 nodes, 5 mem ops → ResMinII=1 but routing fails → II=2, lat=11
  - Extraction logic (4× AND + 2× RS) adds 6 nodes; too many for II=1 routing

### 2026-04-03 — Final trigger selection (all 6×6, all II=1)
- **ChargeCache v7**: II=1, lat=8 — 2-way set-assoc, ACT-gated, packed metadata
- **MASA v6b**: II=1, lat=7 — 1-bit override flag, no CMERGE/SELECT
- **MoPAC v2**: II=1, lat=6 — PRE-sensitive cu_flag check
- **PRADA v2**: II=1, lat=4 — LUT-based state×request lookup

### 2026-04-04 — Update kernels (all 6×6, all II=1)
- **ChargeCache**: II=1, lat=9 — 2-way, HW-managed LRU (SPM auto-updates on STORE)
  - Explored v1 (5L+2S, 3 arrays), v2 (packed single word) — final uses 20-bit rows, separate in/out arrays
  - SPM exposes LRU in bit 31 of entry0 (read-only); no LRU STORE needed (3L+1S=4 mem ops)
- **MASA**: II=1, lat=8 — cmd bit-test (bit4→PRE_SA, bit0→SEL_SA), 3-way mux via dual mask+negate
  - Explored XOR-mux (lat=9) and ARS (lat=9); original 2-mask approach optimal
- **MoPAC**: II=1, lat=12 — 16-bit Fibonacci LFSR, threshold top 2 bits zero → p≈1/4
  - Separate lfsr_in/lfsr_out arrays to avoid aliasing RecMinII
- **PRADA**: II=1, lat=4 — Same LUT approach as trigger (state transition table)
- **Key fix**: Morpher aliasing — same-array read+write inflates RecMinII → separate in/out arrays

### 2026-04-04 — Workspace cleanup
- Archived stale ChargeCache update versions (v1, v2_packed) to `kernels/chargecache/archive/`
- Removed all old kernel copies from `morpher/Morpher_DFG_Generator/benchmarks/terracotta_triggers/` (kept only 4 final)
- Cleaned generated artifacts (dot, pdf, xml, txt, log, bin, csv) from all morpher benchmark dirs
- Removed stale `home/` and `Morpher_DFG_Generator/` dirs from mapper benchmarks
- Updated `results/latencies.md` with separate update kernel section
- Updated this file with update kernel results and corrected MASA trigger to v6b (lat=7)
