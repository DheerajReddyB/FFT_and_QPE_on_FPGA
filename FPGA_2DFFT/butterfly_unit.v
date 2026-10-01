`timescale 1ns/1ps
// ============================================================
// butterfly_unit.v
// Radix-2 DIT Butterfly (Combinational)
//
//   P = A + W*B
//   Q = A - W*B
//
// Data  : 32-bit signed integer
// Twiddle: 16-bit Q15 signed (range ~ -1.0 to +1.0)
// The product W*B is 48-bit Q15; integer part = bits[46:15]
// ============================================================

module butterfly_unit (
    input  wire signed [31:0] ar, ai,   // Input A (real, imag)
    input  wire signed [31:0] br, bi,   // Input B
    input  wire signed [15:0] wr, wi,   // Twiddle W (Q15)
    output wire signed [31:0] pr, pi,   // P = A + W*B
    output wire signed [31:0] qr, qi    // Q = A - W*B
);
    // W*B: 16-bit Q15 x 32-bit integer = 48-bit Q15 result
    wire signed [47:0] t_re_full = $signed(wr)*$signed(br) - $signed(wi)*$signed(bi);
    wire signed [47:0] t_im_full = $signed(wr)*$signed(bi) + $signed(wi)*$signed(br);

    // Descale: arithmetic right-shift by 15 → take bits[46:15] as 32-bit result
    wire signed [31:0] t_re = $signed(t_re_full[46:15]);
    wire signed [31:0] t_im = $signed(t_im_full[46:15]);

    assign pr = ar + t_re;
    assign pi = ai + t_im;
    assign qr = ar - t_re;
    assign qi = ai - t_im;
endmodule
