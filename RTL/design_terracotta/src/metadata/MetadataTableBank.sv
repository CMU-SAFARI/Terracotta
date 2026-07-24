`timescale 1ns/1ps
import terracotta_types_pkg::*;

// MetadataTableBank: wraps NUM_BANKS MetadataTable instances for one technique.
// Two read ports (trigger + update) and one write port (update writeback).
// Since the user guarantees no same-bank conflict between trigger and update,
// each MetadataTable only needs a single read port internally.
//
// SRAM-backed MetadataTable: reads are REGISTERED (1-cycle latency).
// Bank selection indices are pipelined to align with the SRAM output.

module MetadataTableBank #(
    parameter int NUM_BANKS    = terracotta_types_pkg::TC_NUM_BANKS,       // 32
    parameter int BANK_W       = terracotta_types_pkg::TC_BANK_W,         // 5
    parameter int TAG_W        = terracotta_types_pkg::TC_META_TAG_W,     // 26
    parameter int DATA_W       = terracotta_types_pkg::TC_METADATA_W,     // 32
    parameter int DEPTH        = terracotta_types_pkg::TC_META_DEPTH      // 64
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // --- Read port A (trigger lookup, result valid 1 cycle later) ---
    input  logic                   rd_a_en_i,
    input  logic [BANK_W-1:0]      rd_a_bank_i,
    input  logic [TAG_W-1:0]       rd_a_tag_i,
    output logic                   rd_a_hit_o,
    output logic [DATA_W-1:0]      rd_a_data_o,

    // --- Read port B (update lookup, result valid 1 cycle later) ---
    input  logic                   rd_b_en_i,
    input  logic [BANK_W-1:0]      rd_b_bank_i,
    input  logic [TAG_W-1:0]       rd_b_tag_i,
    output logic                   rd_b_hit_o,
    output logic [DATA_W-1:0]      rd_b_data_o,

    // --- Write port (update writeback, synchronous) ---
    input  logic                   wr_en_i,
    input  logic [BANK_W-1:0]      wr_bank_i,
    input  logic [TAG_W-1:0]       wr_tag_i,
    input  logic [DATA_W-1:0]      wr_data_i,

    // --- Invalidation pulse (all banks) ---
    input  logic                   inv_pulse_i
);

    // Per-bank read/write enables (one-hot decode)
    logic [NUM_BANKS-1:0] rd_a_sel;
    logic [NUM_BANKS-1:0] rd_b_sel;
    logic [NUM_BANKS-1:0] wr_sel;

    // Per-bank read results (available 1 cycle after request)
    logic                inst_hit  [NUM_BANKS];
    logic [DATA_W-1:0]   inst_data [NUM_BANKS];

    // One-hot decode
    genvar g;
    generate
        for (g = 0; g < NUM_BANKS; g++) begin : g_decode
            assign rd_a_sel[g] = rd_a_en_i & (rd_a_bank_i == g[BANK_W-1:0]);
            assign rd_b_sel[g] = rd_b_en_i & (rd_b_bank_i == g[BANK_W-1:0]);
            assign wr_sel[g]   = wr_en_i   & (wr_bank_i   == g[BANK_W-1:0]);
        end
    endgenerate

    // Registered bank-select for output mux alignment with SRAM latency
    logic [NUM_BANKS-1:0] rd_a_sel_q;
    logic [NUM_BANKS-1:0] rd_b_sel_q;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            rd_a_sel_q <= '0;
            rd_b_sel_q <= '0;
        end else begin
            rd_a_sel_q <= rd_a_sel;
            rd_b_sel_q <= rd_b_sel;
        end
    end

    // MetadataTable instances — single read port muxed between A and B
    // (no same-bank conflict guaranteed)
    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b++) begin : g_bank
            // Mux read: port A has priority if both select same bank (shouldn't happen)
            wire        this_rd_en  = rd_a_sel[b] | rd_b_sel[b];
            wire [TAG_W-1:0] this_rd_tag = rd_a_sel[b] ? rd_a_tag_i : rd_b_tag_i;

            MetadataTable #(
                .TAG_W(TAG_W), .DATA_W(DATA_W), .DEPTH(DEPTH)
            ) u_meta (
                .clk_i       (clk_i),
                .reset_i     (reset_i),
                .rd_en_i     (this_rd_en),
                .rd_tag_i    (this_rd_tag),
                .rd_hit_o    (inst_hit[b]),
                .rd_data_o   (inst_data[b]),
                .wr_en_i     (wr_sel[b]),
                .wr_tag_i    (wr_tag_i),
                .wr_data_i   (wr_data_i),
                .inv_pulse_i (inv_pulse_i)
            );
        end
    endgenerate

    // Output muxes: use registered bank-select to align with SRAM 1-cycle latency.
    // At most one bank has rd_a_sel_q[i]=1 and at most one has rd_b_sel_q[i]=1.
    always_comb begin
        rd_a_hit_o  = 1'b0;
        rd_a_data_o = '0;
        rd_b_hit_o  = 1'b0;
        rd_b_data_o = '0;
        for (int i = 0; i < NUM_BANKS; i++) begin
            if (rd_a_sel_q[i]) begin
                rd_a_hit_o  = inst_hit[i];
                rd_a_data_o = inst_data[i];
            end
            if (rd_b_sel_q[i]) begin
                rd_b_hit_o  = inst_hit[i];
                rd_b_data_o = inst_data[i];
            end
        end
    end

endmodule
