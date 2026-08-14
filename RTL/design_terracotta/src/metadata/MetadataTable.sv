`timescale 1ns/1ps
import terracotta_types_pkg::*;

// MetadataTable: direct-mapped cache for per-technique, per-bank metadata.
// Uses two fakeram45 SRAM macros:
//   - fakeram45_64x21: stores {stored_tag[19:0], valid_at_write}  (21 bits)
//   - fakeram45_64x32: stores data[31:0]                          (32 bits)
//
// SRAM reads are REGISTERED (1-cycle latency).
// Tag comparison and hit detection are combinational AFTER the SRAM output.
//
// Valid bits are kept as a separate register array for bulk invalidation.
//
// Port timing:
//   Cycle 0: Present rd_tag_i → SRAM captures addr, starts read
//   Cycle 1: SRAM rd_out valid → tag comparison → rd_hit_o / rd_data_o

module MetadataTable #(
    parameter int TAG_W        = terracotta_types_pkg::TC_META_TAG_W,        // 26
    parameter int DATA_W       = terracotta_types_pkg::TC_METADATA_W,        // 32
    parameter int DEPTH        = terracotta_types_pkg::TC_META_DEPTH,        // 64
    parameter int IDX_W        = terracotta_types_pkg::TC_META_IDX_W,        // 6
    parameter int STORED_TAG_W = terracotta_types_pkg::TC_META_STORED_TAG_W  // 20
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // --- Read port (REGISTERED: result valid 1 cycle after rd_en_i) ---
    input  logic                   rd_en_i,
    input  logic [TAG_W-1:0]       rd_tag_i,
    output logic                   rd_hit_o,
    output logic [DATA_W-1:0]      rd_data_o,

    // --- Write port (synchronous) ---
    input  logic                   wr_en_i,
    input  logic [TAG_W-1:0]       wr_tag_i,
    input  logic [DATA_W-1:0]      wr_data_i,

    // --- Invalidation pulse (clears all valid bits) ---
    input  logic                   inv_pulse_i
);

    // ----------------------------------------------------------------
    //  Address / tag extraction
    // ----------------------------------------------------------------
    wire [IDX_W-1:0]        rd_idx        = rd_tag_i[IDX_W-1:0];
    wire [STORED_TAG_W-1:0] rd_stored_tag = rd_tag_i[TAG_W-1:IDX_W];

    wire [IDX_W-1:0]        wr_idx        = wr_tag_i[IDX_W-1:0];
    wire [STORED_TAG_W-1:0] wr_stored_tag = wr_tag_i[TAG_W-1:IDX_W];

    // ----------------------------------------------------------------
    //  Valid bits — kept as registers for bulk invalidation
    // ----------------------------------------------------------------
    logic valid_mem [0:DEPTH-1];

    always_ff @(posedge clk_i) begin
        if (reset_i || inv_pulse_i) begin
            for (int i = 0; i < DEPTH; i++)
                valid_mem[i] <= 1'b0;
        end else if (wr_en_i) begin
            valid_mem[wr_idx] <= 1'b1;
        end
    end

    // ----------------------------------------------------------------
    //  SRAM control — shared address mux (read or write, mutually exclusive)
    // ----------------------------------------------------------------
    logic [IDX_W-1:0] sram_addr;
    logic             sram_ce;
    logic             sram_we;

    always_comb begin
        if (wr_en_i) begin
            sram_addr = wr_idx;
            sram_ce   = 1'b1;
            sram_we   = 1'b1;
        end else begin
            sram_addr = rd_idx;
            sram_ce   = rd_en_i;
            sram_we   = 1'b0;
        end
    end

    // ----------------------------------------------------------------
    //  Tag SRAM: fakeram45_64x21  {stored_tag[19:0], valid_at_write}
    // ----------------------------------------------------------------
    wire [20:0] tag_sram_wd    = {wr_stored_tag, 1'b1};
    wire [20:0] tag_sram_wmask = {21{1'b1}};
    wire [20:0] tag_sram_rd;

    fakeram45_64x21 u_tag_sram (
        .clk       (clk_i),
        .ce_in     (sram_ce),
        .we_in     (sram_we),
        .addr_in   (sram_addr),
        .wd_in     (tag_sram_wd),
        .w_mask_in (tag_sram_wmask),
        .rd_out    (tag_sram_rd)
    );

    // ----------------------------------------------------------------
    //  Data SRAM: fakeram45_64x32
    // ----------------------------------------------------------------
    wire [31:0] data_sram_wmask = {32{1'b1}};
    wire [31:0] data_sram_rd;

    fakeram45_64x32 u_data_sram (
        .clk       (clk_i),
        .ce_in     (sram_ce),
        .we_in     (sram_we),
        .addr_in   (sram_addr),
        .wd_in     (wr_data_i),
        .w_mask_in (data_sram_wmask),
        .rd_out    (data_sram_rd)
    );

    // ----------------------------------------------------------------
    //  Registered pipeline state for tag comparison (cycle 1)
    // ----------------------------------------------------------------
    logic                    rd_en_q;
    logic [STORED_TAG_W-1:0] rd_expected_tag_q;
    logic [IDX_W-1:0]        rd_idx_q;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            rd_en_q           <= 1'b0;
            rd_expected_tag_q <= '0;
            rd_idx_q          <= '0;
        end else begin
            rd_en_q           <= rd_en_i & ~wr_en_i;
            rd_expected_tag_q <= rd_stored_tag;
            rd_idx_q          <= rd_idx;
        end
    end

    // ----------------------------------------------------------------
    //  Hit / data output (cycle 1, combinational from SRAM registered output)
    // ----------------------------------------------------------------
    wire [STORED_TAG_W-1:0] sram_tag_out = tag_sram_rd[20:1];
    wire                    tag_match    = (sram_tag_out == rd_expected_tag_q);

    assign rd_hit_o  = rd_en_q & valid_mem[rd_idx_q] & tag_match;
    assign rd_data_o = rd_hit_o ? data_sram_rd : '0;

endmodule
