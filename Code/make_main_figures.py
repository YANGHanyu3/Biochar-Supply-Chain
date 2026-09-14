"""
make_main_figures.py — consolidated multi-panel main figures (v0.7).

Six main figures for the manuscript, all data-level composites:
  fig2  baseline network, economics and market clearing   (map + bars + step line)
  fig3  spatial inherent values                            (2 maps + heatmap)
  fig4  policy response across paradigms A/B/C             (lines + markers + stacked bars)
  fig5  technology choice and credit basis                 (bars + lines + stacked bars)
  fig6  sensitivity                                        (tornado bars + 2D heatmap)
  fig1  superstructure is produced by fig0_superstructure.py

Palette is restricted to black/white/gray/blue (figstyle v0.7); heatmaps use
the pale->deep-blue ramp. All figures are 400 DPI.
Usage: python make_main_figures.py [scenario]
"""
import sys
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import geopandas as gpd

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
# imported modules read sys.argv[1] as the scenario
sys.argv = ["make_main_figures.py", scen]

import figstyle as FS
import visualize_v2 as V
import fig45_iv_maps as M

FS.apply()
plt.rcParams["font.family"] = "Calibri"
resdir = f"results_v2/{scen}"
figdir = os.path.join(resdir, "figures")
os.makedirs(figdir, exist_ok=True)

CMAP = LinearSegmentedColormap.from_list("blueramp", FS.BLUE_RAMP)
C1, C2, C3, CG = FS.DEEP, FS.MID, FS.LIGHT, FS.GRAY


def _save(fig, name):
    fig.savefig(os.path.join(figdir, name), dpi=400, bbox_inches="tight",
                facecolor="white")
    plt.close(fig)
    print("saved", name)


# =====================================================================
# fig2 — baseline network, economics, market clearing (3 panels)
# =====================================================================
def fig2_baseline():
    z = pd.read_csv(os.path.join(resdir, "z_star_MIP_v2.csv"))
    nm = pd.read_csv(os.path.join("biochar_data_v2", scen, "node_matrix.csv"))
    sup = pd.read_csv(os.path.join("biochar_data_v2", scen, "supply_matrix.csv"))
    z["tech_class"] = np.where(z.tech <= 13, "T1 drying",
                       np.where(z.tech <= 26, "T2 300C", "T2 500C"))
    z = z.merge(nm[["node_id", "lat", "lon"]], left_on="node", right_on="node_id")
    z["size"] = z.scale.map({1: 26, 2: 72, 3: 150}) * (0.6 + 0.4 * z["count"])

    gdf = gpd.read_file("WI_Counties.shp").to_crs(epsg=4326)
    gdf["GEOID"] = gdf["GEOID"].astype(str)
    lakes = gpd.read_file("WI_Lakes.shp").to_crs(epsg=4326)
    avail = sup.groupby("node")["capacity"].sum() / 1e6
    nm["avail"] = nm["node_id"].map(avail).fillna(0.0)
    nmf = pd.read_csv("node_fips.csv")
    nmf["FIPS5"] = nmf["FIPS5"].astype(str)
    nm = nm.merge(nmf[["n_id", "FIPS5"]], left_on="node_id", right_on="n_id", how="left")
    g = gdf.merge(nm[["FIPS5", "avail"]], left_on="GEOID", right_on="FIPS5", how="left")

    fig, axes = plt.subplots(1, 3, figsize=(13.6, 4.3),
                             gridspec_kw={"width_ratios": [1.25, 1, 1]})
    ax = axes[0]
    g.plot(ax=ax, column="avail", cmap=CMAP, edgecolor="white", linewidth=0.4,
           legend=True, missing_kwds=dict(color="#E7E6E6"),
           legend_kwds=dict(shrink=0.6, label="Feedstock availability (Mt wet/yr)"))
    # zoom to the state boundary (v0.8: no lakes layer, tighter framing)
    x0, y0, x1, y1 = gdf.total_bounds
    mx, my = 0.03 * (x1 - x0), 0.03 * (y1 - y0)
    ax.set_xlim(x0 - mx, x1 + mx)
    ax.set_ylim(y0 - my, y1 + my)
    for cls, col, mk in [("T1 drying", CG, "o"), ("T2 300C", C1, "D")]:
        grp = z[z.tech_class == cls]
        if len(grp):
            ax.scatter(grp.lon, grp.lat, s=grp["size"], c=col, marker=mk,
                       edgecolors="white", linewidths=0.5, alpha=0.9,
                       zorder=5, label=cls)
    ax.legend(loc="lower left", fontsize=8, frameon=True, facecolor="white",
              edgecolor="#BFBFBF")
    ax.axis("off")
    FS.panel_label(ax, 0, x=0.0, y=1.02)

    V.draw_economics(axes[1]); FS.panel_label(axes[1], 1)
    V.draw_demand(axes[2]);    FS.panel_label(axes[2], 2)
    fig.tight_layout()
    _save(fig, "fig2_baseline.png")


