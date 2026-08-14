// PRADAUnit.sv — Top-level PRADA controller
//
// Integrates:
//   • BankStateTracker — 32-bank state machine (tracks Closed/Opened/
//       TwoOpened/ThreeOpened/Not per bank)
//   • CaBusEncoderPrada — 2-cycle C/A bus encoder for the 4 new commands
//
// Interface matches the pattern of other Terracotta designs:
//   - Single-cycle command input (cmd_valid_i, cmd_i, bank_group_i, bank_addr_i, row_addr_i)
//   - Registered outputs
//   - C/A bus output for the 4 new PRADA commands

module PRADAUnit
  import prada_types_pkg::*;
(
  input  logic                         clk_i,
  input  logic                         rst_ni,

  // ─── Incoming command ────────────────────────────────────────────────
  input  logic                         cmd_valid_i,
  input  logic [PRADA_CMD_W-1:0]       cmd_i,
  input  logic [PRADA_RANK_W-1:0]      rank_i,
  input  logic [PRADA_BG_W-1:0]        bank_group_i,
  input  logic [PRADA_BA_W-1:0]        bank_addr_i,
  input  logic [PRADA_ROW_W-1:0]       row_addr_i,

  // ─── Ready / stall ──────────────────────────────────────────────────
  output logic                         ready_o,

  // ─── C/A bus output (active for PRADA-specific commands) ─────────────
  output logic                         ca_valid_o,
  output logic [PRADA_CA_BUS_W-1:0]    ca_data_o,

  // ─── Per-bank state vector ───────────────────────────────────────────
  output prada_bank_state_e            bank_state_o [PRADA_NUM_BANKS],
  output logic [PRADA_NUM_BANKS-1:0]   bank_busy_o,

  // ─── Pass-through for standard commands ──────────────────────────────
  output logic                         std_cmd_valid_o,
  output logic [PRADA_CMD_W-1:0]       std_cmd_o,
  output logic [PRADA_RANK_W-1:0]      std_rank_o,
  output logic [PRADA_BG_W-1:0]        std_bank_group_o,
  output logic [PRADA_BA_W-1:0]        std_bank_addr_o,
  output logic [PRADA_ROW_W-1:0]       std_row_addr_o
);

  // ─── Derive flat bank index ──────────────────────────────────────────
  logic [PRADA_BANK_IDX_W-1:0] bank_idx;
  assign bank_idx = {bank_group_i, bank_addr_i};

  // ─── Classify command ────────────────────────────────────────────────
  logic is_prada_cmd;
  assign is_prada_cmd = (cmd_i == CMD_ACTocwl) ||
                        (cmd_i == CMD_ACTwls)  ||
                        (cmd_i == CMD_ACTwl)   ||
                        (cmd_i == CMD_NOT);

  // ─── C/A bus encoder ─────────────────────────────────────────────────
  logic ca_enc_ready;

  CaBusEncoderPrada u_ca_enc (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .req_valid_i (cmd_valid_i & is_prada_cmd),
    .req_ready_o (ca_enc_ready),
    .req_cmd_i   (cmd_i),
    .ca_valid_o  (ca_valid_o),
    .ca_data_o   (ca_data_o)
  );

  // ─── Ready: stall when C/A encoder is busy ──────────────────────────
  assign ready_o = ca_enc_ready;

  // ─── Bank state tracker ──────────────────────────────────────────────
  // Feed commands to the state tracker only when accepted
  logic cmd_accepted;
  assign cmd_accepted = cmd_valid_i & ready_o;

  BankStateTracker u_bank_state (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .cmd_valid_i(cmd_accepted),
    .cmd_i      (cmd_i),
    .bank_idx_i (bank_idx),
    .bank_state_o(bank_state_o),
    .bank_busy_o (bank_busy_o)
  );

  // ─── Standard command pass-through (registered) ──────────────────────
  logic std_valid_r;
  logic [PRADA_CMD_W-1:0]  std_cmd_r;
  logic [PRADA_RANK_W-1:0] std_rank_r;
  logic [PRADA_BG_W-1:0]   std_bg_r;
  logic [PRADA_BA_W-1:0]   std_ba_r;
  logic [PRADA_ROW_W-1:0]  std_row_r;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      std_valid_r <= 1'b0;
      std_cmd_r   <= '0;
      std_rank_r  <= '0;
      std_bg_r    <= '0;
      std_ba_r    <= '0;
      std_row_r   <= '0;
    end else begin
      if (cmd_accepted && !is_prada_cmd) begin
        std_valid_r <= 1'b1;
        std_cmd_r   <= cmd_i;
        std_rank_r  <= rank_i;
        std_bg_r    <= bank_group_i;
        std_ba_r    <= bank_addr_i;
        std_row_r   <= row_addr_i;
      end else begin
        std_valid_r <= 1'b0;
      end
    end
  end

  assign std_cmd_valid_o  = std_valid_r;
  assign std_cmd_o        = std_cmd_r;
  assign std_rank_o       = std_rank_r;
  assign std_bank_group_o = std_bg_r;
  assign std_bank_addr_o  = std_ba_r;
  assign std_row_addr_o   = std_row_r;

endmodule
