`timescale 1ns/1ps
import terracotta_types_pkg::*;

module UpdateUnit #(
    parameter int CMD_W        = terracotta_types_pkg::TC_CMD_W,
    parameter int SA_W         = terracotta_types_pkg::TC_SA_W,
    parameter int ROW_W        = terracotta_types_pkg::TC_ROW_W,
    parameter int COL_W        = terracotta_types_pkg::TC_COL_W,
    parameter int METADATA_W   = terracotta_types_pkg::TC_METADATA_W,
    parameter int TS_W         = terracotta_types_pkg::TC_TS_W,
    parameter int CFG_W        = terracotta_types_pkg::TC_U_CFG_W,
    parameter int CFG_DEPTH    = terracotta_types_pkg::TC_U_CFG_DEPTH,
    parameter int TECH_W       = terracotta_types_pkg::TC_TECH_W,
    parameter int TECH_ID      = 0,
    parameter int BANK_W       = terracotta_types_pkg::TC_BANK_W
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // Two-stage pipeline handshake (input side)
    input  logic                   in_valid_i,
    output logic                   in_ready_o,

    // Packet input (struct; includes tech_id for array gating externally)
    input  update_in_t             pkt_i,

    // Metadata data arriving on cycle-1
    input  logic                   metadata_valid_i,
    input  logic [METADATA_W-1:0]  metadata_in_i,

    // Cycle-0 outputs (lookup to external metadata table)
    output logic                   metadata_tag_valid_o,
    output logic [ROW_W+COL_W+SA_W-1:0] metadata_tag_o,
    output logic [BANK_W-1:0]      rd_bank_id_o,
    output logic                   timer_reload_mask_valid_o,
    output logic [TS_W-1:0]        timer_reload_mask_o,

    // Cycle-1 outputs (updated metadata write intent)
    output logic                   metadata_out_valid_o,
    input  logic                   metadata_out_ready_i,
    output logic [METADATA_W-1:0]  metadata_out_o,
    output logic [ROW_W+COL_W+SA_W-1:0] wr_tag_o,
    output logic [BANK_W-1:0]      wr_bank_id_o,

    // Config write port (boot)
    input  logic                   cfg_wr_en_i,
    input  logic [CMD_W-1:0]       cfg_wr_key_i,
    input  logic [CFG_W-1:0]       cfg_wr_value_i
);
    // Config read keyed by cmd_id (combinational read)
    logic               cfg_rd_en;
    logic [CMD_W-1:0]   cfg_rd_key;
    logic [CFG_W-1:0]   cfg_rd_value;
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

    // Decode cfg fields
    localparam int TAG_USE_W = terracotta_types_pkg::TC_TAG_USE_W;
    localparam int UPDATE_LOGIC_W = terracotta_types_pkg::TC_UPDATE_LOGIC_W;

    localparam int OFF_TAG_USE      = 0;
    localparam int OFF_UPDATE_LOGIC = OFF_TAG_USE + TAG_USE_W;
    localparam int OFF_UPDATE_CONST = OFF_UPDATE_LOGIC + UPDATE_LOGIC_W;
    localparam int OFF_TIMER_MASK   = OFF_UPDATE_CONST + METADATA_W;

    wire [TAG_USE_W-1:0]       cfg_tag_use       = cfg_rd_value[OFF_TAG_USE + TAG_USE_W - 1 -: TAG_USE_W];
    wire [UPDATE_LOGIC_W-1:0]  cfg_update_logic  = cfg_rd_value[OFF_UPDATE_LOGIC + UPDATE_LOGIC_W - 1 -: UPDATE_LOGIC_W];
    wire [METADATA_W-1:0]      cfg_update_const  = cfg_rd_value[OFF_UPDATE_CONST + METADATA_W - 1 -: METADATA_W];
    wire [TS_W-1:0]            cfg_timer_mask    = cfg_rd_value[OFF_TIMER_MASK + TS_W - 1 -: TS_W];

    // Compute metadata tag combinationally in cycle-0 (fixed {sa,row,col} with enables)
    (* keep *) logic [SA_W-1:0]  sa_tag_src;
    (* keep *) logic [ROW_W-1:0] row_tag_src;
    (* keep *) logic [COL_W-1:0] col_tag_src;
    assign sa_tag_src  = pkt_i.sa_id;
    assign row_tag_src = pkt_i.row_id;
    assign col_tag_src = pkt_i.col_id;

    (* keep *) logic [SA_W-1:0]  sa_mask;
    (* keep *) logic [ROW_W-1:0] row_mask;
    (* keep *) logic [COL_W-1:0] col_mask;
    assign sa_mask  = {SA_W{cfg_tag_use[2]}};
    assign row_mask = {ROW_W{cfg_tag_use[1]}};
    assign col_mask = {COL_W{cfg_tag_use[0]}};

    (* keep *) logic [SA_W-1:0]  sa_masked;
    (* keep *) logic [ROW_W-1:0] row_masked;
    (* keep *) logic [COL_W-1:0] col_masked;
    assign sa_masked  = sa_tag_src  & sa_mask;
    assign row_masked = row_tag_src & row_mask;
    assign col_masked = col_tag_src & col_mask;

    // Pipeline registers
    logic                 s0_valid;
    update_in_t           s0_pkt;
    logic [UPDATE_LOGIC_W-1:0] s0_update_logic;
    logic [METADATA_W-1:0]     s0_update_const;
    logic [TS_W-1:0]           s0_timer_mask;
    logic [ROW_W+COL_W+SA_W-1:0] s0_tag;  // latched tag for writeback

    // Stage-1 control
    logic                 s1_valid;
    wire                  s1_ready = (~metadata_out_valid_o) | metadata_out_ready_i;
    wire                  s0_ready = s1_ready;

    assign in_ready_o             = s0_ready;
    assign metadata_tag_valid_o   = in_valid_i & s0_ready; // tag/mask emitted on cycle-0 accept
    assign timer_reload_mask_valid_o = in_valid_i & s0_ready;
    assign metadata_tag_o         = {sa_masked, row_masked, col_masked};
    assign timer_reload_mask_o    = cfg_timer_mask;
    assign rd_bank_id_o           = {pkt_i.bg_id, pkt_i.ba_id};

    // Writeback tag and bank_id from latched cycle-0 state
    assign wr_tag_o     = s0_tag;
    assign wr_bank_id_o = {s0_pkt.bg_id, s0_pkt.ba_id};

    logic [15:0] rng_value;
    LfsrRng u_rng (
        .clk_i(clk_i),
        .reset_i(reset_i),
        .rng_o(rng_value)
    );

    // metadata_out computation (cycle-1)
    logic [METADATA_W-1:0] updated_meta;
    always_comb begin
        unique case (s0_update_logic)
            2'b00: updated_meta = '0;                        // ZERO
            2'b01: updated_meta = metadata_in_i + 1'b1;      // INCR
            2'b10: updated_meta = s0_update_const;           // CONST ASSIGN
            2'b11: updated_meta = (rng_value >= s0_update_const[15:0]) ? 1'b1 : '0; // PROB SET
            default: updated_meta = metadata_in_i;            // PASS
        endcase
    end

    // Registers
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            s0_valid              <= 1'b0;
            s1_valid              <= 1'b0;
            metadata_out_valid_o  <= 1'b0;
            metadata_out_o        <= '0;
        end else begin
            // Stage-1 consume
            if (metadata_out_valid_o && metadata_out_ready_i) begin
                metadata_out_valid_o <= 1'b0;
                s1_valid             <= 1'b0;
            end

            // Stage-0 accept and capture cfg fields
            if (in_valid_i && s0_ready) begin
                s0_valid        <= 1'b1;
                s0_pkt          <= pkt_i;
                s0_update_logic <= cfg_update_logic;
                s0_update_const <= cfg_update_const;
                s0_timer_mask   <= cfg_timer_mask;
                s0_tag          <= {sa_masked, row_masked, col_masked};
            end else if (s0_valid && s1_ready && metadata_valid_i) begin
                // Advance to stage-1 when metadata is available
                s0_valid             <= 1'b0;
                s1_valid             <= 1'b1;
                metadata_out_valid_o <= 1'b1;
                metadata_out_o       <= updated_meta;
            end
        end
    end
endmodule
