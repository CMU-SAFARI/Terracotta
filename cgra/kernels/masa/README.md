# MASA Kernels

## Technique Summary

**MASA** (Multiple Activation by Subarray Access) tracks the currently-selected subarray per bank. When an incoming ACT targets a different subarray, a subarray switch is required (SEL_SA must precede ACT), adding latency.

**Trigger event**: SEL_SA / ACT  
**Core operation**: Compare incoming subarray ID against currently-selected SA per bank  
**Metadata**: Per-bank current SA (`cur_sa[32]`) + valid bits (`sa_valid[32]`)

## Kernel Versions

### v1 — Sequential Stream (`masa_trigger_v1.c`)
- **Status**: Not yet mapped
- **Structure**: Single loop over `n` commands with per-bank state tracking
- **Concern**: Loop-carried dependency on `cur_sa[bid]` and `sa_valid[bid]` (state update)
- **DFG estimate**: ~10-15 nodes (mask + compare + conditional update + store)
