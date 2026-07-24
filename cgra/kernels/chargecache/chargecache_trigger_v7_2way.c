/**
 * ChargeCache Trigger Kernel v7 — ACT-gated, 2-way, packed metadata
 *
 * Reduced to 2-way set-associative to lower memory pressure.
 * Sets doubled (32) to maintain same total entries (64).
 *
 * Packed metadata: entry = (valid << 31) | row_addr
 * Memory ops: 4 LOAD (row, cmd, 2 entries) + 1 STORE (hit) = 5
 * On 6×6 (6 mem PEs): ResMinII = ceil(5/6) = 1
 */

#define NUM_SETS  32
#define NUM_WAYS  2
#define VALID_BIT 0x80000000
#define CMD_ACT   1

int entries[NUM_SETS][NUM_WAYS];

void chargecache_trigger(int n, int *row_addrs, int *cmds, int *hits) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int cmd = cmds[i];
        int set_idx = row & (NUM_SETS - 1);
        int expected = row | VALID_BIT;

        int h0 = (entries[set_idx][0] == expected);
        int h1 = (entries[set_idx][1] == expected);

        int is_act = (cmd == CMD_ACT);
        hits[i] = is_act & (h0 | h1);
    }
}
