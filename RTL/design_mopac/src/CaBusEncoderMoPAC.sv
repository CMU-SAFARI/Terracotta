// CaBusEncoderMoPAC.sv — 2-cycle C/A bus encoder for MoPAC's PRE_CU command
//
// When a PRE_CU is requested, drives two C/A-bus cycles:
//   Cycle 0: bits [4:0] = CA_CMD_PRE_CU (5-bit command ID)
//   Cycle 1: bit  [0]   = 1 (CU signal at the end)
//
// For standard commands the module stays idle (ca_valid_o = 0).
// Handshake: req_valid_i / req_ready_o for upstream.

module CaBusEncoderMoPAC
  import mopac_types_pkg::*;
(
  input  logic                       clk_i,
  input  logic                       rst_ni,

  // ── Request interface (from MoPACUnit) ────────────────────────────
  input  logic                       req_valid_i,   // new PRE_CU to encode
  output logic                       req_ready_o,   // back-pressure

  // ── C/A bus output ────────────────────────────────────────────────
  output logic                       ca_valid_o,    // C/A cycle is valid
  output logic [MOPAC_CA_BUS_W-1:0] ca_data_o      // 14-bit C/A frame
);

  // ─── FSM states ──────────────────────────────────────────────────────
  typedef enum logic [1:0] {
    S_IDLE   = 2'd0,
    S_CYCLE0 = 2'd1,
    S_CYCLE1 = 2'd2
  } state_e;

  state_e state_r, state_nxt;

  // ─── FSM next-state ──────────────────────────────────────────────────
  always_comb begin
    state_nxt = state_r;
    unique case (state_r)
      S_IDLE:   if (req_valid_i) state_nxt = S_CYCLE0;
      S_CYCLE0: state_nxt = S_CYCLE1;
      S_CYCLE1: state_nxt = S_IDLE;
      default:  state_nxt = S_IDLE;
    endcase
  end

  // ─── Registers ───────────────────────────────────────────────────────
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      state_r <= S_IDLE;
    else
      state_r <= state_nxt;
  end

  // ─── Outputs ─────────────────────────────────────────────────────────
  assign req_ready_o = (state_r == S_IDLE);

  always_comb begin
    ca_valid_o = 1'b0;
    ca_data_o  = '0;
    unique case (state_r)
      S_CYCLE0: begin
        ca_valid_o = 1'b1;
        ca_data_o[MOPAC_CA_CMD_W-1:0] = CA_CMD_PRE_CU;  // bits [4:0] = command ID
      end
      S_CYCLE1: begin
        ca_valid_o = 1'b1;
        ca_data_o[0] = 1'b1;  // CU signal bit at the end
      end
      default: ;
    endcase
  end

endmodule
