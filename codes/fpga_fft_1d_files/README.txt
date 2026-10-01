FIRST FPGA FFT TEST
===================

Signal:
    x[n] = 0.4 + 0.5*sin(2*pi*10000*n/200000)

Before FFT:
    DC offset 0.4 is removed.

FFT:
    N = 1024
    Fs = 200 kHz
    radix-2 DIT

Expected:
    Frequency bin spacing = 195.3125 Hz
    Actual signal location = 51.2 bins
    Largest FFT bin should be around bin 51
    Raw FFT frequency at bin 51 = 9960.9375 Hz

Files:
    fft_1024.v
    fft_testbench.v

Icarus Verilog:
    iverilog -g2012 -o fft_sim fft_1024.v fft_testbench.v
    vvp fft_sim

NOTE:
This is the first verification RTL. The twiddle ROM is initialized
with real-valued expressions for simulation. For synthesis on the
actual FPGA, we will replace this with a fixed-point ROM generated
from a coefficient file / FPGA block RAM.
