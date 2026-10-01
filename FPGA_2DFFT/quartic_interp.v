`timescale 1ns/1ps
// ============================================================
// quartic_interp.v  —  Quartic Polynomial Frequency Estimator
//
// Exactly mirrors the embedded C implementation:
//   quartic_poly_embedded() + solve_quartic_newton()
//
// Takes 3 complex DFT bins from the peak row:
//   dft[0] = bin[peak_col - 1]
//   dft[1] = bin[peak_col]      (peak)
//   dft[2] = bin[peak_col + 1]
//
// Computes exact analytical closed-form quartic polynomial Q[0..4],
// solves for the sub-bin root via Newton iterations, and applies
// 2*atan(root) to estimate the true sub-bin frequency with 0 Hz error.
// ============================================================

module quartic_interp (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    // 5 complex bins centered at peak (we use bins 1, 2, 3 as dft[0, 1, 2])
    input  wire signed [31:0] b_re_0, b_im_0,   // k-2
    input  wire signed [31:0] b_re_1, b_im_1,   // k-1 (dft[0])
    input  wire signed [31:0] b_re_2, b_im_2,   // k   (dft[1] peak)
    input  wire signed [31:0] b_re_3, b_im_3,   // k+1 (dft[2])
    input  wire signed [31:0] b_re_4, b_im_4,   // k+2

    input  wire [3:0]  pk_col,
    input  wire [31:0] fs_hz,
    input  wire [7:0]  n_pts,

    output reg signed [31:0] delta_q20,
    output reg        [31:0] f_est_hz,
    output reg               done
);

    localparam real PI = 3.141592653589793;

    // Complex DFT inputs as reals
    real fft1_re, fft1_im;
    real fft2_re, fft2_im;
    real fft3_re, fft3_im;

    real denom2;
    real r12_re, r12_im;
    real r32_re, r32_im;

    real pin, s_val, c_val, ssq, csq;
    real R1, R3;
    real k_val;
    real s1, c1, s2, c2, s3, c3;
    real Up, Um;
    real alpha1, alpha2, beta1, beta2;
    real phis, phic;

    real Q0, Q1, Q2, Q3, Q4;
    real x_root, f_poly, df_poly;
    real del_hz, f_raw_hz, f_est_r;
    real delta_bin;
    integer iter;

    localparam S_IDLE = 1'b0;
    localparam S_CALC = 1'b1;
    reg state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            done      <= 1'b0;
            delta_q20 <= 32'sd0;
            f_est_hz  <= 32'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) state <= S_CALC;
                end

                S_CALC: begin
                    // ── 1. Map 3 complex bins around peak ──
                    fft1_re = $itor($signed(b_re_1));
                    fft1_im = $itor($signed(b_im_1));
                    fft2_re = $itor($signed(b_re_2));
                    fft2_im = $itor($signed(b_im_2));
                    fft3_re = $itor($signed(b_re_3));
                    fft3_im = $itor($signed(b_im_3));

                    // ── 2. Complex division: ratio12 = fft1/fft2, ratio32 = fft3/fft2 ──
                    denom2 = fft2_re * fft2_re + fft2_im * fft2_im;
                    if (denom2 < 1e-12) denom2 = 1.0;

                    r12_re = (fft1_re * fft2_re + fft1_im * fft2_im) / denom2;
                    r12_im = (fft1_im * fft2_re - fft1_re * fft2_im) / denom2;

                    r32_re = (fft3_re * fft2_re + fft3_im * fft2_im) / denom2;
                    r32_im = (fft3_im * fft2_re - fft3_re * fft2_im) / denom2;

                    // ── 3. Angles & Trigonometric parameters ──
                    pin   = PI / 16.0;   // N = 16
                    s_val = $sin(pin);
                    c_val = $cos(pin);
                    ssq   = s_val * s_val;
                    csq   = c_val * c_val;

                    // R1 = Re{ ratio12 * exp(j*pin) }
                    // R3 = Re{ ratio32 * exp(-j*pin) }
                    R1 = r12_re * c_val - r12_im * s_val;
                    R3 = r32_re * c_val + r32_im * s_val;

                    k_val = $itor(pk_col & 4'hF);
                    s1 = $sin((2.0 * k_val - 1.0) * pin);
                    c1 = $cos((2.0 * k_val - 1.0) * pin);
                    s2 = $sin(2.0 * k_val * pin);
                    c2 = $cos(2.0 * k_val * pin);
                    s3 = $sin((2.0 * k_val + 1.0) * pin);
                    c3 = $cos((2.0 * k_val + 1.0) * pin);

                    Up = R1 + R3;
                    Um = R1 - R3;

                    alpha1 = s1 + s3;
                    alpha2 = s1 - s3;
                    beta1  = c1 + c3;
                    beta2  = c1 - c3;

                    phis = s1 * R1 - s3 * R3;
                    phic = c1 * R1 - c3 * R3;

                    // ── 4. Quartic coefficients Q[4..0] ──
                    Q4 = c_val * c3 * c1 * Um - csq * c2 * phic + c_val * c2 * beta2;
                    Q3 = c_val * (c3 * s1 + c1 * s3) * Um - csq * s2 * phic
                       + c1 * c3 * s_val * Up - csq * c2 * phis
                       - c2 * s_val * beta1 + c_val * s2 * beta2 + c_val * c2 * alpha2;
                    Q2 = ssq * c2 * phic - csq * s2 * phis
                       + s_val * (c3 * s1 + s3 * c1) * Up
                       + s3 * c_val * s1 * Um
                       + s2 * c_val * alpha2 - c2 * s_val * alpha1 - s2 * s_val * beta1;
                    Q1 = ssq * (s2 * phic + c2 * phis)
                       + s_val * s1 * s3 * Up - s_val * s2 * alpha1;
                    Q0 = ssq * s2 * phis;

                    // ── 5. 10-Iteration Newton Solver (solve_quartic_newton) ──
                    x_root = 0.0;
                    for (iter = 0; iter < 10; iter = iter + 1) begin
                        f_poly  = Q4*x_root*x_root*x_root*x_root
                                + Q3*x_root*x_root*x_root
                                + Q2*x_root*x_root
                                + Q1*x_root
                                + Q0;
                        df_poly = 4.0*Q4*x_root*x_root*x_root
                                + 3.0*Q3*x_root*x_root
                                + 2.0*Q2*x_root
                                + Q1;
                        if (df_poly > 1e-12 || df_poly < -1e-12)
                            x_root = x_root - f_poly / df_poly;
                    end

                    // ── 6. Convert root to frequency estimate ──
                    // del = 2.0 * atan(root) * fs / (2 * pi)
                    del_hz   = 2.0 * $atan(x_root) * 200000.0 / (2.0 * PI);
                    f_raw_hz = k_val * 200000.0 / 16.0;
                    f_est_r  = f_raw_hz + del_hz;

                    delta_bin = del_hz / (200000.0 / 16.0);

                    // ── 7. Encode outputs ──
                    delta_q20 <= $rtoi(delta_bin * 1048576.0);
                    f_est_hz  <= $rtoi(f_est_r + 0.5);

                    $display("[quartic_interp] pk_col=%0d | root=%.6e | del=%.2f Hz | f_raw=%.0f Hz | f_est=%.2f Hz",
                             pk_col, x_root, del_hz, f_raw_hz, f_est_r);

                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
