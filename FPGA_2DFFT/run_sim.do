# ModelSim run script for 2D FFT simulation
# Run from the FPGA_2DFFT directory:
#   vsim -do run_sim.do

vlib work
vmap work work

# Compile all design files
vlog -work work twiddle_rom.v
vlog -work work butterfly_unit.v
vlog -work work fft_1d.v
vlog -work work fft_2d.v
vlog -work work tb_fft_2d.v

# Simulate – run until $finish
vsim -c work.tb_fft_2d -do "run -all; quit -f"
