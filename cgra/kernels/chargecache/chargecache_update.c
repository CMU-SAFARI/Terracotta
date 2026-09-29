/**
 * ChargeCache Update Kernel — Insert on PRE, 2-way set-assoc, HW-managed LRU
 *
 * On PRE: insert row_addr into HCRAC.
 *   - Hit: re-store same value (SPM marks way as MRU)
 *   - Empty way: insert there
 *   - Conflict: evict LRU way
 *
 * SPM hardware tracks LRU: on every STORE to a way, that way becomes MRU.
 * SPM exposes LRU bit in bit 31 of entry0 (read-only, HW-managed):
 *   entry0 = (lru << 31) | (valid << 20) | row_addr[19:0]
 *   entry1 = (valid << 20) | row_addr[19:0]
 *   lru=0 → way0 is LRU, lru=1 → way1 is LRU
 *
 * No LRU write needed — SPM updates it on STORE.
 *
 * Flat interleaved layout: entries[set*2+way]
 *
 * Write-way selection:
 *   hit0 → write way0 (refresh)
 *   hit1 → write way1 (refresh)
 *   !v1  → write way1 (empty slot)
 *   else → write LRU way (evict)
 *   select_way1 = hit1 | (!hit0 & (!v1 | lru_is_1))
 *
 * Memory: 3 LOAD (row, e0, e1) + 1 STORE (entry) = 4 mem ops
 *   → ResMinII = ceil(4/6) = 1 on 6×6
 *
 * Periodic invalidation handled by a separate sweep kernel.
 * Latency target: < 24 cycles
 */

#define NUM_SETS   32
#define VALID_BIT  0x00100000   /* bit 20 */
#define ROW_MASK   0x000FFFFF   /* 20 bits */
#define TAG_MASK   0x001FFFFF   /* valid + row = 21 bits */

int entries_in[NUM_SETS * 2];
int entries_out[NUM_SETS * 2];

void chargecache_update(int n, int *row_addrs) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int set_base = (row & (NUM_SETS - 1)) << 1;
        int new_tag = (row & ROW_MASK) | VALID_BIT;

        int e0_raw = entries_in[set_base];
        int e1 = entries_in[set_base + 1];

        /* Strip HW-managed LRU bit from entry0 for comparison */
        int w0 = e0_raw & TAG_MASK;
        int lru_is_1 = (e0_raw >> 31) & 1;

        int hit0 = (w0 == new_tag);
        int hit1 = (e1 == new_tag);
        int v1 = (e1 >> 20) & 1;

        int not_hit0 = hit0 ^ 1;
        int select_way1 = hit1 | (not_hit0 & ((v1 ^ 1) | lru_is_1));

        entries_out[set_base + select_way1] = new_tag;
    }
}
