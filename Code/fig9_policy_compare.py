"""
fig9_policy_compare.py - policy comparison panel (A/B/C across paradigms)
From v2 results CSVs. Panels:
  I   production vs policy price (A, C: credit price $/tCO2e)
  II  surplus vs policy price      (A, C: credit price $/tCO2e)
  III net GHG under A vs credit price
  IV  B: production & surplus vs gross-emission cap (kt CO2e)  -- separate unit
This removes the two-unit axis of the previous version (A/C in $/t on the same
axis as B in kt) and the MAC panel duplicated in fig7.
Usage: python fig9_policy_compare.py [scenario]
"""
import sys, os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
resdir = f"results_v2/{scen}"
figdir = os.path.join(resdir, "figures")
os.makedirs(figdir, exist_ok=True)

import figstyle as FS
FS.apply()
C_A = FS.DEEP; C_B = FS.GRAY; C_C = FS.LIGHT; C_B2 = FS.ACCENT

def load(p):
    return pd.read_csv(os.path.join(resdir, p))

a = load("policy_A_bnc_sweep_v2.csv")
b = load("policy_B1_cap_sweep_MAC_v2.csv")
c2 = load("policy_C2_tax_credit_v2.csv")

fig, axes = plt.subplots(2, 2, figsize=(10.2, 7.4))

# I. BC production vs credit price (A and C share the same $/t axis)
ax = axes[0,0]
ax.plot(a.p_c, a.bc_Mt, "o-", color=C_A, lw=2, label="A: baseline-and-credit")
ax.plot(c2.p_c, c2.bc, "^-", color=C_C, lw=2, label="C: VM0044 credit")
ax.set_xlabel("Credit price (USD/tCO$_2$e)")
ax.set_ylabel("Biochar (Mt/yr)")
ax.set_title("Production response", fontweight="bold"); ax.legend(fontsize=8.5)
FS.panel_label(ax, 0)

# II. Surplus vs credit price (A and C)
ax = axes[0,1]
ax.plot(a.p_c, a.profit_M, "o-", color=C_A, lw=2, label="A: baseline-and-credit")
ax.plot(c2.p_c, c2.profit, "^-", color=C_C, lw=2, label="C: VM0044 credit")
ax.set_xlabel("Credit price (USD/tCO$_2$e)")
ax.set_ylabel("System surplus (M USD/yr)")
ax.set_title("Surplus", fontweight="bold")
FS.panel_label(ax, 1)

# III. Net GHG under A
ax = axes[1,0]
ax.plot(a.p_c, a.ghg_Mt, "o-", color=C_A, lw=2)
ax.axhline(0, color="k", lw=0.7)
ax.set_xlabel("Credit price (USD/tCO$_2$e)")
ax.set_ylabel("Net GHG (Mt CO$_2$e/yr)")
ax.set_title("Net GHG under A", fontweight="bold")
FS.panel_label(ax, 2)

# IV. Paradigm B: production & surplus vs gross-emission cap (own unit, kt)
ax = axes[1,1]
ax2 = ax.twinx()
ax.plot(b.cap_kt, b.bc_Mt, "s-", color=C_B, lw=2, label="Biochar")
ax2.plot(b.cap_kt, b.profit_M, "^-", color=C_B2, lw=2, label="Surplus")
ax.annotate("cap tightens", xy=(b.cap_kt.min(), b.bc_Mt.iloc[-1]),
            xytext=(b.cap_kt.min() + 60, b.bc_Mt.iloc[-1] + 0.05),
            fontsize=8, color=C_B, arrowprops=dict(arrowstyle="->", color=C_B, lw=1.0))
ax.set_xlabel("Gross-emission cap (kt CO$_2$e/yr)")
ax.set_ylabel("Biochar (Mt/yr)", color=C_B)
ax2.set_ylabel("System surplus (M USD/yr)", color=C_B2)
ax.tick_params(axis="y", labelcolor=C_B); ax2.tick_params(axis="y", labelcolor=C_B2)
ax.set_title("Paradigm B: cap-and-trade", fontweight="bold")
FS.panel_label(ax, 3)
h1, l1 = ax.get_legend_handles_labels(); h2, l2 = ax2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, fontsize=8.5, loc="lower left")

fig.suptitle(f"Policy comparison across paradigms A/B/C ({scen})", fontweight="bold")
fig.tight_layout(rect=[0, 0, 1, 0.96])
fig.savefig(os.path.join(figdir, "fig9_policy_compare.png"))
plt.close(fig)
print("saved fig9_policy_compare.png")
