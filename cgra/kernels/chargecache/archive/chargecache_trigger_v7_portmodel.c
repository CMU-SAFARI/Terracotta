/**
 * ChargeCache Trigger Kernel v7 — True port model
 *
 * Models the real hardware interface accurately:
 *   - Row address = loop induction variable (simulates input port from
 *     command decoder; NOT loaded from SPM)
 *   - Only HCRAC entries[] are in SPM (the actual metadata)
 *   - Hit result stored to hits[] (still SPM; will be removed via DFG
 *     edit in v7b to model output port)
 *
 * Expected DFG memory ops:
 *   4 LOAD (entries[set_idx][0..3])  — real SPM accesses
 *   1 STORE (hits[row])              — modeled; output port in real HW
 *   → 5 mem ops → ResMinII = ceil(5/4) = 2 on 4×4
 *
 * After DFG edit (v7b, remove STORE):
 *   4 LOAD only → ResMinII = ceil(4/4) = 1 on 4×4
 *
 * Design model:
 *   - One CGRA per bank
 *   - HCRAC in SPM: entries[16][4] = 256 bytes (packed valid+tag)
 *   - Input: row address from command decoder (modeled as induction var)
 *   - Output: hit/miss to controller (modeled as STORE, removable)
 */

#define NUM_SETS  16
#define NUM_WAYS  4
#define VALID_BIT 0x80000000

/* HCRAC metadata in SPM: bit 31 = valid, bits 30:0 = row tag */
int entries[NUM_SETS][NUM_WAYS];

void chargecache_trigger(int n, int *hits) {
    int row;
    for (row = 0; row < n; row++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int set_idx = row & (NUM_SETS - 1);
        int expected = row | VALID_BIT;

        /* 4 SPM lookups — the only real memory accesses */
        int h0 = (entries[set_idx][0] == expected);
        int h1 = (entries[set_idx][1] == expected);
        int h2 = (entries[set_idx][2] == expected);
        int h3 = (entries[set_idx][3] == expected);

        hits[row] = h0 | h1 | h2 | h3;
    }
}
