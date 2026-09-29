/**
 * MoPAC Update Kernel — Probabilistic cu_flag set on ACT via LFSR
 *
 * On ACT: advance per-entry 16-bit LFSR, set cu_flag if output < threshold.
 * Probability ≈ 1/4: threshold = top 2 bits both zero → p(flag) ≈ 25%.
 *
 * 16-bit Fibonacci LFSR: x^16 + x^14 + x^13 + x^11 + 1
 *   feedback_bit = (s ^ (s>>2) ^ (s>>3) ^ (s>>5)) & 1
 *   new_state = (s >> 1) | (feedback_bit << 15)
 *
 * Uses XOR-based feedback only (no negate-and-mask pattern).
 * Separate rng_in/rng_out to avoid aliasing (RecMinII=0).
 *
 * Memory: 1 LOAD (rng_in) + 2 STORE (rng_out, cu_flag) = 3 mem ops
 *   → ResMinII = ceil(3/6) = 1 on 6×6
 *
 * Latency target: < 52 cycles
 */

void mopac_update(int n, int *rng_in, int *rng_out, int *cu_flag) {
    int i;
    for (i = 0; i < n; i++) {
#ifdef CGRA_COMPILER
        please_map_me();
#endif
        int s = rng_in[i];

        /* Fibonacci LFSR: taps at 16,14,13,11 */
        int fb = (s ^ (s >> 2) ^ (s >> 3) ^ (s >> 5)) & 1;
        int new_s = (s >> 1) | (fb << 15);

        /* Threshold: p ≈ 1/4 → top 2 bits of 16-bit state both zero */
        cu_flag[i] = ((new_s & 0xC000) == 0);
        rng_out[i] = new_s;
    }
}
