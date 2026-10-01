"""
plot_two_targets.py
Plots all 3 two-target resolution test cases side by side.
Run after simulations have generated the 3 CSV files.
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

fs  = 200000.0
N   = 16
AMP = 819.0

cases = [
    {"csv": "case1_25k_50k.csv", "f1": 25000, "f2": 50000,
     "label": "Case 1  f1=25 kHz,  f2=50 kHz\n2.0 bins apart  [EASY]",    "color": "green"},
    {"csv": "case2_25k_37k.csv", "f1": 25000, "f2": 37500,
     "label": "Case 2  f1=25 kHz,  f2=37.5 kHz\n1.0 bin  apart  [BORDERLINE]", "color": "orange"},
    {"csv": "case3_25k_31k.csv", "f1": 25000, "f2": 31250,
     "label": "Case 3  f1=25 kHz,  f2=31.25 kHz\n0.5 bins apart  [HARD]",  "color": "red"},
]

fig, axes = plt.subplots(3, 3, figsize=(18, 14))
fig.suptitle(
    "2D FFT Two-Target Resolution Test\n"
    "Bin width = fs/N = 200 kHz / 16 = 12.5 kHz   |   Can FPGA FFT separate two close targets?",
    fontsize=13, fontweight="bold",
)

bins = np.arange(N)
flbl = [str(int(k * fs / N / 1000)) for k in bins]

for row_idx, c in enumerate(cases):
    df  = pd.read_csv(c["csv"])
    mag = df["magnitude"].values.reshape(N, N)
    peak_val = mag.max()
    db  = np.where(mag > 0.001,
                   20 * np.log10(mag / peak_val),
                   -80)
    db  = np.clip(db, -60, 0)
    pk  = np.unravel_index(np.argmax(mag), mag.shape)

    f1_label = "{:.1f}".format(c["f1"] / 1000)
    f2_label = "{:.2f}".format(c["f2"] / 1000)
    b1 = c["f1"] * N / fs   # fractional bin
    b2 = c["f2"] * N / fs

    # ── Column 0: 2D dB heatmap ─────────────────────────────
    ax = axes[row_idx, 0]
    im = ax.imshow(db, cmap="viridis", aspect="auto", origin="upper",
                   vmin=-60, vmax=0)
    fig.colorbar(im, ax=ax, label="dB rel. peak")
    ax.set_title(c["label"], color=c["color"], fontweight="bold", fontsize=10)
    ax.set_xlabel("Col freq bin (kHz)")
    ax.set_ylabel("Row freq bin (kHz)")
    ax.set_xticks(bins[::2])
    ax.set_xticklabels(flbl[::2], rotation=45, fontsize=7)
    ax.set_yticks(bins[::2])
    ax.set_yticklabels(flbl[::2], fontsize=7)
    ax.axvline(b1, color="cyan",   linestyle="--", lw=1.5,
               label="f1={} kHz (bin {:.1f})".format(f1_label, b1))
    ax.axvline(b2, color="yellow", linestyle="--", lw=1.5,
               label="f2={} kHz (bin {:.1f})".format(f2_label, b2))
    ax.legend(fontsize=7, loc="upper right")

    # ── Column 1: 1D slice along Row 0 ──────────────────────
    ax = axes[row_idx, 1]
    fa    = np.arange(N) * fs / N / 1e3
    row0  = mag[0, :]
    ax.stem(fa, row0, linefmt="b-", markerfmt="bo", basefmt="k-")
    ax.axvline(c["f1"] / 1e3, color="cyan", linestyle="--", lw=2,
               label="Target 1: {} kHz".format(f1_label))
    ax.axvline(c["f2"] / 1e3, color="red",  linestyle="--", lw=2,
               label="Target 2: {} kHz".format(f2_label))
    ax.set_xlabel("Frequency (kHz)")
    ax.set_ylabel("Magnitude")
    ax.legend(fontsize=8)
    ax.grid(True, alpha=0.3)

    sorted_idx = np.argsort(row0)[::-1]
    p1_m, p2_m = row0[sorted_idx[0]], row0[sorted_idx[1]]
    ratio = p2_m / p1_m if p1_m > 0 else 0
    if ratio > 0.5:
        verdict = "RESOLVED  ✓"
        vc = "green"
    elif ratio > 0.2:
        verdict = "MARGINAL  ~"
        vc = "orange"
    else:
        verdict = "NOT RESOLVED  ✗"
        vc = "red"
    ax.set_title("Row=0 slice  |  Peak ratio = {:.2f}  →  {}".format(ratio, verdict),
                 color=vc, fontsize=9, fontweight="bold")

    # ── Column 2: Input signal (first 80 samples) ───────────
    ax = axes[row_idx, 2]
    nn = np.arange(80)
    x1 = AMP * np.sin(2 * np.pi * c["f1"] * nn / fs)
    x2 = AMP * np.sin(2 * np.pi * c["f2"] * nn / fs)
    ax.plot(nn, x1 + x2, "b-",  lw=1.5, label="Combined signal")
    ax.plot(nn, x1,       "c--", lw=0.9, alpha=0.75,
            label="Target 1 ({} kHz)".format(f1_label))
    ax.plot(nn, x2,       "r--", lw=0.9, alpha=0.75,
            label="Target 2 ({} kHz)".format(f2_label))
    ax.set_title("Input Signal (first 80 samples)")
    ax.set_xlabel("Sample n")
    ax.set_ylabel("ADC counts")
    ax.legend(fontsize=7)
    ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig("two_targets_resolution.png", dpi=150, bbox_inches="tight")
print("Saved: two_targets_resolution.png")
