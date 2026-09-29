// tb_ChargeCacheUnit.sv — Directed testbench for ChargeCache v2
//
// Tests:
//   T1  ACT on cold cache → MISS
//   T2  PRE (2-cycle) inserts row → verify open-row request
//   T3  ACT same row → HIT + 32-bit reload mask
//   T4  ACT different row → MISS
//   T5  RDA auto-precharge update + subsequent ACT HIT
//   T6  Core isolation: row inserted by core 0 is invisible to core 1
//   T7  Invalidation timer clears entries (fast-forward)
//
`timescale 1ns/1ps
import cc_types_pkg::*;

module tb_ChargeCacheUnit;

    // ── Parameters ──────────────────────────────────────────────────────
    localparam int CMD_W       = cc_types_pkg::CC_CMD_W;
    localparam int RANK_W      = cc_types_pkg::CC_RANK_W;
    localparam int BG_W        = cc_types_pkg::CC_BG_W;
    localparam int BA_W        = cc_types_pkg::CC_BA_W;
    localparam int ROW_W       = cc_types_pkg::CC_ROW_W;
    localparam int NUM_CORES   = cc_types_pkg::CC_NUM_CORES;
    localparam int CORE_ID_W   = cc_types_pkg::CC_CORE_ID_W;
    localparam int NUM_BANKS   = cc_types_pkg::CC_NUM_BANKS;
    localparam int BANK_IDX_W  = cc_types_pkg::CC_BANK_IDX_W;
    localparam int NUM_SETS    = cc_types_pkg::CC_NUM_SETS;
    localparam int NUM_WAYS    = cc_types_pkg::CC_NUM_WAYS;
    localparam int RM_W        = cc_types_pkg::CC_RELOAD_MASK_W;
    localparam int TAG_W       = ROW_W + BA_W + BG_W + RANK_W;
    localparam int SET_W       = $clog2(NUM_SETS);

    // ── DUT signals ─────────────────────────────────────────────────────
    logic              clk, rst;
    logic              in_valid, in_ready;
    logic [CMD_W-1:0]  cmd;
    logic [RANK_W-1:0] rank;
    logic [BG_W-1:0]   bg;
    logic [BA_W-1:0]   ba;
    logic [ROW_W-1:0]  row;
    logic [CORE_ID_W-1:0] core_id;

    // Open-row table interface
    logic              or_req;
    logic [RANK_W-1:0] or_req_rank;
    logic [BG_W-1:0]   or_req_bg;
    logic [BA_W-1:0]   or_req_ba;
    logic              or_resp_valid;
    logic [ROW_W-1:0]  or_resp_row;

    logic              out_valid, out_ready;
    logic              hit;
    logic              rm_valid;
    logic [RM_W-1:0]   rm;
    logic [TAG_W-1:0]  tag_out;
    logic [SET_W-1:0]  set_out;

    // ── DUT ─────────────────────────────────────────────────────────────
    ChargeCacheUnit #(
        .CMD_W(CMD_W), .RANK_W(RANK_W), .BG_W(BG_W), .BA_W(BA_W), .ROW_W(ROW_W),
        .NUM_CORES(NUM_CORES), .CORE_ID_W(CORE_ID_W),
        .NUM_BANKS(NUM_BANKS), .BANK_IDX_W(BANK_IDX_W),
        .NUM_SETS(NUM_SETS), .NUM_WAYS(NUM_WAYS), .RELOAD_MASK_W(RM_W)
    ) dut (
        .clk_i(clk), .reset_i(rst),
        .in_valid_i(in_valid), .in_ready_o(in_ready),
        .cmd_i(cmd), .rank_i(rank), .bg_i(bg), .ba_i(ba), .row_i(row),
        .core_id_i(core_id),
        .open_row_req_o(or_req),
        .open_row_req_rank_o(or_req_rank),
        .open_row_req_bg_o(or_req_bg),
        .open_row_req_ba_o(or_req_ba),
        .open_row_resp_valid_i(or_resp_valid),
        .open_row_resp_row_i(or_resp_row),
        .out_valid_o(out_valid), .out_ready_i(out_ready),
        .hit_o(hit), .reload_mask_valid_o(rm_valid), .reload_mask_o(rm),
        .tag_o(tag_out), .set_idx_o(set_out)
    );

    // ── Clock (4 ns / 250 MHz) ──────────────────────────────────────────
    initial clk = 0;
    always #2 clk = ~clk;

    // ════════════════════════════════════════════════════════════════════
    // Open-Row Table Model
    //   Simple array: open_row_table[bank_idx] = row.
    //   Returns response 1 cycle after request.
    // ════════════════════════════════════════════════════════════════════
    logic [ROW_W-1:0] ort [0:NUM_BANKS-1];
    logic             ort_valid [0:NUM_BANKS-1];
    logic             ort_resp_pending;
    logic [BANK_IDX_W-1:0] ort_resp_bank;

    integer ort_i;
    initial begin
        for (ort_i = 0; ort_i < NUM_BANKS; ort_i++) begin
            ort[ort_i] = '0;
            ort_valid[ort_i] = 1'b0;
        end
    end

    // Track open rows: set on ACT, clear on PRE
    always @(posedge clk) begin
        if (rst) begin
            ort_resp_pending <= 1'b0;
            or_resp_valid    <= 1'b0;
            or_resp_row      <= '0;
        end else begin
            // Default: deassert response
            or_resp_valid <= 1'b0;

            // Record open rows from ACT commands
            if (in_valid && in_ready && cmd == CMD_ACT) begin
                ort[{bg, ba}]       <= row;
                ort_valid[{bg, ba}] <= 1'b1;
            end

            // Latch request
            if (or_req) begin
                ort_resp_pending <= 1'b1;
                ort_resp_bank    <= {or_req_bg, or_req_ba};
            end

            // Respond 1 cycle after request
            if (ort_resp_pending) begin
                ort_resp_pending <= 1'b0;
                or_resp_valid    <= ort_valid[ort_resp_bank];
                or_resp_row      <= ort[ort_resp_bank];
                // Close the row on PRE
                ort_valid[ort_resp_bank] <= 1'b0;
            end
        end
    end

    // ── Helper tasks ────────────────────────────────────────────────────
    task automatic send_act(
        input logic [CORE_ID_W-1:0] t_core,
        input logic [RANK_W-1:0]    t_rank,
        input logic [BG_W-1:0]      t_bg,
        input logic [BA_W-1:0]      t_ba,
        input logic [ROW_W-1:0]     t_row
    );
        @(posedge clk);
        in_valid <= 1'b1;
        cmd      <= CMD_ACT;
        core_id  <= t_core;
        rank     <= t_rank;
        bg       <= t_bg;
        ba       <= t_ba;
        row      <= t_row;
        do @(posedge clk); while (!in_ready);
        in_valid <= 1'b0;
    endtask

    task automatic send_pre(
        input logic [CMD_W-1:0]     t_cmd,    // CMD_PRE, CMD_RDA, CMD_WRA
        input logic [CORE_ID_W-1:0] t_core,
        input logic [RANK_W-1:0]    t_rank,
        input logic [BG_W-1:0]      t_bg,
        input logic [BA_W-1:0]      t_ba
    );
        @(posedge clk);
        in_valid <= 1'b1;
        cmd      <= t_cmd;
        core_id  <= t_core;
        rank     <= t_rank;
        bg       <= t_bg;
        ba       <= t_ba;
        row      <= '0; // don't-care for PRE
        do @(posedge clk); while (!in_ready);
        in_valid <= 1'b0;
    endtask

    task automatic wait_out();
        out_ready <= 1'b1;
        do @(posedge clk); while (!out_valid);
        @(posedge clk); // consume
    endtask

    // ── Stimulus ────────────────────────────────────────────────────────
    integer errors = 0;
    initial begin
        $dumpfile("tb_ChargeCacheUnit.vcd");
        $dumpvars(0, tb_ChargeCacheUnit);

        rst = 1; in_valid = 0; out_ready = 1; core_id = '0;
        cmd = '0; rank = '0; bg = '0; ba = '0; row = '0;
        or_resp_valid = 0; or_resp_row = '0;
        repeat (6) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ── T1: ACT on cold cache → MISS ───────────────────────────────
        $display("[T1] ACT core=0, row=5, ba=1, bg=2, rank=0 → expect MISS");
        send_act(2'd0, 1'b0, 3'd2, 2'd1, 9'd5);
        wait_out();
        if (hit !== 1'b0) begin $error("T1 FAIL: expected miss, got hit"); errors++; end
        else               $display("    PASS");

        // ── T2: PRE same bank → 2-cycle insert ─────────────────────────
        // First need to mark the row open in our ORT model
        // (already done by the ACT in T1 via always block)
        $display("[T2] PRE core=0, ba=1, bg=2 → expect open_row_req then insert");
        send_pre(CMD_PRE, 2'd0, 1'b0, 3'd2, 2'd1);
        // Wait for the 2-cycle PRE to complete and produce output
        wait_out();
        $display("    inserted (tag_o=0x%0h, set_idx_o=%0d)", tag_out, set_out);

        // ── T3: ACT same row → HIT + reload mask ───────────────────────
        $display("[T3] ACT core=0, row=5, ba=1, bg=2, rank=0 → expect HIT");
        send_act(2'd0, 1'b0, 3'd2, 2'd1, 9'd5);
        wait_out();
        if (hit !== 1'b1) begin
            $error("T3 FAIL: expected hit"); errors++;
        end else if (rm !== CC_HIT_RELOAD_MASK) begin
            $error("T3 FAIL: bad mask 0x%0h, expected 0x%0h", rm, CC_HIT_RELOAD_MASK); errors++;
        end else begin
            $display("    PASS  mask=0x%0h", rm);
        end

        // ── T4: ACT different row → MISS ────────────────────────────────
        $display("[T4] ACT core=0, row=99, ba=1, bg=2, rank=0 → expect MISS");
        send_act(2'd0, 1'b0, 3'd2, 2'd1, 9'd99);
        wait_out();
        if (hit !== 1'b0) begin $error("T4 FAIL: expected miss"); errors++; end
        else               $display("    PASS");

        // ── T5: RDA auto-precharge + subsequent HIT ─────────────────────
        // Open row 99 first (ACT already done in T4), now RDA closes it
        $display("[T5] RDA core=0, ba=1, bg=2 → insert row 99 via auto-precharge");
        send_pre(CMD_RDA, 2'd0, 1'b0, 3'd2, 2'd1);
        wait_out();
        $display("    inserted");

        $display("[T5b] ACT core=0, row=99 → expect HIT");
        send_act(2'd0, 1'b0, 3'd2, 2'd1, 9'd99);
        wait_out();
        if (hit !== 1'b1) begin $error("T5b FAIL: expected hit"); errors++; end
        else               $display("    PASS");

        // ── T6: Core isolation ──────────────────────────────────────────
        // Row 5 was inserted by core 0 (T2). Core 1 should see a MISS.
        // Bank {bg=2, ba=1} = flat index 9.  Default map: 9 mod 4 = 1 → core 1.
        // To test isolation, we use a bank assigned to core 0: bank 0 (bg=0,ba=0).
        // Insert row 42 via core 0 on bank 0.
        $display("[T6] Core isolation: insert row 42 via core 0 on bank 0");
        send_act(2'd0, 1'b0, 3'd0, 2'd0, 9'd42);
        wait_out();
        // PRE to insert
        send_pre(CMD_PRE, 2'd0, 1'b0, 3'd0, 2'd0);
        wait_out();
        // ACT on core 0 → HIT
        send_act(2'd0, 1'b0, 3'd0, 2'd0, 9'd42);
        wait_out();
        if (hit !== 1'b1) begin $error("T6a FAIL: core 0 should hit"); errors++; end
        else               $display("    T6a PASS: core 0 hit");

        // Same row, but core 1 → MISS (different HCRAC instance)
        send_act(2'd1, 1'b0, 3'd0, 2'd0, 9'd42);
        wait_out();
        if (hit !== 1'b0) begin $error("T6b FAIL: core 1 should miss"); errors++; end
        else               $display("    T6b PASS: core 1 miss (isolation)");

        // ── T7: Invalidation timer ──────────────────────────────────────
        // The internal timer fires every CC_INV_TIMER_CYCLES.
        // Fast-forward enough cycles to clear all entries.
        $display("[T7] Invalidation: fast-forward timer to clear cache");
        // Total entries per core = NUM_SETS * NUM_WAYS = 128*4 = 512
        // Each inv pulse clears 1 entry. Need 512 pulses.
        // Each pulse requires CC_INV_TIMER_CYCLES cycles.
        // That's too many cycles for simulation, so just verify timer mechanism
        // by checking that after enough cycles, a previously-hit row misses.
        // We'll wait for a reasonable number of inv pulses to hit our entry.
        // For a targeted test: entry at set = tag[6:0], way chosen by LRU.
        // Just run enough timer periods to cycle through all entries.
        // Reduced: run 600 timer periods (> 512 entries).
        repeat (600) begin
            // Fast-forward one timer period
            repeat (cc_types_pkg::CC_INV_TIMER_CYCLES) @(posedge clk);
        end

        // ACT row=42 on core 0 → should MISS after invalidation
        send_act(2'd0, 1'b0, 3'd0, 2'd0, 9'd42);
        wait_out();
        if (hit !== 1'b0) begin $error("T7 FAIL: expected miss after inv"); errors++; end
        else               $display("    PASS");

        // ── Summary ─────────────────────────────────────────────────────
        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

endmodule
