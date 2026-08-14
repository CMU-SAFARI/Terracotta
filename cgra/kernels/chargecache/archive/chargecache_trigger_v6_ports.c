/**
 * ChargeCache Trigger Kernel v6 — Input/output via ports, not SPM
 *
 * Models the real hardware interface:
 *   - Row address arrives as an external input (not SPM-loaded)
 *   - Hit result goes to output (not SPM-stored)
 *   - Only HCRAC entries[] are in SPM (the actual metadata)
 *
 * We model input/output as global scalars rather than arrays.
 * The DFG generator should treat these as OLOAD/OSTORE (register/port
 * operands) rather than SPM LOAD/STORE, freeing up memory ports
 * for the 4 cache-entry lookups.
 *
 * Design model:
 *   - One CGRA per bank
 *   - HCRAC in SPM: entries[16][4] = 256 bytes (packed valid+tag)
 *   - Input: row address from command decoder (external port)
 *   - Output: hit/miss to controller (external port)
 */

#define NUM_SETS  16
#define NUM_WAYS  4
#define VALID_BIT 0x80000000

/* HCRAC metadata in SPM */
int entries[NUM_SETS][NUM_WAYS];

/* External interface registers (not SPM) */
int input_row;    /* Written by command decoder each cycle */
int output_hit;   /* Read by controller */

void chargecache_trigger(int n) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = input_row;
        int set_idx = row & (NUM_SETS - 1);
        int expected = row | VALID_BIT;

        /* 4 SPM lookups — the only real memory accesses */
        int h0 = (entries[set_idx][0] == expected);
        int h1 = (entries[set_idx][1] == expected);
        int h2 = (entries[set_idx][2] == expected);
        int h3 = (entries[set_idx][3] == expected);

        output_hit = h0 | h1 | h2 | h3;
    }
}
