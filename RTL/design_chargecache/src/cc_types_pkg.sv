// cc_types_pkg.sv — ChargeCache type/parameter definitions  (v2)
// Mirrors Terracotta's terracotta_types_pkg for consistent field widths and clock period.
package cc_types_pkg;

  // ─── Address field widths (match Terracotta terracotta_types_pkg) ─────────────
  localparam int CC_CMD_W   = 6;    // command encoding width
  localparam int CC_RANK_W  = 1;    // rank address bits
  localparam int CC_BG_W    = 3;    // bank-group address bits
  localparam int CC_BA_W    = 2;    // bank address bits
  localparam int CC_ROW_W   = 16;    // row address bits

  // ─── Multi-core geometry ──────────────────────────────────────────────
  localparam int CC_NUM_CORES   = 4;    // one HCRAC per core
  localparam int CC_CORE_ID_W   = $clog2(CC_NUM_CORES);  // 2 bits

  // ─── Flat bank addressing (for bank→core map) ────────────────────────
  localparam int CC_NUM_BANKS   = (1 << CC_BG_W) * (1 << CC_BA_W);  // 32
  localparam int CC_BANK_IDX_W  = CC_BG_W + CC_BA_W;                 // 5

  // ─── HCRAC cache geometry (per core) ──────────────────────────────────
  localparam int CC_NUM_ENTRIES = 512;  // total entries per HCRAC
  localparam int CC_NUM_WAYS    = 4;    // set associativity
  localparam int CC_NUM_SETS    = CC_NUM_ENTRIES / CC_NUM_WAYS;  // 128

  // Derived widths
  localparam int CC_SET_IDX_W = (CC_NUM_SETS > 1) ? $clog2(CC_NUM_SETS) : 1;
  localparam int CC_LRU_W     = (CC_NUM_WAYS > 1) ? $clog2(CC_NUM_WAYS) : 1;
  localparam int CC_TAG_W     = CC_ROW_W + CC_BA_W + CC_BG_W + CC_RANK_W;

  // ─── Reload mask (32-bit, matches Terracotta TC_TS_W) ────────────────
  // ChargeCache reduces tRCD, tRAS, tRC on a hit → bits [2:0].
  localparam int                          CC_RELOAD_MASK_W    = 32;
  localparam logic [CC_RELOAD_MASK_W-1:0] CC_HIT_RELOAD_MASK  = 32'h0000_0007;

  // ─── Periodic invalidation timer (1 ms at 250 MHz) ───────────────────
  localparam int CC_INV_TIMER_CYCLES = 250_000;
  localparam int CC_INV_TIMER_W      = $clog2(CC_INV_TIMER_CYCLES + 1);  // 18 bits

  // ─── Command encodings (match Terracotta trigger IDs) ─────────────────
  localparam logic [CC_CMD_W-1:0] CMD_ACT  = 6'd1;
  localparam logic [CC_CMD_W-1:0] CMD_PRE  = 6'd2;
  localparam logic [CC_CMD_W-1:0] CMD_RD   = 6'd3;
  localparam logic [CC_CMD_W-1:0] CMD_RDA  = 6'd4;
  localparam logic [CC_CMD_W-1:0] CMD_WR   = 6'd5;
  localparam logic [CC_CMD_W-1:0] CMD_WRA  = 6'd8;
  localparam logic [CC_CMD_W-1:0] CMD_PREA = 6'd16;
  localparam logic [CC_CMD_W-1:0] CMD_REF  = 6'd32;

endpackage
