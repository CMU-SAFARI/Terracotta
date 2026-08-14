/**
 * MoPAC Trigger Kernel v2 — Per-bank, PRE-sensitive
 *
 * On PRE arrival: check single metadata entry (cu_flag).
 *   - If cu_flag is set → output PREcu command
 *   - If cu_flag is clear → output PRE command (passthrough)
 *
 * The metadata update (setting cu_flag on ACT) happens autonomously
 * with hidden latency — not modeled here.
 *
 * Design model:
 *   - One CGRA per bank
 *   - Inputs in SPM:
 *       cu_flag[i]  — metadata entry (1 = marked for charge-up, 0 = not)
 *       cmd_in[i]   — incoming command type
 *   - Output: cmd_out[i] — PREcu or PRE
 *
 * Logic (branchless):
 *   is_pre = (cmd_in == CMD_PRE)
 *   cmd_out = is_pre ? (cu_flag ? CMD_PREcu : CMD_PRE) : cmd_in
 *
 * Simplified: CGRA only runs on PRE commands (filtered externally),
 * so cmd_in is always PRE. Just read cu_flag and select output.
 *
 * Memory: 1 LOAD (cu_flag) + 1 STORE (cmd_out) = 2 mem ops
 *   → ResMinII = ceil(2/4) = 1
 */

#define CMD_PRE    0x07
#define CMD_PREcu  0x12

void mopac_trigger(int n, int *cu_flag, int *cmd_out) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int flag = cu_flag[i];

        /* Branchless: if flag set → PREcu, else PRE */
        int mask = -(flag & 1);   /* 0 or 0xFFFFFFFF */
        int diff = CMD_PREcu ^ CMD_PRE;  /* XOR difference */
        cmd_out[i] = CMD_PRE ^ (mask & diff);
    }
}
