/**
 * PRADA Trigger Kernel — Per-bank state machine dispatch
 *
 * PRADA tracks the open-subarray state per bank with a simple FSM:
 *   CLOSED(0) → OPENED(1) → TWO_OPENED(2) → THREE_OPENED(3)
 *   Any → NOT(4) on NOT command
 *   Any → CLOSED(0) on PRE
 *
 * The trigger determines whether an incoming PuD command is valid
 * given the current bank state and what C/A encoding to use.
 *
 * Note: PRADA's trigger is mostly control-flow (state machine),
 * which is not a natural CGRA workload. We express it as
 * data-parallel state lookups to measure the datapath cost.
 */

#define NUM_BANKS 32

/* State encoding */
#define ST_CLOSED      0
#define ST_OPENED      1
#define ST_TWO_OPENED  2
#define ST_THREE_OPENED 3
#define ST_NOT         4

/* Command encoding */
#define CMD_ACT    0
#define CMD_PRE    1
#define CMD_PREA   2
#define CMD_ACTwl  3
#define CMD_ACTwls 4
#define CMD_NOT    5

/**
 * prada_trigger - Evaluate PRADA bank state transitions
 * @n:         Number of commands to process
 * @cmds:      Array of command types (CMD_*)
 * @bank_ids:  Array of bank indices (0..31)
 * @actions:   Output: new state after command
 */
void prada_trigger(int n, int *cmds, int *bank_ids, int *actions) {
    int bank_state[NUM_BANKS];
    int b;
    for (b = 0; b < NUM_BANKS; b++) {
        bank_state[b] = ST_CLOSED;
    }

    int i;
    for (i = 0; i < n; i++) {
        int bid = bank_ids[i] & (NUM_BANKS - 1);
        int cmd = cmds[i];
        int state = bank_state[bid];
        int new_state = state;

        if (cmd == CMD_ACT) {
            if (state == ST_CLOSED) {
                new_state = ST_OPENED;
            }
        } else if (cmd == CMD_PRE) {
            new_state = ST_CLOSED;
        } else if (cmd == CMD_PREA) {
            /* Reset all banks — handled separately */
            new_state = ST_CLOSED;
        } else if (cmd == CMD_ACTwl || cmd == CMD_ACTwls) {
            if (state == ST_OPENED) {
                new_state = ST_TWO_OPENED;
            } else if (state == ST_TWO_OPENED) {
                new_state = ST_THREE_OPENED;
            }
        } else if (cmd == CMD_NOT) {
            if (state == ST_OPENED || state == ST_THREE_OPENED) {
                new_state = ST_NOT;
            }
        }

        bank_state[bid] = new_state;
        actions[i] = new_state;
    }
}
