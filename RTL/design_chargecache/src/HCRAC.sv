// HCRAC.sv — Hardware Charge Cache (SRAM-backed)
// Set-associative cache with LRU replacement and round-robin invalidation.
// Tags stored in fakeram45_128x116 SRAM (1-cycle registered read).
// Valid and LRU remain as register arrays.
//
// Timing:
//   Lookup (ACT):  2 cycles — cycle 0 issues SRAM read, cycle 1 tag compare.
//   Update (PRE):  1 cycle  — immediate SRAM masked write (no read needed).
//                   Target way selected from valid_r (first invalid) or lru_r (LRU victim).
//   ACT and PRE never collide on the same HCRAC (guaranteed by protocol).
//
`timescale 1ns/1ps

module HCRAC #(
    parameter int NUM_SETS  = 32,
    parameter int NUM_WAYS  = 4,
    parameter int TAG_W     = 15,
    // Derived (do not override)
    parameter int SET_IDX_W = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    parameter int LRU_W     = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1,
    parameter int WAY_IDX_W = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1
) (
    input  logic                    clk_i,
    input  logic                    reset_i,

    // ── Lookup port (ACT path — 2-cycle pipelined) ──────────────────────
    input  logic                    lookup_en_i,       // cycle 0: issue
    input  logic [SET_IDX_W-1:0]    lookup_set_i,
    input  logic [TAG_W-1:0]        lookup_tag_i,
    output logic                    lookup_done_o,      // cycle 1: result valid
    output logic                    lookup_hit_o,       // cycle 1: hit/miss

    // ── Update port (PRE path — 1-cycle, immediate write) ───────────────
    input  logic                    update_en_i,       // immediate SRAM write
    input  logic [SET_IDX_W-1:0]    update_set_i,
    input  logic [TAG_W-1:0]        update_tag_i,

    // ── Periodic invalidation ───────────────────────────────────────────
    input  logic                    inv_en_i
);

    // ════════════════════════════════════════════════════════════════════
    // SRAM geometry
    //   fakeram45_128x116: 128 rows × 116 bits
    //   Row layout: { unused[27:0], way3_tag[21:0], way2_tag[21:0],
    //                                way1_tag[21:0], way0_tag[21:0] }
    //   We pack NUM_WAYS tags of TAG_W bits each into the 116-bit row.
    // ════════════════════════════════════════════════════════════════════
    localparam int SRAM_DEPTH = 128;
    localparam int SRAM_W     = 116;
    localparam int SRAM_AW    = $clog2(SRAM_DEPTH);  // 7
    localparam int WAY_BITS   = NUM_WAYS * TAG_W;     // 88 for 4×22

    // ════════════════════════════════════════════════════════════════════
    // Register arrays  (valid + LRU kept in registers)
    // ════════════════════════════════════════════════════════════════════
    logic               valid_r [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic [LRU_W-1:0]   lru_r   [0:NUM_SETS-1][0:NUM_WAYS-1];

    // Round-robin invalidation pointer
    localparam int CAPACITY  = NUM_SETS * NUM_WAYS;
    localparam int INV_PTR_W = $clog2(CAPACITY);
    logic [INV_PTR_W-1:0] inv_ptr_r;

    // Helper: decompose inv_ptr into set/way
    wire [SET_IDX_W-1:0] inv_set = inv_ptr_r[INV_PTR_W-1 : WAY_IDX_W];
    wire [WAY_IDX_W-1:0] inv_way = inv_ptr_r[WAY_IDX_W-1 : 0];

    // ════════════════════════════════════════════════════════════════════
    // SRAM instance  (single read/write port)
    // ════════════════════════════════════════════════════════════════════
    logic                sram_ce;
    logic                sram_we;
    logic [SRAM_AW-1:0]  sram_addr;
    logic [SRAM_W-1:0]   sram_wd;
    logic [SRAM_W-1:0]   sram_wmask;
    wire  [SRAM_W-1:0]   sram_rd;

    fakeram45_128x116 u_tag_sram (
        .clk       (clk_i),
        .ce_in     (sram_ce),
        .we_in     (sram_we),
        .addr_in   (sram_addr),
        .wd_in     (sram_wd),
        .w_mask_in (sram_wmask),
        .rd_out    (sram_rd)
    );

    // ════════════════════════════════════════════════════════════════════
    // Lookup pipeline registers  (cycle 0 → cycle 1)
    // ════════════════════════════════════════════════════════════════════
    logic                 lk_pending_r;
    logic [TAG_W-1:0]     lk_tag_r;
    logic [SET_IDX_W-1:0] lk_set_r;

    // Extract per-way tags from SRAM read data (cycle 1, combinational)
    logic [TAG_W-1:0] sram_way_tag [0:NUM_WAYS-1];
    genvar gw;
    generate
        for (gw = 0; gw < NUM_WAYS; gw++) begin : gen_way_extract
            assign sram_way_tag[gw] = sram_rd[gw*TAG_W +: TAG_W];
        end
    endgenerate

    // ════════════════════════════════════════════════════════════════════
    // Cycle 1 — Lookup hit logic  (from registered SRAM output)
    // ════════════════════════════════════════════════════════════════════
    logic [NUM_WAYS-1:0] lk_way_hit;
    integer lk;
    always_comb begin
        for (lk = 0; lk < NUM_WAYS; lk++) begin
            lk_way_hit[lk] = lk_pending_r
                            & valid_r[lk_set_r][lk]
                            & (sram_way_tag[lk] == lk_tag_r);
        end
    end

    assign lookup_done_o = lk_pending_r;
    assign lookup_hit_o  = |lk_way_hit;

    // ════════════════════════════════════════════════════════════════════
    // Update — target way selection  (combinational, from registers only)
    //   1. First invalid way in valid_r[update_set_i]
    //   2. If all valid, LRU victim from lru_r[update_set_i]
    // ════════════════════════════════════════════════════════════════════
    logic [NUM_WAYS-1:0]  upd_invalid_vec;
    logic                 upd_found_invalid;
    logic [WAY_IDX_W-1:0] upd_target_way;
    logic [LRU_W-1:0]     upd_min_lru;

    integer ui;
    always_comb begin
        for (ui = 0; ui < NUM_WAYS; ui++)
            upd_invalid_vec[ui] = ~valid_r[update_set_i][ui];

        upd_found_invalid = |upd_invalid_vec;

        // Default: way 0
        upd_target_way = '0;
        upd_min_lru    = {LRU_W{1'b1}};

        if (upd_found_invalid) begin
            // Pick first invalid way (lowest index wins)
            for (ui = NUM_WAYS - 1; ui >= 0; ui--) begin
                if (upd_invalid_vec[ui])
                    upd_target_way = ui[WAY_IDX_W-1:0];
            end
        end else begin
            // All valid: pick LRU victim
            for (ui = 0; ui < NUM_WAYS; ui++) begin
                if (lru_r[update_set_i][ui] <= upd_min_lru) begin
                    upd_min_lru    = lru_r[update_set_i][ui];
                    upd_target_way = ui[WAY_IDX_W-1:0];
                end
            end
        end
    end

    // ════════════════════════════════════════════════════════════════════
    // Build SRAM write data + mask for update  (immediate write)
    //   Only the target way's TAG_W-bit slice is written.
    // ════════════════════════════════════════════════════════════════════
    logic [SRAM_W-1:0] upd_wd;
    logic [SRAM_W-1:0] upd_wmask;

    always_comb begin
        upd_wd    = '0;
        upd_wmask = '0;
        upd_wd   [upd_target_way * TAG_W +: TAG_W] = update_tag_i;
        upd_wmask[upd_target_way * TAG_W +: TAG_W] = {TAG_W{1'b1}};
    end

    // ════════════════════════════════════════════════════════════════════
    // SRAM port control
    //   update_en_i  → write  (immediate, no read)
    //   lookup_en_i  → read   (cycle 0 of lookup)
    //   These never collide (guaranteed by protocol serialization).
    // ════════════════════════════════════════════════════════════════════
    always_comb begin
        if (update_en_i) begin
            // Immediate SRAM write — tag insert
            sram_ce    = 1'b1;
            sram_we    = 1'b1;
            sram_addr  = SRAM_AW'(update_set_i);
            sram_wd    = upd_wd;
            sram_wmask = upd_wmask;
        end else if (lookup_en_i) begin
            // Cycle 0: lookup read
            sram_ce    = 1'b1;
            sram_we    = 1'b0;
            sram_addr  = SRAM_AW'(lookup_set_i);
            sram_wd    = '0;
            sram_wmask = '0;
        end else begin
            sram_ce    = 1'b0;
            sram_we    = 1'b0;
            sram_addr  = '0;
            sram_wd    = '0;
            sram_wmask = '0;
        end
    end

    // ════════════════════════════════════════════════════════════════════
    // Sequential state updates
    // ════════════════════════════════════════════════════════════════════
    integer si, sj;
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            lk_pending_r  <= 1'b0;
            inv_ptr_r     <= '0;
            for (si = 0; si < NUM_SETS; si++) begin
                for (sj = 0; sj < NUM_WAYS; sj++) begin
                    valid_r[si][sj] <= 1'b0;
                    lru_r[si][sj]   <= '0;
                end
            end
        end else begin

            // ── Lookup: cycle 0 → cycle 1 ───────────────────────────────
            if (lookup_en_i) begin
                lk_pending_r <= 1'b1;
                lk_tag_r     <= lookup_tag_i;
                lk_set_r     <= lookup_set_i;
            end else begin
                lk_pending_r <= 1'b0;
            end

            // ── LRU update on lookup hit (cycle 1) ──────────────────────
            if (lk_pending_r && lookup_hit_o) begin
                for (si = 0; si < NUM_WAYS; si++) begin
                    if (lk_way_hit[si]) begin
                        lru_r[lk_set_r][si] <= LRU_W'(NUM_WAYS - 1);  // MRU
                    end else if (valid_r[lk_set_r][si]) begin
                        lru_r[lk_set_r][si] <= (lru_r[lk_set_r][si] == '0)
                                               ? '0
                                               : lru_r[lk_set_r][si] - LRU_W'(1);
                    end
                end
            end

            // ── Insert on update (immediate, same cycle) ────────────────
            if (update_en_i) begin
                valid_r[update_set_i][upd_target_way] <= 1'b1;
                lru_r  [update_set_i][upd_target_way] <= LRU_W'(NUM_WAYS - 1);
            end

            // ── Round-robin invalidation ────────────────────────────────
            if (inv_en_i) begin
                valid_r[inv_set][inv_way] <= 1'b0;
                inv_ptr_r <= (inv_ptr_r == INV_PTR_W'(CAPACITY - 1))
                             ? '0
                             : inv_ptr_r + INV_PTR_W'(1);
            end

        end
    end

endmodule
