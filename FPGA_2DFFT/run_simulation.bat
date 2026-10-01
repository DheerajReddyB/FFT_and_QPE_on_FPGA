@echo off
echo Running 2D FFT Simulation...
cd /d "D:\SEM-7\Project_Phase_1\FPGA_2DFFT"
"C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe" -c -do "run_sim.do"
pause
