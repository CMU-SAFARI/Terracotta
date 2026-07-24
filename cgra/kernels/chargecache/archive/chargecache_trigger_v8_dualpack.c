/**
 * ChargeCache Trigger Kernel v8 — ACT-gated, 4-way, dual-packed entries
 *
 * Packs 2 ways into a single 32-bit word (row_addr + valid ≤ 16 bits):
 *   bits[31:16] = way1: (valid << 15) | row_addr[14:0]
 *   bits[15:0]  = way0: (valid << 15) | row_addr[14:0]
 *
 * Two 32-bit LOADs fetch all 4 ways:
 *   packed01 = entries_packed[set][0]   (ways 0,1)
 *   packed23 = entries_packed[set][1]   (ways 2,3)
 *
 * Memory ops: 4 LOAD (row, cmd, packed01, packed23) + 1 STORE = 5
 * On 6×6 (6 mem PEs): ResMinII = ceil(5/6) = 1
 * Retains full 4-way associativity with 16 sets (64 entries total).
 */

#define NUM_SETS  16
#define VALID_BIT 0x8000
#define HALF_MASK 0xFFFF
#define CMD_ACT   1

/* Each 32-bit word holds 2 packed ways: [way_hi : way_lo] */
int entries_packed[NUM_SETS][2];

void chargecache_trigger(int n, int *row_addrs, int *cmds, int *hits) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int cmd = cmds[i];
        int set_idx = row & (NUM_SETS - 1);
        int expected = (row & 0x7FFF) | VALID_BIT;

        int packed01 = entries_packed[set_idx][0];
        int packed23 = entries_packed[set_idx][1];

        int w0 = packed01 & HALF_MASK;
        int w1 = (packed01 >> 16) & HALF_MASK;
        int w2 = packed23 & HALF_MASK;
        int w3 = (packed23 >> 16) & HALF_MASK;

        int h0 = (w0 == expected);
        int h1 = (w1 == expected);
        int h2 = (w2 == expected);
        int h3 = (w3 == expected);

        int is_act = (cmd == CMD_ACT);
        hits[i] = is_act & (h0 | h1 | h2 | h3);
    }
}
