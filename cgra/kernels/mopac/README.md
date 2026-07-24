# MoPAC Kernels

## Technique Summary

**MoPAC** (Mostly Open Page with ACT Coalescing) uses a probabilistic mechanism to decide when to promote a PRE to PRE_CU (concurrent unfold). An LFSR generates pseudo-random values; on ACT, if the LFSR exceeds a threshold, a per-bank bit is set. On PRE, if the bit is set, PRE is promoted to PRE_CU.

**Trigger event**: ACT (probabilistic set) and PRE (conditional promote)  
**Core operation**: 16-bit Galois LFSR step + threshold compare + per-bank bit read/write  
**Metadata**: 32-bit bank vector (`bank_cu_vec[32]`) + 16-bit LFSR state

## Kernel Versions

### v1 — Sequential Stream (`mopac_trigger_v1.c`)
- **Status**: Not yet mapped
- **Structure**: Single loop over `n` commands, LFSR advances each iteration
- **Concern**: LFSR has sequential dependency (each step depends on previous), limiting II
- **DFG estimate**: ~15-20 nodes (LFSR shift + XOR + compare + bank lookup + store)