# =====================================================================
# fig3 — spatial inherent values (2 maps + supply heatmap)
# =====================================================================
def fig3_inherent_values():
    sup = pd.read_csv(os.path.join("biochar_data_v2", scen, "supply_matrix.csv"))
    nm = pd.read_csv(os.path.join("biochar_data_v2", scen, "node_matrix.csv"))
    piv = sup.pivot_table(index="node", columns="feedstock", values="capacity",
                          aggfunc="sum").fillna(0.0) / 1e3      # kt wet/yr
    order = piv.sum(axis=1).sort_values(ascending=False).index
    piv = piv.loc[order]
    piv = piv[piv.sum().sort_values(ascending=False).index]

    fig, axes = plt.subplots(1, 3, figsize=(13.6, 4.5),
                             gridspec_kw={"width_ratios": [1, 1, 1.15]})
    v1 = M.draw_iv(axes[0], 27, "Biochar inherent value (USD/t)", "Blues",
                   "USD/t biochar")
    M.add_colorbar(fig, axes[0], v1[0], v1[1], "Blues", "USD/t biochar")
    FS.panel_label(axes[0], 0, x=0.0, y=1.02)
    v2 = M.draw_iv(axes[1], 1, "Wet corn stover inherent value (USD/t)", "Blues",
                   "USD/t wet biomass")
    M.add_colorbar(fig, axes[1], v2[0], v2[1], "Blues", "USD/t wet biomass")
    FS.panel_label(axes[1], 1, x=0.0, y=1.02)

    ax = axes[2]
    im = ax.imshow(piv.values, aspect="auto", cmap=CMAP, interpolation="nearest")
    ax.set_xticks(range(len(piv.columns)))
    ax.set_xticklabels([c.replace("_", " ") for c in piv.columns],
                       rotation=45, ha="right", fontsize=6.5)
    ax.set_ylabel("Counties (sorted by total availability)")
    ax.set_yticks([])
    ax.set_title("Feedstock availability (kt wet/yr)", fontweight="bold", fontsize=11)
    fig.colorbar(im, ax=ax, shrink=0.72, pad=0.02, label="kt wet/yr")
    FS.panel_label(ax, 2, x=0.0, y=1.02)
    fig.tight_layout()
    _save(fig, "fig3_inherent_values.png")


