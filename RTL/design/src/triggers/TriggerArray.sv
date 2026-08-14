`timescale 1ns/1ps
import terracotta_types_pkg::*;

module TriggerArray #(
    parameter int NUM_TECH     = (1 << TC_TECH_W),
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
    parameter int TECH_W       = terracotta_types_pkg::TC_TECH_W
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    input  logic                   in_valid_i,
    output logic                   in_ready_o,
    input  trigger_in_t            pkt_i,

    input  logic                   metadata_valid_i,
    input  logic [METADATA_W-1:0]  metadata_in_i,

    // Shared config write port broadcast to all instances
    input  logic                   cfg_wr_en_i,
    input  logic [REQ_W+CMD_W-1:0] cfg_wr_key_i,
    input  logic [CFG_W-1:0]       cfg_wr_value_i,

    // Outputs (vectorized)
    output logic [NUM_TECH-1:0]    out_valid_o,
    input  logic  [NUM_TECH-1:0]   out_ready_i,
    output trigger_out_t           pkt_o [NUM_TECH],
    // Metadata tag fanout per instance to prevent optimization
    output logic [NUM_TECH-1:0]    metadata_tag_valid_o,
    output logic [ROW_W+COL_W+SA_W-1:0] metadata_tag_o [NUM_TECH]
);
    // Simple fanout on in_ready: ready only if all instances can accept.
    logic [NUM_TECH-1:0] inst_in_ready;
    assign in_ready_o = &inst_in_ready;

    genvar i;
    generate
        for (i = 0; i < NUM_TECH; i++) begin : g_trig
            TriggerUnit #(
                .REQ_W(REQ_W), .CMD_W(CMD_W), .BG_W(BG_W), .BA_W(BA_W), .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W), .PRI_W(PRI_W), .TS_W(TS_W),
                .METADATA_W(METADATA_W), .CFG_W(CFG_W), .CFG_DEPTH(CFG_DEPTH), .CUSTOM_CMD_W(CUSTOM_CMD_W), .TECH_W(TECH_W), .TECH_ID(i)
            ) u_trig (
                .clk_i(clk_i), .reset_i(reset_i),
                .in_valid_i(in_valid_i), .in_ready_o(inst_in_ready[i]),
                .pkt_i(pkt_i),
                .metadata_valid_i(metadata_valid_i), .metadata_in_i(metadata_in_i),
                .metadata_tag_valid_o(metadata_tag_valid_o[i]),
                .metadata_tag_o(metadata_tag_o[i]),
                .cfg_wr_en_i(cfg_wr_en_i), .cfg_wr_key_i(cfg_wr_key_i), .cfg_wr_value_i(cfg_wr_value_i),
                .out_valid_o(out_valid_o[i]), .out_ready_i(out_ready_i[i]),
                .pkt_o(pkt_o[i])
            );
        end
    endgenerate
endmodule
