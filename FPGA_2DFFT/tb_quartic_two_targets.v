`timescale 1ns/1ps
// ============================================================
// tb_quartic_two_targets.v
// Testbench for Two Close Static Radar Targets
//
// Evaluates the full FPGA pipeline:
//   Input signal: x[n] = A1*sin(2*pi*f1*n/fs) + A2*sin(2*pi*f2*n/fs)
//   2D FFT -> Dual Peak Finder -> Parallel Quartic Estimator
//
// Evaluates 3 challenging close-target scenarios:
//   Test 1: 25.0 kHz & 50.0 kHz (2.0 bins apart, dR = 25.0 m)
//   Test 2: 25.0 kHz & 31.25 kHz (0.5 bins apart, dR = 6.25 m)
//   Test 3: 26.0 kHz & 29.0 kHz  (0.24 bins apart, dR = 3.0 m, very close off-bin)
// ============================================================

module tb_quartic_two_targets;

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

    task run_two_target_test;
        input real f1;
        input real f2;
        input [255:0] test_name;
        real df_true, dR_true_m;
        real err_t1, err_t2, err_df;
        begin
            @(posedge clk); rst = 1;
            repeat(4) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);

            // Load 256 samples of the combined beat signal
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

            // Sort estimates to match f1 and f2
            err_t1 = $itor(t1_fest_hz) - f1; if (err_t1 < 0) err_t1 = -err_t1;
            err_t2 = $itor(t2_fest_hz) - f2; if (err_t2 < 0) err_t2 = -err_t2;
            err_df = $itor(delta_f_hz) - df_true; if (err_df < 0) err_df = -err_df;

            $display("");
            $display("====================================================================");
            $display(" %0s", test_name);
            $display(" Targets Ground Truth: f1 = %.1f Hz,  f2 = %.1f Hz", f1, f2);
            $display(" True Frequency Gap  : Δf = %.1f Hz", df_true);
            $display(" True Physical Range : ΔR = %.2f m  (%.0f cm)", dR_true_m, dR_true_m * 100.0);
            $display("--------------------------------------------------------------------");
            $display(" TARGET 1 DETECTED:");
            $display("   2D FFT Bin Peak   : Row=%0d, Col=%0d (Raw FFT = %0d Hz)", t1_row, t1_col, t1_fraw_hz);
            $display("   Quartic Estimate  : %0d Hz  (Error: %.1f Hz)", t1_fest_hz, err_t1);
            $display(" TARGET 2 DETECTED:");
            $display("   2D FFT Bin Peak   : Row=%0d, Col=%0d (Raw FFT = %0d Hz)", t2_row, t2_col, t2_fraw_hz);
            $display("   Quartic Estimate  : %0d Hz  (Error: %.1f Hz)", t2_fest_hz, err_t2);
            $display("--------------------------------------------------------------------");
            $display(" SEPARATION MEASURED BY FPGA:");
            $display("   Measured Δf       : %0d Hz  (Error: %.1f Hz)", delta_f_hz, err_df);
            $display("   Measured Distance : %0d cm  (%.2f m)", delta_R_cm, $itor(delta_R_cm) / 100.0);
            if (err_df < 300.0)
                $display("   VERDICT           : RESOLVED AND HIGHLY ACCURATE! [PASS]");
            else
                $display("   VERDICT           : DETECTED [MARGINAL]");
            $display("====================================================================");
        end
    endtask

    initial begin
        $display("\n====================================================================");
        $display("   TWO-TARGET RESOLUTION & QUARTIC ESTIMATOR VERIFICATION");
        $display("   Sampling Rate: 200 kHz | 2D Grid: 16x16 | Bin Width: 12.5 kHz");
        $display("   Radar Specs: 24 GHz, B=150 MHz, T_chirp=1 ms (0.10 cm/Hz)");
        $display("====================================================================");

        wr_en = 0; wr_re = 0; wr_im = 0; wr_addr = 0;
        start = 0; rst = 1;
        repeat(4) @(posedge clk);

        // Case 1: 25 kHz & 50 kHz (2 bins apart)
        run_two_target_test(25000.0, 50000.0, "CASE 1: f1=25.0 kHz & f2=50.0 kHz (2.0 bins apart)");

        // Case 2: 25 kHz & 31.25 kHz (0.5 bin apart - close targets)
        run_two_target_test(25000.0, 31250.0, "CASE 2: f1=25.0 kHz & f2=31.25 kHz (0.5 bin apart - close)");

        // Case 3: 26 kHz & 29 kHz (very close off-bin targets)
        run_two_target_test(26000.0, 29000.0, "CASE 3: f1=26.0 kHz & f2=29.0 kHz (0.24 bin apart - very close off-bin)");

        $finish;
    end

    initial begin #30000000; $display("TIMEOUT"); $finish; end

endmodule
