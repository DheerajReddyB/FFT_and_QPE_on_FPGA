`timescale 1ns/1ps
// ============================================================
// tb_fft_2d.v  -  Testbench for 2D FFT
// Change F_SIG_HZ below to test any frequency
// ============================================================

module tb_fft_2d;

    // ── Signal parameters (change F_SIG_HZ to test any freq) ─
    localparam real FS_HZ    = 200000.0;
    localparam real F_SIG_HZ = 20000.0;    // <-- CHANGE THIS
    localparam real AMP      = 0.4;
    localparam real ADC_PEAK = 4095.0 * 0.4; // = 1638 counts

    // ── Clock / reset ─────────────────────────────────────────
    reg clk, rst;
    localparam CLK_PERIOD = 10; // 10 ns → 100 MHz

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── DUT connections ───────────────────────────────────────
    reg         wr_en;
    reg  [7:0]  wr_addr;
    reg  signed [31:0] wr_re, wr_im;
    reg         start;
    wire        done;
    reg  [7:0]  rd_addr;
    wire signed [31:0] rd_re, rd_im;

    fft_2d dut (
        .clk    (clk),
        .rst    (rst),
        .wr_en  (wr_en),
        .wr_addr(wr_addr),
        .wr_re  (wr_re),
        .wr_im  (wr_im),
        .start  (start),
        .done   (done),
        .rd_addr(rd_addr),
        .rd_re  (rd_re),
        .rd_im  (rd_im)
    );

    // ── Signal generation variables ───────────────────────────
    integer row, col, n;
    real    angle, sample;
    integer sample_int;

    // ── Output magnitude storage ──────────────────────────────
    real    mag [0:255];
    real    re_f, im_f, m;
    integer peak_row, peak_col, idx;
    real    peak_mag;

    // ── Simulation task: write one word ──────────────────────
    task write_sample;
        input [7:0]  addr;
        input signed [31:0] re, im_val;
        begin
            @(posedge clk);
            wr_en   <= 1'b1;
            wr_addr <= addr;
            wr_re   <= re;
            wr_im   <= im_val;
            @(posedge clk);
            wr_en   <= 1'b0;
        end
    endtask

    // ── Main testbench ────────────────────────────────────────
    initial begin
        $display("=== 2D FFT Testbench ===");
        $display("Signal: 0.5 offset + 0.4 amplitude @ %.0f kHz, fs=%.0f kHz",
                 F_SIG_HZ/1000.0, FS_HZ/1000.0);
        $display("Grid  : 16 x 16 = 256 samples\n");

        // Reset
        rst    = 1; start = 0;
        wr_en  = 0; wr_addr = 0;
        wr_re  = 0; wr_im   = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ── Step 1: Generate and load input samples ──────────
        $display("Loading 256 samples...");
        for (row = 0; row < 16; row = row + 1) begin
            for (col = 0; col < 16; col = col + 1) begin
                n = row * 16 + col;
                // x[n] = ADC_PEAK * sin(2*pi*F_SIG_HZ*n/FS_HZ)  (DC already removed)
                angle      = 2.0 * 3.14159265358979 * F_SIG_HZ * n / FS_HZ;
                sample     = ADC_PEAK * $sin(angle);
                sample_int = $rtoi(sample);
                write_sample(row*16 + col, sample_int, 0);
            end
        end
        $display("Load complete. Starting 2D FFT...\n");

        // ── Step 2: Start 2D FFT ─────────────────────────────
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // ── Step 3: Wait for done ────────────────────────────
        wait(done);
        @(posedge clk);
        $display("2D FFT complete!\n");

        // ── Step 4: Read results and compute magnitudes ───────
        peak_mag = 0.0; peak_row = 0; peak_col = 0;
        for (row = 0; row < 16; row = row + 1) begin
            for (col = 0; col < 16; col = col + 1) begin
                idx    = row * 16 + col;
                rd_addr = idx;
                #1; // Let combinational read settle
                re_f = $itor(rd_re);
                im_f = $itor(rd_im);
                m    = $sqrt(re_f*re_f + im_f*im_f);
                mag[idx] = m;
                if (m > peak_mag) begin
                    peak_mag = m;
                    peak_row = row;
                    peak_col = col;
                end
            end
        end

        // ── Step 5: Print ASCII magnitude table ──────────────
        $display("2D FFT Magnitude Spectrum (16x16, values /100):");
        $display("     | C0    C1    C2    C3    C4    C5    C6    C7    C8    C9    C10   C11   C12   C13   C14   C15");
        $display("-----|---------------------------------------------------------------------------------------------------");
        for (row = 0; row < 16; row = row + 1) begin
            $write("Row%2d|", row);
            for (col = 0; col < 16; col = col + 1) begin
                m = mag[row*16 + col];
                if (m > 0) $write(" %5.0f", m / 100.0);
                else       $write("     0");
            end
            $write("\n");
        end

        // ── Step 6: Export CSV for Python plotting ─────────────
        begin : csv_export
            integer fp;
            fp = $fopen("fft2d_output.csv", "w");
            if (fp == 0) begin
                $display("ERROR: Could not open fft2d_output.csv");
            end else begin
                $fwrite(fp, "row,col,re,im,magnitude,magnitude_dB\n");
                for (row = 0; row < 16; row = row + 1) begin
                    for (col = 0; col < 16; col = col + 1) begin
                        idx     = row * 16 + col;
                        rd_addr = idx;
                        #1;
                        re_f = $itor(rd_re);
                        im_f = $itor(rd_im);
                        m    = mag[idx];
                        if (m > 0.001)
                            $fwrite(fp, "%0d,%0d,%.2f,%.2f,%.4f,%.4f\n",
                                row, col, re_f, im_f, m,
                                20.0 * $ln(m / peak_mag) / $ln(10.0));
                        else
                            $fwrite(fp, "%0d,%0d,%.2f,%.2f,0.0000,-999.0\n",
                                row, col, re_f, im_f);
                    end
                end
                $fclose(fp);
                $display("\nCSV saved: fft2d_output.csv  (run plot_fft2d.py to view heatmap)");
            end
        end

        // ── Step 7: Summary ────────────────────────────────────
        $display("\n=== RESULTS ===");
        $display("Peak magnitude : %.0f (raw)", peak_mag);
        $display("Peak location  : Row=%0d, Col=%0d", peak_row, peak_col);
        $display("Signal freq    : 10 kHz @ fs=200 kHz  →  bin 0.8 (leakage between 0 & 1)");
        $display("Mirror alias   : Peak at Row=13 = N-3 (conjugate symmetry of real signal)");

        $display("\n=== Simulation finished ===");
        $finish;
    end

    // ── Timeout watchdog ─────────────────────────────────────
    initial begin
        #5000000; // 5 ms simulation limit
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    // ── Optional VCD dump (comment out if not needed) ────────
    initial begin
        $dumpfile("fft_2d_sim.vcd");
        $dumpvars(0, tb_fft_2d);
    end

endmodule
