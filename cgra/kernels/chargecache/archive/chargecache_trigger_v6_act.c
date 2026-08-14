/**
 * ChargeCache Trigger Kernel v6 — ACT-gated, 4-way, packed metadata
 *
 * Only fires on ACT command. On ACT, checks if the row address
 * is in the HCRAC (Hot-Row Charge Cache).
 *
 * Packed metadata: entry = (valid << 31) | row_addr
 * Memory ops: 6 LOAD (row, cmd, 4 entries) + 1 STORE (hit) = 7
 * On 6×6 (6 mem PEs): ResMinII = ceil(7/6) = 2
 */

#define NUM_SETS  16
#define NUM_WAYS  4
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
        int h2 = (entries[set_idx][2] == expected);
        int h3 = (entries[set_idx][3] == expected);

        int is_act = (cmd == CMD_ACT);
        hits[i] = is_act & (h0 | h1 | h2 | h3);
    }
}
