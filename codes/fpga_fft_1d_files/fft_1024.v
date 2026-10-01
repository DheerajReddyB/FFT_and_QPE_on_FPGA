`timescale 1ns/1ps

// ============================================================
// 1024-point radix-2 FFT
// Fixed-point input/output:
//   Input  : signed Q1.15
//   Internal: signed 32-bit
//
// This module performs an in-place iterative radix-2 DIT FFT.
// For simulation/first FPGA verification, the complete transform
// is executed after 'start' using a clocked state machine.
//
// Output bins are available through re_out[] / im_out[] after done.
// ============================================================

module fft_1024 #(
    parameter N = 1024,
    parameter ADDR_W = 10
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    input  wire signed [15:0] sample_in,
    input  wire               sample_valid,

    output reg                sample_ready,
    output reg                done,

    output reg signed [31:0] re_out [0:N-1],
    output reg signed [31:0] im_out [0:N-1]
);

    reg signed [31:0] re_mem [0:N-1];
    reg signed [31:0] im_mem [0:N-1];

    // Twiddle ROM: Q1.15
    reg signed [15:0] tw_re [0:N/2-1];
    reg signed [15:0] tw_im [0:N/2-1];

    integer i;
    integer j;
    integer k;

    integer load_count;
    integer stage;
    integer group;
    integer butterfly;
    integer addr_a;
    integer addr_b;
    integer tw_idx;

    reg [3:0] state;

    reg signed [31:0] a_re, a_im;
    reg signed [31:0] b_re, b_im;
    reg signed [31:0] t_re, t_im;

    reg signed [63:0] mult1;
    reg signed [63:0] mult2;
    reg signed [63:0] mult3;
    reg signed [63:0] mult4;

    localparam S_IDLE      = 0;
    localparam S_LOAD      = 1;
    localparam S_BITREV    = 2;
    localparam S_BFLY_READ = 3;
    localparam S_BFLY_CALC = 4;
    localparam S_BFLY_WRITE= 5;
    localparam S_DONE      = 6;

    // --------------------------------------------------------
    // Generate twiddle coefficients.
    // Verilog real arithmetic is used ONLY to initialize the
    // simulation ROM. Synthesizable FPGA designs should replace
    // this with a pre-generated ROM/IP.
    // W[k] = exp(-j*2*pi*k/N)
    // --------------------------------------------------------
    initial begin
        for (i = 0; i < N/2; i = i + 1) begin
            tw_re[i] = $rtoi(32767.0 * $cos(2.0*3.141592653589793*i/N));
            tw_im[i] = $rtoi(32767.0 * $sin(-2.0*3.141592653589793*i/N));
        end

        for (i = 0; i < N; i = i + 1) begin
            re_mem[i] = 0;
            im_mem[i] = 0;
            re_out[i] = 0;
            im_out[i] = 0;
        end
    end

    // --------------------------------------------------------
    // Main FFT state machine
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            sample_ready<= 1'b0;
            done        <= 1'b0;
            load_count  <= 0;
            stage       <= 0;
            group       <= 0;
            butterfly   <= 0;
        end
        else begin
            done <= 1'b0;

            case (state)

                S_IDLE: begin
                    sample_ready <= 1'b0;

                    if (start) begin
                        load_count   <= 0;
                        sample_ready <= 1'b1;
                        state        <= S_LOAD;
                    end
                end

                // ------------------------------------------------
                // Load 1024 time-domain samples.
                // sample_in is already DC-removed Q1.15.
                // ------------------------------------------------
                S_LOAD: begin
                    sample_ready <= 1'b1;

                    if (sample_valid) begin
                        re_mem[load_count] <= {{16{sample_in[15]}},sample_in};
                        im_mem[load_count] <= 32'sd0;

                        if (load_count == N-1) begin
                            sample_ready <= 1'b0;
                            j <= 0;
                            i <= 1;
                            state <= S_BITREV;
                        end
                        else begin
                            load_count <= load_count + 1;
                        end
                    end
                end

                // ------------------------------------------------
                // Bit reversal permutation.
                // ------------------------------------------------
                S_BITREV: begin
                    if (i < N) begin
                        k = N >> 1;

                        while ((j & k) != 0) begin
                            j = j ^ k;
                            k = k >> 1;
                        end

                        j = j ^ k;

                        if (i < j) begin
                            a_re = re_mem[i];
                            a_im = im_mem[i];

                            re_mem[i] <= re_mem[j];
                            im_mem[i] <= im_mem[j];

                            re_mem[j] <= a_re;
                            im_mem[j] <= a_im;
                        end

                        i <= i + 1;
                    end
                    else begin
                        stage     <= 1;
                        group     <= 0;
                        butterfly <= 0;
                        state     <= S_BFLY_READ;
                    end
                end

                // ------------------------------------------------
                // Read butterfly operands.
                // ------------------------------------------------
                S_BFLY_READ: begin
                    // FFT stage has:
                    // half_size = 2^(stage-1)
                    // group length = 2*half_size

                    addr_a = group + butterfly;
                    addr_b = addr_a + (1 << (stage-1));

                    tw_idx = butterfly * (N >> stage);

                    a_re = re_mem[addr_a];
                    a_im = im_mem[addr_a];

                    b_re = re_mem[addr_b];
                    b_im = im_mem[addr_b];

                    state <= S_BFLY_CALC;
                end

                // ------------------------------------------------
                // Complex multiplication:
                //
                // t = b * W
                //
                // W is Q1.15, so arithmetic is shifted right 15.
                // ------------------------------------------------
                S_BFLY_CALC: begin
                    mult1 = b_re * tw_re[tw_idx];
                    mult2 = b_im * tw_im[tw_idx];
                    mult3 = b_re * tw_im[tw_idx];
                    mult4 = b_im * tw_re[tw_idx];

                    t_re = (mult1 - mult2) >>> 15;
                    t_im = (mult3 + mult4) >>> 15;

                    state <= S_BFLY_WRITE;
                end

                // ------------------------------------------------
                // Butterfly:
                //
                // X[a] = A + T
                // X[b] = A - T
                // ------------------------------------------------
                S_BFLY_WRITE: begin
                    re_mem[addr_a] <= a_re + t_re;
                    im_mem[addr_a] <= a_im + t_im;

                    re_mem[addr_b] <= a_re - t_re;
                    im_mem[addr_b] <= a_im - t_im;

                    if (butterfly == ((1 << (stage-1))-1)) begin

                        butterfly <= 0;

                        if (group == N-(1 << stage)) begin
                            group <= 0;

                            if (stage == 10) begin
                                state <= S_DONE;
                            end
                            else begin
                                stage <= stage + 1;
                                state <= S_BFLY_READ;
                            end
                        end
                        else begin
                            group <= group + (1 << stage);
                            state <= S_BFLY_READ;
                        end

                    end
                    else begin
                        butterfly <= butterfly + 1;
                        state <= S_BFLY_READ;
                    end
                end

                // ------------------------------------------------
                // Copy final FFT data to output ports.
                // ------------------------------------------------
                S_DONE: begin
                    for (i = 0; i < N; i = i + 1) begin
                        re_out[i] <= re_mem[i];
                        im_out[i] <= im_mem[i];
                    end

                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