# =====================================================================
# fig4 — policy response across paradigms A/B/C (2x2)
# =====================================================================
def fig4_policy():
    a = pd.read_csv(os.path.join(resdir, "policy_A_bnc_sweep_v2.csv"))
    b = pd.read_csv(os.path.join(resdir, "policy_B1_cap_sweep_MAC_v2.csv"))
    c2 = pd.read_csv(os.path.join(resdir, "policy_C2_tax_credit_v2.csv"))
    # C2 zero-credit point = tiered tax only (C1-free MIP, rates 25/50/100):
    # a matched no-credit baseline so both curves start from the same regime
    c1f = pd.read_csv(os.path.join(resdir, "policy_C1_free_tax_v2.csv"))
    zrow = c1f[(c1f.r1 == 25) & (c1f.r2 == 50) & (c1f.r3 == 100)].iloc[0]
    c2 = pd.concat([pd.DataFrame([dict(p_c=0.0, bc=zrow.bc, bc300=zrow.bc,
                                       bc500=0.0, profit=zrow.profit)]),
                    c2], ignore_index=True)

    fig, axes = plt.subplots(2, 2, figsize=(10.6, 7.4))

    ax = axes[0, 0]
    ax.plot(a.p_c, a.bc_Mt, "o-", color=C1, lw=2, label="A: baseline-and-credit")
    ax.plot(c2.p_c, c2.bc, "^-", color=C3, lw=2, label="C: VM0044 credit")
    ax.set_xlabel("Credit price (USD/tCO$_2$e)")
    ax.set_ylabel("Biochar (Mt/yr)")
    ax.set_title("Production response", fontweight="bold")
    ax.legend(fontsize=8.5)
    FS.panel_label(ax, 0)

    ax = axes[0, 1]
    ax.plot(a.p_c, a.profit_M, "o-", color=C1, lw=2, label="A: baseline-and-credit")
    ax.plot(c2.p_c, c2.profit, "^-", color=C3, lw=2, label="C: VM0044 credit")
    ax.set_xlabel("Credit price (USD/tCO$_2$e)")
    ax.set_ylabel("System surplus (M USD/yr)")
    ax.set_title("Surplus", fontweight="bold")
    ax.legend(fontsize=8.5)
    FS.panel_label(ax, 1)

    ax = axes[1, 0]
    E_base = b.emis_kt.max()
    abate = E_base - b.emis_kt
    ax.plot(abate[1:], b.pi_fd_dollar_per_t[1:], "o-", color=C1, lw=2.2,
            label="finite-difference MAC")
    dual = b[b.pi_dual < -1]
    if len(dual):
        ax.plot(E_base - dual.emis_kt, -dual.pi_dual, "D", color=CG, ms=6, lw=0,
                label=r"vertex dual $-\mu_{\mathrm{CAP}}$")
    ax.axhspan(17, 25, color=FS.PALE, alpha=0.7, label="RGGI 17-25")
    ax.axhspan(55, 100, color=FS.GRAY_L, alpha=0.6, label="EU ETS 55-100 (€50-90)")
    ax.set_xlabel("Gross emission abatement (kt CO$_2$e/yr)")
    ax.set_ylabel("Marginal abatement cost (USD/tCO$_2$e)")
    ax.set_title("Marginal abatement cost", fontweight="bold")
    ax.legend(fontsize=8, loc="upper left")
    FS.panel_label(ax, 2)

    ax = axes[1, 1]
    x = np.arange(len(c2)); w = 0.62
    ax.bar(x, c2.bc300, w, color=C1, label="300 $^\\circ$C")
    ax.bar(x, c2.bc500, w, bottom=c2.bc300, color=C3, label="500 $^\\circ$C")
    ax.set_xticks(x); ax.set_xticklabels([f"{int(p)}" for p in c2.p_c])
    ax.set_xlabel("Credit price (USD/tCO$_2$e)")
    ax.set_ylabel("Biochar (Mt/yr)")
    ax.set_title("Technology mix under VM0044", fontweight="bold")
    ax.set_ylim(0, 2.95)
    ax.legend(fontsize=8.5, loc="upper right")
    FS.panel_label(ax, 3)

    fig.tight_layout()
    _save(fig, "fig4_policy.png")


