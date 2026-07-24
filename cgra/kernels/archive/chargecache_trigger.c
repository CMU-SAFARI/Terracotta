/**
 * ChargeCache Trigger Kernel — 4-way set-associative tag lookup
 *
 * On ACT: build tag from {row, ba, bg, rank}, hash to set index,
 * compare against 4 stored tags in that set.
 * Output: hit (1 if any way matches, 0 otherwise)
 *
 * This is the critical-path trigger evaluation that determines
 * whether an ACT can use reduced tRCD timing (ChargeCache hit).
 */

#define NUM_SETS  128
#define NUM_WAYS  4
#define TAG_BITS  22
#define TAG_MASK  ((1 << TAG_BITS) - 1)

/* HCRAC tag storage: tags[set][way] */
int tags[NUM_SETS][NUM_WAYS];
int valid[NUM_SETS][NUM_WAYS];

/**
 * chargecache_trigger - Evaluate ChargeCache hit on ACT
 * @row:   Row address (16-bit)
 * @ba:    Bank address (2-bit)
 * @bg:    Bank group (3-bit)
 * @rank:  Rank (1-bit)
 * @n:     Number of ACT commands to evaluate
 * @rows:  Array of row addresses
 * @banks: Array of {ba, bg, rank} packed addresses
 * @hits:  Output array of hit results
 */
void chargecache_trigger(int n, int *rows, int *banks, int *hits) {
    int i;
    for (i = 0; i < n; i++) {
        /* Build composite tag: {row[15:0], ba[1:0], bg[2:0], rank[0]} */
        int tag = ((rows[i] & 0xFFFF) << 6) | (banks[i] & 0x3F);
        tag = tag & TAG_MASK;

        /* Compute set index from low bits of tag */
        int set_idx = tag & (NUM_SETS - 1);  /* tag[6:0] */

        /* 4-way parallel tag comparison */
        int hit = 0;
        int w;
        for (w = 0; w < NUM_WAYS; w++) {
            if (valid[set_idx][w] && (tags[set_idx][w] == tag)) {
                hit = 1;
            }
        }

        hits[i] = hit;
    }
}
