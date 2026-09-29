`timescale 1ns/1ps
import terracotta_types_pkg::*;

module TriggerBankArray #(
    parameter int NUM_BANKS    = terracotta_types_pkg::TC_NUM_BANKS,
    parameter int TECH_ID      = 0,
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
    parameter int EWMA_W       = terracotta_types_pkg::TC_EWMA_W
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    input  logic                   in_valid_i,
    output logic                   in_ready_o,
    input  trigger_in_t            pkt_i,

    // Per-bank metadata inputs (broadcast)
    input  logic                   metadata_valid_i,
    input  logic [METADATA_W-1:0]  metadata_in_i,

    // Shared config write port broadcast to all bank instances
    input  logic                   cfg_wr_en_i,
    input  logic [REQ_W+CMD_W-1:0] cfg_wr_key_i,
    input  logic [CFG_W-1:0]       cfg_wr_value_i,

    // EWMA bus-utilization (broadcast from TerracottaUnit)
    input  logic [EWMA_W-1:0]      ewma_bus_util_i,

    // Priority arbitration (to/from TriggerArray)
    output logic                   match_o,
    input  logic                   grant_i,

    // Bus-utilization threshold programming (broadcast to all bank instances)
    input  logic                   bus_util_thresh_wr_en_i,
    input  logic [EWMA_W-1:0]      bus_util_thresh_wr_data_i,

    // Outputs (muxed from all banks)
    output logic                   out_valid_o,
    input  logic                   out_ready_i,
    output trigger_out_t           pkt_o,

    // Metadata tag muxed from all banks
    output logic                   metadata_tag_valid_o,
    output logic [ROW_W+COL_W+SA_W-1:0] metadata_tag_o,
    output logic [BANK_W-1:0]      bank_id_o
);
    genvar i;
    logic [NUM_BANKS-1:0] inst_in_valid;
    logic [NUM_BANKS-1:0] inst_in_ready;
    logic [NUM_BANKS-1:0] inst_out_valid;
    logic [NUM_BANKS-1:0] inst_meta_tag_valid;
    logic [NUM_BANKS-1:0] inst_match;
    logic [ROW_W+COL_W+SA_W-1:0] inst_meta_tag [NUM_BANKS];
    trigger_out_t inst_pkt_out [NUM_BANKS];
    logic [BANK_W-1:0] inst_bank_id [NUM_BANKS];

    // Mux outputs: only one bank active at a time
    always_comb begin
        pkt_o = '0;
        out_valid_o = 1'b0;
        metadata_tag_o = '0;
        metadata_tag_valid_o = 1'b0;
        bank_id_o = '0;
        match_o = 1'b0;

        for (int k = 0; k < NUM_BANKS; k++) begin
            if (inst_out_valid[k]) begin
                out_valid_o = 1'b1;
                pkt_o = inst_pkt_out[k];
            end
            if (inst_meta_tag_valid[k]) begin
                metadata_tag_valid_o = 1'b1;
                metadata_tag_o = inst_meta_tag[k];
                bank_id_o = inst_bank_id[k];
            end
            if (inst_match[k]) begin
                match_o = 1'b1;
            end
        end
    end

    assign in_ready_o = &inst_in_ready;

    logic [BANK_W-1:0] target_bank_idx;
    assign target_bank_idx = {pkt_i.bg_id, pkt_i.ba_id};

    generate
        for (i = 0; i < NUM_BANKS; i++) begin : g_trig
            assign inst_in_valid[i] = in_valid_i && (target_bank_idx == i);

            TriggerUnit #(
                .REQ_W(REQ_W), .CMD_W(CMD_W), .BG_W(BG_W), .BA_W(BA_W),
                .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W), .PRI_W(PRI_W), .TS_W(TS_W),
                .METADATA_W(METADATA_W), .CFG_W(CFG_W), .CFG_DEPTH(CFG_DEPTH),
                .CUSTOM_CMD_W(CUSTOM_CMD_W), .TECH_W(TECH_W), .TECH_ID(TECH_ID),
                .BANK_W(BANK_W), .EWMA_W(EWMA_W)
            ) u_trig (
                .clk_i(clk_i), .reset_i(reset_i),
                .in_valid_i(inst_in_valid[i]), .in_ready_o(inst_in_ready[i]),
                .pkt_i(pkt_i),
                .metadata_valid_i(metadata_valid_i), .metadata_in_i(metadata_in_i),
                .metadata_tag_valid_o(inst_meta_tag_valid[i]),
                .metadata_tag_o(inst_meta_tag[i]),
                .bank_id_o(inst_bank_id[i]),
                .cfg_wr_en_i(cfg_wr_en_i), .cfg_wr_key_i(cfg_wr_key_i), .cfg_wr_value_i(cfg_wr_value_i),
                .ewma_bus_util_i(ewma_bus_util_i),
                .match_o(inst_match[i]),
                .grant_i(grant_i),
                .bus_util_thresh_wr_en_i(bus_util_thresh_wr_en_i),
                .bus_util_thresh_wr_data_i(bus_util_thresh_wr_data_i),
                .out_valid_o(inst_out_valid[i]), .out_ready_i(out_ready_i),
                .pkt_o(inst_pkt_out[i])
            );
        end
    endgenerate
endmodule
