vlib work
vmap work work
vlog -work work twiddle_rom.v
vlog -work work butterfly_unit.v
vlog -work work fft_1d.v
vlog -work work fft_2d.v
vlog -work work quartic_interp.v
vlog -work work peak_finder_dual.v
vlog -work work quartic_dual_top.v
vlog -work work tb_fft_only_two_targets.v
vsim -c work.tb_fft_only_two_targets
run -all
quit -f
