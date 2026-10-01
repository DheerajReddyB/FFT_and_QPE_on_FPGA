`timescale 1ns/1ps
// ============================================================
// tb_fft_only_two_targets.v
// Two Close Static Radar Targets — FFT-ONLY (WITHOUT ESTIMATOR)
//
// Identical test cases and display format as tb_quartic_two_targets.v,
// but uses ONLY the raw FFT bin frequencies (no sub-bin interpolation).
//
// Demonstrates the fundamental resolution limits of standard FFT:
//   - Quantization error: up to ±6250 Hz (±0.5 bin)
//   - Range error: up to ±6.25 m (±625 cm)
//   - Merging problem: targets < 1 bin apart land in the SAME bin!
// ============================================================

module tb_fft_only_two_targets;

    reg clk, rst;
    localparam CLK_PERIOD = 10;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg         wr_en;
    reg  [7:0]  wr_addr;
    reg  signed [31:0] wr_re, wr_im;
    reg         start;
    wire        done;

    wire [3:0]  t1_row, t1_col;
    wire [31:0] t1_fraw_hz, t1_fest_hz;
    wire signed [31:0] t1_delta_q20;

    wire [3:0]  t2_row, t2_col;
    wire [31:0] t2_fraw_hz, t2_fest_hz;
    wire signed [31:0] t2_delta_q20;

    wire [31:0] delta_f_hz;
    wire [31:0] delta_R_cm;

    quartic_dual_top dut (
        .clk        (clk),
        .rst        (rst),
        .wr_en      (wr_en),
        .wr_addr    (wr_addr),
        .wr_re      (wr_re),
        .wr_im      (wr_im),
        .start      (start),
        .done       (done),
        .fs_hz      (32'd200000),
        .n_pts      (8'd16),
        .t1_row     (t1_row),
        .t1_col     (t1_col),
        .t1_fraw_hz (t1_fraw_hz),
        .t1_fest_hz (t1_fest_hz),
        .t1_delta_q20(t1_delta_q20),
        .t2_row     (t2_row),
        .t2_col     (t2_col),
        .t2_fraw_hz (t2_fraw_hz),
        .t2_fest_hz (t2_fest_hz),
        .t2_delta_q20(t2_delta_q20),
        .delta_f_hz (delta_f_hz),
        .delta_R_cm (delta_R_cm)
    );

    task write_sample;
        input [7:0] addr;
        input signed [31:0] re;
        begin
            @(posedge clk);
            wr_en <= 1; wr_addr <= addr; wr_re <= re; wr_im <= 0;
            @(posedge clk);
            wr_en <= 0;
        end
    endtask

    integer row, col, n;
    real ang1, ang2, s_val;

    task run_fft_only_test;
        input real f1;
        input real f2;
        input [255:0] test_name;
        real df_true, dR_true_m;
        real err_t1, err_t2, err_df;
        real df_fft_raw, dR_fft_raw_cm;
        begin
            @(posedge clk); rst = 1;
            repeat(4) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);

            // Load 256 samples of combined signal
            for (row = 0; row < 16; row = row + 1) begin
                for (col = 0; col < 16; col = col + 1) begin
                    n     = row * 16 + col;
                    ang1  = 2.0 * 3.14159265358979 * f1 * n / 200000.0;
                    ang2  = 2.0 * 3.14159265358979 * f2 * n / 200000.0;
                    s_val = 819.0 * $sin(ang1) + 819.0 * $sin(ang2);
                    write_sample(row * 16 + col, $rtoi(s_val));
                end
            end

            @(posedge clk); start <= 1;
            @(posedge clk); start <= 0;

            wait(done);
            @(posedge clk);

            df_true   = (f2 > f1) ? (f2 - f1) : (f1 - f2);
            dR_true_m = df_true * 0.001; // 0.10 cm/Hz = 0.001 m/Hz

            // FFT-only measured frequency difference (WITHOUT ESTIMATOR)
            if (t1_fraw_hz > t2_fraw_hz)
                df_fft_raw = $itor(t1_fraw_hz - t2_fraw_hz);
            else
                df_fft_raw = $itor(t2_fraw_hz - t1_fraw_hz);

            // Range separation: 0.10 cm/Hz (dR_cm = delta_f / 10)
            dR_fft_raw_cm = df_fft_raw * 0.10;

            // Errors using FFT-only estimates
            err_t1 = $itor(t1_fraw_hz) - f1; if (err_t1 < 0) err_t1 = -err_t1;
            err_t2 = $itor(t2_fraw_hz) - f2; if (err_t2 < 0) err_t2 = -err_t2;
            err_df = df_fft_raw - df_true;  if (err_df < 0) err_df = -err_df;

            $display("");
            $display("====================================================================");
            $display(" %0s", test_name);
            $display(" Targets Ground Truth: f1 = %.1f Hz,  f2 = %.1f Hz", f1, f2);
            $display(" True Frequency Gap  : Δf = %.1f Hz", df_true);
            $display(" True Physical Range : ΔR = %.2f m  (%.0f cm)", dR_true_m, dR_true_m * 100.0);
            $display("--------------------------------------------------------------------");
            $display(" TARGET 1 DETECTED (FFT-ONLY):");
            $display("   2D FFT Bin Peak   : Row=%0d, Col=%0d", t1_row, t1_col);
            $display("   FFT-Only Estimate : %0d Hz  (Error: %.1f Hz)", t1_fraw_hz, err_t1);
            $display(" TARGET 2 DETECTED (FFT-ONLY):");
            $display("   2D FFT Bin Peak   : Row=%0d, Col=%0d", t2_row, t2_col);
            $display("   FFT-Only Estimate : %0d Hz  (Error: %.1f Hz)", t2_fraw_hz, err_t2);
            $display("--------------------------------------------------------------------");
            $display(" SEPARATION MEASURED BY FFT-ONLY:");
            $display("   Measured Δf       : %.0f Hz  (Error: %.1f Hz)", df_fft_raw, err_df);
            $display("   Measured Distance : %.0f cm  (%.2f m)", dR_fft_raw_cm, dR_fft_raw_cm / 100.0);
            if (df_fft_raw == 0.0)
                $display("   VERDICT           : MERGED! Cannot separate targets (both land in same bin) [FAIL]");
            else if (err_df < 300.0)
                $display("   VERDICT           : RESOLVED [EXACT INTEGER BIN]");
            else
                $display("   VERDICT           : QUANTIZATION ERROR! Off by %.1f Hz (%.0f cm) [COARSE]", err_df, err_df * 0.10);
            $display("====================================================================");
        end
    endtask

    initial begin
        $display("\n====================================================================");
        $display("   TWO-TARGET RESOLUTION — FFT ONLY (WITHOUT ESTIMATOR)");
        $display("   Sampling Rate: 200 kHz | 2D Grid: 16x16 | Bin Width: 12.5 kHz");
        $display("   Radar Specs: 24 GHz, B=150 MHz, T_chirp=1 ms (0.10 cm/Hz)");
        $display("   Standard FFT Resolution: +/- 6250 Hz (+/- 6.25 m)");
        $display("====================================================================");

        wr_en = 0; wr_re = 0; wr_im = 0; wr_addr = 0;
        start = 0; rst = 1;
        repeat(4) @(posedge clk);

        // Case 1: 25 kHz & 50 kHz (2 bins apart)
        run_fft_only_test(25000.0, 50000.0, "CASE 1: f1=25.0 kHz & f2=50.0 kHz (2.0 bins apart)");

        // Case 2: 25 kHz & 31.25 kHz (0.5 bin apart - close targets)
        run_fft_only_test(25000.0, 31250.0, "CASE 2: f1=25.0 kHz & f2=31.25 kHz (0.5 bin apart - close)");

        // Case 3: 26 kHz & 29 kHz (very close off-bin targets)
        run_fft_only_test(26000.0, 29000.0, "CASE 3: f1=26.0 kHz & f2=29.0 kHz (0.24 bin apart - very close off-bin)");

        $finish;
    end

    initial begin #30000000; $display("TIMEOUT"); $finish; end

endmodule
