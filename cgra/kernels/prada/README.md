# PRADA Kernels

## Technique Summary

**PRADA** (Protective Row Activation for Data Assurance) tracks per-bank open-subarray state through a 5-state FSM. The state determines whether incoming PuD (Processing-using-DRAM) commands are valid and what C/A encoding to use.

**Trigger event**: PuD commands (ACT, PRE, PREA, ACTwl, ACTwls, NOT)  
**Core operation**: State machine transition based on command type and current bank state  
**Metadata**: Per-bank state (`bank_state[32]`), 3 bits per bank (5 states)

## Kernel Versions

### v1 — Sequential FSM (`prada_trigger_v1.c`)
- **Status**: Not yet mapped
- **Structure**: Single loop over `n` commands, full state machine with 6 command types × 5 states
- **Concern**: Heavy control flow (if/else chains) — CGRAs handle this poorly
- **DFG estimate**: Large, heavily predicated; likely fails to map or maps with high II
