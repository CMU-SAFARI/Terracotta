// mopac_types_pkg.sv — MoPAC (Monitoring with Probabilistic ACT Counting) parameters
// Retains ChargeCache address-field widths. Adds MoPAC-specific parameters.
package mopac_types_pkg;

  // ─── Address field widths (match ChargeCache / Terracotta) ────────────
  localparam int MOPAC_CMD_W   = 6;    // internal command encoding width
  localparam int MOPAC_RANK_W  = 1;    // rank address bits
  localparam int MOPAC_BG_W    = 3;    // bank-group address bits
  localparam int MOPAC_BA_W    = 2;    // bank address bits
  localparam int MOPAC_ROW_W   = 16;   // row address bits (same as ChargeCache)

  // ─── Flat bank addressing ────────────────────────────────────────────
  localparam int MOPAC_NUM_BANKS   = (1 << MOPAC_BG_W) * (1 << MOPAC_BA_W);  // 32
  localparam int MOPAC_BANK_IDX_W  = MOPAC_BG_W + MOPAC_BA_W;                 // 5

  // ─── RNG / threshold ─────────────────────────────────────────────────
  // LFSR-based PRNG width — 16-bit gives sufficient randomness for thresholding.
  localparam int MOPAC_RNG_W    = 16;
  // Threshold register width matches RNG width.
  localparam int MOPAC_THRESH_W = MOPAC_RNG_W;  // 16

  // ─── C/A bus encoding for PRE_CU ─────────────────────────────────────
  // PRE_CU takes 2 C/A cycles.
  // Cycle 0: bits [4:0] = 5-bit command ID for PRE_CU.
  // Cycle 1: bit [0]  = CU signal (1 = counter-update). Rest is existing HW.
  localparam int MOPAC_CA_BUS_W   = 14;  // C/A bus width per cycle
  localparam int MOPAC_CA_CMD_W   = 5;   // command-ID field in cycle 0

  // ─── Standard command encodings ──────────────────────────────────────
  localparam logic [MOPAC_CMD_W-1:0] CMD_ACT   = 6'd1;
  localparam logic [MOPAC_CMD_W-1:0] CMD_PRE   = 6'd2;
  localparam logic [MOPAC_CMD_W-1:0] CMD_RD    = 6'd3;
  localparam logic [MOPAC_CMD_W-1:0] CMD_RDA   = 6'd4;
  localparam logic [MOPAC_CMD_W-1:0] CMD_WR    = 6'd5;
  localparam logic [MOPAC_CMD_W-1:0] CMD_WRA   = 6'd8;
  localparam logic [MOPAC_CMD_W-1:0] CMD_PREA  = 6'd16;
  localparam logic [MOPAC_CMD_W-1:0] CMD_REF   = 6'd32;

  // ─── MoPAC-specific command encoding ─────────────────────────────────
  localparam logic [MOPAC_CMD_W-1:0] CMD_PRE_CU = 6'd13;  // precharge with counter-update

  // ─── 5-bit C/A command ID for PRE_CU (in cycle 0 of CA bus) ──────────
  localparam logic [MOPAC_CA_CMD_W-1:0] CA_CMD_PRE_CU = 5'd13;

  // ─── Reload mask (32-bit, matches Terracotta TC_TS_W) ────────────────
  localparam int MOPAC_RELOAD_MASK_W = 32;

endpackage
