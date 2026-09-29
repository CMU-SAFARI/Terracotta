/**
 * MASA Trigger Kernel v5 — Command output (SEL_SA / PRE_SA)
 *
 * Per-bank CGRA trigger that outputs a 6-bit command ID:
 *   - On ACT: if incoming SA != current SA → output SEL_SA
 *   - On PRE: convert to PRE_SA
 *   - Otherwise: buffer/passthrough (output original cmd)
 *
 * SEL_SA and PRE_SA are mutually exclusive per iteration.
 *
 * Design model:
 *   - One CGRA per bank
 *   - Inputs in SPM:
 *       sa_new[i]  — incoming subarray ID
 *       sa_cur[i]  — current (previous) SA for this bank
 *       cmd_in[i]  — incoming command type (6-bit ID)
 *   - Output: cmd_out[i] — 6-bit command ID (SEL_SA, PRE_SA, or passthrough)
 *
 * Memory: 3 LOAD + 1 STORE = 4 mem ops → ResMinII = ceil(4/4) = 1
 */

#define CMD_ACT     0x04   /* ACT command ID (example 6-bit encoding) */
#define CMD_PRE     0x07   /* PRE command ID */
#define CMD_SEL_SA  0x10   /* SEL_SA command ID */
#define CMD_PRE_SA  0x11   /* PRE_SA command ID */

void masa_trigger(int n, int *sa_new, int *sa_cur, int *cmd_in, int *cmd_out) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int cur = sa_cur[i];
        int incoming = sa_new[i];
        int cmd = cmd_in[i];

        /* Branchless: SA switch check only for ACT */
        int is_act = (cmd == CMD_ACT) ? 1 : 0;
        int different = (cur != incoming) ? 1 : 0;
        int need_sel = is_act & different;
        int sel_sa = need_sel * CMD_SEL_SA;

        /* Branchless: PRE → PRE_SA conversion */
        int is_pre = (cmd == CMD_PRE) ? 1 : 0;
        int pre_sa = is_pre * CMD_PRE_SA;

        /* Combine: at most one is nonzero; otherwise passthrough */
        int override = sel_sa | pre_sa;
        int has_override = (override != 0) ? 1 : 0;

        /* If override, use it; otherwise pass original cmd through */
        cmd_out[i] = has_override * override + (1 - has_override) * cmd;
    }
}
