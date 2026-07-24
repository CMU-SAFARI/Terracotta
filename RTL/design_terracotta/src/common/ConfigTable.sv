`timescale 1ns/1ps

module ConfigTable #(
    parameter int KEY_W   = 16,
    parameter int CFG_W   = 64,
    parameter int DEPTH   = 256
) (
    input  logic                   clk_i,
    input  logic                   reset_i,
    // Read port (single-cycle combinational read)
    input  logic                   rd_en_i,
    input  logic [KEY_W-1:0]       rd_key_i,
    output logic [CFG_W-1:0]       rd_value_o,
    output logic                   rd_hit_o,
    // Write port (sync)
    input  logic                   wr_en_i,
    input  logic [KEY_W-1:0]       wr_key_i,
    input  logic [CFG_W-1:0]       wr_value_i
);
    localparam int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    logic              valid_mem [0:DEPTH-1];
    logic [ADDR_W-1:0] rd_addr;

    // Standard-cell memory implementation only (SRAM macro path removed)
    logic [CFG_W-1:0] mem [0:DEPTH-1];
    always_comb begin
        rd_addr    = rd_key_i[ADDR_W-1:0];
        rd_value_o = rd_en_i ? mem[rd_addr] : '0;
        rd_hit_o   = rd_en_i ? valid_mem[rd_addr] : 1'b0;
    end
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            integer i;
            for (i = 0; i < DEPTH; i++) begin
                valid_mem[i] <= 1'b0;
            end
        end else begin
            if (wr_en_i) begin
                mem[wr_key_i[ADDR_W-1:0]]      <= wr_value_i;
                valid_mem[wr_key_i[ADDR_W-1:0]]<= 1'b1;
            end
        end
    end
endmodule
