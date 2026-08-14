/**
 * PRADA Update Kernel — State transitions via LUT
 *
 * Transitions:
 *   ACT/ACTwl/ACTocwl:
 *     closed(0) → opened(1), opened(1) → two_opened(2),
 *     two_opened(2) → three_opened(3)
 *   PRE:
 *     any → closed(0)
 *   NOT:
 *     opened(1)/two_opened(2)/three_opened(3) → not(4)
 *
 * Use a LUT indexed by (cmd_type << 3) | state → new_state.
 *
 * cmd_type encoding (3 bits):
 *   0 = ACT/ACTwl/ACTocwl (all do same transition)
 *   1 = PRE
 *   2 = NOT
 *
 * Memory: 2 LOAD (cmd_type, state) + 1 LOAD (table) + 1 STORE (state) = 4 mem ops
 *   → ResMinII = ceil(4/6) = 1 on 6×6
 */

/* Transition table: [cmd_type * 8 + state] → new_state
 * States: 0=closed, 1=opened, 2=two_opened, 3=three_opened, 4=not
 */
int prada_update_table[24] = {
    /* ACT-like (cmd_type=0): closed→opened, opened→two, two→three, three→three, not→not */
    1, 2, 3, 3, 4, 0, 0, 0,
    /* PRE (cmd_type=1): any→closed */
    0, 0, 0, 0, 0, 0, 0, 0,
    /* NOT (cmd_type=2): closed→closed, opened→not, two→not, three→not, not→not */
    0, 4, 4, 4, 4, 0, 0, 0
};

void prada_update(int n, int *cmd_type_in, int *state_in, int *state_out) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int ct = cmd_type_in[i];
        int s = state_in[i];
        int idx = (ct << 3) | s;
        state_out[i] = prada_update_table[idx];
    }
}
