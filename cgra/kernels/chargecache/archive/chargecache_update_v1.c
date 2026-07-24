/**
 * ChargeCache Update Kernel — Insert on PRE, 2-way set-assoc, LRU eviction
 *
 * On PRE: insert row_addr into HCRAC.
 *   - If hit (already cached): update LRU, no write needed to entries
 *   - If one way empty: insert into empty way, update LRU
 *   - If conflict (both valid, neither matches): evict LRU way, update LRU
 *
 * Entry format (16-bit): (valid << 15) | row_addr[14:0]
 * LRU per set: 1 bit (0 = way0 is LRU, 1 = way1 is LRU)
 *
 * Packed layout: entries[set][2] in SPM, lru[set] in SPM
 *
 * Memory: 3 LOAD (row_addr, entry0, entry1) + 2 STORE (entry_lru_way, lru) = 5 mem ops
 *   → ResMinII = ceil(5/6) = 1 on 6×6
 *
 * We write to the LRU way unconditionally (if hit, we rewrite same value).
 * The "other" way's LRU bit is set to mark IT as LRU next time.
 *
 * Separate invalidation sweep runs independently (not modeled here).
 *
 * Latency target: < 24 cycles
 */

#define NUM_SETS   32
#define VALID_BIT  0x8000

int entries0[NUM_SETS];  /* way 0 per set */
int entries1[NUM_SETS];  /* way 1 per set */

void chargecache_update(int n, int *row_addrs, int *lru) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int row = row_addrs[i];
        int set_idx = row & (NUM_SETS - 1);
        int new_entry = (row & 0x7FFF) | VALID_BIT;

        int e0 = entries0[set_idx];
        int e1 = entries1[set_idx];

        /* Check hits */
        int hit0 = (e0 == new_entry);
        int hit1 = (e1 == new_entry);

        /* Check valid bits */
        int v0 = (e0 >> 15) & 1;
        int v1 = (e1 >> 15) & 1;

        /*
         * Write target selection (which way to overwrite):
         *   - hit0 → write way0 (refresh), lru points to way1
         *   - hit1 → write way1 (refresh), lru points to way0
         *   - !v0  → write way0 (empty slot), lru points to way1
         *   - !v1  → write way1 (empty slot), lru points to way0
         *   - conflict → write LRU way, lru flips
         *
         * Simplification: always write to one way. Pick way1 if:
         *   hit1 OR (!hit0 AND (v0 AND !lru_is_way1))
         *   ... this gets complex. 
         *
         * Better: unconditionally write to LRU way.
         *   If hit on non-LRU way → harmless (overwrites LRU with new_entry,
         *   but hit means the entry is already there, so cache still correct
         *   since the other way has it).
         *   Actually no: if hit on way0 and LRU=way1, we'd overwrite way1
         *   with the same value that's in way0, duplicating it.
         *
         * Simplest correct approach: 
         *   write_way1 = hit1 | (!hit0 & (v0 | lru_bit))
         *   Meaning: write to way1 if hit1, or if no hit0 and (way0 valid or lru=way1)
         *   Otherwise write to way0.
         *
         * Even simpler: use lru_bit as select, but override on hit.
         *   select = hit1 ? 1 : hit0 ? 0 : lru_bit
         *   But conditionals → CMERGE/SELECT.
         *
         * Branchless: 
         *   select_way1 = hit1 | (~hit0 & lru_bit)
         *   (if neither hit: use LRU; if hit0: force way0; if hit1: force way1)
         *   Wait, ~hit0 when hit0=0 is 0xFFFFFFFF. Need: !hit0 = (hit0 == 0) or (1 - hit0)
         *   Since hit0 is 0 or 1: not_hit0 = 1 ^ hit0
         */
        int lru_bit = lru[set_idx] & 1;
        int not_hit0 = 1 ^ hit0;
        int select_way1 = hit1 | (not_hit0 & lru_bit);

        /* Branchless write: write new_entry to selected way */
        /* We need to write to entries0 OR entries1 based on select_way1.
         * On CGRA with fixed STORE addresses, we can't dynamically choose
         * which array to STORE to. Instead, write BOTH ways:
         *   entries0[set] = select_way1 ? e0 : new_entry  (write way0 if !select_way1)
         *   entries1[set] = select_way1 ? new_entry : e1   (write way1 if select_way1)
         *
         * Branchless:
         *   mask1 = -select_way1 (0 or 0xFFFFFFFF)
         *   mask0 = ~mask1
         *   entries0[set] = (mask0 & new_entry) | (mask1 & e0)
         *   entries1[set] = (mask1 & new_entry) | (mask0 & e1)
         */
        int mask1 = -select_way1;           /* 0 or 0xFFFFFFFF */
        int mask0 = mask1 ^ 0xFFFFFFFF;     /* complement */

        entries0[set_idx] = (mask0 & new_entry) | (mask1 & e0);
        entries1[set_idx] = (mask1 & new_entry) | (mask0 & e1);

        /* Update LRU: point to the OTHER way (the one we just wrote is MRU) */
        lru[set_idx] = 1 ^ select_way1;
    }
}
