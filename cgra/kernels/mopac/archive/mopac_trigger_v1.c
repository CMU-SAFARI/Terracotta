/**
 * MoPAC-C Trigger Kernel — Probabilistic ACT tagging + PRE promotion
 *
 * On ACT: advance LFSR, compare against threshold, set bank bit
 * On PRE: check bank bit, decide whether to promote to PRE_CU
 *
 * This kernel evaluates the MoPAC trigger for a sequence of commands.
 * The LFSR is a 16-bit Galois LFSR with polynomial
 *   x^16 + x^15 + x^13 + x^4 + 1
 */

#define NUM_BANKS 32
#define LFSR_POLY 0xB400  /* taps at bits 15, 13, 4 (Galois form) */

/**
 * mopac_trigger - Evaluate MoPAC probabilistic trigger
 * @n:         Number of commands to process
 * @cmds:      Array of command types (0=ACT, 1=PRE)
 * @bank_ids:  Array of bank indices (0..31)
 * @threshold: Probabilistic threshold (16-bit)
 * @results:   Output: 1 if PRE promoted to PRE_CU, 0 otherwise
 */
void mopac_trigger(int n, int *cmds, int *bank_ids, int threshold, int *results) {
    int bank_cu_vec[NUM_BANKS];
    int b;
    for (b = 0; b < NUM_BANKS; b++) {
        bank_cu_vec[b] = 0;
    }

    int lfsr = 0xACE1;  /* seed */
    int i;

    for (i = 0; i < n; i++) {
        /* Advance LFSR every cycle */
        int feedback = lfsr & 1;
        lfsr = lfsr >> 1;
        if (feedback) {
            lfsr = lfsr ^ LFSR_POLY;
        }

        int bid = bank_ids[i] & (NUM_BANKS - 1);
        int cmd = cmds[i];

        if (cmd == 0) {
            /* ACT: probabilistic set */
            if ((lfsr & 0xFFFF) >= (threshold & 0xFFFF)) {
                bank_cu_vec[bid] = 1;
            }
            results[i] = 0;  /* ACT never promotes */
        } else {
            /* PRE: check and conditionally promote */
            results[i] = bank_cu_vec[bid];
            bank_cu_vec[bid] = 0;
        }
    }
}
