/**
 * ChargeCache Trigger Kernel v4 — Branchless, per-bank, 16-set, 4-way
 *
 * Same as v3 but avoids short-circuit && to eliminate conditional branches.
 * Uses bitwise AND instead, producing a purely dataflow DFG with no
 * CMERGE/SELECT nodes — smaller DFG, better CGRA fit.
 *
 * Design model:
 *   - One CGRA per bank, HCRAC in SPM (16 sets × 4 ways)
 *   - On ACT: hash row → set index, compare 4 ways, OR results
 */

#define NUM_SETS  16
#define NUM_WAYS  4

int tags[NUM_SETS][NUM_WAYS];
int valid[NUM_SETS][NUM_WAYS];

void chargecache_trigger(int n, int *row_addrs, int *hits) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int set_idx = row & (NUM_SETS - 1);

        /* Branchless 4-way comparison: valid & (tag == row) */
        int h0 = valid[set_idx][0] & (tags[set_idx][0] == row);
        int h1 = valid[set_idx][1] & (tags[set_idx][1] == row);
        int h2 = valid[set_idx][2] & (tags[set_idx][2] == row);
        int h3 = valid[set_idx][3] & (tags[set_idx][3] == row);

        hits[i] = h0 | h1 | h2 | h3;
    }
}
