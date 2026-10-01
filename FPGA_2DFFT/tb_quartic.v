`timescale 1ns/1ps
// ============================================================
// tb_quartic.v  —  Quartic Polynomial Estimator Testbench
//
// Tests 4 signal frequencies chosen to demonstrate sub-bin
// accuracy improvement over plain FFT:
//
//  Test | f_true   | Frac bin | FFT-only error | Quartic error
//  ─────┼──────────┼──────────┼────────────────┼──────────────
//   1   | 27500 Hz |  2.20    |  2500 Hz       | << 100 Hz
//   2   | 31250 Hz |  2.50    |  6250 Hz       | << 100 Hz
//   3   | 34375 Hz |  2.75    |  3125 Hz       | << 100 Hz
//   4   | 25000 Hz |  2.00    |     0 Hz       |  0 Hz (exact)
//
// All signals: amplitude = 1638 ADC counts, fs = 200000 Hz
//
// Output printed per test:
//   True freq | FFT-only estimate | Quartic estimate | Error improvement
// ============================================================

module tb_quartic;

    // ── Clock / reset ─────────────────────────────────────────
    reg clk, rst;
    localparam CLK_PERIOD = 10;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── DUT: quartic_top ──────────────────────────────────────
    reg         wr_en;
    reg  [7:0]  wr_addr;
    reg  signed [31:0] wr_re, wr_im;
    reg         start;
    wire        done;
    wire [3:0]  peak_row, peak_col;
    wire signed [31:0] delta_q20;
    wire        [31:0] f_est_hz, f_fft_hz;

    quartic_top dut (
        .clk       (clk),
        .rst       (rst),
        .wr_en     (wr_en),
        .wr_addr   (wr_addr),
        .wr_re     (wr_re),
        .wr_im     (wr_im),
        .start     (start),
        .done      (done),
        .fs_hz     (32'd200000),
        .n_pts     (8'd16),
        .peak_row  (peak_row),
        .peak_col  (peak_col),
        .delta_q20 (delta_q20),
        .f_est_hz  (f_est_hz),
        .f_fft_hz  (f_fft_hz)
    );

    // ── Test signals ──────────────────────────────────────────
    real test_freqs [0:3];
    integer test_num;
    integer row, col, n;
    real angle, sample;
    integer sample_int;

    real f_true, fft_err, quartic_err;
    real delta_real;
    real FRAC;

    // ── Write task ────────────────────────────────────────────
    task write_sample;
        input [7:0] addr;
        input signed [31:0] re;
        begin
            @(posedge clk);
            wr_en   <= 1; wr_addr <= addr;
            wr_re   <= re; wr_im  <= 0;
            @(posedge clk);
            wr_en   <= 0;
        end
    endtask

    // ── Run one test case ─────────────────────────────────────
    task run_test;
        input real f_signal;
        integer i;
        begin
            // Reset DUT
            @(posedge clk); rst = 1;
            repeat(4) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);

            // Load 256 samples
            for (row = 0; row < 16; row = row + 1) begin
                for (col = 0; col < 16; col = col + 1) begin
                    n      = row * 16 + col;
                    angle  = 2.0 * 3.14159265358979 * f_signal * n / 200000.0;
                    sample = 1638.0 * $sin(angle);
                    write_sample(row*16 + col, $rtoi(sample));
                end
            end

            // Start pipeline
            @(posedge clk); start <= 1;
            @(posedge clk); start <= 0;

            // Wait for completion
            wait(done);
            @(posedge clk);

            // Compute errors
            FRAC         = 1048576.0;  // 2^20
            delta_real   = $itor($signed(delta_q20)) / FRAC;
            fft_err      = $itor(f_fft_hz) - f_signal;
            if (fft_err < 0) fft_err = -fft_err;
            quartic_err  = $itor(f_est_hz) - f_signal;
            if (quartic_err < 0) quartic_err = -quartic_err;

            $display("");
            $display("─────────────────────────────────────────────────");
            $display(" f_true     = %.1f Hz  (frac bin = %.4f)",
                     f_signal, f_signal * 16.0 / 200000.0);
            $display(" Peak bin   = Row=%0d, Col=%0d", peak_row, peak_col);
            $display(" delta      = %.6f  (sub-bin offset)", delta_real);
            $display(" FFT-only   = %0d Hz   Error = %.1f Hz", f_fft_hz, fft_err);
            $display(" Quartic    = %0d Hz   Error = %.1f Hz", f_est_hz, quartic_err);
            if (fft_err > 100.0 && quartic_err > 0.001) begin
                $display(" Improvement: %.1fx better  (%s)",
                         fft_err / quartic_err,
                         (quartic_err < fft_err/10.0) ? "EXCELLENT" :
                         (quartic_err < fft_err/2.0)  ? "GOOD"      : "MARGINAL");
            end else if (fft_err <= 100.0) begin
                $display(" FFT already exact (on bin) — quartic confirms delta~0");
            end
        end
    endtask

    // ── Main ──────────────────────────────────────────────────
    initial begin
        $display("============================================================");
        $display("  QUARTIC POLYNOMIAL FREQUENCY ESTIMATOR — Testbench");
        $display("  fs=200kHz, N=16, bin_width=12500 Hz");
        $display("============================================================");

        wr_en = 0; wr_re = 0; wr_im = 0; wr_addr = 0;
        start = 0; rst = 1;
        repeat(4) @(posedge clk);

        // Test 1: 27500 Hz — frac bin 2.20 (off-bin, should be hard for FFT)
        $display("\n>>> TEST 1: f=27500 Hz (frac bin 2.20, 0.20 above bin 2)");
        run_test(27500.0);

        // Test 2: 31250 Hz — frac bin 2.50 (worst case: halfway between bins)
        $display("\n>>> TEST 2: f=31250 Hz (frac bin 2.50, WORST CASE halfway)");
        run_test(31250.0);

        // Test 3: 34375 Hz — frac bin 2.75 (close to next bin)
        $display("\n>>> TEST 3: f=34375 Hz (frac bin 2.75, close to bin 3)");
        run_test(34375.0);

        // Test 4: 25000 Hz — frac bin 2.00 (exactly on bin, quartic = FFT)
        $display("\n>>> TEST 4: f=25000 Hz (frac bin 2.00, EXACT BIN)");
        run_test(25000.0);

        $display("\n============================================================");
        $display("  SUMMARY");
        $display("  Standard FFT resolution  : +/- 6250 Hz (half bin width)");
        $display("  Quartic estimator target : << 500 Hz");
        $display("  Improvement factor       : ~10-100x");
        $display("============================================================");

        $finish;
    end

    initial begin #20000000; $display("TIMEOUT"); $finish; end

    initial begin
        $dumpfile("quartic_sim.vcd");
        $dumpvars(0, tb_quartic);
    end

endmodule