# =====================================================================
# fig5 — technology choice and credit basis (3 panels)
# =====================================================================
def fig5_credit_basis():
    ghg = pd.read_csv("biochar_data_v2/near-term/ghg_factors_v2.csv")
    alpha = pd.read_csv("biochar_data_v2/near-term/alpha_matrix.csv", header=None).values
    names = [g.replace("T1_Dehyd_", "").replace("T2300C_Pyrol_", "")
              .replace("T2500C_Pyrol_", "") for g in ghg.tech_name.values]
    pghg = dict(zip(ghg.tech_id.values, ghg.process_ghg_per_t_ref.values))
    sghg = dict(zip(ghg.tech_id.values,
                    ghg.ghg_seq_per_t_bc.values + ghg.ghg_n2o_per_t_bc.values))
    bghg = dict(zip(ghg.tech_id.values, ghg.baseline_ghg_per_t_ref.values))
    NF = 13
    rate_bc, rate_v44 = {}, {}
    y3s, y5s, r3s, r5s = [], [], [], []
    for f in range(NF):
        t1, t2, t2b = f + 1, NF + f + 1, 2 * NF + f + 1
        eta = alpha[f, NF + f]
        y3 = alpha[t2 - 1, 2 * NF]; y5 = alpha[t2b - 1, 2 * NF]
        b_ = bghg[t1] / eta
        e3 = pghg[t1] / eta + pghg[t2]
        e5 = pghg[t1] / eta + pghg[t2b]
        s3 = sghg[t2] * y3; s5 = sghg[t2b] * y5
        rate_bc[(f, 3)] = (b_ - e3 - s3) / 1000.0
        rate_bc[(f, 5)] = (b_ - e5 - s5) / 1000.0
        rate_v44[(f, 3)] = alpha[t2 - 1, 2 * NF + 1]
        rate_v44[(f, 5)] = alpha[t2b - 1, 2 * NF + 1]
        y3s.append(y3); y5s.append(y5); r3s.append(rate_bc[(f, 3)]); r5s.append(rate_bc[(f, 5)])
    y3, y5 = float(np.mean(y3s)), float(np.mean(y5s))
    r3, r5 = float(np.mean(r3s)), float(np.mean(r5s))
    C_DRY = 130.0
    pc = np.linspace(0, 300, 300)
    prem_bc = (r5 / y5 - r3 / y3) * pc - C_DRY * (1.0 / y5 - 1.0 / y3)
    pc_star_bc = C_DRY * (1.0 / y5 - 1.0 / y3) / (r5 / y5 - r3 / y3)
    prem_dry = (y3 - y5) * 250.0 - (r5 - r3) * pc
    pc_star_dry = (y3 - y5) * 250.0 / (r5 - r3)

    fig, axes = plt.subplots(1, 3, figsize=(13.6, 4.3),
                             gridspec_kw={"width_ratios": [1.15, 1.1, 1]})

    reps = ["Corn_Stover", "Wheat_Straw", "Poplar", "Logging_Residues"]
    idx = [names.index(r) for r in reps]
    x = np.arange(len(reps)); w = 0.2
    ax = axes[0]
    ax.bar(x - 1.5 * w, [rate_bc[(f, 3)] for f in idx], w, color=C1, label="B&C, 300 C")
    ax.bar(x - 0.5 * w, [rate_bc[(f, 5)] for f in idx], w, color=C3, label="B&C, 500 C")
    ax.bar(x + 0.5 * w, [rate_v44[(f, 3)] for f in idx], w, color=FS.GRAY_L,
           edgecolor=CG, linewidth=0.4, label="VM0044, 300 C")
    ax.bar(x + 1.5 * w, [rate_v44[(f, 5)] for f in idx], w, color=CG,
           label="VM0044, 500 C")
    ax.set_xticks(x)
    ax.set_xticklabels(["corn", "wheat", "poplar", "log. res."], fontsize=8.5)
    ax.set_ylabel("Credit rate (tCC / t dry)")
    ax.set_title("Credit basis by feedstock", fontweight="bold")
    ax.legend(fontsize=7.5, loc="upper left")
    ax.set_ylim(0, 2.6)
    FS.panel_label(ax, 0)

    ax = axes[1]
    ax.axhline(0, color="k", lw=0.8)
    ax.plot(pc, prem_bc, lw=2.4, color=C1,
            label="demand-bound: per t biochar served")
    ax.plot(pc, prem_dry, lw=2.0, color=CG,
            label="supply-bound: per dry t (L segment)")
    ax.scatter([pc_star_bc], [0], s=55, color=C1, zorder=5, edgecolors="white")
    ax.annotate(f"~{pc_star_bc:.0f}", (pc_star_bc, 0), textcoords="offset points",
                xytext=(8, -18), fontsize=9.5, color=C1, fontweight="bold")
    ax.scatter([pc_star_dry], [0], s=55, color=CG, zorder=5, edgecolors="white")
    ax.annotate(f"~{pc_star_dry:.0f}", (pc_star_dry, 0), textcoords="offset points",
                xytext=(8, -16), fontsize=9.5, color=CG, fontweight="bold")
    ax.axhspan(17, 25, color=FS.PALE, alpha=0.6)
    ax.axhspan(55, 100, color=FS.GRAY_L, alpha=0.6)
    ax.set_xlabel("Credit price (USD/tCO$_2$e)")
    ax.set_ylabel("500 C premium over 300 C (USD/t)")
    ax.set_title("Two-regime crossover", fontweight="bold")
    ax.legend(fontsize=7.5, loc="lower right")
    ax.set_xlim(0, 300); ax.set_ylim(-120, 160)
    FS.panel_label(ax, 1)

    ax = axes[2]
    for sc, off in [("near-term", -0.19), ("mature-market medium", 0.19)]:
        v = pd.read_csv(os.path.join("results_v2b", sc, "policy_A_bnc_sweep_v2b.csv"))
        xx = np.arange(len(v)) + off
        col = C1 if sc == "near-term" else C3
        ax.bar(xx, v.bc300_Mt, 0.36, color=col, label=f"BC300 ({sc[:9]})")
        ax.bar(xx, v.bc500_Mt, 0.36, bottom=v.bc300_Mt, color=col, alpha=0.45,
               hatch="///", edgecolor="white", linewidth=0.3,
               label=f"BC500 ({sc[:9]})")
    ax.set_xticks(np.arange(4))
    ax.set_xticklabels(["0", "50", "100", "200"])
    ax.set_xlabel("Credit price (USD/tCO$_2$e)")
    ax.set_ylabel("Biochar (Mt/yr)")
    ax.set_title("Quality-differentiated mix (v2b)", fontweight="bold")
    ax.legend(fontsize=6.8, ncol=1)
    FS.panel_label(ax, 2)

    fig.tight_layout()
    _save(fig, "fig5_credit_basis.png")


