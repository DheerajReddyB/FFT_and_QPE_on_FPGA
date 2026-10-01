`timescale 1ns/1ps
// ============================================================
// peak_finder.v
// Scans the 16×16 (256-entry) 2D FFT output, finds the bin
// with the maximum squared magnitude, then reads out the 5
// complex values at columns (pk_col-2 .. pk_col+2) of the
// peak row.  The 5 values feed the quartic estimator.
//
// Read port of fft_2d is combinational (async), so we use a
// 2-phase clock: phase-A sets the address, phase-B latches.
//
// States:
//   IDLE  → SCAN_A → SCAN_B → EXTRACT_A → EXTRACT_B → DONE
//
// Timing:
//   Scan    : 256 * 2 = 512 cycles
//   Extract :   5 * 2 =  10 cycles
//   Total   : ~522 cycles after start
// ============================================================

module peak_finder (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    // ── fft_2d read port (shared with testbench) ──────────────
    output reg  [7:0]  fft_rd_addr,
    input  wire signed [31:0] fft_rd_re,
    input  wire signed [31:0] fft_rd_im,

    // ── Peak location ─────────────────────────────────────────
    output reg  [3:0]  pk_row,
    output reg  [3:0]  pk_col,

    // ── 5 complex bins centred at peak: index 0=k-2, 1=k-1, 2=k, 3=k+1, 4=k+2 ──
    output reg signed [31:0] b_re_0, b_im_0,
    output reg signed [31:0] b_re_1, b_im_1,
    output reg signed [31:0] b_re_2, b_im_2,
    output reg signed [31:0] b_re_3, b_im_3,
    output reg signed [31:0] b_re_4, b_im_4,

    output reg         done
);

    // ── States ────────────────────────────────────────────────
    localparam S_IDLE      = 3'd0;
    localparam S_SCAN_A    = 3'd1;   // Set address
    localparam S_SCAN_B    = 3'd2;   // Latch data, update max
    localparam S_EXTRACT_A = 3'd3;   // Set address for one of 5 bins
    localparam S_EXTRACT_B = 3'd4;   // Latch bin data
    localparam S_DONE      = 3'd5;

    reg [2:0]  state;
    reg [7:0]  scan_cnt;    // 0..255
    reg [2:0]  ext_cnt;     // 0..4  (which of 5 bins)

    // Peak tracking
    reg [63:0] max_magsq;
    reg [63:0] cur_magsq;

    // Temporary for latch
    reg signed [31:0] latch_re, latch_im;

    // Signed intermediate for squared magnitude (64-bit)
    wire signed [63:0] sq_re = $signed(fft_rd_re) * $signed(fft_rd_re);
    wire signed [63:0] sq_im = $signed(fft_rd_im) * $signed(fft_rd_im);

    // Address for 5-bin extraction (with column wrap-around mod 16)
    function [7:0] extract_addr;
        input [3:0] row;
        input [3:0] col;
        input [2:0] offset;   // 0..4 mapped to -2..+2
        reg   [3:0] c;
        begin
            // column = (pk_col + offset - 2) mod 16
            c = (col + offset - 4'd2) & 4'hF;
            extract_addr = {row, c};
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_IDLE;
            scan_cnt    <= 8'd0;
            ext_cnt     <= 3'd0;
            max_magsq   <= 64'd0;
            pk_row      <= 4'd0;
            pk_col      <= 4'd0;
            fft_rd_addr <= 8'd0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                // ────────────────────────────────────────────
                S_IDLE: begin
                    if (start) begin
                        scan_cnt  <= 8'd0;
                        max_magsq <= 64'd0;
                        state     <= S_SCAN_A;
                    end
                end

                // ── Scan: phase A — set address ─────────────
                S_SCAN_A: begin
                    fft_rd_addr <= scan_cnt;
                    state       <= S_SCAN_B;
                end

                // ── Scan: phase B — latch & compare ─────────
                S_SCAN_B: begin
                    // Only consider positive-frequency half (col 0..7)
                    // to avoid picking the conjugate mirror peak
                    if (scan_cnt[3:0] <= 4'd7) begin
                        cur_magsq = sq_re + sq_im;
                        if (cur_magsq > max_magsq) begin
                            max_magsq <= cur_magsq;
                            pk_row    <= scan_cnt[7:4];
                            pk_col    <= scan_cnt[3:0];
                        end
                    end
                    if (scan_cnt == 8'd255) begin
                        ext_cnt <= 3'd0;
                        state   <= S_EXTRACT_A;
                    end else begin
                        scan_cnt <= scan_cnt + 8'd1;
                        state    <= S_SCAN_A;
                    end
                end

                // ── Extract: phase A — set address ──────────
                S_EXTRACT_A: begin
                    fft_rd_addr <= extract_addr(pk_row, pk_col, ext_cnt);
                    state       <= S_EXTRACT_B;
                end

                // ── Extract: phase B — latch bin ─────────────
                S_EXTRACT_B: begin
                    case (ext_cnt)
                        3'd0: begin b_re_0 <= fft_rd_re; b_im_0 <= fft_rd_im; end
                        3'd1: begin b_re_1 <= fft_rd_re; b_im_1 <= fft_rd_im; end
                        3'd2: begin b_re_2 <= fft_rd_re; b_im_2 <= fft_rd_im; end
                        3'd3: begin b_re_3 <= fft_rd_re; b_im_3 <= fft_rd_im; end
                        3'd4: begin b_re_4 <= fft_rd_re; b_im_4 <= fft_rd_im; end
                        default:;
                    endcase
                    if (ext_cnt == 3'd4) begin
                        state <= S_DONE;
                    end else begin
                        ext_cnt <= ext_cnt + 3'd1;
                        state   <= S_EXTRACT_A;
                    end
                end

                // ────────────────────────────────────────────
                S_DONE: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule
