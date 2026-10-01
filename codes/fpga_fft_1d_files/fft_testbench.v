`timescale 1ns/1ps

// ============================================================
// Testbench for 1024-point FFT
//
// Signal:
//      x[n] = 0.4 + 0.5*sin(2*pi*10000*n/200000)
//
// DC offset is removed before the FFT, matching the old
// LaunchXL implementation.
//
// Expected:
//      Fs       = 200 kHz
//      Fsignal  = 10 kHz
//      N        = 1024
//      bin      = 51.2
//      FFT peak ~= bin 51
//      bin 51   = 9960.94 Hz
//      bin 52   = 10156.25 Hz
// ============================================================

module fft_testbench;

    localparam N  = 1024;
    localparam FS = 200000.0;
    localparam F0 = 10000.0;

    reg clk;
    reg rst;
    reg start;
    reg sample_valid;

    reg signed [15:0] sample_in;

    wire sample_ready;
    wire done;

    wire signed [31:0] re_out [0:N-1];
    wire signed [31:0] im_out [0:N-1];

    integer n;
    integer k;
    integer peak_bin;

    real signal_value;
    real dc_removed;

    real mag2;
    real best_mag2;
    real freq;

    fft_1024 #(
        .N(N)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .sample_ready(sample_ready),
        .done(done),
        .re_out(re_out),
        .im_out(im_out)
    );

    // 100 MHz simulation clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin

        rst = 1;
        start = 0;
        sample_valid = 0;
        sample_in = 0;

        #100;
        rst = 0;

        // Start FFT acquisition
        @(posedge clk);
        start <= 1;

        @(posedge clk);
        start <= 0;

        // ----------------------------------------------------
        // Generate 1024 samples.
        //
        // Original:
        // x[n] = 0.4 + 0.5*sin(...)
        //
        // FFT input:
        // x_fft[n] = x[n] - 0.4
        //            = 0.5*sin(...)
        //
        // Q1.15 scaling.
        // ----------------------------------------------------
        for (n = 0; n < N; n = n + 1) begin

            @(posedge clk);

            signal_value = 0.4 +
                           0.5 * $sin(2.0*3.141592653589793*
                                      F0*n/FS);

            dc_removed = signal_value - 0.4;

            if (dc_removed > 0.999) dc_removed = 0.999;
            if (dc_removed < -1.0) dc_removed = -1.0;

            sample_in <= $rtoi(dc_removed * 32768.0);
            sample_valid <= 1;
        end

        @(posedge clk);
        sample_valid <= 0;
        sample_in <= 0;

        // Wait for FFT
        wait(done);

        #20;

        // ----------------------------------------------------
        // Find positive-frequency peak.
        // Ignore DC bin and Nyquist.
        // ----------------------------------------------------
        peak_bin = 1;
        best_mag2 = 0.0;

        for (k = 1; k < N/2; k = k + 1) begin

            mag2 = $itor(re_out[k]) * $itor(re_out[k]) +
                   $itor(im_out[k]) * $itor(im_out[k]);

            if (mag2 > best_mag2) begin
                best_mag2 = mag2;
                peak_bin = k;
            end
        end

        freq = peak_bin * FS / N;

        $display("");
        $display("==============================================");
        $display("        1024-POINT FFT VERIFICATION");
        $display("==============================================");
        $display("Sampling frequency : %0.2f Hz", FS);
        $display("Input frequency    : %0.2f Hz", F0);
        $display("FFT size            : %0d", N);
        $display("Bin spacing         : %0.6f Hz", FS/N);
        $display("----------------------------------------------");
        $display("Detected peak bin   : %0d", peak_bin);
        $display("Raw FFT frequency   : %0.6f Hz", freq);
        $display("Expected bin        : 51.2");
        $display("==============================================");
        $display("");

        // Print bins around expected peak
        for (k = 48; k <= 54; k = k + 1) begin
            mag2 = $itor(re_out[k]) * $itor(re_out[k]) +
                   $itor(im_out[k]) * $itor(im_out[k]);

            $display("BIN %0d  FREQ=%0.3f Hz  RE=%0d  IM=%0d  MAG2=%0.3e",
                     k,
                     k*FS/N,
                     re_out[k],
                     im_out[k],
                     mag2);
        end

        #100;
        $finish;
    end

endmodule
