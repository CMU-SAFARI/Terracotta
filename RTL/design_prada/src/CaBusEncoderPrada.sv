// CaBusEncoderPrada.sv — C/A bus encoder for PRADA new commands
//
// When a PRADA-specific command (ACTocwl, ACTwls, ACTwl, NOT) is issued,
// this module drives two C/A-bus cycles:
//   Cycle 0: bits [4:0] = 5-bit command ID
//   Cycle 1: existing hardware (row addr etc.) — driven as zeros here
//
// For standard commands the module stays idle and the CA bus is not driven
// (ca_valid_o = 0 so downstream muxing can bypass).
//
// Handshake:  req_valid_i / req_ready_o  for upstream;
//             ca_valid_o / ca_data_o     for the physical C/A bus.

module CaBusEncoderPrada
  import prada_types_pkg::*;
(
  input  logic                     clk_i,
  input  logic                     rst_ni,

  // ── Request interface (from PRADAUnit) ────────────────────────────
  input  logic                     req_valid_i,    // new command to encode
  output logic                     req_ready_o,    // back-pressure
  input  logic [PRADA_CMD_W-1:0]  req_cmd_i,      // internal command code

  // ── C/A bus output ────────────────────────────────────────────────
  output logic                     ca_valid_o,     // C/A cycle is valid
  output logic [PRADA_CA_BUS_W-1:0] ca_data_o     // 14-bit C/A frame
);

  // ─── FSM states ──────────────────────────────────────────────────────
  typedef enum logic [1:0] {
    S_IDLE   = 2'd0,
    S_CYCLE0 = 2'd1,
    S_CYCLE1 = 2'd2
  } state_e;

  state_e state_r, state_nxt;
  logic [PRADA_CA_CMD_W-1:0] cmd_id_r;   // latched 5-bit CA command ID

  // ─── Determine if the incoming command is a PRADA-specific one ────────
  logic is_prada_cmd;
  assign is_prada_cmd = (req_cmd_i == CMD_ACTocwl) ||
                        (req_cmd_i == CMD_ACTwls)  ||
                        (req_cmd_i == CMD_ACTwl)   ||
                        (req_cmd_i == CMD_NOT);

  // ─── Map internal command code → 5-bit C/A command ID ────────────────
  logic [PRADA_CA_CMD_W-1:0] cmd_id_nxt;
  always_comb begin
    unique case (req_cmd_i)
      CMD_ACTocwl: cmd_id_nxt = CA_CMD_ACTocwl;
      CMD_ACTwls:  cmd_id_nxt = CA_CMD_ACTwls;
      CMD_ACTwl:   cmd_id_nxt = CA_CMD_ACTwl;
      CMD_NOT:     cmd_id_nxt = CA_CMD_NOT;
      default:     cmd_id_nxt = '0;
    endcase
  end

  // ─── FSM next-state ──────────────────────────────────────────────────
  always_comb begin
    state_nxt = state_r;
    unique case (state_r)
      S_IDLE: begin
        if (req_valid_i && is_prada_cmd)
          state_nxt = S_CYCLE0;
      end
      S_CYCLE0: state_nxt = S_CYCLE1;
      S_CYCLE1: state_nxt = S_IDLE;
      default:  state_nxt = S_IDLE;
    endcase
  end

  // ─── Registers ───────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_r  <= S_IDLE;
      cmd_id_r <= '0;
    end else begin
      state_r <= state_nxt;
      if (state_r == S_IDLE && req_valid_i && is_prada_cmd)
        cmd_id_r <= cmd_id_nxt;
    end
  end

  // ─── Outputs ─────────────────────────────────────────────────────────
  // Ready when idle (or when not a PRADA command — pass through immediately)
  assign req_ready_o = (state_r == S_IDLE);

  always_comb begin
    ca_valid_o = 1'b0;
    ca_data_o  = '0;
    unique case (state_r)
      S_CYCLE0: begin
        ca_valid_o = 1'b1;
        ca_data_o[PRADA_CA_CMD_W-1:0] = cmd_id_r;  // bits [4:0] = command ID
        // bits [13:5] = don't-care / existing HW
      end
      S_CYCLE1: begin
        ca_valid_o = 1'b1;
        // Entire cycle 1 is existing hardware — zeros as placeholder
        ca_data_o = '0;
      end
      default: ;
    endcase
  end

endmodule
