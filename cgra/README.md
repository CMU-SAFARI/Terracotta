# CGRA Trigger & Update Latency Evaluation

Model memory-controller trigger and metadata-update logic for 4 DRAM techniques
on a HyCUBE 6×6 CGRA using the [Morpher](https://github.com/ecolab-nus/morpher)
framework. Provides per-technique CGRA latencies for Ramulator2 evaluation.

## Results Summary

All 8 kernels (4 triggers + 4 updates) map at **II = 1** on a **6×6 HyCUBE CGRA**.

### Trigger Latencies

| Technique   | Latency (cycles) | Kernel |
|-------------|:-:|--------|
| ChargeCache | 8  | 2-way set-assoc tag lookup, ACT-gated |
| MASA        | 7  | 1-bit override flag, no CMERGE/SELECT |
| MoPAC       | 6  | PRE-sensitive cu_flag, branchless mux |
| PRADA       | 4  | LUT: `(request<<3)\|state` → command |

### Update Latencies

| Technique   | Latency (cycles) | Kernel |
|-------------|:-:|--------|
| ChargeCache | 9  | 2-way insert, SPM hardware-managed LRU |
| MASA        | 8  | cmd bit-test, dual-mask 3-way mux |
| MoPAC       | 12 | 16-bit Fibonacci LFSR, p≈1/4 threshold |
| PRADA       | 4  | LUT state transition table |

Full details in [`latencies.md`](latencies.md).

## Directory Structure

```
cgra/
├── README.md
├── PROGRESS.md                  # Build log & recovery plan
├── kernels/
│   ├── chargecache/
│   │   ├── chargecache_trigger_v7_2way.c
│   │   ├── chargecache_update.c
│   │   └── archive/             # Superseded versions
│   ├── masa/
│   │   ├── masa_trigger_v6b_override.c
│   │   ├── masa_update.c
│   │   └── archive/
│   ├── mopac/
│   │   ├── mopac_trigger_v2_perbank.c
│   │   ├── mopac_update.c
│   │   └── archive/
│   └── prada/
│       ├── prada_trigger_v2_lut.c
│       ├── prada_update.c
│       └── archive/
├── configs/
│   ├── hycube_6x6_light.yaml    # Standard mapping config
│   ├── hycube_4x4_light.yaml
│   └── hycube_4x4.yaml
├── morpher/                     # Morpher framework (3 git submodules)
├── scripts/
│   └── map_all.sh               # Map all 8 kernels onto CGRA
└── latencies.md                 # Full results with design decisions
```

## Reproducing Results

### 1. Build Morpher

```bash
cd morpher
git submodule update --init --remote
bash build_all.sh
```

Requires: LLVM/Clang 10.0.0, g++-7, cmake ≥ 3.16, Python 3.8+.

### 2. Map All Kernels

```bash
bash scripts/map_all.sh
```

This maps all 8 kernels (4 triggers + 4 updates) onto the 6×6 HyCUBE CGRA using
Morpher's light mode (DFG generation + mapping, no cycle-accurate simulation).
Each kernel takes a few seconds.

### 3. Verify Results

Mapper output prints `Map Success with II = <ii>  (lat = <lat>)` for each kernel.
Compare against the tables above.

## CGRA Architecture

| Parameter | Value |
|-----------|-------|
| Architecture | HyCUBE |
| Grid Size | 6×6 (36 PEs) |
| FU PEs | 30 (non-memory, 1-cycle) |
| FU_MEM PEs | 6 (left column, 2-cycle, LOAD/STORE capable) |
| Registers | 4 per PE |
| Datapath | 32-bit |
| Mapping Mode | Light (PartPredLight DFG) |

## Design Decisions

1. **One CGRA per bank** — all kernels operate on per-bank metadata in on-chip SPM.
2. **6×6 grid** — minimum size achieving II=1 for all techniques. 4×4 has only 4
   FU_MEM PEs, insufficient for ChargeCache (5 mem ops).
3. **Separate in/out arrays** — Morpher infers loop-carried RecMinII from same-pointer
   read+write; separate arrays eliminate this.
4. **SPM hardware LRU** — ChargeCache update assumes SPM tracks LRU on STORE;
   CGRA only reads LRU bit, never writes it.
5. **LUT over control flow** — PRADA uses table lookup to avoid state-machine
   branching, which CGRAs handle poorly.
6. **Boolean outputs** — MASA trigger outputs a 1-bit override flag instead of
   command constants, avoiding CMERGE/SELECT node bloat.
