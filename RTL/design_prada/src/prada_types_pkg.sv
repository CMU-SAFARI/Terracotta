// prada_types_pkg.sv — PRADA (Processing-in-DRAM Accelerator) type/parameter definitions
// Mirrors Terracotta's terracotta_types_pkg and retains ChargeCache address parameters.
// PRADA extends the DRAM controller with 4 new commands:
//   ACTocwl, ACTwls, ACTwl, NOT
// Each new command occupies 2 C/A cycles; cycle-0 carries a 5-bit command ID.
package prada_types_pkg;

  // ─── Address field widths (match ChargeCache / Terracotta) ────────────
  localparam int PRADA_CMD_W   = 6;    // internal command encoding width
  localparam int PRADA_RANK_W  = 1;    // rank address bits
  localparam int PRADA_BG_W    = 3;    // bank-group address bits
  localparam int PRADA_BA_W    = 2;    // bank address bits
  localparam int PRADA_ROW_W   = 16;   // row address bits (same as ChargeCache)

  // ─── Flat bank addressing ────────────────────────────────────────────
  localparam int PRADA_NUM_BANKS   = (1 << PRADA_BG_W) * (1 << PRADA_BA_W);  // 32
  localparam int PRADA_BANK_IDX_W  = PRADA_BG_W + PRADA_BA_W;                 // 5

  // ─── C/A bus encoding ────────────────────────────────────────────────
  // New PRADA commands are sent over two 14-bit C/A cycles.
  // Cycle 0: bits [4:0] = 5-bit command ID (rest is don't-care / existing HW).
  // Cycle 1: entirely existing hardware — no additional modelling needed.
  localparam int PRADA_CA_BUS_W   = 14;  // C/A bus width per cycle
  localparam int PRADA_CA_CMD_W   = 5;   // command-ID field in cycle 0 of CA bus

  // ─── Standard command encodings ──────────────────────────────────────
  localparam logic [PRADA_CMD_W-1:0] CMD_ACT   = 6'd1;
  localparam logic [PRADA_CMD_W-1:0] CMD_PRE   = 6'd2;
  localparam logic [PRADA_CMD_W-1:0] CMD_RD    = 6'd3;
  localparam logic [PRADA_CMD_W-1:0] CMD_RDA   = 6'd4;
  localparam logic [PRADA_CMD_W-1:0] CMD_WR    = 6'd5;
  localparam logic [PRADA_CMD_W-1:0] CMD_WRA   = 6'd8;
  localparam logic [PRADA_CMD_W-1:0] CMD_PREA  = 6'd16;
  localparam logic [PRADA_CMD_W-1:0] CMD_REF   = 6'd32;

  // ─── PRADA-specific command encodings ────────────────────────────────
  localparam logic [PRADA_CMD_W-1:0] CMD_ACTocwl = 6'd9;   // activate + open copy wordline
  localparam logic [PRADA_CMD_W-1:0] CMD_ACTwls  = 6'd10;  // activate wordline (short)
  localparam logic [PRADA_CMD_W-1:0] CMD_ACTwl   = 6'd11;  // activate wordline
  localparam logic [PRADA_CMD_W-1:0] CMD_NOT     = 6'd12;  // bitwise NOT operation

  // ─── 5-bit C/A command IDs (used inside the 14-bit C/A frame cycle 0) ─
  localparam logic [PRADA_CA_CMD_W-1:0] CA_CMD_ACTocwl = 5'd9;
  localparam logic [PRADA_CA_CMD_W-1:0] CA_CMD_ACTwls  = 5'd10;
  localparam logic [PRADA_CA_CMD_W-1:0] CA_CMD_ACTwl   = 5'd11;
  localparam logic [PRADA_CA_CMD_W-1:0] CA_CMD_NOT     = 5'd12;

  // ─── Per-bank state encoding ─────────────────────────────────────────
  // PRADA operations require multi-step state tracking per bank.
  localparam int PRADA_BANK_STATE_W = 3;
  typedef enum logic [PRADA_BANK_STATE_W-1:0] {
    BS_CLOSED       = 3'd0,
    BS_OPENED       = 3'd1,
    BS_TWO_OPENED   = 3'd2,
    BS_THREE_OPENED = 3'd3,
    BS_NOT          = 3'd4
  } prada_bank_state_e;

  // ─── Reload mask (32-bit, matches Terracotta TC_TS_W) ────────────────
  localparam int PRADA_RELOAD_MASK_W = 32;

endpackage
