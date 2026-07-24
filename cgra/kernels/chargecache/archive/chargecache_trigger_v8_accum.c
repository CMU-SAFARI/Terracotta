/**
 * ChargeCache Trigger Kernel v8 — Port-model with accumulator
 *
 * Models the real hardware interface:
 *   - expected value (row|VALID_BIT) arrives via input port, modeled as
 *     loop-invariant parameter -> OLOAD in DFG (any PE, no mem port)
 *   - HCRAC entries in SPM -> 4 LOADs (mem PEs only)
 *   - hit result goes to output port -> modeled as accumulator (no STORE
 *     in loop body); acc is just to keep LLVM from DCE'ing the loads
 *   - i = set index (iterate over sets to keep LOADs loop-variant)
 *
 * DFG memory analysis:
 *   4 LOAD (entries[i*4+0..3]) -> ResMinII = ceil(4/4) = 1
 *   1 OLOAD (expected)         -> any PE, no mem port pressure
 *   acc recurrence (ADD)       -> RecMinII = 1
 *   No STORE in loop body
 *   -> Target: II=1 on 4x4
 *
 * Design model:
 *   - One CGRA per bank
 *   - HCRAC in SPM: entries[16*4] = 256 bytes (packed valid+tag)
 *   - Input: expected value from command decoder (input port -> OLOAD)
 *   - Output: hit/miss to controller (output port -> no STORE needed)
 */

#define NUM_SETS 16
#define NUM_WAYS 4

int chargecache_trigger(int n, int *entries, int expected) {
    int acc = 0;
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int base = i * NUM_WAYS;
        int h0 = (entries[base]     == expected);
        int h1 = (entries[base + 1] == expected);
        int h2 = (entries[base + 2] == expected);
        int h3 = (entries[base + 3] == expected);
        acc += h0 | h1 | h2 | h3;
    }
    return acc;
}
