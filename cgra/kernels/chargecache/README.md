# ChargeCache Kernels

## Technique Summary

**ChargeCache** caches recently-activated row addresses in an HCRAC (Hot-Row Address Cache). On a subsequent ACT, the row address is looked up. A **hit** means reduced tRCD can be used (the row's cells are still sufficiently charged from the recent activation).

**Trigger event**: ACT command  
**Core operation**: Set-associative tag lookup in HCRAC  
**Metadata**: Per-bank HCRAC stored in CGRA SPM  
**Design model**: One CGRA per bank, 16 sets × 4 ways

## Kernel Versions

### v1 — Nested Loop (`chargecache_trigger_v1_nested.c`)
- **Status**: ❌ Does not map (Morpher extracts innermost loop only)
- **Structure**: Outer loop over `n` commands, inner loop over 4 ways
- **Problem**: Inner `w` loop creates loop-carried dependency (RecMinII=7)
- **DFG**: 22 nodes, mapper fails

### v2 — Unrolled 4-Way (`chargecache_trigger_v2_unrolled.c`)
- **Status**: ✅ Maps on 4×4
- **Structure**: Single loop, 4-way unrolled with `&&` short-circuit
- **DFG**: 40 nodes (many CMERGE/SELECT from branch-based `&&`)
- **Results (4×4)**: II=4, latency=14

### v3 — Per-Bank, 16 Sets (`chargecache_trigger_v3_perbank.c`)
- **Status**: ✅ Maps on 4×4 and 6×6
- **Structure**: Per-bank model (16 sets), `&&` short-circuit
- **DFG**: 44 nodes
- **Results (4×4)**: II=3, latency=17
- **Results (6×6)**: II=2, latency=13

### v4 — Branchless (`chargecache_trigger_v4_branchless.c`)
- **Status**: ✅ Maps on 4×4 and 6×6
- **Structure**: Bitwise AND instead of `&&` — no conditional branches
- **DFG**: 34 nodes (9 LOAD, 8 LS, 7 OR, 5 AND, 4 CMP, 1 STORE)
- **Results (4×4)**: II=3, latency=10
- **Results (6×6)**: II=2, latency=12

### v5 — Packed Metadata (`chargecache_trigger_v5_packed.c`) ← **Best**
- **Status**: ✅ Maps on 4×4 and 6×6
- **Structure**: Valid+tag packed into one word → halves memory loads
- **DFG**: 20 nodes (5 LOAD, 5 OR, 4 LS, 4 CMP, 1 AND, 1 STORE)
- **Results (4×4)**: II=2, latency=12
- **Results (6×6)**: II=2, latency=9 (ResMinII=1 but routing prevents II=1)

## Summary Table

| Version | DFG Nodes | 4×4 II | 4×4 Lat | 6×6 II | 6×6 Lat | Key Change |
|---------|-----------|--------|---------|--------|---------|------------|
| v1 nested | 22 | ❌ | ❌ | — | — | Inner loop fails |
| v2 unrolled | 40 | 4 | 14 | — | — | Unrolled but `&&` branches |
| v3 per-bank | 44 | 3 | 17 | 2 | 13 | 16 sets, per-bank model |
| v4 branchless | 34 | 3 | 10 | 2 | 12 | Bitwise AND, no branches |
| v5 packed | 20 | 2 | 12 | 2 | 9 | Valid+tag in one word |

## II Bottleneck Analysis

The limiting factor for II is **memory port count**:
- 4×4 grid: 4 memory-capable PEs (left column)
- 6×6 grid: 6 memory-capable PEs
- v5 has 5 LOAD + 1 STORE = 6 memory ops → ResMinII = ceil(6/4) = 2 on 4×4
- On 6×6: ResMinII=1 but routing congestion prevents II=1

To achieve II=1: need ≥6 memory PEs + sufficient routing, or reduce memory ops further.

## Design Notes

- HCRAC metadata stored in CGRA SPM (only 256 bytes for packed v5)
- The loop iterates over sequential ACTs to this bank (n=variable for Morpher, but single-trigger latency is the per-iteration DFG depth)
- For Ramulator2: **effective latency** is the pipeline depth (latency column)
