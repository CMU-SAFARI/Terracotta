// CaBusEncoder.sv — C/A bus command encoder for SEL_SA and PRE_SA
//
// Constructs the two-cycle 14-bit C/A bus frames:
//   Cycle 0:  [4:0] = command ID,  [13:5] = reserved / assumed logic
//   Cycle 1:  [SA_W-1:0] = subarray ID,  upper bits = 0
//
// A request pulse triggers a 2-cycle transmission.
// During transmission the encoder is busy (not accepting new requests).
`timescale 1ns/1ps

module CaBusEncoder #(
    parameter int CA_BUS_W = 14,
    parameter int CA_CMD_W = 5,
    parameter int SA_W     = 7
) (
    input  logic                clk_i,
    input  logic                reset_i,

    // ── Request interface ───────────────────────────────────────────────
    input  logic                req_valid_i,      // pulse to start a 2-cycle send
    output logic                req_ready_o,      // high when idle
    input  logic [CA_CMD_W-1:0] req_cmd_id_i,     // CA_CMD_SEL_SA or CA_CMD_PRE_SA
    input  logic [SA_W-1:0]     req_sa_id_i,      // subarray ID to encode

    // ── C/A bus output ──────────────────────────────────────────────────
    output logic                ca_valid_o,        // frame valid this cycle
    output logic [CA_BUS_W-1:0] ca_data_o          // 14-bit frame
);

    // ────────────────────────────────────────────────────────────────────
    // FSM: IDLE → CYCLE0 → CYCLE1 → IDLE
    // ────────────────────────────────────────────────────────────────────
    typedef enum logic [1:0] {
        ST_IDLE   = 2'd0,
        ST_CYCLE0 = 2'd1,
        ST_CYCLE1 = 2'd2
    } state_t;

    state_t state_r;
    logic [CA_CMD_W-1:0] cmd_r;
    logic [SA_W-1:0]     sa_r;

    assign req_ready_o = (state_r == ST_IDLE);

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state_r <= ST_IDLE;
            cmd_r   <= '0;
            sa_r    <= '0;
        end else begin
            case (state_r)
                ST_IDLE: begin
                    if (req_valid_i) begin
                        state_r <= ST_CYCLE0;
                        cmd_r   <= req_cmd_id_i;
                        sa_r    <= req_sa_id_i;
                    end
                end
                ST_CYCLE0: begin
                    state_r <= ST_CYCLE1;
                end
                ST_CYCLE1: begin
                    state_r <= ST_IDLE;
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end

    // ────────────────────────────────────────────────────────────────────
    // C/A bus frame construction
    // ────────────────────────────────────────────────────────────────────
    always_comb begin
        ca_valid_o = 1'b0;
        ca_data_o  = '0;

        case (state_r)
            ST_CYCLE0: begin
                ca_valid_o = 1'b1;
                // Cycle 0: bits [4:0] = command ID, upper bits zeroed (assumed logic)
                ca_data_o  = '0;
                ca_data_o[CA_CMD_W-1:0] = cmd_r;
            end
            ST_CYCLE1: begin
                ca_valid_o = 1'b1;
                // Cycle 1: LSB bits = subarray ID
                ca_data_o  = '0;
                ca_data_o[SA_W-1:0] = sa_r;
            end
            default: begin
                ca_valid_o = 1'b0;
                ca_data_o  = '0;
            end
        endcase
    end

endmodule
