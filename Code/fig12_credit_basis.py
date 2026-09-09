"""
fig12_credit_basis.py - credit basis and the 300C/500C technology crossover
=========================================================================
Deterministic (parameter-driven) figure, cross-checked against model runs:
  (a) Carbon credit rates per t dry biomass under the two credit bases:
      baseline-and-credit (LCFS-style, B - E+ - S per t dry) vs
      VM0044 (sequestration-based, gated by H/C <= 0.7), for representative
      feedstocks and both pyrolysis temperatures.
  (b) The 500C margin premium over 300C in TWO resource regimes:
      - demand-bound (feedstock abundant, e.g. mature-market): the binding
        resource is biochar demand, and 500C's LOWER yield multiplies credit
        revenue per tonne of biochar served: crossover at p_c ~ $61/t for all
        demand segments.
      - supply-bound (feedstock scarce, e.g. near-term): per-dry-tonne
        margins rule, and the 300C yield advantage keeps it optimal until
        p_c ~ $240/t for the bulk ($250) segment.
Usage: python fig12_credit_basis.py
"""
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11,
                     "axes.spines.top": False, "axes.spines.right": False,
                     "figure.dpi": 200, "savefig.dpi": 300, "savefig.bbox": "tight"})
import figstyle as FS
FS.apply()
C_A = FS.DEEP; C_C = FS.GRAY; C_300 = FS.DEEP; C_500 = FS.LIGHT; C_GREY = "#BFBFBF"

N_FS = 13
ghg = pd.read_csv("biochar_data_v2/near-term/ghg_factors_v2.csv")
alpha = pd.read_csv("biochar_data_v2/near-term/alpha_matrix.csv", header=None).values
names = [g.replace("T1_Dehyd_", "").replace("T2300C_Pyrol_", "").replace("T2500C_Pyrol_", "")
         for g in ghg.tech_name.values]

pghg = dict(zip(ghg.tech_id.values, ghg.process_ghg_per_t_ref.values))
sghg = dict(zip(ghg.tech_id.values, ghg.ghg_seq_per_t_bc.values + ghg.ghg_n2o_per_t_bc.values))
bghg = dict(zip(ghg.tech_id.values, ghg.baseline_ghg_per_t_ref.values))

rate_bc = {}; rate_v44 = {}
y3s, y5s, r3s, r5s = [], [], [], []
for f in range(N_FS):
    t1, t2, t2b = f + 1, N_FS + f + 1, 2 * N_FS + f + 1
    eta_f = alpha[f, N_FS + f]
    y3 = alpha[t2 - 1, 2 * N_FS]; y5 = alpha[t2b - 1, 2 * N_FS]
    b = bghg[t1] / eta_f
    e3 = pghg[t1] / eta_f + pghg[t2]
    e5 = pghg[t1] / eta_f + pghg[t2b]
    s3 = sghg[t2] * y3; s5 = sghg[t2b] * y5
    rate_bc[(f, 3)] = (b - e3 - s3) / 1000.0
    rate_bc[(f, 5)] = (b - e5 - s5) / 1000.0
    rate_v44[(f, 3)] = alpha[t2 - 1, 2 * N_FS + 1]
    rate_v44[(f, 5)] = alpha[t2b - 1, 2 * N_FS + 1]
    y3s.append(y3); y5s.append(y5); r3s.append(rate_bc[(f, 3)]); r5s.append(rate_bc[(f, 5)])

y3 = float(np.mean(y3s)); y5 = float(np.mean(y5s))
r3 = float(np.mean(r3s)); r5 = float(np.mean(r5s))
C_DRY = 130.0   # marginal cost of a dry tonne (farmgate ~60 + T1/T2 opex ~36 + transport ~15 + capex ~20)

# (b) demand-bound regime: margin premium per tonne of BIOCHAR served
#     500C: P + (r5/y5)pc - C_DRY/y5 ; 300C: P + (r3/y3)pc - C_DRY/y3  -> P cancels
pc_d = np.linspace(0, 300, 300)
prem_bc = (r5/y5 - r3/y3) * pc_d - C_DRY * (1.0/y5 - 1.0/y3)
pc_star_bc = C_DRY * (1.0/y5 - 1.0/y3) / (r5/y5 - r3/y3)

# (b2) supply-bound regime: margin premium per DRY tonne for the bulk L segment ($250/t)
prem_dry = (y3 - y5) * 250.0 - (r5 - r3) * pc_d
pc_star_dry = (y3 - y5) * 250.0 / (r5 - r3)

