// BankStateTracker.sv — Per-bank state machine for PRADA operations
//
// Tracks the state of each of 32 banks through PRADA's multi-step operations.
// State transitions match the DDR5-PRADA.cpp model:
//
//   Closed ──ACT/ACTocwl──► Opened ──ACTwl/ACTwls──► TwoOpened ──ACTwl/ACTwls──► ThreeOpened
//                           Opened ──NOT──────────► Not
//                           ThreeOpened ──NOT─────► Not
//                           Any ──PRE/PREA────────► Closed
//
// Outputs a per-bank state vector and a flag indicating if the bank is busy
// (i.e., in a multi-step PRADA operation and not Closed).

module BankStateTracker
  import prada_types_pkg::*;
(
  input  logic                     clk_i,
  input  logic                     rst_ni,

  // Command interface
  input  logic                     cmd_valid_i,
  input  logic [PRADA_CMD_W-1:0]  cmd_i,
  input  logic [PRADA_BANK_IDX_W-1:0] bank_idx_i,  // flat bank index (BG*4 + BA)

  // State outputs (one state per bank)
  output prada_bank_state_e        bank_state_o [PRADA_NUM_BANKS],
  output logic [PRADA_NUM_BANKS-1:0] bank_busy_o   // 1 if bank is not Closed
);

  // ─── State registers ─────────────────────────────────────────────────
  prada_bank_state_e bank_state_r [PRADA_NUM_BANKS];

  // ─── Combinational next-state logic ──────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < PRADA_NUM_BANKS; i++) begin
        bank_state_r[i] <= BS_CLOSED;
      end
    end else if (cmd_valid_i) begin
      unique case (cmd_i)
        // ── ACT / ACTocwl: Closed → Opened ──────────────────────────
        CMD_ACT, CMD_ACTocwl: begin
          if (bank_state_r[bank_idx_i] == BS_CLOSED) begin
            bank_state_r[bank_idx_i] <= BS_OPENED;
          end
        end

        // ── ACTwl: Opened → TwoOpened, TwoOpened → ThreeOpened ──────
        CMD_ACTwl: begin
          if (bank_state_r[bank_idx_i] == BS_OPENED) begin
            bank_state_r[bank_idx_i] <= BS_TWO_OPENED;
          end else if (bank_state_r[bank_idx_i] == BS_TWO_OPENED) begin
            bank_state_r[bank_idx_i] <= BS_THREE_OPENED;
          end
        end

        // ── ACTwls: Opened → TwoOpened, TwoOpened → ThreeOpened ─────
        CMD_ACTwls: begin
          if (bank_state_r[bank_idx_i] == BS_OPENED) begin
            bank_state_r[bank_idx_i] <= BS_TWO_OPENED;
          end else if (bank_state_r[bank_idx_i] == BS_TWO_OPENED) begin
            bank_state_r[bank_idx_i] <= BS_THREE_OPENED;
          end
        end

        // ── NOT: Opened/ThreeOpened → Not ───────────────────────────
        CMD_NOT: begin
          if (bank_state_r[bank_idx_i] == BS_OPENED ||
              bank_state_r[bank_idx_i] == BS_THREE_OPENED) begin
            bank_state_r[bank_idx_i] <= BS_NOT;
          end
        end

        // ── PRE: Any → Closed (single bank) ────────────────────────
        CMD_PRE: begin
          bank_state_r[bank_idx_i] <= BS_CLOSED;
        end

        // ── PREA: All banks → Closed ───────────────────────────────
        CMD_PREA: begin
          for (int i = 0; i < PRADA_NUM_BANKS; i++) begin
            bank_state_r[i] <= BS_CLOSED;
          end
        end

        default: ; // Standard RD/WR/REF etc. — no state change
      endcase
    end
  end

  // ─── Output assignments ──────────────────────────────────────────────
  always_comb begin
    for (int i = 0; i < PRADA_NUM_BANKS; i++) begin
      bank_state_o[i] = bank_state_r[i];
      bank_busy_o[i]  = (bank_state_r[i] != BS_CLOSED);
    end
  end

endmodule
