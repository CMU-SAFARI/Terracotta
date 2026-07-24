/**
 * PRADA Trigger Kernel v2 — Lookup table, per-bank
 *
 * Reads current state and request type, outputs the command via
 * a pre-populated lookup table in SPM.
 *
 * States (3 bits):
 *   0 = closed
 *   1 = opened
 *   2 = two-opened
 *   3 = three-opened
 *   4 = not
 *
 * Requests (2 bits):
 *   0 = RowClone
 *   1 = NOT
 *   2 = AND/OR
 *   3 = NANDNOR
 *
 * Output commands:
 *   0x01 = ACT
 *   0x02 = ACTwl
 *   0x03 = PRE
 *   0x04 = NOT
 *   0x05 = ACTocwl
 *   0x06 = ACTwls
 *
 * Table layout (request * 8 + state):
 *   RowClone:  [ACT, ACTwl, PRE,  0,    0   ]
 *   NOT:       [ACT, NOT,   0,    0,    PRE ]
 *   AND/OR:    [ACTocwl, ACTwl, ACTwls, PRE, 0]
 *   NANDNOR:   [ACTocwl, ACTwl, ACTwls, NOT, PRE]
 *
 * Memory: 2 LOAD (state, req) + 1 LOAD (table) + 1 STORE = 4 mem ops
 *   → ResMinII = ceil(4/6) = 1 on 6×6
 */

/* Command encodings */
#define CMD_ACT     0x01
#define CMD_ACTwl   0x02
#define CMD_PRE     0x03
#define CMD_NOT     0x04
#define CMD_ACTocwl 0x05
#define CMD_ACTwls  0x06

/*
 * Lookup table: 4 requests × 8 slots (stride 8 for shift).
 * Indexed by (request << 3) | state.
 */
int prada_table[32] = {
    /* RowClone (req=0): closed→ACT, opened→ACTwl, two-opened→PRE */
    CMD_ACT, CMD_ACTwl, CMD_PRE, 0, 0, 0, 0, 0,
    /* NOT (req=1): closed→ACT, opened→NOT, not→PRE */
    CMD_ACT, CMD_NOT, 0, 0, CMD_PRE, 0, 0, 0,
    /* AND/OR (req=2): closed→ACTocwl, opened→ACTwl, two-opened→ACTwls, three-opened→PRE */
    CMD_ACTocwl, CMD_ACTwl, CMD_ACTwls, CMD_PRE, 0, 0, 0, 0,
    /* NANDNOR (req=3): closed→ACTocwl, opened→ACTwl, two-opened→ACTwls, three-opened→NOT, not→PRE */
    CMD_ACTocwl, CMD_ACTwl, CMD_ACTwls, CMD_NOT, CMD_PRE, 0, 0, 0
};

void prada_trigger(int n, int *state_in, int *req_in, int *cmd_out) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int state = state_in[i];
        int req = req_in[i];
        int idx = (req << 3) | state;
        cmd_out[i] = prada_table[idx];
    }
}
