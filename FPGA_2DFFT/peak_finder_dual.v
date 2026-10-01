`timescale 1ns/1ps
// ============================================================
// peak_finder_dual.v  —  Dual-Target Peak Detector
//
// Detects TWO distinct targets in the 16x16 2D FFT output:
//   Pass 1: Scans positive frequencies (cols 0..7) to find Target 1 peak.
//   Pass 2: Re-scans positive frequencies, suppressing the 3x3
//           neighborhood around Target 1 to locate Target 2 peak.
//   Extract: Reads 3 complex DFT bins around Target 1 (col-1, col, col+1)
//            and 3 complex DFT bins around Target 2.
//
// Total latency: ~1040 cycles (~10.4 us at 100 MHz)
// ============================================================

module peak_finder_dual (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    // ── fft_2d read port ──────────────────────────────────────
    output reg  [7:0]  fft_rd_addr,
    input  wire signed [31:0] fft_rd_re,
    input  wire signed [31:0] fft_rd_im,

    // ── Target 1 peak & 3 complex bins ────────────────────────
    output reg  [3:0]  pk1_row, pk1_col,
    output reg signed [31:0] t1_re_0, t1_im_0,  // k1 - 1
    output reg signed [31:0] t1_re_1, t1_im_1,  // k1 (peak)
    output reg signed [31:0] t1_re_2, t1_im_2,  // k1 + 1

    // ── Target 2 peak & 3 complex bins ────────────────────────
    output reg  [3:0]  pk2_row, pk2_col,
    output reg signed [31:0] t2_re_0, t2_im_0,  // k2 - 1
    output reg signed [31:0] t2_re_1, t2_im_1,  // k2 (peak)
    output reg signed [31:0] t2_re_2, t2_im_2,  // k2 + 1

    output reg [63:0]  pk1_magsq,
    output reg [63:0]  pk2_magsq,
    output reg         done
);

    localparam S_IDLE     = 3'd0;
    localparam S_SCAN1_A  = 3'd1;
    localparam S_SCAN1_B  = 3'd2;
    localparam S_SCAN2_A  = 3'd3;
    localparam S_SCAN2_B  = 3'd4;
    localparam S_EXT_A    = 3'd5;
    localparam S_EXT_B    = 3'd6;
    localparam S_DONE     = 3'd7;

    reg [2:0] state;
    reg [7:0] scan_cnt;
    reg [2:0] ext_cnt; // 0..5 (0..2 for T1, 3..5 for T2)

    wire signed [63:0] sq_re = $signed(fft_rd_re) * $signed(fft_rd_re);
    wire signed [63:0] sq_im = $signed(fft_rd_im) * $signed(fft_rd_im);
    reg  [63:0] cur_magsq;

    // Check if (r, c) is in the 3x3 neighborhood of pk1
    function in_pk1_neighborhood;
        input [3:0] r, c;
        input [3:0] r1, c1;
        reg signed [4:0] dr, dc;
        begin
            dr = $signed({1'b0, r}) - $signed({1'b0, r1});
            dc = $signed({1'b0, c}) - $signed({1'b0, c1});
            // Handle row wrap-around mod 16
            if (dr >  8) dr = dr - 16;
            if (dr < -8) dr = dr + 16;
            in_pk1_neighborhood = (dr >= -1 && dr <= 1) && (dc >= -1 && dc <= 1);
        end
    endfunction

    // Address helper for 3-bin extraction (col-1, col, col+1)
    function [7:0] bin_addr;
        input [3:0] row;
        input [3:0] col;
        input [1:0] offset; // 0: -1, 1: 0, 2: +1
        reg   [3:0] c;
        begin
            c = (col + {2'b00, offset} - 4'd1) & 4'hF;
            bin_addr = {row, c};
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_IDLE;
            scan_cnt    <= 8'd0;
            ext_cnt     <= 3'd0;
            pk1_magsq   <= 64'd0;
            pk2_magsq   <= 64'd0;
            pk1_row     <= 4'd0;
            pk1_col     <= 4'd0;
            pk2_row     <= 4'd0;
            pk2_col     <= 4'd0;
            fft_rd_addr <= 8'd0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        scan_cnt  <= 8'd0;
                        pk1_magsq <= 64'd0;
                        pk2_magsq <= 64'd0;
                        state     <= S_SCAN1_A;
                    end
                end

                // ── Pass 1: Scan for Target 1 ─────────────────
                S_SCAN1_A: begin
                    fft_rd_addr <= scan_cnt;
                    state       <= S_SCAN1_B;
                end

                S_SCAN1_B: begin
                    if (scan_cnt[3:0] <= 4'd7) begin // positive frequency half
                        cur_magsq = sq_re + sq_im;
                        if (cur_magsq > pk1_magsq) begin
                            pk1_magsq <= cur_magsq;
                            pk1_row   <= scan_cnt[7:4];
                            pk1_col   <= scan_cnt[3:0];
                        end
                    end
                    if (scan_cnt == 8'd255) begin
                        scan_cnt <= 8'd0;
                        state    <= S_SCAN2_A;
                    end else begin
                        scan_cnt <= scan_cnt + 8'd1;
                        state    <= S_SCAN1_A;
                    end
                end

                // ── Pass 2: Scan for Target 2 (excluding T1) ─
                S_SCAN2_A: begin
                    fft_rd_addr <= scan_cnt;
                    state       <= S_SCAN2_B;
                end

                S_SCAN2_B: begin
                    if (scan_cnt[3:0] <= 4'd7) begin
                        if (!in_pk1_neighborhood(scan_cnt[7:4], scan_cnt[3:0], pk1_row, pk1_col)) begin
                            cur_magsq = sq_re + sq_im;
                            if (cur_magsq > pk2_magsq) begin
                                pk2_magsq <= cur_magsq;
                                pk2_row   <= scan_cnt[7:4];
                                pk2_col   <= scan_cnt[3:0];
                            end
                        end
                    end
                    if (scan_cnt == 8'd255) begin
                        ext_cnt <= 3'd0;
                        state   <= S_EXT_A;
                    end else begin
                        scan_cnt <= scan_cnt + 8'd1;
                        state    <= S_SCAN2_A;
                    end
                end

                // ── Extract Phase A: Set Address ──────────────
                S_EXT_A: begin
                    case (ext_cnt)
                        3'd0: fft_rd_addr <= bin_addr(pk1_row, pk1_col, 2'd0); // T1 col-1
                        3'd1: fft_rd_addr <= bin_addr(pk1_row, pk1_col, 2'd1); // T1 col
                        3'd2: fft_rd_addr <= bin_addr(pk1_row, pk1_col, 2'd2); // T1 col+1
                        3'd3: fft_rd_addr <= bin_addr(pk2_row, pk2_col, 2'd0); // T2 col-1
                        3'd4: fft_rd_addr <= bin_addr(pk2_row, pk2_col, 2'd1); // T2 col
                        3'd5: fft_rd_addr <= bin_addr(pk2_row, pk2_col, 2'd2); // T2 col+1
                        default: fft_rd_addr <= 8'd0;
                    endcase
                    state <= S_EXT_B;
                end

                // ── Extract Phase B: Latch Complex Bins ───────
                S_EXT_B: begin
                    case (ext_cnt)
                        3'd0: begin t1_re_0 <= fft_rd_re; t1_im_0 <= fft_rd_im; end
                        3'd1: begin t1_re_1 <= fft_rd_re; t1_im_1 <= fft_rd_im; end
                        3'd2: begin t1_re_2 <= fft_rd_re; t1_im_2 <= fft_rd_im; end
                        3'd3: begin t2_re_0 <= fft_rd_re; t2_im_0 <= fft_rd_im; end
                        3'd4: begin t2_re_1 <= fft_rd_re; t2_im_1 <= fft_rd_im; end
                        3'd5: begin t2_re_2 <= fft_rd_re; t2_im_2 <= fft_rd_im; end
                        default:;
                    endcase
                    if (ext_cnt == 3'd5) begin
                        state <= S_DONE;
                    end else begin
                        ext_cnt <= ext_cnt + 3'd1;
                        state   <= S_EXT_A;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
