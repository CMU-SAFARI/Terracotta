`timescale 1ns/1ps
import terracotta_types_pkg::*;

// TerracottaSingleTech: Single-technique wrapper for synthesis.
// Contains: 1 TriggerUnit + 1 UpdateUnit + 1 ActionUnit + 1 MetadataTableBank.
//
// Synthesize once and multiply results by NUM_TECH (4) for full Terracotta cost.
// The shared TriggerArray config broadcast overhead is negligible (fanout only).
//
// Pipeline:
//   pkt_i → TriggerUnit → fork → UpdateUnit + ActionUnit
//                                    ↕              ↓
//                           MetadataTableBank    wave output
//
// Metadata feedback: SRAM-backed MetadataTable with 1-cycle registered read
//   Cycle N:   Trigger/Update accept, emit tag → MetadataTableBank SRAM read
//   Cycle N+1: SRAM output → tag comparison → hit/data fed directly back

module TerracottaSingleTech #(
    parameter int TECH_ID        = 0,
    parameter int TECH_W         = terracotta_types_pkg::TC_TECH_W,
    parameter int REQ_W          = terracotta_types_pkg::TC_REQ_W,
    parameter int CMD_W          = terracotta_types_pkg::TC_CMD_W,
    parameter int BG_W           = terracotta_types_pkg::TC_BG_W,
    parameter int BA_W           = terracotta_types_pkg::TC_BA_W,
    parameter int SA_W           = terracotta_types_pkg::TC_SA_W,
    parameter int ROW_W          = terracotta_types_pkg::TC_ROW_W,
    parameter int COL_W          = terracotta_types_pkg::TC_COL_W,
    parameter int PRI_W          = terracotta_types_pkg::TC_PRI_W,
    parameter int TS_W           = terracotta_types_pkg::TC_TS_W,
    parameter int METADATA_W     = terracotta_types_pkg::TC_METADATA_W,
    parameter int BANK_W         = terracotta_types_pkg::TC_BANK_W,
    parameter int NUM_BANKS      = terracotta_types_pkg::TC_NUM_BANKS,
    parameter int METATAG_W      = terracotta_types_pkg::TC_META_TAG_W,
    parameter int META_DEPTH     = terracotta_types_pkg::TC_META_DEPTH,
    parameter int T_CFG_W        = terracotta_types_pkg::TC_T_CFG_W,
    parameter int T_CFG_DEPTH    = terracotta_types_pkg::TC_T_CFG_DEPTH,
    parameter int CUSTOM_CMD_W   = terracotta_types_pkg::TC_CUSTOM_CMD_W,
    parameter int U_CFG_W        = terracotta_types_pkg::TC_U_CFG_W,
    parameter int U_CFG_DEPTH    = terracotta_types_pkg::TC_U_CFG_DEPTH,
    parameter int A_CFG_W        = terracotta_types_pkg::TC_A_CFG_W,
    parameter int A_CFG_DEPTH    = terracotta_types_pkg::TC_A_CFG_DEPTH,
    parameter int A_PAYLOAD_W    = terracotta_types_pkg::TC_A_PAYLOAD_W,
    parameter int A_PAYLOAD_DEPTH= terracotta_types_pkg::TC_A_PAYLOAD_DEPTH,
    parameter int PAYLOAD_IDX_W  = terracotta_types_pkg::TC_PAYLOAD_IDX_W,
    parameter int WAVE_W         = terracotta_types_pkg::TC_WAVE_W
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // ======================== Input Packet ========================
    input  logic                   in_valid_i,
    output logic                   in_ready_o,
    input  trigger_in_t            pkt_i,

    // ======================== Metadata Invalidation ========================
    input  logic                   inv_pulse_i,

    // ======================== Trigger Config Write ========================
    input  logic                   t_cfg_wr_en_i,
    input  logic [REQ_W+CMD_W-1:0] t_cfg_wr_key_i,
    input  logic [T_CFG_W-1:0]    t_cfg_wr_value_i,

    // ======================== Update Config Write ========================
    input  logic                   u_cfg_wr_en_i,
    input  logic [CMD_W-1:0]       u_cfg_wr_key_i,
    input  logic [U_CFG_W-1:0]    u_cfg_wr_value_i,

    // ======================== Action Config Write ========================
    input  logic                   a_cfg_wr_en_i,
    input  logic [CMD_W-1:0]       a_cfg_wr_key_i,
    input  logic [A_CFG_W-1:0]    a_cfg_wr_value_i,

    // ======================== Action Payload Write ========================
    input  logic                   a_payload_wr_en_i,
    input  logic [PAYLOAD_IDX_W-1:0] a_payload_wr_key_i,
    input  logic [A_PAYLOAD_W-1:0] a_payload_wr_value_i,

    // ======================== Action Wave Output ========================
    output logic                   wave_out_valid_o,
    input  logic                   wave_out_ready_i,
    output action_wave_t           wave_o,

    // ======================== Timer Reload Mask ========================
    output logic                   timer_reload_mask_valid_o,
    output logic [TS_W-1:0]        timer_reload_mask_o
);

    // ================================================================
    //  TriggerUnit
    // ================================================================
    logic                          trig_out_valid, trig_out_ready;
    trigger_out_t                  trig_out_pkt;
    logic                          trig_meta_tag_valid;
    logic [METATAG_W-1:0]          trig_meta_tag;
    logic [BANK_W-1:0]             trig_bank_id;
    logic                          trig_meta_valid;
    logic [METADATA_W-1:0]         trig_meta_in;

    TriggerBankArray #(
        .NUM_BANKS(NUM_BANKS), .TECH_ID(TECH_ID),
        .REQ_W(REQ_W), .CMD_W(CMD_W), .BG_W(BG_W), .BA_W(BA_W),
        .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W), .PRI_W(PRI_W), .TS_W(TS_W),
        .METADATA_W(METADATA_W), .CFG_W(T_CFG_W), .CFG_DEPTH(T_CFG_DEPTH),
        .CUSTOM_CMD_W(CUSTOM_CMD_W), .TECH_W(TECH_W),
        .BANK_W(BANK_W)
    ) u_trig (
        .clk_i              (clk_i),
        .reset_i            (reset_i),
        .in_valid_i         (in_valid_i),
        .in_ready_o         (in_ready_o),
        .pkt_i              (pkt_i),
        .metadata_valid_i   (trig_meta_valid),
        .metadata_in_i      (trig_meta_in),
        .metadata_tag_valid_o(trig_meta_tag_valid),
        .metadata_tag_o     (trig_meta_tag),
        .bank_id_o          (trig_bank_id),
        .cfg_wr_en_i        (t_cfg_wr_en_i),
        .cfg_wr_key_i       (t_cfg_wr_key_i),
        .cfg_wr_value_i     (t_cfg_wr_value_i),
        // Single-tech mode: no EWMA throttling, always granted
        .ewma_bus_util_i    ('0),
        .match_o            (/* unused */),
        .grant_i            (1'b1),
        .bus_util_thresh_wr_en_i  (1'b0),
        .bus_util_thresh_wr_data_i('0),
        .out_valid_o        (trig_out_valid),
        .out_ready_i        (trig_out_ready),
        .pkt_o              (trig_out_pkt)
    );

    // ================================================================
    //  Trigger → Update/Action fork (skid-free)
    // ================================================================
    logic upd_in_valid, upd_in_ready;
    logic act_in_valid, act_in_ready;

    assign trig_out_ready = upd_in_ready & act_in_ready;
    assign upd_in_valid   = trig_out_valid & act_in_ready;
    assign act_in_valid   = trig_out_valid & upd_in_ready;

    // trigger_out_t → update_in_t
    update_in_t upd_pkt;
    always_comb begin
        upd_pkt.tech_id   = trig_out_pkt.tech_id;
        upd_pkt.cmd_id    = trig_out_pkt.cmd_id;
        upd_pkt.bg_id     = trig_out_pkt.bg_id;
        upd_pkt.ba_id     = trig_out_pkt.ba_id;
        upd_pkt.sa_id     = trig_out_pkt.sa_id;
        upd_pkt.row_id    = trig_out_pkt.row_id;
        upd_pkt.col_id    = trig_out_pkt.col_id;
        upd_pkt.prio      = trig_out_pkt.prio;
        upd_pkt.timestamp = trig_out_pkt.timestamp;
    end

    // trigger_out_t → action_in_t
    action_in_t act_pkt;
    always_comb begin
        act_pkt.tech_id   = trig_out_pkt.tech_id;
        act_pkt.cmd_id    = trig_out_pkt.cmd_id;
        act_pkt.bg_id     = trig_out_pkt.bg_id;
        act_pkt.ba_id     = trig_out_pkt.ba_id;
        act_pkt.sa_id     = trig_out_pkt.sa_id;
        act_pkt.row_id    = trig_out_pkt.row_id;
        act_pkt.col_id    = trig_out_pkt.col_id;
        act_pkt.prio      = trig_out_pkt.prio;
        act_pkt.timestamp = trig_out_pkt.timestamp;
    end

    // ================================================================
    //  UpdateUnit
    // ================================================================
    logic                   upd_meta_tag_valid;
    logic [METATAG_W-1:0]   upd_meta_tag;
    logic [BANK_W-1:0]      upd_rd_bank_id;
    logic                   upd_timer_valid;
    logic [TS_W-1:0]        upd_timer_mask;
    logic                   upd_meta_out_valid;
    logic [METADATA_W-1:0]  upd_meta_out;
    logic [METATAG_W-1:0]   upd_wr_tag;
    logic [BANK_W-1:0]      upd_wr_bank_id;
    logic                   upd_meta_valid;
    logic [METADATA_W-1:0]  upd_meta_in;

    UpdateUnit #(
        .CMD_W(CMD_W), .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W),
        .METADATA_W(METADATA_W), .TS_W(TS_W),
        .CFG_W(U_CFG_W), .CFG_DEPTH(U_CFG_DEPTH),
        .TECH_W(TECH_W), .TECH_ID(TECH_ID), .BANK_W(BANK_W)
    ) u_upd (
        .clk_i                       (clk_i),
        .reset_i                     (reset_i),
        .in_valid_i                  (upd_in_valid),
        .in_ready_o                  (upd_in_ready),
        .pkt_i                       (upd_pkt),
        .metadata_valid_i            (upd_meta_valid),
        .metadata_in_i               (upd_meta_in),
        .metadata_tag_valid_o        (upd_meta_tag_valid),
        .metadata_tag_o              (upd_meta_tag),
        .rd_bank_id_o                (upd_rd_bank_id),
        .timer_reload_mask_valid_o   (upd_timer_valid),
        .timer_reload_mask_o         (upd_timer_mask),
        .metadata_out_valid_o        (upd_meta_out_valid),
        .metadata_out_ready_i        (1'b1),
        .metadata_out_o              (upd_meta_out),
        .wr_tag_o                    (upd_wr_tag),
        .wr_bank_id_o                (upd_wr_bank_id),
        .cfg_wr_en_i                 (u_cfg_wr_en_i),
        .cfg_wr_key_i                (u_cfg_wr_key_i),
        .cfg_wr_value_i              (u_cfg_wr_value_i)
    );

    assign timer_reload_mask_valid_o = upd_timer_valid;
    assign timer_reload_mask_o       = upd_timer_mask;

    // ================================================================
    //  ActionUnit
    // ================================================================
    ActionUnit #(
        .CMD_W(CMD_W), .BG_W(BG_W), .BA_W(BA_W), .SA_W(SA_W),
        .ROW_W(ROW_W), .COL_W(COL_W), .PRI_W(PRI_W), .TS_W(TS_W),
        .CFG_W(A_CFG_W), .CFG_DEPTH(A_CFG_DEPTH),
        .PAYLOAD_W(A_PAYLOAD_W), .PAYLOAD_DEPTH(A_PAYLOAD_DEPTH)
    ) u_act (
        .clk_i              (clk_i),
        .reset_i            (reset_i),
        .in_valid_i         (act_in_valid),
        .in_ready_o         (act_in_ready),
        .pkt_i              (act_pkt),
        .out_valid_o        (wave_out_valid_o),
        .out_ready_i        (wave_out_ready_i),
        .wave_o             (wave_o),
        .cfg_wr_en_i        (a_cfg_wr_en_i),
        .cfg_wr_key_i       (a_cfg_wr_key_i),
        .cfg_wr_value_i     (a_cfg_wr_value_i),
        .payload_wr_en_i    (a_payload_wr_en_i),
        .payload_wr_key_i   (a_payload_wr_key_i),
        .payload_wr_value_i (a_payload_wr_value_i)
    );

    // ================================================================
    //  MetadataTableBank (32 banks, SRAM-backed)
    // ================================================================
    logic                   mbank_rd_a_hit;
    logic [METADATA_W-1:0]  mbank_rd_a_data;
    logic                   mbank_rd_b_hit;
    logic [METADATA_W-1:0]  mbank_rd_b_data;

    MetadataTableBank #(
        .NUM_BANKS(NUM_BANKS), .BANK_W(BANK_W),
        .TAG_W(METATAG_W), .DATA_W(METADATA_W), .DEPTH(META_DEPTH)
    ) u_mbank (
        .clk_i        (clk_i),
        .reset_i      (reset_i),
        // Read port A: trigger lookup
        .rd_a_en_i    (trig_meta_tag_valid),
        .rd_a_bank_i  (trig_bank_id),
        .rd_a_tag_i   (trig_meta_tag),
        .rd_a_hit_o   (mbank_rd_a_hit),
        .rd_a_data_o  (mbank_rd_a_data),
        // Read port B: update lookup
        .rd_b_en_i    (upd_meta_tag_valid),
        .rd_b_bank_i  (upd_rd_bank_id),
        .rd_b_tag_i   (upd_meta_tag),
        .rd_b_hit_o   (mbank_rd_b_hit),
        .rd_b_data_o  (mbank_rd_b_data),
        // Write port: update writeback
        .wr_en_i      (upd_meta_out_valid),
        .wr_bank_i    (upd_wr_bank_id),
        .wr_tag_i     (upd_wr_tag),
        .wr_data_i    (upd_meta_out),
        // Invalidation
        .inv_pulse_i  (inv_pulse_i)
    );

    // ================================================================
    //  Metadata feedback (SRAM provides 1-cycle latency, no extra regs)
    // ================================================================
    // Trigger path: direct connect
    assign trig_meta_valid = mbank_rd_a_hit;
    assign trig_meta_in    = mbank_rd_a_data;

    // Update path: register upd_meta_tag_valid to align with SRAM output
    logic upd_lookup_q;
    always_ff @(posedge clk_i) begin
        if (reset_i)
            upd_lookup_q <= 1'b0;
        else
            upd_lookup_q <= upd_meta_tag_valid;
    end
    assign upd_meta_valid = upd_lookup_q;
    assign upd_meta_in    = mbank_rd_b_hit ? mbank_rd_b_data : '0;

endmodule
