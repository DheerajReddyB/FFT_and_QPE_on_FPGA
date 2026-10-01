# ModelSim GUI run script
# Opens the waveform viewer so you can inspect signals

vlib work
vmap work work

vlog -work work twiddle_rom.v
vlog -work work butterfly_unit.v
vlog -work work fft_1d.v
vlog -work work fft_2d.v
vlog -work work tb_fft_2d.v

# Load simulation (with GUI)
vsim work.tb_fft_2d

# Add useful signals to waveform window
add wave -divider "Clock/Reset"
add wave /tb_fft_2d/clk
add wave /tb_fft_2d/rst

add wave -divider "Control"
add wave /tb_fft_2d/start
add wave /tb_fft_2d/done

add wave -divider "Write Interface"
add wave /tb_fft_2d/wr_en
add wave -radix unsigned /tb_fft_2d/wr_addr
add wave -radix decimal  /tb_fft_2d/wr_re

add wave -divider "2D FFT State"
add wave /tb_fft_2d/dut/state
add wave -radix unsigned /tb_fft_2d/dut/rc_idx
add wave -radix unsigned /tb_fft_2d/dut/el_idx
add wave /tb_fft_2d/dut/col_mode

add wave -divider "FFT-1D Interface"
add wave /tb_fft_2d/dut/fft1d_start
add wave /tb_fft_2d/dut/fft1d_done
add wave -radix decimal  /tb_fft_2d/dut/fft1d_din_re
add wave -radix decimal  /tb_fft_2d/dut/fft1d_din_im

add wave -divider "FFT-1D Internal State"
add wave /tb_fft_2d/dut/fft1d_inst/state
add wave -radix unsigned /tb_fft_2d/dut/fft1d_inst/cnt
add wave -radix unsigned /tb_fft_2d/dut/fft1d_inst/stage

add wave -divider "Read Output"
add wave -radix unsigned /tb_fft_2d/rd_addr
add wave -radix decimal  /tb_fft_2d/rd_re
add wave -radix decimal  /tb_fft_2d/rd_im

# Run simulation
run -all

# Zoom waveform to fit
wave zoom full
