"""
plot_fft2d.py — Plot the 2D FFT output from ModelSim simulation

Run AFTER the simulation has generated fft2d_output.csv:
    python plot_fft2d.py

Requires:  pip install numpy matplotlib pandas
"""

import numpy as np
import matplotlib.pyplot as plt
import pandas as pd
import os

# ── Load CSV ──────────────────────────────────────────────────────────────────
csv_path = os.path.join(os.path.dirname(__file__), "fft2d_output.csv")

if not os.path.exists(csv_path):
    print("ERROR: fft2d_output.csv not found.")
    print("  → Run the ModelSim simulation first:")
    print('       vsim.exe -c -do run_sim.do')
    exit(1)

df = pd.read_csv(csv_path)
N = 16

# ── Reshape into 16×16 grids ─────────────────────────────────────────────────
mag_grid = df["magnitude"].values.reshape(N, N)
db_grid  = df["magnitude_dB"].values.reshape(N, N)
db_grid  = np.clip(db_grid, -60, 0)   # Clip floor at -60 dB

# Frequency axis labels (0..15 bins, fs=200 kHz → 0..187.5 kHz)
fs   = 200e3
bins = np.arange(N)
freq_labels = [f"{int(k*fs/N/1000)}" for k in bins]  # kHz

# ── Figure layout ─────────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(18, 6))
fig.suptitle("2D FFT Output  —  10 kHz sine, fs=200 kHz, 16×16 grid",
             fontsize=14, fontweight="bold")

# ── Plot 1: Raw magnitude (linear) ────────────────────────────────────────────
ax = axes[0]
im = ax.imshow(mag_grid, cmap="hot", aspect="auto", origin="upper")
fig.colorbar(im, ax=ax, label="Magnitude (raw)")
ax.set_title("Linear Magnitude")
ax.set_xlabel("Column frequency bin")
ax.set_ylabel("Row frequency bin")
ax.set_xticks(bins); ax.set_xticklabels(freq_labels, rotation=45, fontsize=8)
ax.set_yticks(bins); ax.set_yticklabels(freq_labels, fontsize=8)
# Mark peak
peak_idx = np.unravel_index(np.argmax(mag_grid), mag_grid.shape)
ax.plot(peak_idx[1], peak_idx[0], "c*", markersize=14,
        label=f"Peak @ Row={peak_idx[0]}, Col={peak_idx[1]}")
ax.legend(fontsize=8, loc="upper right")

# ── Plot 2: dB magnitude ──────────────────────────────────────────────────────
ax = axes[1]
im = ax.imshow(db_grid, cmap="viridis", aspect="auto", origin="upper",
               vmin=-60, vmax=0)
fig.colorbar(im, ax=ax, label="dB (rel. to peak)")
ax.set_title("Magnitude (dB, floor −60 dB)")
ax.set_xlabel("Column frequency bin")
ax.set_ylabel("Row frequency bin")
ax.set_xticks(bins); ax.set_xticklabels(freq_labels, rotation=45, fontsize=8)
ax.set_yticks(bins); ax.set_yticklabels(freq_labels, fontsize=8)
ax.plot(peak_idx[1], peak_idx[0], "r*", markersize=14,
        label=f"Peak @ ({peak_idx[0]},{peak_idx[1]})")
ax.legend(fontsize=8, loc="upper right")

# ── Plot 3: 1D column-spectrum at the peak row ────────────────────────────────
ax = axes[2]
peak_row_data = mag_grid[peak_idx[0], :]
mirror_row    = N - 1 - peak_idx[0]
mirror_data   = mag_grid[mirror_row, :]

freq_axis = np.arange(N) * fs / N / 1e3   # kHz

ax.stem(freq_axis, peak_row_data,    linefmt="C0-", markerfmt="C0o",
        basefmt="k-", label=f"Row {peak_idx[0]} (peak row)")
ax.stem(freq_axis, mirror_data,      linefmt="C1--", markerfmt="C1^",
        basefmt="k-", label=f"Row {mirror_row} (mirror alias)")
ax.axvline(10, color="red", linestyle=":", linewidth=1.5, label="10 kHz signal")
ax.set_title("1D slice at peak row")
ax.set_xlabel("Frequency (kHz)")
ax.set_ylabel("Magnitude")
ax.legend(fontsize=8)
ax.set_xlim(0, fs/1e3)
ax.grid(True, alpha=0.3)

# Annotation box
textstr = (
    f"Signal:    10 kHz\n"
    f"fs:        200 kHz\n"
    f"N per dim: 16\n"
    f"Bin width: {fs/N/1000:.1f} kHz\n"
    f"Frac bin:  {16*10e3/fs:.2f}\n"
    f"Peak bin:  Col={peak_idx[1]}, Row={peak_idx[0]}"
)
ax.text(0.98, 0.97, textstr, transform=ax.transAxes,
        verticalalignment="top", horizontalalignment="right",
        fontsize=8, family="monospace",
        bbox=dict(boxstyle="round", facecolor="wheat", alpha=0.7))

plt.tight_layout()
out_path = os.path.join(os.path.dirname(__file__), "fft2d_spectrum.png")
plt.savefig(out_path, dpi=150, bbox_inches="tight")
print(f"Plot saved: {out_path}")
plt.show()
