/**
 * ChargeCache Trigger Kernel v3 — Per-bank, 16-set, 4-way lookup
 *
 * Design model:
 *   - One CGRA per bank
 *   - HCRAC metadata (tags + valid) stored in CGRA's SPM
 *   - 16 sets × 4 ways per bank
 *   - On ACT: build tag from row address, hash to set, compare 4 ways
 *   - Output: hit (1) or miss (0)
 *
 * The loop over n represents processing sequential ACT commands to
 * this bank over time. Morpher extracts the single-iteration DFG,
 * which IS the per-trigger latency.
 *
 * Tag = row_addr (16-bit). Set index = tag[3:0] (low 4 bits).
 * Tag stored in HCRAC = full 16-bit row address.
 *
 * 4-way comparisons are manually unrolled for CGRA spatial parallelism.
 */

#define NUM_SETS  16
#define NUM_WAYS  4

/* Per-bank HCRAC — stored in CGRA SPM (512 bytes total) */
int tags[NUM_SETS][NUM_WAYS];
int valid[NUM_SETS][NUM_WAYS];

void chargecache_trigger(int n, int *row_addrs, int *hits) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int set_idx = row & (NUM_SETS - 1);  /* low 4 bits → set */

        /* 4-way parallel tag comparison — unrolled */
        int h0 = valid[set_idx][0] && (tags[set_idx][0] == row);
        int h1 = valid[set_idx][1] && (tags[set_idx][1] == row);
        int h2 = valid[set_idx][2] && (tags[set_idx][2] == row);
        int h3 = valid[set_idx][3] && (tags[set_idx][3] == row);

        hits[i] = h0 | h1 | h2 | h3;
    }
}
