`timescale 1ns/1ps
// ============================================================
// twiddle_rom.v
// Twiddle factor ROM for N=16 FFT
// W_16^k = cos(2*pi*k/16) - j*sin(2*pi*k/16), Q15 format (x32767)
//
// k  |  cos(2pi*k/16)  | -sin(2pi*k/16)
// ---+-----------------+----------------
// 0  |  1.0000         |  0.0000
// 1  |  0.9239         | -0.3827
// 2  |  0.7071         | -0.7071
// 3  |  0.3827         | -0.9239
// 4  |  0.0000         | -1.0000
// 5  | -0.3827         | -0.9239
// 6  | -0.7071         | -0.7071
// 7  | -0.9239         | -0.3827
// ============================================================

module twiddle_rom (
    input  wire [2:0]         addr,   // Twiddle index k = 0..7
    output reg  signed [15:0] w_re,   // Real part Q15
    output reg  signed [15:0] w_im    // Imaginary part Q15
);
    always @(*) begin
        case (addr)
            3'd0: begin w_re = 16'sd32767;  w_im =  16'sd0;     end
            3'd1: begin w_re = 16'sd30273;  w_im = -16'sd12539; end
            3'd2: begin w_re = 16'sd23170;  w_im = -16'sd23170; end
            3'd3: begin w_re = 16'sd12539;  w_im = -16'sd30273; end
            3'd4: begin w_re =  16'sd0;     w_im = -16'sd32767; end
            3'd5: begin w_re = -16'sd12539; w_im = -16'sd30273; end
            3'd6: begin w_re = -16'sd23170; w_im = -16'sd23170; end
            3'd7: begin w_re = -16'sd30273; w_im = -16'sd12539; end
            default: begin w_re = 16'sd32767; w_im = 16'sd0; end
        endcase
    end
endmodule
