/**
 * MASA Trigger Kernel v3 — Per-bank, independent iterations
 *
 * Each iteration compares the incoming SA against the previously-active SA.
 * Both values come from input arrays (the controller stages them).
 * No loop-carried state — each check is independent.
 *
 * Design model:
 *   - One CGRA per bank
 *   - Input arrays in SPM:
 *       sa_new[i]     — incoming subarray ID for command i
 *       sa_cur[i]     — current (previous) SA for this bank at command i
 *       valid_flags[i] — whether bank had a valid SA before command i
 *   - Output array: switches[i] — 1 if SA switch needed
 *
 * Memory ops per iteration:
 *   3 LOAD (sa_new, sa_cur, valid_flags)
 *   1 STORE (switches)
 *   → 4 mem ops → ResMinII = ceil(4/4) = 1 on 4×4
 *
 * Branchless logic:
 *   different = (sa_cur[i] != sa_new[i])
 *   need_switch = valid_flags[i] & different
 */

#define SA_MASK 0x7F

void masa_trigger(int n, int *sa_new, int *sa_cur, int *valid_flags, int *switches) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int cur = sa_cur[i];
        int incoming = sa_new[i];
        int valid = valid_flags[i];

        int different = (cur != incoming) ? 1 : 0;
        int need_switch = valid & different;

        switches[i] = need_switch;
    }
}
