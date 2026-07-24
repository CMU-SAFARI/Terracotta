/**
 * MASA Trigger Kernel v6b — Boolean override flag, zero CMERGE/SELECT
 *
 * Output is a 1-bit override flag (0 or 1):
 *   - 1 on ACT when SA mismatch → controller issues SEL_SA
 *   - 1 on PRE → controller issues PRE_SA
 *   - 0 otherwise → controller passes original cmd
 *
 * Since ACT and PRE are mutually exclusive commands, the controller
 * disambiguates: override + original_cmd → actual command.
 *
 * Expected DFG: 3 LOAD + 3 CMP + 1 AND + 1 OR + 1 STORE = 9 nodes
 * Critical path: LOAD→CMP→AND→OR→STORE = 5 levels → lat ≈ 6-7
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

        cmd_out[i] = (is_act & different) | is_pre;
    }
}
