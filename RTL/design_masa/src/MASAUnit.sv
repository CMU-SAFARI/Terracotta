// MASAUnit.sv — Top-level MASA (Multitude of Activated SubArrays) controller
//
// Architecture:
//   - Subarray-aware DRAM controller extension.
//   - 32 banks, each with 128 subarrays (SA_W = 7).
//   - Per-bank SubarraySelector maintains a one-hot bitvector of the
//     currently-selected subarray.
//   - SEL_SA: selects a subarray within a bank (sets one bit, clears rest).
//   - PRE_SA: precharges a specific subarray.
//   - CaBusEncoder constructs 2-cycle 14-bit C/A bus frames for SEL_SA / PRE_SA.
//   - Handles standard ACT / PRE / RD / WR pass-through with subarray context.
//   - Single-cycle command processing for ACT / SEL_SA / PRE_SA.
//   - Registered outputs.
//
`timescale 1ns/1ps
import masa_types_pkg::*;

module MASAUnit #(
    parameter int CMD_W         = masa_types_pkg::MASA_CMD_W,
    parameter int RANK_W        = masa_types_pkg::MASA_RANK_W,
    parameter int BG_W          = masa_types_pkg::MASA_BG_W,
    parameter int BA_W          = masa_types_pkg::MASA_BA_W,
    parameter int ROW_W         = masa_types_pkg::MASA_ROW_W,
    parameter int SA_W          = masa_types_pkg::MASA_SA_W,
    parameter int NUM_SA        = masa_types_pkg::MASA_NUM_SA_PER_BANK,
    parameter int NUM_BANKS     = masa_types_pkg::MASA_NUM_BANKS,
    parameter int BANK_IDX_W    = masa_types_pkg::MASA_BANK_IDX_W,
    parameter int CA_BUS_W      = masa_types_pkg::MASA_CA_BUS_W,
    parameter int CA_CMD_W      = masa_types_pkg::MASA_CA_CMD_W,
    parameter int RELOAD_MASK_W = masa_types_pkg::MASA_RELOAD_MASK_W
) (
    input  logic                     clk_i,
    input  logic                     reset_i,

    // ── Input handshake ─────────────────────────────────────────────────
    input  logic                     in_valid_i,
    output logic                     in_ready_o,

    // ── Command & address ───────────────────────────────────────────────
    input  logic [CMD_W-1:0]         cmd_i,
    input  logic [RANK_W-1:0]        rank_i,
    input  logic [BG_W-1:0]          bg_i,
    input  logic [BA_W-1:0]          ba_i,
    input  logic [SA_W-1:0]          sa_i,       // subarray address
    input  logic [ROW_W-1:0]         row_i,      // row within subarray

    // ── C/A bus output (for SEL_SA / PRE_SA two-cycle frames) ───────────
    output logic                     ca_valid_o,
    output logic [CA_BUS_W-1:0]      ca_data_o,

    // ── Output handshake ────────────────────────────────────────────────
    output logic                     out_valid_o,
    input  logic                     out_ready_i,

    // ── Results ─────────────────────────────────────────────────────────
    output logic [CMD_W-1:0]         out_cmd_o,
    output logic [RANK_W-1:0]        out_rank_o,
    output logic [BG_W-1:0]          out_bg_o,
    output logic [BA_W-1:0]          out_ba_o,
    output logic [SA_W-1:0]          out_sa_o,
    output logic [ROW_W-1:0]         out_row_o,
    output logic                     sa_switch_o,   // SEL_SA changed the active SA
    output logic [NUM_SA-1:0]        sa_bitmask_o   // current SA selection for debug
);

    // ════════════════════════════════════════════════════════════════════
    // Flat bank index
    // ════════════════════════════════════════════════════════════════════
    wire [BANK_IDX_W-1:0] bank_idx = {bg_i, ba_i};

    // ════════════════════════════════════════════════════════════════════
    // Command decode
    // ════════════════════════════════════════════════════════════════════
    wire is_act    = (cmd_i == masa_types_pkg::CMD_ACT);
    wire is_pre    = (cmd_i == masa_types_pkg::CMD_PRE)
                   | (cmd_i == masa_types_pkg::CMD_RDA)
                   | (cmd_i == masa_types_pkg::CMD_WRA);
    wire is_sel_sa = (cmd_i == masa_types_pkg::CMD_SEL_SA);
    wire is_pre_sa = (cmd_i == masa_types_pkg::CMD_PRE_SA);
    wire is_rd     = (cmd_i == masa_types_pkg::CMD_RD);
    wire is_wr     = (cmd_i == masa_types_pkg::CMD_WR);

    // Need C/A bus encoding?
    wire needs_ca_encode = is_sel_sa | is_pre_sa;

    // ════════════════════════════════════════════════════════════════════
    // SubarraySelector instances (one per bank)
    // ════════════════════════════════════════════════════════════════════
    logic [NUM_BANKS-1:0]              bank_any_selected;
    logic [SA_W-1:0]                   bank_selected_sa   [0:NUM_BANKS-1];
    logic [NUM_SA-1:0]                 bank_sa_bitmask    [0:NUM_BANKS-1];

    // Forward-declare flow-control
    wire s0_accept;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_BANKS; gi++) begin : gen_sa_sel

            // SEL_SA enable: only when writing to this bank
            wire this_sel_en = in_valid_i & s0_accept & is_sel_sa
                             & (bank_idx == BANK_IDX_W'(gi));

            SubarraySelector #(
                .NUM_SA (NUM_SA),
                .SA_W   (SA_W)
            ) u_sa_sel (
                .clk_i          (clk_i),
                .reset_i        (reset_i),
                .sel_en_i       (this_sel_en),
                .sel_sa_id_i    (sa_i),
                .any_selected_o (bank_any_selected[gi]),
                .selected_sa_o  (bank_selected_sa[gi]),
                .sa_bitmask_o   (bank_sa_bitmask[gi])
            );
        end
    endgenerate

    // Current bank's selected SA info
    wire               cur_any_selected = bank_any_selected[bank_idx];
    wire [SA_W-1:0]    cur_selected_sa  = bank_selected_sa[bank_idx];
    wire [NUM_SA-1:0]  cur_sa_bitmask   = bank_sa_bitmask[bank_idx];

    // Detect SA switch: SEL_SA and the new SA differs from current
    wire sa_switching = is_sel_sa & cur_any_selected & (sa_i != cur_selected_sa);

    // ════════════════════════════════════════════════════════════════════
    // CaBusEncoder — constructs 2-cycle C/A frames for SEL_SA / PRE_SA
    // ════════════════════════════════════════════════════════════════════
    logic              ca_enc_req_valid;
    logic              ca_enc_req_ready;
    logic [CA_CMD_W-1:0] ca_enc_cmd;
    logic [SA_W-1:0]   ca_enc_sa;

    CaBusEncoder #(
        .CA_BUS_W (CA_BUS_W),
        .CA_CMD_W (CA_CMD_W),
        .SA_W     (SA_W)
    ) u_ca_enc (
        .clk_i         (clk_i),
        .reset_i       (reset_i),
        .req_valid_i   (ca_enc_req_valid),
        .req_ready_o   (ca_enc_req_ready),
        .req_cmd_id_i  (ca_enc_cmd),
        .req_sa_id_i   (ca_enc_sa),
        .ca_valid_o    (ca_valid_o),
        .ca_data_o     (ca_data_o)
    );

    // Feed the encoder when we accept a SEL_SA or PRE_SA
    assign ca_enc_req_valid = in_valid_i & s0_accept & needs_ca_encode;
    assign ca_enc_cmd       = is_sel_sa ? masa_types_pkg::CA_CMD_SEL_SA
                                        : masa_types_pkg::CA_CMD_PRE_SA;
    assign ca_enc_sa        = sa_i;

    // ════════════════════════════════════════════════════════════════════
    // Flow control
    //   Stall when: C/A encoder is busy, or output not consumed
    // ════════════════════════════════════════════════════════════════════
    wire output_ok = ~out_valid_o | out_ready_i;
    wire ca_ok     = needs_ca_encode ? ca_enc_req_ready : 1'b1;
    assign s0_accept  = output_ok & ca_ok;
    assign in_ready_o = s0_accept;

    // ════════════════════════════════════════════════════════════════════
    // Output pipeline (1-stage registered)
    // ════════════════════════════════════════════════════════════════════
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            out_valid_o  <= 1'b0;
            out_cmd_o    <= '0;
            out_rank_o   <= '0;
            out_bg_o     <= '0;
            out_ba_o     <= '0;
            out_sa_o     <= '0;
            out_row_o    <= '0;
            sa_switch_o  <= 1'b0;
            sa_bitmask_o <= '0;
        end else begin
            // Consume output
            if (out_valid_o && out_ready_i)
                out_valid_o <= 1'b0;

            // Accept new command
            if (in_valid_i && s0_accept) begin
                out_valid_o  <= 1'b1;
                out_cmd_o    <= cmd_i;
                out_rank_o   <= rank_i;
                out_bg_o     <= bg_i;
                out_ba_o     <= ba_i;
                out_sa_o     <= sa_i;
                out_row_o    <= row_i;
                sa_switch_o  <= sa_switching;
                sa_bitmask_o <= cur_sa_bitmask;
            end
        end
    end

endmodule
