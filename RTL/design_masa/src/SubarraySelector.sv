// SubarraySelector.sv — Per-bank subarray selection bitvector
//
// Maintains a one-hot bitvector (NUM_SA bits, one per subarray in a bank).
//   - SEL_SA: sets ONLY the addressed subarray bit; clears all others.
//   - Provides the currently-selected subarray ID as output.
//
// All outputs are combinational from registered state.
`timescale 1ns/1ps

module SubarraySelector #(
    parameter int NUM_SA  = 128,
    parameter int SA_W    = (NUM_SA > 1) ? $clog2(NUM_SA) : 1
) (
    input  logic                clk_i,
    input  logic                reset_i,

    // ── Selection control ───────────────────────────────────────────────
    input  logic                sel_en_i,       // pulse: new SEL_SA for this bank
    input  logic [SA_W-1:0]     sel_sa_id_i,    // subarray to select

    // ── Status outputs (combinational) ──────────────────────────────────
    output logic                any_selected_o, // at least one SA selected
    output logic [SA_W-1:0]     selected_sa_o,  // ID of the currently-selected SA
    output logic [NUM_SA-1:0]   sa_bitmask_o    // full bitvector
);

    // ────────────────────────────────────────────────────────────────────
    // Bitvector register
    // ────────────────────────────────────────────────────────────────────
    logic [NUM_SA-1:0] sa_vec_r;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            sa_vec_r <= '0;  // nothing selected after reset
        end else if (sel_en_i) begin
            // One-hot: set only the addressed subarray
            sa_vec_r <= NUM_SA'(1) << sel_sa_id_i;
        end
    end

    // ────────────────────────────────────────────────────────────────────
    // Output logic
    // ────────────────────────────────────────────────────────────────────
    assign sa_bitmask_o   = sa_vec_r;
    assign any_selected_o = |sa_vec_r;

    // Priority-encode the first (only) set bit back to an index.
    // Since the vector is always one-hot (or zero), this is exact.
    integer pi;
    always_comb begin
        selected_sa_o = '0;
        for (pi = NUM_SA - 1; pi >= 0; pi--) begin
            if (sa_vec_r[pi])
                selected_sa_o = SA_W'(pi);
        end
    end

endmodule
