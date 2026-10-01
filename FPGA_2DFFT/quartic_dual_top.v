`timescale 1ns/1ps
// ============================================================
// quartic_dual_top.v  —  Two-Target 2D FFT + Quartic Processor
//
// Pipeline:
//   1. Load 256 samples into internal 16x16 complex memory.
//   2. Run 2D FFT (Row-FFT + Column-FFT).
//   3. peak_finder_dual finds both targets (Peak 1 & Peak 2).
//   4. Two parallel quartic_interp engines estimate true sub-bin
//      frequencies for both targets simultaneously.
//   5. Computes frequency separation Δf and physical radar distance ΔR.
// ============================================================

module quartic_dual_top (
    input  wire        clk,
    input  wire        rst,

    // ── Input loading ─────────────────────────────────────────
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire signed [31:0] wr_re,
    input  wire signed [31:0] wr_im,

    // ── Control ───────────────────────────────────────────────
    input  wire        start,
    output reg         done,

    // ── Parameters ───────────────────────────────────────────
    input  wire [31:0] fs_hz,
    input  wire [7:0]  n_pts,

    // ── Target 1 Outputs ──────────────────────────────────────
    output wire [3:0]  t1_row, t1_col,
    output wire [31:0] t1_fraw_hz,
    output wire [31:0] t1_fest_hz,
    output wire signed [31:0] t1_delta_q20,

    // ── Target 2 Outputs ──────────────────────────────────────
    output wire [3:0]  t2_row, t2_col,
    output wire [31:0] t2_fraw_hz,
    output wire [31:0] t2_fest_hz,
    output wire signed [31:0] t2_delta_q20,

    // ── Two-Target Radar Metrics ──────────────────────────────
    output reg  [31:0] delta_f_hz,   // Frequency separation |f1 - f2| in Hz
    output reg  [31:0] delta_R_cm    // Range separation in cm (B=150MHz, T=1ms -> 0.10 cm/Hz)
);

    // ── Internal wires ────────────────────────────────────────
    wire [7:0]  fft_rd_addr;
    wire signed [31:0] fft_rd_re, fft_rd_im;
    wire fft_done, pf_done, qi1_done, qi2_done;
    reg  pf_start, qi_start;

    // Target 1 bins
    wire signed [31:0] t1_re_0, t1_im_0;
    wire signed [31:0] t1_re_1, t1_im_1;
    wire signed [31:0] t1_re_2, t1_im_2;

    // Target 2 bins
    wire signed [31:0] t2_re_0, t2_im_0;
    wire signed [31:0] t2_re_1, t2_im_1;
    wire signed [31:0] t2_re_2, t2_im_2;

    wire [63:0] pk1_magsq, pk2_magsq;

    // Raw FFT frequencies
    assign t1_fraw_hz = {28'd0, t1_col} * fs_hz / {24'd0, n_pts};
    assign t2_fraw_hz = {28'd0, t2_col} * fs_hz / {24'd0, n_pts};

    // ── Pipeline Sequencer ────────────────────────────────────
    localparam S_IDLE = 2'd0;
    localparam S_FFT  = 2'd1;
    localparam S_PF   = 2'd2;
    localparam S_QI   = 2'd3;

    reg [1:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            pf_start   <= 1'b0;
            qi_start   <= 1'b0;
            done       <= 1'b0;
            delta_f_hz <= 32'd0;
            delta_R_cm <= 32'd0;
        end else begin
            pf_start <= 1'b0;
            qi_start <= 1'b0;
            done     <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) state <= S_FFT;
                end

                S_FFT: begin
                    if (fft_done) begin
                        pf_start <= 1'b1;
                        state    <= S_PF;
                    end
                end

                S_PF: begin
                    if (pf_done) begin
                        qi_start <= 1'b1;
                        state    <= S_QI;
                    end
                end

                S_QI: begin
                    if (qi1_done && qi2_done) begin
                        // Compute frequency separation
                        if (t1_fest_hz > t2_fest_hz)
                            delta_f_hz <= t1_fest_hz - t2_fest_hz;
                        else
                            delta_f_hz <= t2_fest_hz - t1_fest_hz;

                        // Range separation: 0.10 cm/Hz for B=150MHz, T=1ms (dR_cm = delta_f / 10)
                        if (t1_fest_hz > t2_fest_hz)
                            delta_R_cm <= (t1_fest_hz - t2_fest_hz) / 32'd10;
                        else
                            delta_R_cm <= (t2_fest_hz - t1_fest_hz) / 32'd10;

                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // ── 2D FFT Instance ───────────────────────────────────────
    fft_2d fft_inst (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_re   (wr_re),
        .wr_im   (wr_im),
        .start   (start),
        .done    (fft_done),
        .rd_addr (fft_rd_addr),
        .rd_re   (fft_rd_re),
        .rd_im   (fft_rd_im)
    );

    // ── Dual Peak Finder Instance ─────────────────────────────
    peak_finder_dual pf_dual_inst (
        .clk         (clk),
        .rst         (rst),
        .start       (pf_start),
        .fft_rd_addr (fft_rd_addr),
        .fft_rd_re   (fft_rd_re),
        .fft_rd_im   (fft_rd_im),
        .pk1_row     (t1_row),
        .pk1_col     (t1_col),
        .t1_re_0     (t1_re_0), .t1_im_0 (t1_im_0),
        .t1_re_1     (t1_re_1), .t1_im_1 (t1_im_1),
        .t1_re_2     (t1_re_2), .t1_im_2 (t1_im_2),
        .pk2_row     (t2_row),
        .pk2_col     (t2_col),
        .t2_re_0     (t2_re_0), .t2_im_0 (t2_im_0),
        .t2_re_1     (t2_re_1), .t2_im_1 (t2_im_1),
        .t2_re_2     (t2_re_2), .t2_im_2 (t2_im_2),
        .pk1_magsq   (pk1_magsq),
        .pk2_magsq   (pk2_magsq),
        .done        (pf_done)
    );

    // ── Quartic Estimator for Target 1 ────────────────────────
    quartic_interp qi_t1 (
        .clk       (clk),
        .rst       (rst),
        .start     (qi_start),
        .b_re_0    (32'd0),   .b_im_0 (32'd0),
        .b_re_1    (t1_re_0), .b_im_1 (t1_im_0),
        .b_re_2    (t1_re_1), .b_im_2 (t1_im_1),
        .b_re_3    (t1_re_2), .b_im_3 (t1_im_2),
        .b_re_4    (32'd0),   .b_im_4 (32'd0),
        .pk_col    (t1_col),
        .fs_hz     (fs_hz),
        .n_pts     (n_pts),
        .delta_q20 (t1_delta_q20),
        .f_est_hz  (t1_fest_hz),
        .done      (qi1_done)
    );

    // ── Quartic Estimator for Target 2 ────────────────────────
    quartic_interp qi_t2 (
        .clk       (clk),
        .rst       (rst),
        .start     (qi_start),
        .b_re_0    (32'd0),   .b_im_0 (32'd0),
        .b_re_1    (t2_re_0), .b_im_1 (t2_im_0),
        .b_re_2    (t2_re_1), .b_im_2 (t2_im_1),
        .b_re_3    (t2_re_2), .b_im_3 (t2_im_2),
        .b_re_4    (32'd0),   .b_im_4 (32'd0),
        .pk_col    (t2_col),
        .fs_hz     (fs_hz),
        .n_pts     (n_pts),
        .delta_q20 (t2_delta_q20),
        .f_est_hz  (t2_fest_hz),
        .done      (qi2_done)
    );

endmodule
