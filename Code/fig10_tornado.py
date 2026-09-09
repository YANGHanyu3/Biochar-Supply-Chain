"""
fig10_tornado.py — tornado diagram of one-at-a-time sensitivity
Usage: python fig10_tornado.py [scenario]
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

s = pd.read_csv(os.path.join(resdir, "sensitivity_v2.csv"))
base = s[s.case == "baseline"].iloc[0]
s = s[s.case != "baseline"].copy()

# pair low/high for each parameter
params = {
    "farmgate": ("farmgate -20%", "farmgate +20%", "Farmgate price −20%"),
    "transport": ("transport -20%", "transport +20%", "Transport cost −20%"),
    "demand cap": ("demand cap -20%", "demand cap +20%", "Demand capacity −20%"),
    "demand price": ("demand price -20%", "demand price +20%", "Demand price −20%"),
    "sink": ("sink $0", "sink $60", "Sink value $0-60"),
}
rows = []
for key, (lo, hi, label) in params.items():
    vlo = s[s.case == lo]["profit_M"].values[0]
    vhi = s[s.case == hi]["profit_M"].values[0]
    rows.append((label, vlo, vhi))
# one-sided supply shock (proxy for field-collection losses), reported in §3.8
avail = s[s.case == "supply cap -40%"]["profit_M"].values[0]
rows.append(("Feedstock availability −40%", avail, base.profit_M))
rows.sort(key=lambda r: abs(r[1] - base.profit_M) + abs(r[2] - base.profit_M))

labels = [r[0] for r in rows]
lo_vals = np.array([r[1] - base.profit_M for r in rows])
hi_vals = np.array([r[2] - base.profit_M for r in rows])

fig, ax = plt.subplots(figsize=(7.8, 4.7))
y = np.arange(len(rows))
ax.barh(y, lo_vals, color=FS.GRAY, alpha=0.9, label="low (−20%)")
ax.barh(y, hi_vals, color=FS.DEEP, alpha=0.9, label="high (+20%)")
ax.axvline(0, color="k", lw=0.8)
ax.set_yticks(y); ax.set_yticklabels(labels)
ax.set_xlabel(f"Change in system surplus (M USD/yr) vs baseline {base.profit_M:.0f} M USD/yr")
ax.set_title(f"One-at-a-time sensitivity of S0 surplus ({scen})", fontweight="bold")
ax.legend(loc="lower right")
fig.savefig(os.path.join(figdir, "fig10_tornado.png"))
plt.close(fig)
print("saved fig10_tornado.png")
