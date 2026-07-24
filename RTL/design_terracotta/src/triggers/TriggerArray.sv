`timescale 1ns/1ps
import terracotta_types_pkg::*;

// TriggerArray: Multi-technique trigger wrapper with priority arbitration
// and EWMA bus-utilization throttling.
//
// Instantiates NUM_TECH TriggerBankArrays (one per technique).
// Each TriggerBankArray contains NUM_BANKS TriggerUnit instances.
//
// Priority arbitration (cycle 1, combinational):
//   - Collects match_o from each TriggerBankArray
//   - Selects the highest-priority matching technique (prio_r)
//   - Drives grant_i=1 only to the winner
//   - All techniques produce out_valid every cycle (non-winners pass-through)
//
// EWMA bus-utilization threshold is per-technique (inside TriggerUnit).
// EWMA running average is global (inside TerracottaUnit), broadcast here.

module TriggerArray #(
    parameter int NUM_TECH     = (1 << terracotta_types_pkg::TC_TECH_W),
    parameter int NUM_BANKS    = terracotta_types_pkg::TC_NUM_BANKS,
    parameter int REQ_W        = terracotta_types_pkg::TC_REQ_W,
    parameter int CMD_W        = terracotta_types_pkg::TC_CMD_W,
    parameter int BG_W         = terracotta_types_pkg::TC_BG_W,
    parameter int BA_W         = terracotta_types_pkg::TC_BA_W,
    parameter int SA_W         = terracotta_types_pkg::TC_SA_W,
    parameter int ROW_W        = terracotta_types_pkg::TC_ROW_W,
    parameter int COL_W        = terracotta_types_pkg::TC_COL_W,
    parameter int PRI_W        = terracotta_types_pkg::TC_PRI_W,
    parameter int TS_W         = terracotta_types_pkg::TC_TS_W,
    parameter int METADATA_W   = terracotta_types_pkg::TC_METADATA_W,
    parameter int CFG_W        = terracotta_types_pkg::TC_T_CFG_W,
    parameter int CFG_DEPTH    = terracotta_types_pkg::TC_T_CFG_DEPTH,
    parameter int CUSTOM_CMD_W = terracotta_types_pkg::TC_CUSTOM_CMD_W,
    parameter int TECH_W       = terracotta_types_pkg::TC_TECH_W,
    parameter int BANK_W       = terracotta_types_pkg::TC_BANK_W,
    parameter int EWMA_W       = terracotta_types_pkg::TC_EWMA_W,
    parameter int PRIO_W       = terracotta_types_pkg::TC_TECH_PRIO_W
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // ======================== Input ========================
    input  logic                   in_valid_i,
    output logic                   in_ready_o,
    input  trigger_in_t            pkt_i,

    // ======================== Per-tech metadata feedback ========================
    input  logic [NUM_TECH-1:0]              metadata_valid_i,
    input  logic [METADATA_W-1:0]            metadata_in_i    [NUM_TECH],

    // ======================== Config write (broadcast) ========================
    input  logic                   cfg_wr_en_i,
    input  logic [REQ_W+CMD_W-1:0] cfg_wr_key_i,
    input  logic [CFG_W-1:0]       cfg_wr_value_i,

    // ======================== EWMA bus-util (global, from TerracottaUnit) ========================
    input  logic [EWMA_W-1:0]      ewma_bus_util_i,

    // ======================== Per-tech threshold programming ========================
    input  logic                   bus_util_thresh_wr_en_i,
    input  logic [TECH_W-1:0]      bus_util_thresh_wr_tech_i,
    input  logic [EWMA_W-1:0]      bus_util_thresh_wr_data_i,

    // ======================== Per-tech priority programming ========================
    input  logic                   tech_prio_wr_en_i,
    input  logic [TECH_W-1:0]      tech_prio_wr_tech_i,
    input  logic [PRIO_W-1:0]      tech_prio_wr_data_i,

    // ======================== Per-tech outputs ========================
    output logic [NUM_TECH-1:0]    out_valid_o,
    input  logic [NUM_TECH-1:0]    out_ready_i,
    output trigger_out_t           pkt_o          [NUM_TECH],

    // ======================== Per-tech metadata tag outputs ========================
    output logic [NUM_TECH-1:0]              metadata_tag_valid_o,
    output logic [ROW_W+COL_W+SA_W-1:0]     metadata_tag_o  [NUM_TECH],
    output logic [BANK_W-1:0]                bank_id_o       [NUM_TECH],

    // ======================== Trigger-fired indicator ========================
    output logic                   trigger_fired_o
);

    // ================================================================
    //  Per-technique priority registers
    // ================================================================
    logic [PRIO_W-1:0] prio_r [NUM_TECH];
    integer pi;
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            for (pi = 0; pi < NUM_TECH; pi++)
                prio_r[pi] <= PRIO_W'(pi);  // default: tech 0→prio 0, tech 1→prio 1, etc.
        end else if (tech_prio_wr_en_i) begin
            prio_r[tech_prio_wr_tech_i] <= tech_prio_wr_data_i;
        end
    end

    // ================================================================
    //  Per-tech TriggerBankArray instances
    // ================================================================
    logic [NUM_TECH-1:0] inst_in_ready;
    logic [NUM_TECH-1:0] inst_match;
    logic [NUM_TECH-1:0] inst_grant;

    // Per-tech bus-util threshold write enable (addressed decode)
    logic [NUM_TECH-1:0] thresh_wr_en;
    genvar t;
    generate
        for (t = 0; t < NUM_TECH; t++) begin : g_thresh_decode
            assign thresh_wr_en[t] = bus_util_thresh_wr_en_i
                                   & (bus_util_thresh_wr_tech_i == TECH_W'(t));
        end
    endgenerate

    generate
        for (t = 0; t < NUM_TECH; t++) begin : g_tech

            TriggerBankArray #(
                .NUM_BANKS(NUM_BANKS), .TECH_ID(t),
                .REQ_W(REQ_W), .CMD_W(CMD_W), .BG_W(BG_W), .BA_W(BA_W),
                .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W), .PRI_W(PRI_W), .TS_W(TS_W),
                .METADATA_W(METADATA_W), .CFG_W(CFG_W), .CFG_DEPTH(CFG_DEPTH),
                .CUSTOM_CMD_W(CUSTOM_CMD_W), .TECH_W(TECH_W),
                .BANK_W(BANK_W), .EWMA_W(EWMA_W)
            ) u_bank_array (
                .clk_i              (clk_i),
                .reset_i            (reset_i),
                .in_valid_i         (in_valid_i),
                .in_ready_o         (inst_in_ready[t]),
                .pkt_i              (pkt_i),
                .metadata_valid_i   (metadata_valid_i[t]),
                .metadata_in_i      (metadata_in_i[t]),
                .cfg_wr_en_i        (cfg_wr_en_i),
                .cfg_wr_key_i       (cfg_wr_key_i),
                .cfg_wr_value_i     (cfg_wr_value_i),
                .ewma_bus_util_i    (ewma_bus_util_i),
                .match_o            (inst_match[t]),
                .grant_i            (inst_grant[t]),
                .bus_util_thresh_wr_en_i  (thresh_wr_en[t]),
                .bus_util_thresh_wr_data_i(bus_util_thresh_wr_data_i),
                .out_valid_o        (out_valid_o[t]),
                .out_ready_i        (out_ready_i[t]),
                .pkt_o              (pkt_o[t]),
                .metadata_tag_valid_o(metadata_tag_valid_o[t]),
                .metadata_tag_o     (metadata_tag_o[t]),
                .bank_id_o          (bank_id_o[t])
            );
        end
    endgenerate

    // in_ready: stall if ANY technique's bank array is not ready
    assign in_ready_o = &inst_in_ready;

    // ================================================================
    //  Priority arbiter (combinational, cycle 1)
    //  Selects the highest-priority technique among those with match=1.
    //  Higher prio_r value = higher priority.
    // ================================================================
    always_comb begin
        inst_grant = '0;
        trigger_fired_o = 1'b0;

        if (|inst_match) begin
            automatic int best_tech = 0;
            automatic logic [PRIO_W-1:0] best_prio = '0;
            automatic logic found = 1'b0;

            for (int k = 0; k < NUM_TECH; k++) begin
                if (inst_match[k]) begin
                    if (!found || prio_r[k] > best_prio) begin
                        best_tech = k;
                        best_prio = prio_r[k];
                        found = 1'b1;
                    end
                end
            end

            inst_grant[best_tech] = 1'b1;
            trigger_fired_o = 1'b1;
        end
    end

endmodule
