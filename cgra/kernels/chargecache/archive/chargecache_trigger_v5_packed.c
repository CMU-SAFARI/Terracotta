/**
 * ChargeCache Trigger Kernel v5 — Packed metadata, branchless, per-bank
 *
 * Packs valid bit + tag into a single 32-bit word to halve memory loads:
 *   entry[set][way] = (valid << 31) | (row_addr & 0x7FFFFFFF)
 *   For 16-bit row addresses: entry = (1 << 31) | row_addr
 *   Invalid entry: entry = 0
 *
 * To check: extract valid (bit 31), extract tag (bits 30:0), compare.
 * This reduces LOADs from 9 to 5 (1 row_addr + 4 entries).
 *
 * Design model:
 *   - One CGRA per bank
 *   - HCRAC in SPM: entries[16][4] = 256 bytes
 *   - On ACT: hash row → set, compare 4 packed entries
 */

#define NUM_SETS  16
#define NUM_WAYS  4
#define VALID_BIT 0x80000000
#define TAG_MASK  0x7FFFFFFF

/* Packed HCRAC: bit 31 = valid, bits 30:0 = row address tag */
int entries[NUM_SETS][NUM_WAYS];

void chargecache_trigger(int n, int *row_addrs, int *hits) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int set_idx = row & (NUM_SETS - 1);
        /* Build expected entry: valid + tag */
        int expected = row | VALID_BIT;

        /* 4-way comparison: just compare packed word directly */
        int h0 = (entries[set_idx][0] == expected);
        int h1 = (entries[set_idx][1] == expected);
        int h2 = (entries[set_idx][2] == expected);
        int h3 = (entries[set_idx][3] == expected);

        hits[i] = h0 | h1 | h2 | h3;
    }
}
