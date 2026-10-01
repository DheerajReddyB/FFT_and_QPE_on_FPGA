`timescale 1ns/1ps
// ============================================================
// fft_1d.v  –  16-point Radix-2 DIT FFT  (Sequential)
//
// Operation sequence (after start pulse):
//   1. LOAD  : 16 clock cycles – captures din_re/din_im
//              Element-0 is sampled on the SAME clock as start=1.
//              Elements 1..15 are sampled on the next 15 clocks.
//   2. CALC  : 4 stages × 8 butterflies = 32 clock cycles
//   3. DONE  : done=1 for one clock; output readable via rd_addr/rd_re/rd_im
//
// Total latency from start to done:  ~48 clock cycles
//
// Bit-reversal is applied implicitly during the LOAD phase:
//   sample n is stored at address bitrev4(n) so that the in-place
//   DIT butterfly loop produces naturally-ordered output.
// ============================================================

module fft_1d (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,          // Pulse to begin. Hold din valid for 16 clks.
    input  wire signed [31:0] din_re,  // Element 0 valid at start, 1..15 on next clocks
    input  wire signed [31:0] din_im,
    input  wire [3:0]  rd_addr,        // Async output read address
    output wire signed [31:0] rd_re,   // Output real (valid after done)
    output wire signed [31:0] rd_im,   // Output imag
    output reg         done             // Pulses 1 when FFT complete
);

    localparam N = 16;

    // States
    localparam S_IDLE = 2'd0;
    localparam S_LOAD = 2'd1;
    localparam S_CALC = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0] state;
    reg [3:0] cnt;    // Load: 1..15 | Calc: 0..7
    reg [1:0] stage;  // FFT stage 0..3

    // Internal data buffer (N complex words)
    reg signed [31:0] buf_re [0:N-1];
    reg signed [31:0] buf_im [0:N-1];

    // Async read port
    assign rd_re = buf_re[rd_addr];
    assign rd_im = buf_im[rd_addr];

    // -------------------------------------------------------
    // Bit-reversal function (4-bit)
    // -------------------------------------------------------
    function [3:0] brev4;
        input [3:0] a;
        begin brev4 = {a[0], a[1], a[2], a[3]}; end
    endfunction

    // -------------------------------------------------------
    // Butterfly address & twiddle index (combinational)
    // Computed from cnt (butterfly index 0..7) and stage (0..3)
    //
    // Stage s:
    //   half   = 2^s
    //   i      = cnt & (half-1)           (position within group)
    //   grp    = cnt >> s                  (group index)
    //   top    = grp*(2^(s+1)) + i
    //   bot    = top + half
    //   tw_k   = i * (8 >> s)  = i << (3-s)
    // -------------------------------------------------------
    reg [3:0] top_a, bot_a;
    reg [2:0] tw_k;

    always @(*) begin
        case (stage)
            2'd0: begin // half=1, each butterfly is adjacent pair
                top_a = {cnt[2:0], 1'b0};
                bot_a = {cnt[2:0], 1'b1};
                tw_k  = 3'd0;
            end
            2'd1: begin // half=2
                top_a = {cnt[2], cnt[1], 1'b0, cnt[0]};
                bot_a = top_a + 4'd2;
                tw_k  = {cnt[0], 2'b00};   // cnt[0]*4 → {0,4}
            end
            2'd2: begin // half=4
                top_a = {cnt[2], 1'b0, cnt[1], cnt[0]};
                bot_a = top_a + 4'd4;
                tw_k  = {cnt[1:0], 1'b0};  // cnt[1:0]*2 → {0,2,4,6}
            end
            default: begin // stage 3: half=8, single group
                top_a = {1'b0, cnt[2:0]};
                bot_a = {1'b1, cnt[2:0]};
                tw_k  = cnt[2:0];           // 0..7
            end
        endcase
    end

    // -------------------------------------------------------
    // Twiddle ROM and Butterfly unit
    // -------------------------------------------------------
    wire signed [15:0] tw_re, tw_im;
    twiddle_rom trom (
        .addr (tw_k),
        .w_re (tw_re),
        .w_im (tw_im)
    );

    wire signed [31:0] p_re, p_im, q_re, q_im;
    butterfly_unit bfly (
        .ar (buf_re[top_a]), .ai (buf_im[top_a]),
        .br (buf_re[bot_a]), .bi (buf_im[bot_a]),
        .wr (tw_re),         .wi (tw_im),
        .pr (p_re),          .pi (p_im),
        .qr (q_re),          .qi (q_im)
    );

    // -------------------------------------------------------
    // Main state machine
    // -------------------------------------------------------
    integer j;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            cnt   <= 4'd0;
            stage <= 2'd0;
            done  <= 1'b0;
            for (j = 0; j < N; j = j + 1) begin
                buf_re[j] <= 32'sd0;
                buf_im[j] <= 32'sd0;
            end
        end else begin
            done <= 1'b0; // default

            case (state)
                // -------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        // Capture element 0 immediately (bit-reversed address)
                        buf_re[brev4(4'd0)] <= din_re;
                        buf_im[brev4(4'd0)] <= din_im;
                        cnt   <= 4'd1;
                        state <= S_LOAD;
                    end
                end

                // -------------------------------------------------
                // Load elements 1..15 on successive clocks
                // -------------------------------------------------
                S_LOAD: begin
                    buf_re[brev4(cnt)] <= din_re;
                    buf_im[brev4(cnt)] <= din_im;
                    if (cnt == 4'd15) begin
                        cnt   <= 4'd0;
                        stage <= 2'd0;
                        state <= S_CALC;
                    end else begin
                        cnt <= cnt + 4'd1;
                    end
                end

                // -------------------------------------------------
                // Butterfly computation: 4 stages × 8 butterflies
                // -------------------------------------------------
                S_CALC: begin
                    // Write butterfly result back in-place
                    buf_re[top_a] <= p_re;
                    buf_im[top_a] <= p_im;
                    buf_re[bot_a] <= q_re;
                    buf_im[bot_a] <= q_im;

                    if (cnt[2:0] == 3'd7) begin   // Last butterfly of this stage
                        cnt <= 4'd0;
                        if (stage == 2'd3) begin   // All 4 stages done
                            state <= S_DONE;
                            done  <= 1'b1;
                        end else begin
                            stage <= stage + 2'd1;
                        end
                    end else begin
                        cnt <= cnt + 4'd1;
                    end
                end

                // -------------------------------------------------
                S_DONE: begin
                    done <= 1'b1;
                    // Allow re-trigger for next row/col
                    if (start) begin
                        buf_re[brev4(4'd0)] <= din_re;
                        buf_im[brev4(4'd0)] <= din_im;
                        cnt   <= 4'd1;
                        state <= S_LOAD;
                        done  <= 1'b0;
                    end
                end
            endcase
        end
    end

endmodule
