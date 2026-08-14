/**
 * MASA Trigger Kernel v5c — Bitwise command output
 *
 * Per-bank CGRA trigger. Outputs a command override:
 *   - On ACT with SA mismatch → SEL_SA (0x10)
 *   - On PRE → PRE_SA (0x11)
 *   - Otherwise → 0 (controller passes original cmd)
 *
 * Uses bitwise masking to avoid multiply→CMERGE/SELECT bloat:
 *   mask = -flag (flag=0→mask=0, flag=1→mask=0xFFFFFFFF)
 *   result = mask & constant
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

        /* SA switch: only on ACT, branchless */
        int is_act = -(cmd == CMD_ACT);       /* 0 or 0xFFFFFFFF */
        int different = -(cur != incoming);    /* 0 or 0xFFFFFFFF */
        int sel_sa = is_act & different & CMD_SEL_SA;

        /* PRE → PRE_SA, branchless */
        int is_pre = -(cmd == CMD_PRE);        /* 0 or 0xFFFFFFFF */
        int pre_sa = is_pre & CMD_PRE_SA;

        cmd_out[i] = sel_sa | pre_sa;
    }
}
