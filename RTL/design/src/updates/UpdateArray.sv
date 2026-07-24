`timescale 1ns/1ps
import terracotta_types_pkg::*;

module UpdateArray #(
    parameter int SA_W         = terracotta_types_pkg::TC_SA_W,
    parameter int ROW_W        = terracotta_types_pkg::TC_ROW_W,
    parameter int COL_W        = terracotta_types_pkg::TC_COL_W,
    parameter int METADATA_W   = terracotta_types_pkg::TC_METADATA_W,
    parameter int TS_W         = terracotta_types_pkg::TC_TS_W,
    parameter int CMD_W        = terracotta_types_pkg::TC_CMD_W,
    parameter int CFG_W        = terracotta_types_pkg::TC_U_CFG_W,
    parameter int CFG_DEPTH    = terracotta_types_pkg::TC_U_CFG_DEPTH,
    parameter int TECH_W       = terracotta_types_pkg::TC_TECH_W,
    parameter int NUM_TECH     = (1 << terracotta_types_pkg::TC_TECH_W)
) (
    input  logic                         clk_i,
    input  logic                         reset_i,

    // Input handshake
    input  logic                         in_valid_i,
    output logic                         in_ready_o,

    // Packet input including tech_id
    input  update_in_t                   pkt_i,

    // Metadata stream arriving for stage-1 of selected unit
    input  logic                         metadata_valid_i,
    input  logic [METADATA_W-1:0]        metadata_in_i,

    // Config write (broadcast to all instances)
    input  logic                         cfg_wr_en_i,
    input  logic [CMD_W-1:0]             cfg_wr_key_i,
    input  logic [CFG_W-1:0]             cfg_wr_value_i,

    // Per-instance ready for metadata_out (to connect to metadata unit ports)
    input  logic [NUM_TECH-1:0]          metadata_out_ready_i,

    // Cycle-0 outputs per instance
    output logic [NUM_TECH-1:0]          metadata_tag_valid_o,
    output logic [ROW_W+COL_W+SA_W-1:0]  metadata_tag_o       [NUM_TECH],
    output logic [NUM_TECH-1:0]          timer_reload_mask_valid_o,
    output logic [TS_W-1:0]              timer_reload_mask_o  [NUM_TECH],

    // Cycle-1 outputs per instance
    output logic [NUM_TECH-1:0]          metadata_out_valid_o,
    output logic [METADATA_W-1:0]        metadata_out_o       [NUM_TECH]
);
    // One-hot select for tech_id
    logic [NUM_TECH-1:0] tech_sel_oh;
    genvar ti;
    generate
        for (ti = 0; ti < NUM_TECH; ti++) begin : g_sel
            assign tech_sel_oh[ti] = (pkt_i.tech_id == ti[TECH_W-1:0]);
        end
    endgenerate

    // Gate in_valid per instance
    logic [NUM_TECH-1:0] inst_in_valid;
    assign inst_in_valid = {NUM_TECH{in_valid_i}} & tech_sel_oh;

    // Collect per-instance in_ready to compute array-level in_ready
    logic [NUM_TECH-1:0] inst_in_ready;
    assign in_ready_o = |(inst_in_ready & tech_sel_oh);

    // Instantiate units
    genvar i;
    generate
        for (i = 0; i < NUM_TECH; i++) begin : g_upd
            UpdateUnit #(
                .CMD_W(CMD_W), .SA_W(SA_W), .ROW_W(ROW_W), .COL_W(COL_W), .METADATA_W(METADATA_W), .TS_W(TS_W),
                .CFG_W(CFG_W), .CFG_DEPTH(CFG_DEPTH), .TECH_W(TECH_W), .TECH_ID(i)
            ) u_upd (
                .clk_i(clk_i), .reset_i(reset_i),
                .in_valid_i(inst_in_valid[i]), .in_ready_o(inst_in_ready[i]),
                .pkt_i(pkt_i),
                .metadata_valid_i(metadata_valid_i), .metadata_in_i(metadata_in_i),
                .metadata_tag_valid_o(metadata_tag_valid_o[i]),
                .metadata_tag_o(metadata_tag_o[i]),
                .timer_reload_mask_valid_o(timer_reload_mask_valid_o[i]),
                .timer_reload_mask_o(timer_reload_mask_o[i]),
                .metadata_out_valid_o(metadata_out_valid_o[i]),
                .metadata_out_ready_i(metadata_out_ready_i[i]),
                .metadata_out_o(metadata_out_o[i]),
                .cfg_wr_en_i(cfg_wr_en_i), .cfg_wr_key_i(cfg_wr_key_i), .cfg_wr_value_i(cfg_wr_value_i)
            );
        end
    endgenerate
endmodule
