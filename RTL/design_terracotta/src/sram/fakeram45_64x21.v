// Black-box stub for fakeram45_64x21 SRAM macro (NanGate 45nm)
// 64 entries × 21-bit words, single-port, synchronous read/write
// Port names match the Liberty (.lib) cell definition.
// For synthesis: Yosys treats this as a black box mapped to the .lib cell.
// For simulation: replace with a behavioral model.

(* blackbox *)
module fakeram45_64x21 (
    output [20:0] rd_out,
    input  [5:0]  addr_in,
    input         we_in,
    input  [20:0] wd_in,
    input  [20:0] w_mask_in,
    input         clk,
    input         ce_in
);
endmodule
