/**
 * MASA Trigger Kernel v6 — Bit-field command output, no CMERGE/SELECT
 *
 * Eliminates conditional constant materialization (CMERGE/SELECT)
 * by constructing the output command from individual bit positions:
 *   SEL_SA  = 0x10 = bit4
 *   PRE_SA  = 0x11 = bit4 | bit0
 *   PASS    = 0x00
 *
 * bit4 = (is_act & different) | is_pre
 * bit0 = is_pre
 * cmd_out = (bit4 << 4) | bit0
 *
 * Expected ~11 nodes, 4 mem ops, no CMERGE/SELECT.
 * Critical path: LOAD→CMP→AND→OR→LS→OR→STORE = 7 levels → lat ≈ 8
 */

#define CMD_ACT  0x04
#define CMD_PRE  0x07

void masa_trigger(int n, int *sa_new, int *sa_cur, int *cmd_in, int *cmd_out) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int cur = sa_cur[i];
        int incoming = sa_new[i];
        int cmd = cmd_in[i];

        int is_act = (cmd == CMD_ACT);
        int different = (cur != incoming);
        int is_pre = (cmd == CMD_PRE);

        int bit4 = (is_act & different) | is_pre;
        int bit0 = is_pre;

        cmd_out[i] = (bit4 << 4) | bit0;
    }
}
