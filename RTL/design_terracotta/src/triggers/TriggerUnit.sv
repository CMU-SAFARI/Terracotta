`timescale 1ns/1ps
import terracotta_types_pkg::*;

module TriggerUnit #(
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
    parameter int TECH_ID      = 0,
    parameter int BANK_W       = terracotta_types_pkg::TC_BANK_W,
    parameter int EWMA_W       = terracotta_types_pkg::TC_EWMA_W
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // Handshake (not part of packet)
    input  logic                   in_valid_i,
    output logic                   in_ready_o,
    output logic                   out_valid_o,
    input  logic                   out_ready_i,

    // Packet input (struct)
    input  trigger_in_t            pkt_i,

    // Metadata (arrives from previous cycle external logic)
    input  logic                   metadata_valid_i,
    input  logic [METADATA_W-1:0]  metadata_in_i,

    // Metadata lookup interface (cycle 0): computed tag to external table
    output logic                   metadata_tag_valid_o,
    output logic [ROW_W+COL_W+SA_W-1:0] metadata_tag_o,
    output logic [BANK_W-1:0]      bank_id_o,

    // Config table write ports (boot-time programming only; table is instantiated internally)
    input  logic                   cfg_wr_en_i,
    input  logic [REQ_W+CMD_W-1:0] cfg_wr_key_i,
    input  logic [CFG_W-1:0]       cfg_wr_value_i,

    // EWMA bus-utilization throttling (from TerracottaUnit)
    input  logic [EWMA_W-1:0]      ewma_bus_util_i,

    // Priority arbitration interface (combinational, cycle 1)
    output logic                   match_o,    // this unit matched (before grant)
    input  logic                   grant_i,    // arbiter grants custom-cmd emission

    // Per-technique bus-util threshold programming
    input  logic                   bus_util_thresh_wr_en_i,
    input  logic [EWMA_W-1:0]      bus_util_thresh_wr_data_i,

    // Output packet (struct; includes technology id from instance)
    output trigger_out_t           pkt_o
);
    localparam int KEY_W = REQ_W + CMD_W;

    // Two-stage pipelined handshake implemented below

    // Config table read (combinational)
    logic                   cfg_rd_en;
    logic [REQ_W+CMD_W-1:0] cfg_rd_key;
    logic [CFG_W-1:0]       cfg_rd_value;
    // cfg_rd_en/rd_key assigned in pipelined handshake section

    ConfigTable #(
        .KEY_W(REQ_W+CMD_W),
        .CFG_W(CFG_W),
        .DEPTH(CFG_DEPTH)
    ) u_cfg (
        .clk_i(clk_i), .reset_i(reset_i),
        .rd_en_i(cfg_rd_en), .rd_key_i(cfg_rd_key), .rd_value_o(cfg_rd_value), .rd_hit_o(cfg_rd_hit),
        .wr_en_i(cfg_wr_en_i), .wr_key_i(cfg_wr_key_i), .wr_value_i(cfg_wr_value_i)
    );

    // Decode cfg_rd_value fields (pipelined trigger behavior)
    // New Layout (LSB → MSB):
    //   [0]                          cfg_require_meta (1=require metadata on next cycle)
    //   [TC_MATCH_LOGIC_W-1:0]       cfg_match_logic (4 bits: op_sel[1:0], rhs_sel[3:2])
    //   [METADATA_W-1:0]             cfg_match_value (unused in new semantics)
    //   [CUSTOM_CMD_W-1:0]           cfg_custom_cmd_id
    //   [TC_CMD_FEEDBACK_W-1:0]      cfg_cmd_feedback
    //   [METADATA_W-1:0]             cfg_meta_const (modulo constant)
    localparam int MATCH_LOGIC_W   = terracotta_types_pkg::TC_MATCH_LOGIC_W;
    localparam int CMD_FEEDBACK_W  = terracotta_types_pkg::TC_CMD_FEEDBACK_W;

    localparam int OFF_REQUIRE      = 0;
    localparam int OFF_MATCH_LOGIC  = OFF_REQUIRE + 1;
    localparam int OFF_MATCH_VALUE  = OFF_MATCH_LOGIC + MATCH_LOGIC_W;
    localparam int OFF_CUSTOM_CMD   = OFF_MATCH_VALUE + METADATA_W;
    localparam int OFF_CMD_FEEDBACK = OFF_CUSTOM_CMD + CUSTOM_CMD_W;
    localparam int OFF_META_CONST   = OFF_CMD_FEEDBACK + CMD_FEEDBACK_W;

    wire                      cfg_require_meta = cfg_rd_value[OFF_REQUIRE];
    wire [MATCH_LOGIC_W-1:0]  cfg_match_logic  = cfg_rd_value[OFF_MATCH_LOGIC + MATCH_LOGIC_W - 1 -: MATCH_LOGIC_W];
    wire [METADATA_W-1:0]     cfg_match_value  = cfg_rd_value[OFF_MATCH_VALUE + METADATA_W - 1 -: METADATA_W];
    wire [CUSTOM_CMD_W-1:0]   cfg_custom_cmd_id= cfg_rd_value[OFF_CUSTOM_CMD + CUSTOM_CMD_W - 1 -: CUSTOM_CMD_W];
    wire [CMD_FEEDBACK_W-1:0] cfg_cmd_feedback = cfg_rd_value[OFF_CMD_FEEDBACK + CMD_FEEDBACK_W - 1 -: CMD_FEEDBACK_W];
    wire [METADATA_W-1:0]     cfg_meta_const   = cfg_rd_value[OFF_META_CONST + METADATA_W - 1 -: METADATA_W];

    // Metadata tag composition: fixed field positions {sa_id, row_id, col_id}
    // Config provides per-field enables: use_sa (MSB), use_row, use_col (LSB).
    localparam int TAG_USE_W = terracotta_types_pkg::TC_TAG_USE_W;
    localparam int OFF_TAG_USE = OFF_META_CONST + METADATA_W;
    wire [TAG_USE_W-1:0]        cfg_tag_use = cfg_rd_value[OFF_TAG_USE + TAG_USE_W - 1 -: TAG_USE_W];
    wire                        cfg_use_sa  = cfg_tag_use[2];
    wire                        cfg_use_row = cfg_tag_use[1];
    wire                        cfg_use_col = cfg_tag_use[0];

    // Compute metadata tag combinationally in cycle 0 (when accepting input)
    localparam int METATAG_W = ROW_W + COL_W + SA_W;
    (* keep *) logic [SA_W-1:0]  sa_tag_src;
    (* keep *) logic [ROW_W-1:0] row_tag_src;
    (* keep *) logic [COL_W-1:0] col_tag_src;
    assign sa_tag_src  = pkt_i.sa_id;
    assign row_tag_src = pkt_i.row_id;
    assign col_tag_src = pkt_i.col_id;

    (* keep *) logic [SA_W-1:0]  sa_mask;
    (* keep *) logic [ROW_W-1:0] row_mask;
    (* keep *) logic [COL_W-1:0] col_mask;
    assign sa_mask  = {SA_W{cfg_use_sa}};
    assign row_mask = {ROW_W{cfg_use_row}};
    assign col_mask = {COL_W{cfg_use_col}};

    (* keep *) logic [SA_W-1:0]  sa_masked;
    (* keep *) logic [ROW_W-1:0] row_masked;
    (* keep *) logic [COL_W-1:0] col_masked;
    assign sa_masked  = sa_tag_src  & sa_mask;
    assign row_masked = row_tag_src & row_mask;
    assign col_masked = col_tag_src & col_mask;

    assign metadata_tag_valid_o = in_valid_i & s0_ready & cfg_require_meta;
    assign metadata_tag_o       = {sa_masked, row_masked, col_masked};
    assign bank_id_o            = {pkt_i.bg_id, pkt_i.ba_id};

    // Two-stage pipeline registers
    logic                    s0_valid;
    trigger_in_t            s0_pkt;
    logic                    s0_require_meta;
    logic [MATCH_LOGIC_W-1:0] s0_match_logic;
    logic [METADATA_W-1:0]    s0_match_value;
    logic [CUSTOM_CMD_W-1:0]  s0_custom_cmd_id;
    logic [CMD_FEEDBACK_W-1:0] s0_cmd_feedback;
    logic [METADATA_W-1:0]    s0_meta_const;
    logic                    s0_cfg_hit;

    logic                    s1_valid;
    trigger_out_t            s1_pkt;
    logic                    cfg_rd_hit;

    // Internal pipeline ready conditions
    wire s1_ready = (~s1_valid) | out_ready_i;
    wire s0_ready = s1_ready;

    // Handshake updates
    assign in_ready_o  = s0_ready;
    assign out_valid_o = s1_valid;

    // Config table read tied to stage-0 accept
    assign cfg_rd_en  = in_valid_i & s0_ready;
    assign cfg_rd_key = {pkt_i.req_id, pkt_i.cmd_id};

    // Match functions using metadata operation on cycle-1
    wire base_meta_ok = s0_require_meta ? metadata_valid_i : 1'b1;
    // New matching: compare LHS=metadata_in_i against RHS selected by config with op_sel.
    logic cmp_true;
    always_comb begin
        cmp_true = 1'b0;
        unique case (s0_match_logic[3:2])
            2'b00: begin // const
                unique case (s0_match_logic[1:0])
                    2'b00: cmp_true = (metadata_in_i <  s0_meta_const);
                    2'b01: cmp_true = (metadata_in_i == s0_meta_const);
                    2'b10: cmp_true = (metadata_in_i != s0_meta_const);
                    default: cmp_true = 1'b0;
                endcase
            end
            2'b01: begin // sa_id
                unique case (s0_match_logic[1:0])
                    2'b00: cmp_true = (metadata_in_i[SA_W-1:0]  <  s0_pkt.sa_id);
                    2'b01: cmp_true = (metadata_in_i[SA_W-1:0]  == s0_pkt.sa_id);
                    2'b10: cmp_true = (metadata_in_i[SA_W-1:0]  != s0_pkt.sa_id);
                    default: cmp_true = 1'b0;
                endcase
            end
            2'b10: begin // row_id
                unique case (s0_match_logic[1:0])
                    2'b00: cmp_true = (metadata_in_i[ROW_W-1:0] <  s0_pkt.row_id);
                    2'b01: cmp_true = (metadata_in_i[ROW_W-1:0] == s0_pkt.row_id);
                    2'b10: cmp_true = (metadata_in_i[ROW_W-1:0] != s0_pkt.row_id);
                    default: cmp_true = 1'b0;
                endcase
            end
            2'b11: begin // col_id
                unique case (s0_match_logic[1:0])
                    2'b00: cmp_true = (metadata_in_i[COL_W-1:0] <  s0_pkt.col_id);
                    2'b01: cmp_true = (metadata_in_i[COL_W-1:0] == s0_pkt.col_id);
                    2'b10: cmp_true = (metadata_in_i[COL_W-1:0] != s0_pkt.col_id);
                    default: cmp_true = 1'b0;
                endcase
            end
        endcase
    end
    wire trigger_match = s0_require_meta ? (base_meta_ok & cmp_true)
                                         : s0_cfg_hit;

    // ════════════════════════════════════════════════════════════════════
    // Bus-utilization threshold register (programmable, per-technique)
    //   Default 0xFFFF = never throttle.
    // ════════════════════════════════════════════════════════════════════
    logic [EWMA_W-1:0] bus_util_threshold_r;
    always_ff @(posedge clk_i) begin
        if (reset_i)
            bus_util_threshold_r <= {EWMA_W{1'b1}};  // max = no throttle
        else if (bus_util_thresh_wr_en_i)
            bus_util_threshold_r <= bus_util_thresh_wr_data_i;
    end

    // EWMA masking: suppress match when bus utilization exceeds threshold
    wire bus_util_ok     = (ewma_bus_util_i <= bus_util_threshold_r);
    wire effective_match = trigger_match & bus_util_ok;

    // Combinational match output for priority arbiter (cycle 1, before grant)
    assign match_o = s0_valid & effective_match;

    // Output register stage
    // Pipeline state and outputs
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            s0_valid <= 1'b0;
            s1_valid <= 1'b0;
            pkt_o    <= '0;
        end else begin
            // Stage-1 consume
            if (s1_valid && out_ready_i) begin
                s1_valid <= 1'b0;
            end

            // Stage-0 accept new input and capture cfg
            if (in_valid_i && s0_ready) begin
                s0_valid         <= 1'b1;
                s0_pkt           <= pkt_i;
                s0_require_meta  <= cfg_require_meta;
                s0_match_logic   <= cfg_match_logic;
                s0_match_value   <= cfg_match_value;
                s0_custom_cmd_id <= cfg_custom_cmd_id;
                s0_cmd_feedback  <= cfg_cmd_feedback;
                s0_meta_const    <= cfg_meta_const;
                s0_cfg_hit       <= cfg_rd_hit;
            end else if (s0_valid && s1_ready) begin
                // Advance to stage-1
                s0_valid <= 1'b0;
                s1_valid <= 1'b1;
                // Compose output packet based on stored stage-0 and current metadata
                s1_pkt.tech_id   <= TECH_ID[TECH_W-1:0];
                s1_pkt.bg_id     <= s0_pkt.bg_id;
                s1_pkt.ba_id     <= s0_pkt.ba_id;
                s1_pkt.sa_id     <= s0_pkt.sa_id;
                s1_pkt.row_id    <= s0_pkt.row_id;
                s1_pkt.col_id    <= s0_pkt.col_id;
                s1_pkt.prio      <= s0_pkt.prio;
                s1_pkt.timestamp <= s0_pkt.timestamp;
                // Command assignment gated by effective_match AND grant
                if (effective_match && grant_i) begin
                    s1_pkt.cmd_id       <= s0_custom_cmd_id[CMD_W-1:0];
                    s1_pkt.cmd_feedback <= s0_cmd_feedback;
                end else begin
                    // No match or not granted: pass-through original cmd
                    s1_pkt.cmd_id       <= s0_pkt.cmd_id;
                    s1_pkt.cmd_feedback <= '0;
                end
                // Register output packet
                pkt_o <= s1_pkt;
            end
        end
    end
endmodule
