// masa_types_pkg.sv — MASA (Multitude of Activated SubArrays) type/parameter definitions
// Mirrors Terracotta's terracotta_types_pkg for consistent field widths and clock period.
// MASA extends the DRAM controller with subarray awareness: SEL_SA / PRE_SA commands.
package masa_types_pkg;

  // ─── Address field widths (match Terracotta terracotta_types_pkg) ─────────────
  localparam int MASA_CMD_W   = 6;    // command encoding width
  localparam int MASA_RANK_W  = 1;    // rank address bits
  localparam int MASA_BG_W    = 3;    // bank-group address bits
  localparam int MASA_BA_W    = 2;    // bank address bits
  localparam int MASA_ROW_W   = 9;    // row-within-subarray address bits (scaled)

  // ─── Subarray geometry ────────────────────────────────────────────────
  // 1 << 7 = 128 subarrays per bank.
  // Original row space (9 bits) is split: upper 7 = SA, lower 2 = row-within-SA.
  localparam int MASA_SA_W           = 7;   // subarray address bits
  localparam int MASA_NUM_SA_PER_BANK = 1 << MASA_SA_W;  // 128

  // ─── Flat bank addressing ────────────────────────────────────────────
  localparam int MASA_NUM_BANKS   = (1 << MASA_BG_W) * (1 << MASA_BA_W);  // 32
  localparam int MASA_BANK_IDX_W  = MASA_BG_W + MASA_BA_W;                 // 5

  // ─── C/A bus encoding ────────────────────────────────────────────────
  // SEL_SA and PRE_SA are sent over two 14-bit C/A cycles.
  // Cycle 0: bits [4:0] = command ID, bits [13:5] = assumed logic (don't-care here)
  // Cycle 1: bits [SA_W-1:0] = subarray ID
  localparam int MASA_CA_BUS_W   = 14;  // C/A bus width per cycle
  localparam int MASA_CA_CMD_W   = 5;   // command-ID field in cycle 0 of CA bus

  // ─── Command encodings ───────────────────────────────────────────────
  localparam logic [MASA_CMD_W-1:0] CMD_ACT    = 6'd1;
  localparam logic [MASA_CMD_W-1:0] CMD_PRE    = 6'd2;
  localparam logic [MASA_CMD_W-1:0] CMD_RD     = 6'd3;
  localparam logic [MASA_CMD_W-1:0] CMD_RDA    = 6'd4;
  localparam logic [MASA_CMD_W-1:0] CMD_WR     = 6'd5;
  localparam logic [MASA_CMD_W-1:0] CMD_WRA    = 6'd8;
  localparam logic [MASA_CMD_W-1:0] CMD_PREA   = 6'd16;
  localparam logic [MASA_CMD_W-1:0] CMD_REF    = 6'd32;
  // MASA-specific commands
  localparam logic [MASA_CMD_W-1:0] CMD_SEL_SA = 6'd9;   // select subarray
  localparam logic [MASA_CMD_W-1:0] CMD_PRE_SA = 6'd10;  // precharge subarray

  // ─── C/A bus command IDs (5-bit, used inside the 14-bit C/A frame) ───
  localparam logic [MASA_CA_CMD_W-1:0] CA_CMD_SEL_SA = 5'd9;
  localparam logic [MASA_CA_CMD_W-1:0] CA_CMD_PRE_SA = 5'd10;

  // ─── Reload mask (32-bit, matches Terracotta TC_TS_W) ────────────────
  localparam int MASA_RELOAD_MASK_W = 32;

endpackage
