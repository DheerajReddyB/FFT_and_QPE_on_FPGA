`timescale 1ns/1ps
// ============================================================
// quartic_top.v
// Top-level: connects fft_2d → peak_finder → quartic_interp
//
// Pipeline:
//   1. Load samples via wr_en/wr_addr/wr_re/wr_im
//   2. Pulse start → 2D FFT runs
//   3. After fft_done, peak_finder scans & extracts 5 bins
//   4. After pf_done, quartic_interp computes sub-bin freq
//   5. After qi_done, f_est_hz / delta_q20 are valid + done=1
// ============================================================

module quartic_top (
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

    // ── System parameters ────────────────────────────────────
    input  wire [31:0] fs_hz,     // e.g. 200000
    input  wire [7:0]  n_pts,     // e.g. 16

    // ── Results ───────────────────────────────────────────────
    output wire [3:0]  peak_row,
    output wire [3:0]  peak_col,
    output wire signed [31:0] delta_q20,
    output wire        [31:0] f_est_hz,
    output wire        [31:0] f_fft_hz   // FFT-only (bin × fs/N)
);

    // ── Internal wires ────────────────────────────────────────
    // fft_2d ↔ peak_finder read port
    wire [7:0]  fft_rd_addr;
    wire signed [31:0] fft_rd_re, fft_rd_im;

    wire        fft_done, pf_done, qi_done;
    reg         pf_start, qi_start;

    // 5 bins from peak_finder → quartic_interp
    wire signed [31:0] b_re_0, b_im_0;
    wire signed [31:0] b_re_1, b_im_1;
    wire signed [31:0] b_re_2, b_im_2;
    wire signed [31:0] b_re_3, b_im_3;
    wire signed [31:0] b_re_4, b_im_4;

    // ── FFT-only frequency: pk_col * fs_hz / n_pts ───────────
    // Use 64-bit intermediate to avoid 32x32 overflow
    wire [63:0] pk_col_64 = {60'd0, peak_col};
    wire [63:0] fs_hz_64  = {32'd0, fs_hz};
    wire [63:0] n_pts_64  = {56'd0, n_pts};
    wire [63:0] f_fft_64  = pk_col_64 * fs_hz_64 / n_pts_64;
    assign f_fft_hz = f_fft_64[31:0];

    // ── Stage sequencer ───────────────────────────────────────
    localparam S_IDLE   = 2'd0;
    localparam S_FFT    = 2'd1;
    localparam S_PF     = 2'd2;
    localparam S_QI     = 2'd3;

    reg [1:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            pf_start <= 1'b0;
            qi_start <= 1'b0;
            done     <= 1'b0;
        end else begin
            pf_start <= 1'b0;
            qi_start <= 1'b0;
            done     <= 1'b0;

            case (state)
                S_IDLE: if (start) state <= S_FFT;

                S_FFT: if (fft_done) begin
                    pf_start <= 1'b1;
                    state    <= S_PF;
                end

                S_PF: if (pf_done) begin
                    qi_start <= 1'b1;
                    state    <= S_QI;
                end

                S_QI: if (qi_done) begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // ── fft_2d instance ───────────────────────────────────────
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

    // ── peak_finder instance ──────────────────────────────────
    peak_finder pf_inst (
        .clk         (clk),
        .rst         (rst),
        .start       (pf_start),
        .fft_rd_addr (fft_rd_addr),
        .fft_rd_re   (fft_rd_re),
        .fft_rd_im   (fft_rd_im),
        .pk_row      (peak_row),
        .pk_col      (peak_col),
        .b_re_0      (b_re_0), .b_im_0 (b_im_0),
        .b_re_1      (b_re_1), .b_im_1 (b_im_1),
        .b_re_2      (b_re_2), .b_im_2 (b_im_2),
        .b_re_3      (b_re_3), .b_im_3 (b_im_3),
        .b_re_4      (b_re_4), .b_im_4 (b_im_4),
        .done        (pf_done)
    );

    // ── quartic_interp instance ───────────────────────────────
    quartic_interp qi_inst (
        .clk       (clk),
        .rst       (rst),
        .start     (qi_start),
        .b_re_0    (b_re_0), .b_im_0 (b_im_0),
        .b_re_1    (b_re_1), .b_im_1 (b_im_1),
        .b_re_2    (b_re_2), .b_im_2 (b_im_2),
        .b_re_3    (b_re_3), .b_im_3 (b_im_3),
        .b_re_4    (b_re_4), .b_im_4 (b_im_4),
        .pk_col    (peak_col),
        .fs_hz     (fs_hz),
        .n_pts     (n_pts),
        .delta_q20 (delta_q20),
        .f_est_hz  (f_est_hz),
        .done      (qi_done)
    );

endmodule
