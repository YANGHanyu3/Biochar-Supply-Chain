"""
fig11_v2b_mix.py - BC300/BC500 technology mix vs credit price (v2b)
Panels: near-term (Paradigm A) | mature-market medium (Paradigm A)
ASCII labels, USD units.
Usage: python fig11_v2b_mix.py
"""
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import figstyle as FS

FS.apply()
C300 = FS.DEEP; C500 = FS.LIGHT

fig, axes = plt.subplots(1, 2, figsize=(9.8, 4.2))
for ax, scen in zip(axes, ["near-term", "mature-market medium"]):
    f = os.path.join("results_v2b", scen, "policy_A_bnc_sweep_v2b.csv")
    if not os.path.exists(f):
        print("skip", scen)
        continue
    a = pd.read_csv(f)
    x = np.arange(len(a)); w = 0.4
    ax.bar(x - w / 2, a.bc300_Mt, w, color=C300, label="BC300 (300C)")
    ax.bar(x + w / 2, a.bc500_Mt, w, color=C500, label="BC500 (500C)")
    ax.set_xticks(x)
    ax.set_xticklabels([f"{int(p)}" for p in a.p_c])
    ax.set_xlabel("Credit price (USD/tCO2e)")
    ax.set_ylabel("Biochar (Mt/yr)")
    ax.set_title(scen, fontweight="bold")
    FS.panel_label(ax, 0 if scen == "near-term" else 1)
    ax.legend(fontsize=9.5)
    ax.set_ylim(0, 5.2)
    if scen == "mature-market medium":
        ax.annotate(f"p$_c$ = \$50 is demand-bound\n(below the ≈\$61/t crossover)",
                    xy=(2, 3.9), xytext=(2.05, 4.2), fontsize=8, color=FS.INK,
                    ha="center")
fig.suptitle("Technology mix under baseline-and-credit (v2b quality-differentiated model)",
             fontweight="bold")
fig.tight_layout(rect=[0, 0, 1, 0.95])
fig.savefig("results_v2b/fig11_v2b_mix.png")
plt.close(fig)
print("saved results_v2b/fig11_v2b_mix.png")
