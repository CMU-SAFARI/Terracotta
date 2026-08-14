// ChargeCacheUnit.sv — Top-level ChargeCache module  (v4, SRAM-backed)
//
// Architecture:
//   - 4 HCRAC instances (one per core), 512 entries each (128 sets × 4 ways).
//   - Tags stored in fakeram45_128x116 SRAM; valid/LRU in registers.
//   - ACT path (2 cycles):  cycle 0: cmd decode → tag build → HCRAC SRAM read;
//                            cycle 1: SRAM output → tag compare → registered output.
//   - PRE path (2 cycles):  cycle 0: assert open_row_req_o;
//                            cycle 1: consume response, build tag → HCRAC SRAM write → registered output.
//   - Bank-to-core map:  configurable register array  bank_core_map_r[0:31].
//   - Internal 1 ms invalidation timer (250 000 cycles @ 250 MHz).
//   - 32-bit reload_mask_o (matches Terracotta TC_TS_W / UpdateUnit timer_reload_mask).
//
`timescale 1ns/1ps
import cc_types_pkg::*;

module ChargeCacheUnit #(
    parameter int CMD_W          = cc_types_pkg::CC_CMD_W,
    parameter int RANK_W         = cc_types_pkg::CC_RANK_W,
    parameter int BG_W           = cc_types_pkg::CC_BG_W,
    parameter int BA_W           = cc_types_pkg::CC_BA_W,
    parameter int ROW_W          = cc_types_pkg::CC_ROW_W,
    parameter int NUM_CORES      = cc_types_pkg::CC_NUM_CORES,
    parameter int CORE_ID_W      = cc_types_pkg::CC_CORE_ID_W,
    parameter int NUM_BANKS      = cc_types_pkg::CC_NUM_BANKS,
    parameter int BANK_IDX_W     = cc_types_pkg::CC_BANK_IDX_W,
    parameter int NUM_SETS       = cc_types_pkg::CC_NUM_SETS,
    parameter int NUM_WAYS       = cc_types_pkg::CC_NUM_WAYS,
    parameter int RELOAD_MASK_W  = cc_types_pkg::CC_RELOAD_MASK_W,
    // Derived (do not override)
    parameter int TAG_W          = ROW_W + BA_W + BG_W + RANK_W,
    parameter int SET_IDX_W      = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1
) (
    input  logic                     clk_i,
    input  logic                     reset_i,

    // ── Input handshake ─────────────────────────────────────────────────
    input  logic                     in_valid_i,
    output logic                     in_ready_o,

    // ── Command & address ───────────────────────────────────────────────
    input  logic [CMD_W-1:0]         cmd_i,
    input  logic [RANK_W-1:0]        rank_i,
    input  logic [BG_W-1:0]          bg_i,
    input  logic [BA_W-1:0]          ba_i,
    input  logic [ROW_W-1:0]         row_i,

    // ── Core ID (from memory controller) ────────────────────────────────
    input  logic [CORE_ID_W-1:0]     core_id_i,

    // ── Open-row table interface (PRE path) ─────────────────────────────
    output logic                     open_row_req_o,
    output logic [RANK_W-1:0]        open_row_req_rank_o,
    output logic [BG_W-1:0]          open_row_req_bg_o,
    output logic [BA_W-1:0]          open_row_req_ba_o,
    input  logic                     open_row_resp_valid_i,
    input  logic [ROW_W-1:0]         open_row_resp_row_i,

    // ── Output handshake ────────────────────────────────────────────────
    output logic                     out_valid_o,
    input  logic                     out_ready_i,

    // ── Results ─────────────────────────────────────────────────────────
    output logic                     hit_o,
    output logic                     reload_mask_valid_o,
    output logic [RELOAD_MASK_W-1:0] reload_mask_o,
    output logic [TAG_W-1:0]         tag_o,
    output logic [SET_IDX_W-1:0]     set_idx_o
);

    // ════════════════════════════════════════════════════════════════════
    // Bank-to-core map  (dynamic; set on ACT, cleared on PRE)
    // ════════════════════════════════════════════════════════════════════
    logic [CORE_ID_W-1:0] bank_core_map_r     [0:NUM_BANKS-1];
    logic                 bank_core_map_valid_r[0:NUM_BANKS-1];

    wire [BANK_IDX_W-1:0] bank_idx = {bg_i, ba_i};

    // ════════════════════════════════════════════════════════════════════
    // Command decode
    // ════════════════════════════════════════════════════════════════════
    wire is_act = (cmd_i == cc_types_pkg::CMD_ACT);
    wire is_pre = (cmd_i == cc_types_pkg::CMD_PRE)
                | (cmd_i == cc_types_pkg::CMD_RDA)
                | (cmd_i == cc_types_pkg::CMD_WRA);

    wire s0_ready;

    // ════════════════════════════════════════════════════════════════════
    // Bank-to-core map: sequential update
    // ════════════════════════════════════════════════════════════════════
    integer bci;
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            for (bci = 0; bci < NUM_BANKS; bci++) begin
                bank_core_map_r[bci]      <= '0;
                bank_core_map_valid_r[bci] <= 1'b0;
            end
        end else begin
            if (in_valid_i && s0_ready) begin
                if (is_act) begin
                    bank_core_map_r[bank_idx]      <= core_id_i;
                    bank_core_map_valid_r[bank_idx] <= 1'b1;
                end else if (is_pre) begin
                    bank_core_map_valid_r[bank_idx] <= 1'b0;
                end
            end
        end
    end

    // ════════════════════════════════════════════════════════════════════
    // ACT path  (2-cycle: SRAM read → compare)
    // ════════════════════════════════════════════════════════════════════
    wire [TAG_W-1:0]     act_tag     = {row_i, ba_i, bg_i, rank_i};
    wire [SET_IDX_W-1:0] act_set_idx = act_tag[SET_IDX_W-1:0];
    wire [CORE_ID_W-1:0] act_core    = core_id_i;

    // ACT pending state (blocks input during SRAM read cycle)
    logic                 act_pending_r;
    logic [TAG_W-1:0]     act_tag_r;
    logic [SET_IDX_W-1:0] act_set_idx_r;
    logic [CORE_ID_W-1:0] act_core_r;

    wire act_start = in_valid_i & s0_ready & is_act;

    // ════════════════════════════════════════════════════════════════════
    // PRE path  (2-cycle: open_row_req → response + SRAM write + output)
    // ════════════════════════════════════════════════════════════════════
    logic                 pre_pending_r;       // cycle 0→1: waiting for open-row response
    logic                 pre_bank_valid_r;
    logic [CORE_ID_W-1:0] pre_core_r;
    logic [RANK_W-1:0]    pre_rank_r;
    logic [BG_W-1:0]      pre_bg_r;
    logic [BA_W-1:0]      pre_ba_r;

    wire pre_start = in_valid_i & in_ready_o & is_pre;

    // PRE cycle 1: response received, build tag, dispatch SRAM write
    wire pre_resp = pre_pending_r & open_row_resp_valid_i;
    wire [TAG_W-1:0]     pre_tag     = {open_row_resp_row_i, pre_ba_r, pre_bg_r, pre_rank_r};
    wire [SET_IDX_W-1:0] pre_set_idx = pre_tag[SET_IDX_W-1:0];

    // Drive open-row request on cycle 0
    assign open_row_req_o      = pre_start;
    assign open_row_req_rank_o = rank_i;
    assign open_row_req_bg_o   = bg_i;
    assign open_row_req_ba_o   = ba_i;

    // ════════════════════════════════════════════════════════════════════
    // ACT / PRE pipeline state machine
    // ════════════════════════════════════════════════════════════════════
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            act_pending_r      <= 1'b0;
            pre_pending_r      <= 1'b0;
            pre_bank_valid_r   <= 1'b0;
        end else begin
            // ACT: cycle 0 → cycle 1
            if (act_start) begin
                act_pending_r <= 1'b1;
                act_tag_r     <= act_tag;
                act_set_idx_r <= act_set_idx;
                act_core_r    <= act_core;
            end else begin
                act_pending_r <= 1'b0;
            end

            // PRE: cycle 0 (accept) → cycle 1 (response)
            if (pre_start) begin
                pre_pending_r    <= 1'b1;
                pre_bank_valid_r <= bank_core_map_valid_r[bank_idx];
                pre_core_r       <= bank_core_map_r[bank_idx];
                pre_rank_r       <= rank_i;
                pre_bg_r         <= bg_i;
                pre_ba_r         <= ba_i;
            end else if (pre_resp) begin
                pre_pending_r <= 1'b0;
            end
        end
    end

    // ════════════════════════════════════════════════════════════════════
    // Internal 1 ms invalidation timer
    // ════════════════════════════════════════════════════════════════════
    localparam int INV_MAX = cc_types_pkg::CC_INV_TIMER_CYCLES;
    localparam int INV_W   = cc_types_pkg::CC_INV_TIMER_W;

    logic [INV_W-1:0] inv_timer_r;
    logic              inv_pulse;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            inv_timer_r <= '0;
        end else begin
            if (inv_timer_r == INV_W'(INV_MAX - 1)) begin
                inv_timer_r <= '0;
            end else begin
                inv_timer_r <= inv_timer_r + INV_W'(1);
            end
        end
    end

    assign inv_pulse = (inv_timer_r == INV_W'(INV_MAX - 1));

    // ════════════════════════════════════════════════════════════════════
    // HCRAC instances  (one per core)
    // ════════════════════════════════════════════════════════════════════
    logic [NUM_CORES-1:0] hcrac_lookup_done;
    logic [NUM_CORES-1:0] hcrac_lookup_hit;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_CORES; gi++) begin : gen_hcrac

            // Lookup: only the core_id matching this instance (cycle 0)
            wire this_lookup_en = act_start
                                & (act_core == CORE_ID_W'(gi));

            // Update: dispatch on PRE response (cycle 1, immediate write)
            wire this_update_en = pre_resp & pre_bank_valid_r
                                & (pre_core_r == CORE_ID_W'(gi));

            HCRAC #(
                .NUM_SETS  (NUM_SETS),
                .NUM_WAYS  (NUM_WAYS),
                .TAG_W     (TAG_W)
            ) u_hcrac (
                .clk_i           (clk_i),
                .reset_i         (reset_i),
                // Lookup (2-cycle)
                .lookup_en_i     (this_lookup_en),
                .lookup_set_i    (act_set_idx),
                .lookup_tag_i    (act_tag),
                .lookup_done_o   (hcrac_lookup_done[gi]),
                .lookup_hit_o    (hcrac_lookup_hit[gi]),
                // Update (1-cycle, immediate write)
                .update_en_i     (this_update_en),
                .update_set_i    (pre_set_idx),
                .update_tag_i    (pre_tag),
                // Invalidation
                .inv_en_i        (inv_pulse)
            );
        end
    endgenerate

    // Aggregate lookup result from the selected core (cycle 1)
    wire act_hit_c1 = hcrac_lookup_hit[act_core_r];

    // ════════════════════════════════════════════════════════════════════
    // Flow control
    //   Stall while ACT SRAM read pending or PRE open-row pending.
    // ════════════════════════════════════════════════════════════════════
    assign s0_ready   = (~out_valid_o | out_ready_i)
                      & ~act_pending_r
                      & ~pre_pending_r;
    assign in_ready_o = s0_ready;

    // ════════════════════════════════════════════════════════════════════
    // Output pipeline  (registered)
    // ════════════════════════════════════════════════════════════════════
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            out_valid_o        <= 1'b0;
            hit_o              <= 1'b0;
            reload_mask_valid_o <= 1'b0;
            reload_mask_o      <= '0;
            tag_o              <= '0;
            set_idx_o          <= '0;
        end else begin
            // Consume output
            if (out_valid_o && out_ready_i)
                out_valid_o <= 1'b0;

            // ── ACT path output (cycle 1: SRAM result ready) ────────────
            if (act_pending_r) begin
                out_valid_o         <= 1'b1;
                tag_o               <= act_tag_r;
                set_idx_o           <= act_set_idx_r;
                hit_o               <= act_hit_c1;
                reload_mask_valid_o <= act_hit_c1;
                reload_mask_o       <= act_hit_c1
                                       ? cc_types_pkg::CC_HIT_RELOAD_MASK
                                       : {RELOAD_MASK_W{1'b0}};
            end

            // ── PRE path output (cycle 1: response → SRAM write → output) ──
            if (pre_resp) begin
                out_valid_o         <= 1'b1;
                tag_o               <= pre_tag;
                set_idx_o           <= pre_set_idx;
                hit_o               <= 1'b0;
                reload_mask_valid_o <= 1'b0;
                reload_mask_o       <= '0;
            end
        end
    end

endmodule
