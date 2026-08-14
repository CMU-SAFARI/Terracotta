/**
 * ChargeCache Update Kernel — Insert on PRE, 2-way, fully packed
 *
 * Packs both ways + LRU into a single 32-bit word per set:
 *   bits[31]    = LRU (0=way0 is LRU, 1=way1 is LRU)
 *   bits[30:16] = way1: (valid << 14) | row_addr[13:0]
 *   bits[15:0]  = way0: (valid << 14) | row_addr[13:0]
 *
 * On PRE: read row_addr → compute set → read packed word →
 *   determine hit/miss/conflict → update packed word → write back.
 *
 * Memory: 2 LOAD (row_addr, packed_set) + 1 STORE (packed_set) = 3 mem ops
 *   → ResMinII = ceil(3/6) = 1 (very comfortable)
 *
 * Latency target: < 24 cycles
 *
 * Row addr uses 14 bits (16K rows), valid = bit 14 of each half-word.
 */

#define NUM_SETS     32
#define HALF_MASK    0x7FFF    /* 15 bits per way */
#define VALID_BIT    0x4000    /* bit 14 within 15-bit half */
#define ROW_MASK     0x3FFF    /* 14-bit row address */
#define LRU_BIT      0x80000000

int packed_sets[NUM_SETS];

void chargecache_update(int n, int *row_addrs, int *packed_sets_arr) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int set_idx = row & (NUM_SETS - 1);
        int packed = packed_sets_arr[set_idx];

        int new_tag = (row & ROW_MASK) | VALID_BIT;  /* 15-bit: valid + row */

        /* Extract way0, way1, lru */
        int w0 = packed & HALF_MASK;
        int w1 = (packed >> 16) & HALF_MASK;
        int lru_is_1 = (packed >> 31) & 1;  /* 1 = way1 is LRU */

        /* Check hits */
        int hit0 = (w0 == new_tag);
        int hit1 = (w1 == new_tag);

        /* Select which way to write:
         *   hit1 → write way1 (select=1)
         *   hit0 → write way0 (select=0)
         *   neither hit → write LRU way (select=lru_is_1)
         */
        int not_hit0 = 1 ^ hit0;
        int select1 = hit1 | (not_hit0 & lru_is_1);

        /* Compute new way values:
         *   If select1=1: way1 = new_tag, way0 unchanged
         *   If select1=0: way0 = new_tag, way1 unchanged
         */
        int m1 = -select1;               /* 0 or 0xFFFFFFFF */
        int m0 = m1 ^ 0xFFFFFFFF;        /* complement */

        int new_w0 = (m0 & new_tag) | (m1 & w0);
        int new_w1 = (m1 & new_tag) | (m0 & w1);

        /* New LRU: points to the way we did NOT write (MRU = written way) */
        int new_lru = (1 ^ select1) << 31;

        /* Repack */
        packed_sets_arr[set_idx] = new_lru | (new_w1 << 16) | new_w0;
    }
}
