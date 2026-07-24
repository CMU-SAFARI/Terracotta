/**
 * MASA Trigger Kernel v4 — Minimal: no valid bit, compare only
 *
 * Simplified model:
 *   - cur_sa is a single SPM register (1 LOAD)
 *   - sa_new comes from input array (1 LOAD)
 *   - Output: switch flag (1 STORE)
 *   - No valid bit (assume initialized at reset)
 *
 * Logic: need_switch = (cur_sa != sa_new)
 * Memory: 2 LOAD + 1 STORE = 3 mem ops → ResMinII = 1
 */

void masa_trigger(int n, int *sa_new, int *cur_sa, int *switches) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int different = (cur_sa[i] != sa_new[i]) ? 1 : 0;
        switches[i] = different;
    }
}
