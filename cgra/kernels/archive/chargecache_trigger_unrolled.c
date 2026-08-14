/**
 * ChargeCache Trigger Kernel — 4-way tag lookup (manually unrolled)
 *
 * The inner 4-way comparison is unrolled so Morpher sees a single-loop
 * DFG with all 4 comparisons as parallel operations — matching how
 * this would actually execute on a CGRA with spatial parallelism.
 *
 * On ACT: build tag from {row, ba, bg, rank}, hash to set index,
 * compare against 4 stored tags in that set.
 * Output: hit (1 if any way matches, 0 otherwise)
 */

#define NUM_SETS  128
#define NUM_WAYS  4
#define TAG_BITS  22
#define TAG_MASK  ((1 << TAG_BITS) - 1)

/* HCRAC tag storage: tags[set][way] */
int tags[NUM_SETS][NUM_WAYS];
int valid[NUM_SETS][NUM_WAYS];

void chargecache_trigger(int n, int *rows, int *banks, int *hits) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        /* Build composite tag: {row[15:0], ba[1:0], bg[2:0], rank[0]} */
        int tag = ((rows[i] & 0xFFFF) << 6) | (banks[i] & 0x3F);
        tag = tag & TAG_MASK;

        /* Compute set index from low bits of tag */
        int set_idx = tag & (NUM_SETS - 1);  /* tag[6:0] */

        /* 4-way parallel tag comparison — explicitly unrolled */
        int h0 = valid[set_idx][0] && (tags[set_idx][0] == tag);
        int h1 = valid[set_idx][1] && (tags[set_idx][1] == tag);
        int h2 = valid[set_idx][2] && (tags[set_idx][2] == tag);
        int h3 = valid[set_idx][3] && (tags[set_idx][3] == tag);

        hits[i] = h0 | h1 | h2 | h3;
    }
}
