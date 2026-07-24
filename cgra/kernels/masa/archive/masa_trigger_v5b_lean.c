/**
 * MASA Trigger Kernel v5b — Lean command output
 *
 * Per-bank CGRA trigger. Outputs a command override ID:
 *   - On ACT with SA mismatch → SEL_SA
 *   - On PRE → PRE_SA
 *   - Otherwise → 0 (no override; controller passes original cmd)
 *
 * The controller handles the mux: if cmd_out != 0, inject cmd_out;
 * otherwise forward the original command. This keeps the CGRA lean.
 *
 * Inputs in SPM:
 *   sa_new[i], sa_cur[i], cmd_in[i]
 * Output: cmd_out[i] (0 = no override, nonzero = inject this cmd)
 *
 * Memory: 3 LOAD + 1 STORE = 4 mem ops → ResMinII = ceil(4/4) = 1
 */

#define CMD_ACT     0x04
#define CMD_PRE     0x07
#define CMD_SEL_SA  0x10
#define CMD_PRE_SA  0x11

void masa_trigger(int n, int *sa_new, int *sa_cur, int *cmd_in, int *cmd_out) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int cur = sa_cur[i];
        int incoming = sa_new[i];
        int cmd = cmd_in[i];

        /* SA switch: only on ACT */
        int is_act = (cmd == CMD_ACT) ? 1 : 0;
        int different = (cur != incoming) ? 1 : 0;
        int sel_sa = (is_act & different) * CMD_SEL_SA;

        /* PRE → PRE_SA */
        int is_pre = (cmd == CMD_PRE) ? 1 : 0;
        int pre_sa = is_pre * CMD_PRE_SA;

        cmd_out[i] = sel_sa | pre_sa;
    }
}
