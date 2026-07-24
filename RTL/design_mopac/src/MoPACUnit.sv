// MoPACUnit.sv — Top-level MoPAC controller
//
// MoPAC (Monitoring with Probabilistic ACT Counting):
//   • 16-bit LFSR RNG compared against a hardcoded threshold register
//   • 32-bit bank bitvector (one bit per bank)
//   • On ACT: if rng >= threshold, set the bit for the addressed bank
//   • On PRE: if the bank's bit is set → issue PRE_CU (2-cycle C/A encoding),
//             then clear the bit.  The bit is always cleared on PRE.
//   • On PREA: clear all bits in the vector.

module MoPACUnit
  import mopac_types_pkg::*;
(
  input  logic                         clk_i,
  input  logic                         rst_ni,

  // ─── Incoming command ────────────────────────────────────────────────
  input  logic                         cmd_valid_i,
  input  logic [MOPAC_CMD_W-1:0]       cmd_i,
  input  logic [MOPAC_RANK_W-1:0]      rank_i,
  input  logic [MOPAC_BG_W-1:0]        bank_group_i,
  input  logic [MOPAC_BA_W-1:0]        bank_addr_i,
  input  logic [MOPAC_ROW_W-1:0]       row_addr_i,

  // ─── Threshold configuration ─────────────────────────────────────────
  input  logic [MOPAC_THRESH_W-1:0]    threshold_i,

  // ─── Ready / stall ──────────────────────────────────────────────────
  output logic                         ready_o,

  // ─── C/A bus output (active for PRE_CU) ──────────────────────────────
  output logic                         ca_valid_o,
  output logic [MOPAC_CA_BUS_W-1:0]    ca_data_o,

  // ─── Bank CU bitvector (observable) ──────────────────────────────────
  output logic [MOPAC_NUM_BANKS-1:0]   bank_cu_vec_o,

  // ─── Pass-through for standard commands ──────────────────────────────
  output logic                         std_cmd_valid_o,
  output logic [MOPAC_CMD_W-1:0]       std_cmd_o,
  output logic [MOPAC_RANK_W-1:0]      std_rank_o,
  output logic [MOPAC_BG_W-1:0]        std_bank_group_o,
  output logic [MOPAC_BA_W-1:0]        std_bank_addr_o,
  output logic [MOPAC_ROW_W-1:0]       std_row_addr_o
);

  // ─── Derive flat bank index ──────────────────────────────────────────
  logic [MOPAC_BANK_IDX_W-1:0] bank_idx;
  assign bank_idx = {bank_group_i, bank_addr_i};

  // ─── LFSR RNG ────────────────────────────────────────────────────────
  logic [MOPAC_RNG_W-1:0] rng_value;

  LfsrRng u_rng (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .rng_o  (rng_value)
  );

  // ─── Bank CU bitvector register ──────────────────────────────────────
  logic [MOPAC_NUM_BANKS-1:0] bank_cu_vec_r;

  // ─── C/A bus encoder for PRE_CU ──────────────────────────────────────
  logic ca_enc_ready;
  logic ca_enc_req_valid;

  CaBusEncoderMoPAC u_ca_enc (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .req_valid_i (ca_enc_req_valid),
    .req_ready_o (ca_enc_ready),
    .ca_valid_o  (ca_valid_o),
    .ca_data_o   (ca_data_o)
  );

  // ─── Command classification ──────────────────────────────────────────
  logic is_act, is_pre, is_prea;
  assign is_act  = (cmd_i == CMD_ACT);
  assign is_pre  = (cmd_i == CMD_PRE);
  assign is_prea = (cmd_i == CMD_PREA);

  // ─── Threshold comparison ────────────────────────────────────────────
  logic rng_exceeds_threshold;
  assign rng_exceeds_threshold = (rng_value >= threshold_i);

  // ─── PRE → PRE_CU promotion ─────────────────────────────────────────
  // A PRE is promoted to PRE_CU when the bank's bit is set.
  logic pre_promoted;
  assign pre_promoted = is_pre & bank_cu_vec_r[bank_idx];

  // ─── Ready: stall when C/A encoder is busy ──────────────────────────
  assign ready_o = ca_enc_ready;

  // ─── Command accepted this cycle ─────────────────────────────────────
  logic cmd_accepted;
  assign cmd_accepted = cmd_valid_i & ready_o;

  // ─── Fire PRE_CU into C/A encoder ───────────────────────────────────
  assign ca_enc_req_valid = cmd_accepted & pre_promoted;

  // ─── Bank CU bitvector update ────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bank_cu_vec_r <= '0;
    end else if (cmd_accepted) begin
      if (is_prea) begin
        // PREA: clear all bits
        bank_cu_vec_r <= '0;
      end else if (is_pre) begin
        // PRE: always clear the addressed bank's bit
        bank_cu_vec_r[bank_idx] <= 1'b0;
      end else if (is_act) begin
        // ACT: set bit if RNG >= threshold
        if (rng_exceeds_threshold)
          bank_cu_vec_r[bank_idx] <= 1'b1;
      end
    end
  end

  // ─── Standard command pass-through (registered) ──────────────────────
  // Pass through all commands except when a PRE is promoted to PRE_CU
  // (the PRE_CU is handled by the C/A encoder instead).
  logic std_valid_r;
  logic [MOPAC_CMD_W-1:0]  std_cmd_r;
  logic [MOPAC_RANK_W-1:0] std_rank_r;
  logic [MOPAC_BG_W-1:0]   std_bg_r;
  logic [MOPAC_BA_W-1:0]   std_ba_r;
  logic [MOPAC_ROW_W-1:0]  std_row_r;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      std_valid_r <= 1'b0;
      std_cmd_r   <= '0;
      std_rank_r  <= '0;
      std_bg_r    <= '0;
      std_ba_r    <= '0;
      std_row_r   <= '0;
    end else begin
      if (cmd_accepted && !pre_promoted) begin
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

  // ─── Observable output ───────────────────────────────────────────────
  assign bank_cu_vec_o = bank_cu_vec_r;

endmodule