# =====================================================================
# fig6 — sensitivity (tornado + demand grid heatmap)
# =====================================================================
def fig6_sensitivity():
    s = pd.read_csv(os.path.join(resdir, "sensitivity_v2.csv"))
    base = s[s.case == "baseline"].iloc[0]
    s = s[s.case != "baseline"].copy()
    params = {
        "farmgate": ("farmgate -20%", "farmgate +20%", "Farmgate price"),
        "transport": ("transport -20%", "transport +20%", "Transport cost"),
        "demand cap": ("demand cap -20%", "demand cap +20%", "Demand capacity"),
        "demand price": ("demand price -20%", "demand price +20%", "Demand price"),
        "sink": ("sink $0", "sink $60", "Sink value"),
    }
    rows = []
    for k, (lo, hi, lab) in params.items():
        rows.append((lab, s[s.case == lo]["profit_M"].values[0],
                     s[s.case == hi]["profit_M"].values[0]))
    avail = s[s.case == "supply cap -20%"]["profit_M"].values[0]
    avail_hi = s[s.case == "supply cap +20%"]["profit_M"].values[0]
    rows.append(("Feedstock availability", avail, avail_hi))
    rows.sort(key=lambda r: abs(r[1] - base.profit_M) + abs(r[2] - base.profit_M))
    labels = [r[0] for r in rows]
    lo_v = np.array([r[1] - base.profit_M for r in rows])
    hi_v = np.array([r[2] - base.profit_M for r in rows])

    fig, axes = plt.subplots(1, 2, figsize=(12.6, 4.6),
                             gridspec_kw={"width_ratios": [1.15, 1]})
    ax = axes[0]
    y = np.arange(len(rows))
    ax.barh(y, lo_v, color=CG, alpha=0.9, label="low (−20%)")
    ax.barh(y, hi_v, color=C1, alpha=0.9, label="high (+20%)")
    ax.axvline(0, color="k", lw=0.8)
    ax.set_yticks(y); ax.set_yticklabels(labels, fontsize=9)
    ax.set_xlabel(f"Change in surplus (M USD/yr) vs baseline {base.profit_M:.0f}")
    ax.set_title("One-at-a-time sensitivity", fontweight="bold")
    ax.legend(loc="lower right", fontsize=8.5)
    FS.panel_label(ax, 0)

    ax = axes[1]
    g = pd.read_csv(os.path.join(resdir, "sensitivity_grid_v2.csv"))
    piv = g.pivot(index="price_mult", columns="cap_mult", values="profit_M")
    im = ax.imshow(piv.values, cmap=CMAP, origin="lower", aspect="auto")
    ax.set_xticks(range(len(piv.columns)))
    ax.set_xticklabels([f"{c:g}" for c in piv.columns])
    ax.set_yticks(range(len(piv.index)))
    ax.set_yticklabels([f"{r:g}" for r in piv.index])
    ax.set_xlabel("Demand capacity multiplier")
    ax.set_ylabel("Demand price multiplier")
    ax.set_title("Joint demand sensitivity (M USD/yr)", fontweight="bold")
    for i in range(piv.shape[0]):
        for j in range(piv.shape[1]):
            val = piv.values[i, j]
            ax.text(j, i, f"{val:.0f}", ha="center", va="center", fontsize=7.5,
                    color="white" if val > 0.6 * piv.values.max() else FS.INK)
    fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02, label="System surplus (M USD/yr)")
    FS.panel_label(ax, 1, x=0.0, y=1.02)

    fig.tight_layout()
    _save(fig, "fig6_sensitivity.png")


if __name__ == "__main__":
    fig2_baseline()
    fig3_inherent_values()
    fig4_policy()
    fig5_credit_basis()
    fig6_sensitivity()
    print("main figures written to", figdir)
