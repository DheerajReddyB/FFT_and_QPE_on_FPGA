vlib work
vmap work work
vlog -work work twiddle_rom.v butterfly_unit.v fft_1d.v fft_2d.v tb_fft_2d_two_targets.v
vsim -c work.tb_fft_2d_two_targets
run -all
quit -f
