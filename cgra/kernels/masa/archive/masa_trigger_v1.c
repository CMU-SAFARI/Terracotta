/**
 * MASA Trigger Kernel — Subarray selection tracking
 *
 * On SEL_SA: encode subarray ID, detect subarray switch
 * The trigger fires when the selected subarray changes,
 * requiring a SEL_SA command before the ACT.
 *
 * Core operation: compare incoming SA with currently-selected SA
 * per bank, and determine if a subarray switch is needed.
 */

#define NUM_BANKS 32
#define SA_MASK   0x7F  /* 7-bit subarray ID (128 subarrays) */

/**
 * masa_trigger - Evaluate MASA subarray switch detection
 * @n:         Number of commands to evaluate
 * @bank_ids:  Array of bank indices (0..31)
 * @sa_ids:    Array of target subarray IDs (0..127)
 * @switches:  Output: 1 if SA switch needed, 0 otherwise
 */
void masa_trigger(int n, int *bank_ids, int *sa_ids, int *switches) {
    int cur_sa[NUM_BANKS];
    int sa_valid[NUM_BANKS];
    int b;
    for (b = 0; b < NUM_BANKS; b++) {
        cur_sa[b] = 0;
        sa_valid[b] = 0;
    }

    int i;
    for (i = 0; i < n; i++) {
        int bid = bank_ids[i] & (NUM_BANKS - 1);
        int sa = sa_ids[i] & SA_MASK;

        /* Detect subarray switch */
        int need_switch = 0;
        if (sa_valid[bid]) {
            if (cur_sa[bid] != sa) {
                need_switch = 1;
            }
        }

        /* Update selected subarray */
        cur_sa[bid] = sa;
        sa_valid[bid] = 1;

        switches[i] = need_switch;
    }
}
