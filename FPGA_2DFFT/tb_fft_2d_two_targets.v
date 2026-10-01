`timescale 1ns/1ps
// ============================================================
// tb_fft_2d_two_targets.v  -  Two-Target Resolution Test
//
// Simulates two RADAR static targets (two frequency components):
//   x[n] = A1*sin(2*pi*f1*n/fs) + A2*sin(2*pi*f2*n/fs)
//
// Tests whether the 2D FFT can separate two close targets.
// Frequency resolution limit: delta_f = fs/N = 200kHz/16 = 12.5 kHz/bin
//
// Three test cases (set TEST_CASE parameter):
//   1 - f1=25kHz, f2=50kHz   (2 bins apart)  -> Easy to resolve
//   2 - f1=25kHz, f2=37.5kHz (1 bin apart)   -> Borderline
//   3 - f1=25kHz, f2=31.25kHz(0.5 bin apart) -> May fail (merge)
// ============================================================

module tb_fft_2d_two_targets;

    // ── CHANGE THIS to 1, 2, or 3 ──────────────────────────────
    localparam integer TEST_CASE = 3;
    // ───────────────────────────────────────────────────────────

    localparam real FS_HZ  = 200000.0;
    localparam real N_DIM  = 16.0;
    localparam real BIN_W  = FS_HZ / N_DIM;   // 12500 Hz per bin

    // Target frequencies per test case
    localparam real F1_C1 = 25000.0,  F2_C1 = 50000.0;
    localparam real F1_C2 = 25000.0,  F2_C2 = 37500.0;
    localparam real F1_C3 = 25000.0,  F2_C3 = 31250.0;

    // Active frequencies selected by TEST_CASE
    real F1, F2;
    initial begin
        case (TEST_CASE)
            1: begin F1 = F1_C1; F2 = F2_C1; end
            2: begin F1 = F1_C2; F2 = F2_C2; end
            3: begin F1 = F1_C3; F2 = F2_C3; end
            default: begin F1 = F1_C1; F2 = F2_C1; end
        endcase
    end

    localparam real AMP1  = 819.0;   // 0.2 * 4095 (half scale each target)
    localparam real AMP2  = 819.0;

    // ── Clock / reset ─────────────────────────────────────────
    reg clk, rst;
    localparam CLK_PERIOD = 10;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── DUT connections ───────────────────────────────────────
    reg        wr_en;
    reg  [7:0] wr_addr;
    reg  signed [31:0] wr_re, wr_im;
    reg        start;
    wire       done;
    reg  [7:0] rd_addr;
    wire signed [31:0] rd_re, rd_im;

    fft_2d dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_addr(wr_addr),
        .wr_re(wr_re), .wr_im(wr_im),
        .start(start), .done(done),
        .rd_addr(rd_addr), .rd_re(rd_re), .rd_im(rd_im)
    );

    // ── Variables ─────────────────────────────────────────────
    integer row, col, n;
    real    a1, a2, sample;
    integer sample_int;
    real    mag [0:255];
    real    re_f, im_f, m, peak_mag;
    integer peak_row, peak_col, idx;

    // Write task
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

    // ── Main testbench ────────────────────────────────────────
    initial begin
        $display("==============================================");
        $display(" 2D FFT Two-Target Resolution Test");
        $display("==============================================");

        case (TEST_CASE)
            1: begin
                $display("TEST CASE 1: f1=%.1f kHz, f2=%.1f kHz", F1_C1/1000, F2_C1/1000);
                $display("Separation : %.1f kHz  = 2.0 bins  [EASY - should resolve]",
                         (F2_C1-F1_C1)/1000);
            end
            2: begin
                $display("TEST CASE 2: f1=%.1f kHz, f2=%.1f kHz", F1_C2/1000, F2_C2/1000);
                $display("Separation : %.2f kHz = 1.0 bin   [BORDERLINE]",
                         (F2_C2-F1_C2)/1000);
            end
            3: begin
                $display("TEST CASE 3: f1=%.1f kHz, f2=%.2f kHz", F1_C3/1000, F2_C3/1000);
                $display("Separation : %.3f kHz = 0.5 bins  [HARD - may merge]",
                         (F2_C3-F1_C3)/1000);
            end
        endcase

        $display("Bin width  : %.1f kHz/bin  (fs=%.0f kHz, N=%0.0f)",
                 BIN_W/1000, FS_HZ/1000, N_DIM);
        $display("Amplitudes : A1=A2=%.0f ADC counts each", AMP1);
        $display("----------------------------------------------\n");

        // Reset
        rst=1; start=0; wr_en=0; wr_re=0; wr_im=0; wr_addr=0;
        repeat(4) @(posedge clk);
        rst=0;
        repeat(2) @(posedge clk);

        // ── Load two-target signal ────────────────────────────
        $display("Loading two-target signal (256 samples)...");
        for (row = 0; row < 16; row = row + 1) begin
            for (col = 0; col < 16; col = col + 1) begin
                n = row * 16 + col;
                // Two-target beat signal (sum of two sinusoids, DC removed)
                a1 = AMP1 * $sin(2.0 * 3.14159265358979 * F1 * n / FS_HZ);
                a2 = AMP2 * $sin(2.0 * 3.14159265358979 * F2 * n / FS_HZ);
                sample     = a1 + a2;
                sample_int = $rtoi(sample);
                write_sample(row*16 + col, sample_int);
            end
        end

        // ── Start 2D FFT ──────────────────────────────────────
        @(posedge clk); start <= 1;
        @(posedge clk); start <= 0;
        wait(done);
        @(posedge clk);
        $display("2D FFT complete!\n");

        // ── Read and compute magnitudes ───────────────────────
        peak_mag=0; peak_row=0; peak_col=0;
        for (row = 0; row < 16; row = row + 1) begin
            for (col = 0; col < 16; col = col + 1) begin
                idx = row*16+col;
                rd_addr = idx; #1;
                re_f = $itor(rd_re); im_f = $itor(rd_im);
                m = $sqrt(re_f*re_f + im_f*im_f);
                mag[idx] = m;
                if (m > peak_mag) begin
                    peak_mag=m; peak_row=row; peak_col=col;
                end
            end
        end

        // ── Print spectrum table ──────────────────────────────
        $display("2D FFT Magnitude (16x16, values/100):");
        $display("     |  C0   C1   C2   C3   C4   C5   C6   C7   C8   C9  C10  C11  C12  C13  C14  C15");
        $display("-----|-------------------------------------------------------------------------------------");
        for (row = 0; row < 16; row = row + 1) begin
            $write("Row%2d|", row);
            for (col = 0; col < 16; col = col + 1) begin
                m = mag[row*16+col];
                if (m > 500) $write("  [%2.0f]", m/100.0);  // bracket = strong peak
                else         $write("  %3.0f ", m/100.0);
            end
            $write("\n");
        end

        // ── Export CSV for Python ─────────────────────────────
        begin : csv_block
            integer fp;
            fp = $fopen("two_targets_output.csv", "w");
            $fwrite(fp, "row,col,re,im,magnitude\n");
            for (row = 0; row < 16; row = row + 1) begin
                for (col = 0; col < 16; col = col + 1) begin
                    idx = row*16+col;
                    rd_addr = idx; #1;
                    $fwrite(fp, "%0d,%0d,%.2f,%.2f,%.4f\n",
                        row, col, $itor(rd_re), $itor(rd_im), mag[idx]);
                end
            end
            $fclose(fp);
            $display("\nCSV saved: two_targets_output.csv");
        end

        // ── Summary and resolution verdict ────────────────────
        $display("\n=== RESOLUTION VERDICT ===");
        $display("Peak magnitude : %.0f  at Row=%0d, Col=%0d",
                 peak_mag, peak_row, peak_col);

        // Find second peak (must be separated by at least 2 bins from first peak)
        begin : second_peak
            real  second_mag;
            integer second_row, second_col;
            second_mag = 0;
            for (row = 0; row < 16; row = row + 1) begin
                for (col = 0; col < 16; col = col + 1) begin
                    m = mag[row*16+col];
                    if (m > second_mag) begin
                        // Must be at least 2 bins away from primary peak
                        if (((row-peak_row)*(row-peak_row) +
                             (col-peak_col)*(col-peak_col)) > 4) begin
                            second_mag  = m;
                            second_row  = row;
                            second_col  = col;
                        end
                    end
                end
            end
            $display("2nd peak mag   : %.0f  at Row=%0d, Col=%0d",
                     second_mag, second_row, second_col);
            $display("Peak ratio     : %.2f  (>0.5 means both targets visible)",
                     second_mag / peak_mag);

            if (second_mag / peak_mag > 0.5)
                $display("RESULT: RESOLVED - Two separate peaks detected! Targets are distinguishable.");
            else if (second_mag / peak_mag > 0.2)
                $display("RESULT: MARGINAL - Second peak visible but weak. Targets partially merged.");
            else
                $display("RESULT: NOT RESOLVED - Targets merged into one blob. Cannot distinguish.");
        end

        $display("\n=== Simulation finished ===");
        $finish;
    end

    initial begin #10000000; $display("TIMEOUT"); $finish; end
    initial begin $dumpfile("two_targets.vcd"); $dumpvars(0, tb_fft_2d_two_targets); end

endmodule