print(f"y3={y3:.3f} y5={y5:.3f} r3={r3:.3f} r5={r5:.3f}")
print(f"demand-bound crossover (all segments): {pc_star_bc:.0f} USD/t")
print(f"supply-bound crossover (L segment):     {pc_star_dry:.0f} USD/t")

fig, axes = plt.subplots(1, 2, figsize=(11.6, 4.6))

# ---- (a) credit rates per t dry ----
reps = ["Corn_Stover", "Wheat_Straw", "Poplar", "Logging_Residues"]
idx = [names.index(r) for r in reps]
x = np.arange(len(reps))
w = 0.19
axes[0].bar(x - 1.5 * w, [rate_bc[(f, 3)] for f in idx], w, color=C_300, label="B&C, 300C")
axes[0].bar(x - 0.5 * w, [rate_bc[(f, 5)] for f in idx], w, color=C_500, label="B&C, 500C")
axes[0].bar(x + 0.5 * w, [rate_v44[(f, 3)] for f in idx], w, color=FS.GRAY_L, label="VM0044, 300C")
axes[0].bar(x + 1.5 * w, [rate_v44[(f, 5)] for f in idx], w, color=FS.GRAY, label="VM0044, 500C")
axes[0].set_xticks(x)
axes[0].set_xticklabels(["corn\n(300C INELIGIBLE)", "wheat\n(300C INELIGIBLE)", "poplar\n(300C INELIGIBLE)", "log. res.\n(300C INELIGIBLE)"],
                        fontsize=9.5)
axes[0].set_ylabel("Carbon credit rate (tCC / t dry)")
axes[0].set_title("Credit basis: B&C (avoided baseline) vs VM0044 (sequestration)",
                  fontsize=11)
FS.panel_label(axes[0], 0)
axes[0].legend(fontsize=9, loc="upper left")
axes[0].set_ylim(0, 2.2)

# ---- (b) two-regime crossover ----
axes[1].axhline(0, color="k", lw=0.8)
axes[1].plot(pc_d, prem_bc, lw=2.6, color=C_500,
             label="demand-bound regime: 500C premium per t BIOCHAR (all segments)")
axes[1].plot(pc_d, prem_dry, lw=2.2, color=C_300,
             label="supply-bound regime: 500C premium per dry t (L segment, $250/t)")
axes[1].scatter([pc_star_bc], [0], s=60, color=C_500, zorder=5, edgecolors="white", linewidths=1.0)
axes[1].annotate(f"~{pc_star_bc:.0f}", (pc_star_bc, 0), textcoords="offset points",
                 xytext=(8, 12), fontsize=10.5, color=C_500, fontweight="bold")
axes[1].scatter([pc_star_dry], [0], s=60, color=C_300, zorder=5, edgecolors="white", linewidths=1.0)
axes[1].annotate(f"~{pc_star_dry:.0f}", (pc_star_dry, 0), textcoords="offset points",
                 xytext=(8, -18), fontsize=10.5, color=C_300, fontweight="bold")
axes[1].axhspan(17, 25, color="#BDD7EE", alpha=0.30)
axes[1].axhspan(55, 100, color="#D9D9D9", alpha=0.45)
axes[1].axhspan(100, 250, color="#BFBFBF", alpha=0.35)
axes[1].text(255, 40, "voluntary\n100-250", fontsize=8.5, color="#B2182B")
axes[1].text(6, 30, "RGGI", fontsize=8.5, color="#3182BD")
axes[1].text(6, 103, "EU ETS", fontsize=8.5, color="#E6550D")
axes[1].set_xlabel("Credit price p_c (USD/tCO2e)")
axes[1].set_ylabel("500C margin premium over 300C (USD/t)")
axes[1].set_title("Which resource binds decides the crossover (feedstock averages)",
                  fontsize=11)
FS.panel_label(axes[1], 1)
axes[1].legend(fontsize=8.5, loc="upper left")
axes[1].set_xlim(0, 300)
axes[1].set_ylim(-120, 160)

fig.suptitle("Credit basis and the two-regime 300/500C crossover",
             fontweight="bold", fontsize=12)
fig.tight_layout(rect=[0, 0, 1, 0.94])
os.makedirs("results_v2b", exist_ok=True)
fig.savefig("results_v2b/fig12_credit_basis.png")
plt.close(fig)
print("saved results_v2b/fig12_credit_basis.png")
