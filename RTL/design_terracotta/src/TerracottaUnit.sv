`timescale 1ns/1ps
import terracotta_types_pkg::*;

// TerracottaUnit: Top-level module integrating Triggers, Updates, Actions,
// and per-technique per-bank MetadataTableBanks.
//
// Pipeline flow (per-technique):
//   Input pkt → TriggerArray → fork → UpdateUnit + ActionUnit
//                                       ↕              ↓
//                              MetadataTableBank     wave output
//
// Metadata feedback timing (SRAM-backed, no external registers):
//   Cycle N  : TriggerUnit/UpdateUnit accepts, outputs tag → MetadataTableBank SRAM read request
//   Cycle N+1: SRAM registered output → tag comparison → hit+data fed directly as metadata_valid_i / metadata_in_i

module TerracottaUnit #(
    parameter int NUM_TECH       = (1 << terracotta_types_pkg::TC_TECH_W),
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
    parameter int WAVE_W         = terracotta_types_pkg::TC_WAVE_W,
    parameter int EWMA_W         = terracotta_types_pkg::TC_EWMA_W,
    parameter int EWMA_ALPHA_W   = terracotta_types_pkg::TC_EWMA_ALPHA_W,
    parameter int EWMA_WINDOW_W  = terracotta_types_pkg::TC_EWMA_WINDOW_W,
    parameter int PRIO_W         = terracotta_types_pkg::TC_TECH_PRIO_W
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

    // ======================== EWMA Config Write ========================
    input  logic                        ewma_alpha_wr_en_i,
    input  logic [EWMA_ALPHA_W-1:0]     ewma_alpha_wr_data_i,
    input  logic                        ewma_window_wr_en_i,
    input  logic [EWMA_WINDOW_W-1:0]    ewma_window_wr_data_i,

    // ======================== Per-tech Bus-Util Threshold Write ========================
    input  logic                        bus_util_thresh_wr_en_i,
    input  logic [TECH_W-1:0]           bus_util_thresh_wr_tech_i,
    input  logic [EWMA_W-1:0]           bus_util_thresh_wr_data_i,

    // ======================== Per-tech Priority Write ========================
    input  logic                        tech_prio_wr_en_i,
    input  logic [TECH_W-1:0]           tech_prio_wr_tech_i,
    input  logic [PRIO_W-1:0]           tech_prio_wr_data_i,

    // ======================== Action Wave Outputs (per tech) ========================
    output logic [NUM_TECH-1:0]    wave_out_valid_o,
    input  logic [NUM_TECH-1:0]    wave_out_ready_i,
    output action_wave_t           wave_o [NUM_TECH],

    // ======================== Timer Reload Mask (per tech) ========================
    output logic [NUM_TECH-1:0]    timer_reload_mask_valid_o,
    output logic [TS_W-1:0]        timer_reload_mask_o [NUM_TECH]
);

    // ================================================================
    //  Internal wires: TriggerArray ↔ per-tech logic
    // ================================================================

    // TriggerArray outputs
    logic [NUM_TECH-1:0]   trig_out_valid;
    logic [NUM_TECH-1:0]   trig_out_ready;
    trigger_out_t          trig_out_pkt    [NUM_TECH];

    // Trigger metadata tag outputs (cycle 0, per-tech)
    logic [NUM_TECH-1:0]   trig_meta_tag_valid;
    logic [METATAG_W-1:0]  trig_meta_tag   [NUM_TECH];
    logic [BANK_W-1:0]     trig_bank_id    [NUM_TECH];

    // Trigger metadata feedback inputs (cycle 1, per-tech)
    logic [NUM_TECH-1:0]   trig_meta_valid;
    logic [METADATA_W-1:0] trig_meta_in    [NUM_TECH];

    // Trigger-fired indicator from priority arbiter
    logic                  trigger_fired;

    // ================================================================
    //  EWMA Bus-Utilization Counter
    // ================================================================
    logic [EWMA_ALPHA_W-1:0]  ewma_alpha_r;
    logic [EWMA_WINDOW_W-1:0] ewma_window_r;
    logic [EWMA_W-1:0]        ewma_bus_util_r;
    logic [EWMA_WINDOW_W-1:0] window_counter_r;
    logic [EWMA_W-1:0]        busy_cycles_r;

    // Alpha & window programming
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            ewma_alpha_r  <= '0;           // shift=0 → alpha=1 (no smoothing)
            ewma_window_r <= EWMA_WINDOW_W'(1024); // default window
        end else begin
            if (ewma_alpha_wr_en_i)
                ewma_alpha_r <= ewma_alpha_wr_data_i;
            if (ewma_window_wr_en_i)
                ewma_window_r <= ewma_window_wr_data_i;
        end
    end

    // EWMA combinational intermediate signals
    logic                        ewma_window_hit;
    logic signed [EWMA_W:0]     ewma_diff;
    logic signed [EWMA_W:0]     ewma_delta;
    logic signed [EWMA_W+1:0]   ewma_new_val;

    assign ewma_window_hit = (window_counter_r >= ewma_window_r) && (ewma_window_r != '0);
    assign ewma_diff    = {1'b0, busy_cycles_r} - {1'b0, ewma_bus_util_r};
    assign ewma_delta   = ewma_diff >>> ewma_alpha_r;
    assign ewma_new_val = {1'b0, ewma_bus_util_r} + ewma_delta;

    // EWMA update (every cycle)
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            ewma_bus_util_r  <= '0;
            window_counter_r <= '0;
            busy_cycles_r    <= '0;
        end else begin
            if (ewma_window_hit) begin
                // Window boundary: update EWMA with saturation
                if (ewma_new_val < 0)
                    ewma_bus_util_r <= '0;
                else if (ewma_new_val > {2'b0, {EWMA_W{1'b1}}})
                    ewma_bus_util_r <= {EWMA_W{1'b1}};
                else
                    ewma_bus_util_r <= ewma_new_val[EWMA_W-1:0];

                // Reset window
                window_counter_r <= EWMA_WINDOW_W'(1);
                busy_cycles_r    <= trigger_fired ? EWMA_W'(1) : '0;
            end else begin
                window_counter_r <= window_counter_r + EWMA_WINDOW_W'(1);
                if (trigger_fired && busy_cycles_r < {EWMA_W{1'b1}})
                    busy_cycles_r <= busy_cycles_r + EWMA_W'(1);
            end
        end
    end

    // ================================================================
    //  TriggerArray (multi-tech with priority arbitration)
    // ================================================================
    TriggerArray #(
        .NUM_TECH(NUM_TECH), .NUM_BANKS(NUM_BANKS),
        .REQ_W(REQ_W), .CMD_W(CMD_W),
        .BG_W(BG_W), .BA_W(BA_W), .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W),
        .PRI_W(PRI_W), .TS_W(TS_W), .METADATA_W(METADATA_W),
        .CFG_W(T_CFG_W), .CFG_DEPTH(T_CFG_DEPTH),
        .CUSTOM_CMD_W(CUSTOM_CMD_W), .TECH_W(TECH_W), .BANK_W(BANK_W),
        .EWMA_W(EWMA_W), .PRIO_W(PRIO_W)
    ) u_trigger_array (
        .clk_i          (clk_i),
        .reset_i        (reset_i),
        .in_valid_i     (in_valid_i),
        .in_ready_o     (in_ready_o),
        .pkt_i          (pkt_i),
        // Per-tech metadata feedback
        .metadata_valid_i    (trig_meta_valid),
        .metadata_in_i       (trig_meta_in),
        // Config
        .cfg_wr_en_i    (t_cfg_wr_en_i),
        .cfg_wr_key_i   (t_cfg_wr_key_i),
        .cfg_wr_value_i (t_cfg_wr_value_i),
        // EWMA bus-util
        .ewma_bus_util_i(ewma_bus_util_r),
        // Per-tech threshold programming
        .bus_util_thresh_wr_en_i  (bus_util_thresh_wr_en_i),
        .bus_util_thresh_wr_tech_i(bus_util_thresh_wr_tech_i),
        .bus_util_thresh_wr_data_i(bus_util_thresh_wr_data_i),
        // Per-tech priority programming
        .tech_prio_wr_en_i  (tech_prio_wr_en_i),
        .tech_prio_wr_tech_i(tech_prio_wr_tech_i),
        .tech_prio_wr_data_i(tech_prio_wr_data_i),
        // Outputs
        .out_valid_o         (trig_out_valid),
        .out_ready_i         (trig_out_ready),
        .pkt_o               (trig_out_pkt),
        .metadata_tag_valid_o(trig_meta_tag_valid),
        .metadata_tag_o      (trig_meta_tag),
        .bank_id_o           (trig_bank_id),
        .trigger_fired_o     (trigger_fired)
    );

    // ================================================================
    //  Per-tech: MetadataTableBank + Fork + UpdateUnit + ActionUnit
    // ================================================================
    genvar t;
    generate
        for (t = 0; t < NUM_TECH; t++) begin : g_tech

            // --------------------------------------------------------
            //  Trigger → Update/Action fork (skid-free)
            // --------------------------------------------------------
            logic upd_in_valid, upd_in_ready;
            logic act_in_valid, act_in_ready;

            assign trig_out_ready[t] = upd_in_ready & act_in_ready;
            assign upd_in_valid      = trig_out_valid[t] & act_in_ready;
            assign act_in_valid      = trig_out_valid[t] & upd_in_ready;

            // Convert trigger_out_t → update_in_t (drop cmd_feedback)
            update_in_t upd_pkt;
            always_comb begin
                upd_pkt.tech_id   = trig_out_pkt[t].tech_id;
                upd_pkt.cmd_id    = trig_out_pkt[t].cmd_id;
                upd_pkt.bg_id     = trig_out_pkt[t].bg_id;
                upd_pkt.ba_id     = trig_out_pkt[t].ba_id;
                upd_pkt.sa_id     = trig_out_pkt[t].sa_id;
                upd_pkt.row_id    = trig_out_pkt[t].row_id;
                upd_pkt.col_id    = trig_out_pkt[t].col_id;
                upd_pkt.prio      = trig_out_pkt[t].prio;
                upd_pkt.timestamp = trig_out_pkt[t].timestamp;
            end

            // Convert trigger_out_t → action_in_t (drop cmd_feedback)
            action_in_t act_pkt;
            always_comb begin
                act_pkt.tech_id   = trig_out_pkt[t].tech_id;
                act_pkt.cmd_id    = trig_out_pkt[t].cmd_id;
                act_pkt.bg_id     = trig_out_pkt[t].bg_id;
                act_pkt.ba_id     = trig_out_pkt[t].ba_id;
                act_pkt.sa_id     = trig_out_pkt[t].sa_id;
                act_pkt.row_id    = trig_out_pkt[t].row_id;
                act_pkt.col_id    = trig_out_pkt[t].col_id;
                act_pkt.prio      = trig_out_pkt[t].prio;
                act_pkt.timestamp = trig_out_pkt[t].timestamp;
            end

            // --------------------------------------------------------
            //  UpdateUnit (per-tech instance)
            // --------------------------------------------------------
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
                .TECH_W(TECH_W), .TECH_ID(t), .BANK_W(BANK_W)
            ) u_upd (
                .clk_i             (clk_i),
                .reset_i           (reset_i),
                .in_valid_i        (upd_in_valid),
                .in_ready_o        (upd_in_ready),
                .pkt_i             (upd_pkt),
                // Metadata feedback (registered from MetadataTableBank)
                .metadata_valid_i  (upd_meta_valid),
                .metadata_in_i     (upd_meta_in),
                // Cycle-0 outputs
                .metadata_tag_valid_o    (upd_meta_tag_valid),
                .metadata_tag_o          (upd_meta_tag),
                .rd_bank_id_o            (upd_rd_bank_id),
                .timer_reload_mask_valid_o(upd_timer_valid),
                .timer_reload_mask_o     (upd_timer_mask),
                // Cycle-1 outputs (writeback)
                .metadata_out_valid_o    (upd_meta_out_valid),
                .metadata_out_ready_i    (1'b1),  // MetadataTable write is always ready
                .metadata_out_o          (upd_meta_out),
                .wr_tag_o                (upd_wr_tag),
                .wr_bank_id_o            (upd_wr_bank_id),
                // Config
                .cfg_wr_en_i       (u_cfg_wr_en_i),
                .cfg_wr_key_i      (u_cfg_wr_key_i),
                .cfg_wr_value_i    (u_cfg_wr_value_i)
            );

            // Expose timer reload mask
            assign timer_reload_mask_valid_o[t] = upd_timer_valid;
            assign timer_reload_mask_o[t]       = upd_timer_mask;

            // --------------------------------------------------------
            //  ActionUnit (per-tech instance)
            // --------------------------------------------------------
            ActionUnit #(
                .CMD_W(CMD_W), .BG_W(BG_W), .BA_W(BA_W), .SA_W(SA_W),
                .ROW_W(ROW_W), .COL_W(COL_W), .PRI_W(PRI_W), .TS_W(TS_W),
                .CFG_W(A_CFG_W), .CFG_DEPTH(A_CFG_DEPTH),
                .PAYLOAD_W(A_PAYLOAD_W), .PAYLOAD_DEPTH(A_PAYLOAD_DEPTH)
            ) u_act (
                .clk_i             (clk_i),
                .reset_i           (reset_i),
                .in_valid_i        (act_in_valid),
                .in_ready_o        (act_in_ready),
                .pkt_i             (act_pkt),
                .out_valid_o       (wave_out_valid_o[t]),
                .out_ready_i       (wave_out_ready_i[t]),
                .wave_o            (wave_o[t]),
                // Config (broadcast)
                .cfg_wr_en_i       (a_cfg_wr_en_i),
                .cfg_wr_key_i      (a_cfg_wr_key_i),
                .cfg_wr_value_i    (a_cfg_wr_value_i),
                .payload_wr_en_i   (a_payload_wr_en_i),
                .payload_wr_key_i  (a_payload_wr_key_i),
                .payload_wr_value_i(a_payload_wr_value_i)
            );

            // --------------------------------------------------------
            //  MetadataTableBank (per-tech, contains NUM_BANKS tables)
            // --------------------------------------------------------
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
                .rd_a_en_i    (trig_meta_tag_valid[t]),
                .rd_a_bank_i  (trig_bank_id[t]),
                .rd_a_tag_i   (trig_meta_tag[t]),
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

            // --------------------------------------------------------
            //  Metadata feedback (no extra registers — SRAM provides 1-cycle latency)
            // --------------------------------------------------------
            // Trigger path: SRAM output is already 1 cycle after tag emission → direct connect
            assign trig_meta_valid[t] = mbank_rd_a_hit;
            assign trig_meta_in[t]    = mbank_rd_a_data;

            // Update path: SRAM read result is 1 cycle after tag emission.
            // UpdateUnit needs upd_meta_valid = "lookup was requested" (regardless of hit).
            // We still register upd_meta_tag_valid to align with the SRAM output.
            logic upd_lookup_q;
            always_ff @(posedge clk_i) begin
                if (reset_i)
                    upd_lookup_q <= 1'b0;
                else
                    upd_lookup_q <= upd_meta_tag_valid;
            end
            assign upd_meta_valid = upd_lookup_q;
            assign upd_meta_in    = mbank_rd_b_hit ? mbank_rd_b_data : '0;

        end // g_tech
    endgenerate

endmodule
