`timescale 1ns/1ps
import terracotta_types_pkg::*;

module ActionArray #(
    parameter int CMD_W            = terracotta_types_pkg::TC_CMD_W,
    parameter int BG_W             = terracotta_types_pkg::TC_BG_W,
    parameter int BA_W             = terracotta_types_pkg::TC_BA_W,
    parameter int SA_W             = terracotta_types_pkg::TC_SA_W,
    parameter int ROW_W            = terracotta_types_pkg::TC_ROW_W,
    parameter int COL_W            = terracotta_types_pkg::TC_COL_W,
    parameter int PRI_W            = terracotta_types_pkg::TC_PRI_W,
    parameter int TS_W             = terracotta_types_pkg::TC_TS_W,
    parameter int REG_ID_W         = terracotta_types_pkg::TC_REG_ID_W,
    parameter int OPER_SEL_W       = terracotta_types_pkg::TC_OPERAND_SEL_W,
    parameter int ACTION_PARAM_W   = terracotta_types_pkg::TC_ACTION_PARAM_W,
    parameter int CFG_W            = terracotta_types_pkg::TC_A_CFG_W,
    parameter int CFG_DEPTH        = terracotta_types_pkg::TC_A_CFG_DEPTH,
    parameter int PAYLOAD_W        = terracotta_types_pkg::TC_A_PAYLOAD_W,
    parameter int PAYLOAD_DEPTH    = terracotta_types_pkg::TC_A_PAYLOAD_DEPTH,
    parameter int TECH_W           = terracotta_types_pkg::TC_TECH_W,
    parameter int NUM_TECH         = (1 << terracotta_types_pkg::TC_TECH_W)
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // Input handshake
    input  logic                   in_valid_i,
    output logic                   in_ready_o,

    // Packet input with tech_id
    input  action_in_t             pkt_i,

    // Wave output handshake per-tech
    output logic [NUM_TECH-1:0]    out_valid_o,
    input  logic  [NUM_TECH-1:0]   out_ready_i,
    output action_wave_t           wave_o [NUM_TECH],

    // Config write (broadcast)
    input  logic                   cfg_wr_en_i,
    input  logic [CMD_W-1:0]       cfg_wr_key_i,
    input  logic [CFG_W-1:0]       cfg_wr_value_i,

    // Payload table write (broadcast)
    input  logic                   payload_wr_en_i,
    input  logic [terracotta_types_pkg::TC_PAYLOAD_IDX_W-1:0] payload_wr_key_i,
    input  logic [PAYLOAD_W-1:0]   payload_wr_value_i
);
    // One-hot selection from tech_id
    logic [NUM_TECH-1:0] tech_sel_oh;
    genvar t;
    generate
        for (t = 0; t < NUM_TECH; t++) begin : g_sel
            assign tech_sel_oh[t] = (pkt_i.tech_id == t[TECH_W-1:0]);
        end
    endgenerate

    // Gate in_valid per instance; in_ready is OR of selected instance
    logic [NUM_TECH-1:0] inst_in_valid;
    logic [NUM_TECH-1:0] inst_in_ready;
    assign inst_in_valid = {NUM_TECH{in_valid_i}} & tech_sel_oh;
    assign in_ready_o    = |(inst_in_ready & tech_sel_oh);

    genvar i;
    generate
        for (i = 0; i < NUM_TECH; i++) begin : g_act
            ActionUnit #(
                .CMD_W(CMD_W), .BG_W(BG_W), .BA_W(BA_W), .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W), .PRI_W(PRI_W), .TS_W(TS_W),
                .REG_ID_W(REG_ID_W), .OPER_SEL_W(OPER_SEL_W), .ACTION_PARAM_W(ACTION_PARAM_W),
                .CFG_W(CFG_W), .CFG_DEPTH(CFG_DEPTH), .PAYLOAD_W(PAYLOAD_W), .PAYLOAD_DEPTH(PAYLOAD_DEPTH)
            ) u_act (
                .clk_i(clk_i), .reset_i(reset_i),
                .in_valid_i(inst_in_valid[i]), .in_ready_o(inst_in_ready[i]),
                .pkt_i(pkt_i),
                .out_valid_o(out_valid_o[i]), .out_ready_i(out_ready_i[i]), .wave_o(wave_o[i]),
                .cfg_wr_en_i(cfg_wr_en_i), .cfg_wr_key_i(cfg_wr_key_i), .cfg_wr_value_i(cfg_wr_value_i),
                .payload_wr_en_i(payload_wr_en_i), .payload_wr_key_i(payload_wr_key_i), .payload_wr_value_i(payload_wr_value_i)
            );
        end
    endgenerate
endmodule
