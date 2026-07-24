// LfsrRng.sv — 16-bit Galois LFSR pseudo-random number generator
//
// Maximal-length 16-bit LFSR using polynomial x^16 + x^15 + x^13 + x^4 + 1.
// Tap positions (from MSB, 1-indexed): 16, 15, 13, 4.
// Advances every clock cycle. Output is the full 16-bit register value.
// Non-zero seed ensures the LFSR never locks up at zero.

module LfsrRng
  import mopac_types_pkg::*;
#(
  parameter logic [MOPAC_RNG_W-1:0] SEED = 16'hACE1  // non-zero default seed
)(
  input  logic                     clk_i,
  input  logic                     rst_ni,

  output logic [MOPAC_RNG_W-1:0]  rng_o   // current LFSR value
);

  logic [MOPAC_RNG_W-1:0] lfsr_r;

  // Galois LFSR: feedback bit is the LSB; XOR at tap positions 16,15,13,4
  // (0-indexed taps: 15,14,12,3)
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lfsr_r <= SEED;
    end else begin
      // Shift right by 1; feed back LSB into tap positions
      lfsr_r[MOPAC_RNG_W-1] <= lfsr_r[0];                         // bit 15 ← feedback
      lfsr_r[MOPAC_RNG_W-2] <= lfsr_r[MOPAC_RNG_W-1] ^ lfsr_r[0]; // bit 14 ← b15 ^ fb (tap 15)
      lfsr_r[MOPAC_RNG_W-3] <= lfsr_r[MOPAC_RNG_W-2];             // bit 13 ← b14
      lfsr_r[MOPAC_RNG_W-4] <= lfsr_r[MOPAC_RNG_W-3] ^ lfsr_r[0]; // bit 12 ← b13 ^ fb (tap 13)
      // Bits 11 down to 4: straight shift
      for (int i = 11; i >= 4; i--) begin
        lfsr_r[i] <= lfsr_r[i+1];
      end
      lfsr_r[3] <= lfsr_r[4] ^ lfsr_r[0];  // bit 3 ← b4 ^ fb (tap 4)
      // Bits 2 down to 0: straight shift
      for (int i = 2; i >= 0; i--) begin
        lfsr_r[i] <= lfsr_r[i+1];
      end
    end
  end

  assign rng_o = lfsr_r;

endmodule
