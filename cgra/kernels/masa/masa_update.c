/**
 * MASA Update Kernel — SA state management with command test
 *
 * Tests the actual command:
 *   SEL_SA = 0x10 (bit4=1, bit0=0) → write target_sa
 *   PRE_SA = 0x11 (bit4=1, bit0=1) → write 0 (INVALID)
 *   Other  (bit4=0)                → write sa_in (no change)
 *
 * Bit-test: bit4 = (cmd >> 4) & 1, bit0 = cmd & 1
 *   is_sel  = bit4 & ~bit0      — 1 for SEL_SA only
 *   is_keep = ~bit4             — 1 for non-update cmds (bit0 irrelevant)
 *
 * result = (sel_mask & tgt) | (keep_mask & cur)
 *   PRE_SA: both masks = 0 → result = 0 (INVALID) naturally
 *
 * Memory: 3 LOAD (cmd, tgt, sa_in) + 1 STORE (sa_out) = 4 mem ops
 */

void masa_update(int n, int *cmd_in, int *target_sa, int *sa_in, int *sa_out) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int cmd = cmd_in[i];
        int tgt = target_sa[i];
        int cur = sa_in[i];

        int bit4 = (cmd >> 4) & 1;
        int bit0 = cmd & 1;
        int is_sel = bit4 & (bit0 ^ 1);

        int sel_mask = -is_sel;
        int keep_mask = -(bit4 ^ 1);

        sa_out[i] = (sel_mask & tgt) | (keep_mask & cur);
    }
}
