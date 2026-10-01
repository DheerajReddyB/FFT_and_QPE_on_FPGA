`timescale 1ns/1ps
// ============================================================
// fft_2d.v  –  16×16-point 2D FFT  (Row-Column Decomposition)
//
// Algorithm:
//   1. Load 256 input samples into internal memory via wr_en interface.
//   2. Pulse start.
//   3. Perform 16 row-FFTs  (rows 0..15, each is a 16-point FFT).
//   4. Perform 16 col-FFTs  (columns 0..15).
//   5. Assert done.  Results readable via rd_addr/rd_re/rd_im.
//
// Memory layout: mem[row*16 + col]  (row-major, 8-bit address 0..255)
//
// Timing:
//   One 16-point FFT ≈ 48 cycles (16 load + 32 compute)
//   Writeback        ≈ 16 cycles
//   32 FFTs total   ≈ 32 × 64 = ~2048 cycles for full 2D FFT
//
// ============================================================

module fft_2d (
    input  wire        clk,
    input  wire        rst,

    // ── Input loading (must complete before asserting start) ──
    input  wire        wr_en,            // Write strobe
    input  wire [7:0]  wr_addr,          // 0..255  (row*16+col)
    input  wire signed [31:0] wr_re,     // Real part of sample
    input  wire signed [31:0] wr_im,     // Imaginary part of sample

    // ── Control ──
    input  wire        start,            // Pulse to begin 2D FFT
    output reg         done,             // Asserted when complete

    // ── Output read (async, valid after done) ──
    input  wire [7:0]  rd_addr,
    output wire signed [31:0] rd_re,
    output wire signed [31:0] rd_im
);

    localparam N    = 16;
    localparam SIZE = 256; // N*N

    // ──────────────────────────────────────────────────────────
    // Internal complex memory  (row-major, 256 entries)
    // ──────────────────────────────────────────────────────────
    reg signed [31:0] mem_re [0:SIZE-1];
    reg signed [31:0] mem_im [0:SIZE-1];

    assign rd_re = mem_re[rd_addr];
    assign rd_im = mem_im[rd_addr];

    // ──────────────────────────────────────────────────────────
    // State machine
    // ──────────────────────────────────────────────────────────
    localparam S_IDLE     = 3'd0;
    localparam S_ROW_LOAD = 3'd1;   // Feed one row into FFT1D
    localparam S_ROW_FFT  = 3'd2;   // Wait for FFT1D done
    localparam S_ROW_WB   = 3'd3;   // Write-back row results
    localparam S_COL_LOAD = 3'd4;   // Feed one column into FFT1D
    localparam S_COL_FFT  = 3'd5;   // Wait for FFT1D done
    localparam S_COL_WB   = 3'd6;   // Write-back column results
    localparam S_DONE     = 3'd7;

    reg [2:0] state;
    reg [3:0] rc_idx;   // Current row or column index (0..15)
    reg [3:0] el_idx;   // Element index within row/col (0..15)
    reg       col_mode; // 0 = row-FFT phase, 1 = col-FFT phase

    // ──────────────────────────────────────────────────────────
    // FFT-1D interface
    // ──────────────────────────────────────────────────────────
    reg  fft1d_start;
    wire fft1d_done;

    // Data to FFT-1D: directly from memory (wire mux, no register latency)
    wire [7:0] load_mem_addr = col_mode ? {el_idx, rc_idx} : {rc_idx, el_idx};
    wire signed [31:0] fft1d_din_re = mem_re[load_mem_addr];
    wire signed [31:0] fft1d_din_im = mem_im[load_mem_addr];

    // Read-back from FFT-1D: driven by el_idx (combinational)
    wire [3:0]  fft1d_rd_addr = el_idx[3:0];
    wire signed [31:0] fft1d_rd_re;
    wire signed [31:0] fft1d_rd_im;

    fft_1d fft1d_inst (
        .clk     (clk),
        .rst     (rst),
        .start   (fft1d_start),
        .din_re  (fft1d_din_re),
        .din_im  (fft1d_din_im),
        .rd_addr (fft1d_rd_addr),
        .rd_re   (fft1d_rd_re),
        .rd_im   (fft1d_rd_im),
        .done    (fft1d_done)
    );

    // ──────────────────────────────────────────────────────────
    // State machine logic
    // ──────────────────────────────────────────────────────────
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            rc_idx     <= 4'd0;
            el_idx     <= 4'd0;
            col_mode   <= 1'b0;
            fft1d_start<= 1'b0;
            done       <= 1'b0;
            for (i = 0; i < SIZE; i = i + 1) begin
                mem_re[i] <= 32'sd0;
                mem_im[i] <= 32'sd0;
            end
        end else begin
            fft1d_start <= 1'b0; // Default: deassert

            // Allow writes to memory at any time in IDLE
            if (wr_en && state == S_IDLE) begin
                mem_re[wr_addr] <= wr_re;
                mem_im[wr_addr] <= wr_im;
            end

            case (state)
                // ────────────────────────────
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state    <= S_ROW_LOAD;
                        rc_idx   <= 4'd0;
                        el_idx   <= 4'd0;
                        col_mode <= 1'b0;
                        fft1d_start <= 1'b1; // Start FFT-1D for row 0
                    end
                end

                // ────────────────────────────
                // ROW phase
                // ────────────────────────────

                // Advance el_idx to drive data into FFT-1D (via wire).
                // FFT-1D captures el_idx=0 on the same clock fft1d_start=1 (in IDLE state).
                // Then captures el_idx=1..15 on subsequent clocks (in LOAD state).
                S_ROW_LOAD: begin
                    if (el_idx == 4'd15) begin
                        state  <= S_ROW_FFT;
                        el_idx <= 4'd0;
                    end else begin
                        el_idx <= el_idx + 4'd1;
                    end
                end

                S_ROW_FFT: begin
                    if (fft1d_done) begin
                        state  <= S_ROW_WB;
                        el_idx <= 4'd0;
                    end
                end

                // Write-back 16 results from FFT-1D into row rc_idx of memory
                S_ROW_WB: begin
                    mem_re[{rc_idx, el_idx}] <= fft1d_rd_re;
                    mem_im[{rc_idx, el_idx}] <= fft1d_rd_im;

                    if (el_idx == 4'd15) begin
                        el_idx <= 4'd0;
                        if (rc_idx == 4'd15) begin
                            // All rows done → switch to column phase
                            state    <= S_COL_LOAD;
                            rc_idx   <= 4'd0;
                            col_mode <= 1'b1;
                            fft1d_start <= 1'b1;
                        end else begin
                            state  <= S_ROW_LOAD;
                            rc_idx <= rc_idx + 4'd1;
                            fft1d_start <= 1'b1;
                        end
                    end else begin
                        el_idx <= el_idx + 4'd1;
                    end
                end

                // ────────────────────────────
                // COL phase (symmetric to ROW)
                // ────────────────────────────
                S_COL_LOAD: begin
                    if (el_idx == 4'd15) begin
                        state  <= S_COL_FFT;
                        el_idx <= 4'd0;
                    end else begin
                        el_idx <= el_idx + 4'd1;
                    end
                end

                S_COL_FFT: begin
                    if (fft1d_done) begin
                        state  <= S_COL_WB;
                        el_idx <= 4'd0;
                    end
                end

                // Write-back 16 results into column rc_idx
                S_COL_WB: begin
                    mem_re[{el_idx, rc_idx}] <= fft1d_rd_re;
                    mem_im[{el_idx, rc_idx}] <= fft1d_rd_im;

                    if (el_idx == 4'd15) begin
                        el_idx <= 4'd0;
                        if (rc_idx == 4'd15) begin
                            state <= S_DONE;
                        end else begin
                            state  <= S_COL_LOAD;
                            rc_idx <= rc_idx + 4'd1;
                            fft1d_start <= 1'b1;
                        end
                    end else begin
                        el_idx <= el_idx + 4'd1;
                    end
                end

                // ────────────────────────────
                S_DONE: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule
