`timescale 1ns/1ps
import terracotta_types_pkg::*;

module ActionUnit #(
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
    parameter int PAYLOAD_DEPTH    = terracotta_types_pkg::TC_A_PAYLOAD_DEPTH
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // Handshake (packet level): accept only when not busy
    input  logic                   in_valid_i,
    output logic                   in_ready_o,

    // Packet input
    input  action_in_t             pkt_i,

    // Wave output (header then payload entries): 15-bit packed format
    output logic                   out_valid_o,
    input  logic                   out_ready_i,
    output action_wave_t           wave_o,

    // Action config write (key=cmd_id)
    input  logic                   cfg_wr_en_i,
    input  logic [CMD_W-1:0]       cfg_wr_key_i,
    input  logic [CFG_W-1:0]       cfg_wr_value_i,

    // Payload table write (key=payload index)
    input  logic                   payload_wr_en_i,
    input  logic [terracotta_types_pkg::TC_PAYLOAD_IDX_W-1:0] payload_wr_key_i,
    input  logic [PAYLOAD_W-1:0]   payload_wr_value_i
);
    // Config read (combinational) on accept
    logic                 cfg_rd_en;
    logic [CMD_W-1:0]     cfg_rd_key;
    logic [CFG_W-1:0]     cfg_rd_value;
    assign cfg_rd_en  = in_valid_i & in_ready_o;
    assign cfg_rd_key = pkt_i.cmd_id;

    ConfigTable #(
        .KEY_W(CMD_W),
        .CFG_W(CFG_W),
        .DEPTH(CFG_DEPTH)
    ) u_cfg (
        .clk_i(clk_i), .reset_i(reset_i),
        .rd_en_i(cfg_rd_en), .rd_key_i(cfg_rd_key), .rd_value_o(cfg_rd_value), .rd_hit_o(),
        .wr_en_i(cfg_wr_en_i), .wr_key_i(cfg_wr_key_i), .wr_value_i(cfg_wr_value_i)
    );

    // Decode cfg: payload_idx and payload_range
    localparam int PAYLOAD_IDX_W   = terracotta_types_pkg::TC_PAYLOAD_IDX_W;
    localparam int PAYLOAD_RANGE_W = terracotta_types_pkg::TC_PAYLOAD_RANGE_W;
    localparam int OFF_PAYLOAD_IDX = 0;
    localparam int OFF_PAYLOAD_RANGE = OFF_PAYLOAD_IDX + PAYLOAD_IDX_W;
    wire [PAYLOAD_IDX_W-1:0]   cfg_payload_idx   = cfg_rd_value[OFF_PAYLOAD_IDX + PAYLOAD_IDX_W - 1 -: PAYLOAD_IDX_W];
    wire [PAYLOAD_RANGE_W-1:0] cfg_payload_range = cfg_rd_value[OFF_PAYLOAD_RANGE + PAYLOAD_RANGE_W - 1 -: PAYLOAD_RANGE_W];

    // Payload table (combinational read) indexed by current entry
    logic                                     p_rd_en;
    logic [PAYLOAD_IDX_W-1:0]                 p_rd_key;
    logic [PAYLOAD_W-1:0]                     p_rd_value;
    ConfigTable #(
        .KEY_W(PAYLOAD_IDX_W),
        .CFG_W(PAYLOAD_W),
        .DEPTH(PAYLOAD_DEPTH)
    ) u_payload (
        .clk_i(clk_i), .reset_i(reset_i),
        .rd_en_i(p_rd_en), .rd_key_i(p_rd_key), .rd_value_o(p_rd_value), .rd_hit_o(),
        .wr_en_i(payload_wr_en_i), .wr_key_i(payload_wr_key_i), .wr_value_i(payload_wr_value_i)
    );

    // Decode payload entry
    localparam int OFF_REG_ID   = 0;
    localparam int OFF_OPER_SEL = OFF_REG_ID + REG_ID_W;
    wire [REG_ID_W-1:0]   p_reg_id   = p_rd_value[OFF_REG_ID + REG_ID_W - 1 -: REG_ID_W];
    wire [OPER_SEL_W-1:0] p_operand_sel = p_rd_value[OFF_OPER_SEL + OPER_SEL_W - 1 -: OPER_SEL_W];

    // Operand mux from packet fields (zero-extended to ACTION_PARAM_W)
    logic [ACTION_PARAM_W-1:0] operand_mux;
    always_comb begin
        unique case (p_operand_sel)
            2'd0:  operand_mux = {{(ACTION_PARAM_W-SA_W){1'b0}},  pkt_i.sa_id};
            2'd1:  operand_mux = {{(ACTION_PARAM_W-ROW_W){1'b0}}, pkt_i.row_id};
            2'd2:  operand_mux = {{(ACTION_PARAM_W-COL_W){1'b0}}, pkt_i.col_id};
            default: operand_mux = '0;
        endcase
    end

    // FSM: emit header (1 cycle) then payload_range entries; busy until done
    typedef enum logic [1:0] {S_IDLE, S_HDR, S_PAYLOAD} state_e;
    state_e state_q, state_d;
    logic [PAYLOAD_RANGE_W-1:0] count_q, count_d;
    logic [PAYLOAD_IDX_W-1:0]   base_idx_q;

    // Packet latch
    action_in_t s_pkt_q;

    // Control
    assign in_ready_o = (state_q == S_IDLE) & ((~out_valid_o) | out_ready_i);
    assign p_rd_en    = (state_q == S_PAYLOAD);
    assign p_rd_key   = base_idx_q + count_q;

    // Wave composition: 15-bit packed format
    // MSB [14] = 1; F flag [13] = 1 for final payload wave
    logic [TC_WAVE_W-1:0] hdr_word, payload_word;
    always_comb begin
        // Declare local packed fields first (tools require declarations before statements)
        logic [7:0] cmd8;
        logic [2:0] bg3;
        logic [1:0] ba2;
        logic [3:0] reg4;
        logic [8:0] op9;

        // Compute header fields (LSBs truncated/zero-extended to target widths)
        cmd8 = { {(8-terracotta_types_pkg::TC_CMD_W){1'b0}}, s_pkt_q.cmd_id[terracotta_types_pkg::TC_CMD_W-1:0] };
        bg3  = s_pkt_q.bg_id[2:0];
        ba2  = s_pkt_q.ba_id[1:0];

        hdr_word = '0;
        hdr_word[14]    = 1'b1;
        hdr_word[13]    = 1'b0; // header
        hdr_word[12:5]  = cmd8;
        hdr_word[4:2]   = bg3;
        hdr_word[1:0]   = ba2;

        // Payload fields
        reg4 = { {(4-terracotta_types_pkg::TC_REG_ID_W){1'b0}}, p_reg_id[terracotta_types_pkg::TC_REG_ID_W-1:0] };
        op9  = operand_mux[8:0];
        payload_word = '0;
        payload_word[14]   = 1'b1;
        payload_word[13]   = (count_q + 1 >= cfg_payload_range) ? 1'b1 : 1'b0; // final payload indicator
        payload_word[12:9] = reg4;
        payload_word[8:0]  = op9;

        // Select wave based on state
        unique case (state_q)
            S_HDR:     wave_o = hdr_word;
            S_PAYLOAD: wave_o = payload_word;
            default:   wave_o = '0;
        endcase
    end

    // Next-state logic
    always_comb begin
        state_d   = state_q;
        count_d   = count_q;
        out_valid_o = 1'b0;
        if (state_q == S_IDLE) begin
            if (in_valid_i && in_ready_o) begin
                state_d   = S_HDR;
            end
        end else if (state_q == S_HDR) begin
            out_valid_o = 1'b1;
            if (out_ready_i) begin
                if (cfg_payload_range != 0) begin
                    state_d = S_PAYLOAD;
                    count_d = '0;
                end else begin
                    state_d = S_IDLE;
                end
            end
        end else if (state_q == S_PAYLOAD) begin
            out_valid_o = 1'b1;
            if (out_ready_i) begin
                if (count_q + 1 < cfg_payload_range) begin
                    count_d = count_q + 1;
                end else begin
                    state_d = S_IDLE;
                end
            end
        end
    end

    // Registers
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_q    <= S_IDLE;
            count_q    <= '0;
            base_idx_q <= '0;
            s_pkt_q    <= '0;
        end else begin
            state_q <= state_d;
            count_q <= count_d;
            if (in_valid_i && in_ready_o) begin
                s_pkt_q    <= pkt_i;
                base_idx_q <= cfg_payload_idx;
            end
        end
    end
endmodule
