/**
 * MASA Trigger Kernel v2 — Per-bank, branchless, packed state
 *
 * Models one CGRA per bank. MASA tracks the currently-selected
 * subarray. On each ACT/SEL_SA, compare incoming SA with stored SA
 * to detect subarray switches.
 *
 * Design model:
 *   - One CGRA per bank
 *   - State in SPM: state[1] packed word (bit 31=valid, bits 6:0=SA ID)
 *   - Input: incoming SA IDs from command decoder (sa_in[i])
 *   - Output: switch flags (switches[i])
 *
 * Per-iteration:
 *   1 LOAD  (state[0] — current packed state)
 *   1 LOAD  (sa_in[i] — incoming SA from input array)
 *   1 STORE (state[0] — updated packed state)
 *   1 STORE (switches[i] — output flag)
 *   → 4 mem ops → ResMinII = ceil(4/4) = 1 on 4×4
 *
 * Branchless: need_switch = valid & (cur_sa != new_sa)
 *   valid = state >> 31
 *   cur_sa = state & 0x7F
 *   need_switch = valid & (cur_sa != new_sa)  [all bitwise, no branches]
 *   new_state = (1 << 31) | (new_sa & 0x7F)   [always mark valid]
 */

#define SA_MASK    0x7F
#define VALID_BIT  0x80000000

void masa_trigger(int n, int *sa_in, int *switches, int *state) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int cur_state = state[0];
        int new_sa = sa_in[i] & SA_MASK;

        /* Extract valid and current SA from packed state */
        int valid = (cur_state >> 31) & 1;
        int cur_sa = cur_state & SA_MASK;

        /* Branchless switch detection */
        int different = (cur_sa != new_sa) ? 1 : 0;
        int need_switch = valid & different;

        /* Update state: always valid, new SA */
        state[0] = new_sa | VALID_BIT;

        switches[i] = need_switch;
    }
}
