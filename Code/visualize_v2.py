"""
visualize_v2.py - v2 publication figures (clean ASCII labels, USD units)
=======================================================================
Reads results_v2/{scenario}/*.csv and produces publication figures:
  fig2_economics      cost/revenue waterfall
  fig3_demand_curve   step demand + equilibrium
  fig6_policyA        B&C sweep: profit, BC, carbon credits
  fig7_policyB_MAC    marginal abatement cost curve + market price bands
  fig8_policyC_tech   tiered tax + credit: tech choice 300 vs 500
NOTE: all labels ASCII; currency written "USD" to avoid $/mathtext issues.
Usage: python visualize_v2.py [scenario]
"""
import sys, os, re
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import figstyle as FS

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
resdir = f"results_v2/{scen}"
figdir = os.path.join(resdir, "figures")
os.makedirs(figdir, exist_ok=True)

FS.apply()
C_BC = FS.DEEP; C_CC = FS.ACCENT; C_300 = FS.DEEP; C_500 = FS.LIGHT
C_GREY = FS.GRAY
SEG_COLORS = {"H": FS.DEEP, "M": FS.LIGHT, "L": FS.ACCENT, "sink": FS.GRAY}


def parse_summary(path):
    out = {}
    with open(path) as f:
        text = f.read()
    for k, v in re.findall(r'([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(-?[\d.]+)', text):
        try:
            out[k] = float(v)
        except ValueError:
            pass
    return out


S0 = parse_summary(os.path.join(resdir, "S0_summary.txt"))


# -----------------------------------------------------------------
# fig2: economics waterfall
# -----------------------------------------------------------------
def draw_economics(ax):
    vals = S0
    items = [
        ("Biochar revenue", vals["revenue_M"]),
        ("Biomass farmgate", -vals["farm_M"]),
        ("OPEX", -vals["opex_M"]),
        ("Transport", -vals["trans_M"]),
        ("Annualized CAPEX", -vals["capex_M"]),
    ]
    labels = [i[0] for i in items]
    v = np.array([i[1] for i in items])
    for i, (lbl, val) in enumerate(items):
        color = C_BC if val > 0 else C_GREY      # deep blue revenue, gray costs (group palette)
        ax.bar(i, val, 0.58, color=color, alpha=0.92, edgecolor="white", linewidth=0.6)
        ax.text(i, val + (12 if val > 0 else -12), f"{val:+.0f}",
                ha="center", va="bottom" if val > 0 else "top", fontsize=11)
    ax.axhline(0, color="#262626", lw=0.9)
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=24, ha="right", fontsize=10.5)
    ax.set_ylabel("Million USD / yr", fontsize=11.5)
    ax.tick_params(labelsize=10.5)
    ax.set_title(f"System economics ({scen}, S0 baseline)", fontsize=12.5, fontweight="bold")
    ax.set_ylim(v.min() * 1.06, v.max() * 1.22)
    net = sum(v)
    ax.text(0.03, 0.965, f"Net surplus: {net:+.1f} M USD/yr", transform=ax.transAxes,
            va="top", fontsize=11, fontweight="bold", color=FS.INK)


# -----------------------------------------------------------------
# fig2: economics waterfall
# -----------------------------------------------------------------
def fig_economics():
    fig, ax = plt.subplots(figsize=(6.4, 4.3))
    draw_economics(ax)
    fig.savefig(os.path.join(figdir, "fig2_economics.png"))
    plt.close(fig)


# -----------------------------------------------------------------
# fig3: step demand curve + equilibrium
# -----------------------------------------------------------------
def draw_demand(ax):
    dem = pd.read_csv(os.path.join("biochar_data_v2", scen, "demand_matrix.csv"))
    segs = dem[dem.segment.isin(["H", "M", "L"])]
    xs, ys = [], []
    cum = 0.0
    for seg in ["H", "M", "L"]:
        cap = segs[segs.segment == seg]["capacity"].sum() / 1e6
        price = segs[segs.segment == seg]["bid"].iloc[0]
        xs += [cum, cum + cap]
        ys += [price, price]
        cum += cap
    ax.step(xs, ys, where="post", color=C_BC, lw=2.4)
    s2f = os.path.join(resdir, "S2_summary.txt")
    if os.path.exists(s2f):
        s2 = parse_summary(s2f)
        bc = s2["bc_Mt"]
        price_eq = 800.0 if bc <= 0.8 else (500.0 if bc <= 2.3 else 250.0)
        ax.axhline(price_eq, color=C_GREY, ls="--", lw=1.1)
        ax.text(3.15, 610 if price_eq > 400 else 430, f"equilibrium price ~ {price_eq:.0f} USD/t",
                fontsize=10, color=C_GREY, ha="center")
        ax.axvline(bc, color=C_GREY, ls=":", lw=1.1)
        ax.annotate(f"equilibrium Q = {bc:.2f} Mt/yr", xy=(bc, 500),
                    xytext=(bc + 0.5, 545), fontsize=10, color=C_GREY,
                    arrowprops=dict(arrowstyle="-", color=C_GREY, lw=1.1))
    ax.text(0.42, 752, "H: CDR premium", fontsize=9.5, ha="center")
    ax.text(1.55, 545, "M: quality ag / industrial", fontsize=9.5, ha="center")
    ax.text(3.55, 130, "L: bulk agricultural", fontsize=9.5, ha="center")
    ax.set_xlim(0, 5.0)
    ax.set_ylim(0, 900)
    ax.set_xlabel("Biochar quantity (Mt/yr)", fontsize=11.5)
    ax.set_ylabel("Price (USD/t biochar)", fontsize=11.5)
    ax.tick_params(labelsize=10.5)
    ax.set_title(f"Step demand curve and market clearing ({scen})", fontsize=12.5, fontweight="bold")


# -----------------------------------------------------------------
# fig3: step demand curve + equilibrium
# -----------------------------------------------------------------
def fig_demand():
    fig, ax = plt.subplots(figsize=(6.6, 4.2))
    draw_demand(ax)
    fig.savefig(os.path.join(figdir, "fig3_demand_curve.png"))
    plt.close(fig)


# -----------------------------------------------------------------
# fig2 composite (data-level): economics (I) + demand curve (II)
# -----------------------------------------------------------------
def fig_econmarket_composite():
    fig, axes = plt.subplots(1, 2, figsize=(11.8, 4.4))
    draw_economics(axes[0])
    draw_demand(axes[1])
    FS.panel_label(axes[0], 0)
    FS.panel_label(axes[1], 1)
    fig.savefig(os.path.join(figdir, "fig2_econmarket.png"), dpi=400, bbox_inches="tight")
    plt.close(fig)
    print("saved fig2_econmarket.png (data-level composite)")


# -----------------------------------------------------------------
# fig6: policy A sweep
# -----------------------------------------------------------------
def fig_policyA():
    f = os.path.join(resdir, "policy_A_bnc_sweep_v2.csv")
    if not os.path.exists(f):
        print("skip fig6: no policy A results")
        return
    a = pd.read_csv(f)
    # vertical stack of three full-width panels; each keeps its own x ticks
    fig, axes = plt.subplots(3, 1, figsize=(7.0, 8.6))
    axes[0].plot(a.p_c, a.profit_M, "o-", color=C_BC, lw=2)
    axes[0].set_xlabel("Credit price (USD/tCO2e)")
    axes[0].set_ylabel("System surplus (M USD/yr)")
    axes[0].set_title("Surplus", fontweight="bold")
    FS.panel_label(axes[0], 0)
    x = np.arange(len(a)); w = 0.6
    bot = np.zeros(len(a))
    for seg, col, colname in [("H", SEG_COLORS["H"], "seg_H"), ("M", SEG_COLORS["M"], "seg_M"),
                              ("L", SEG_COLORS["L"], "seg_L"), ("sink", SEG_COLORS["sink"], "sink_Mt")]:
        vals = a[colname] / 1e6 if colname != "sink_Mt" else a[colname]
        axes[1].bar(x, vals, w, bottom=bot, color=col, edgecolor="white",
                    linewidth=0.5, label=seg)
        bot += vals
    axes[1].set_xticks(x)
    axes[1].set_xticklabels([f"{int(p)}" for p in a.p_c])
    axes[1].set_xlabel("Credit price (USD/tCO2e)")
    axes[1].set_ylabel("Biochar (Mt/yr)")
    axes[1].set_title("Production by segment", fontweight="bold")
    FS.panel_label(axes[1], 1)
    axes[1].legend(fontsize=9, ncol=2, loc="upper left")
    axes[2].plot(a.p_c, a.cc_Mt, "o-", color=C_500, lw=2, label="Credits produced")
    axes[2].plot(a.p_c, a.ghg_Mt, "s-", color=C_300, lw=2, label="Net GHG")
    axes[2].axhline(0, color="k", lw=0.7)
    axes[2].set_xlabel("Credit price (USD/tCO2e)")
    axes[2].set_ylabel("Mt CO2e / yr")
    axes[2].set_title("Credits and net GHG", fontweight="bold")
    FS.panel_label(axes[2], 2)
    axes[2].legend(fontsize=9)
    fig.suptitle(f"Paradigm A: baseline-and-credit sweep ({scen})", fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    fig.savefig(os.path.join(figdir, "fig6_policyA.png"))
    plt.close(fig)


# -----------------------------------------------------------------
# fig7: MAC curve (finite-difference) + market price bands
# -----------------------------------------------------------------
def fig_policyB():
    f = os.path.join(resdir, "policy_B1_cap_sweep_MAC_v2.csv")
    if not os.path.exists(f):
        print("skip fig7: no policy B results")
        return
    b = pd.read_csv(f)
    fig, axes = plt.subplots(1, 2, figsize=(9.8, 4.0))
    E_base = b.emis_kt.max()
    abate = E_base - b.emis_kt
    axes[0].plot(abate[1:], b.pi_fd_dollar_per_t[1:], "o-", color=C_BC, lw=2.2,
                 label="finite-difference MAC")
    dual = b[b.pi_dual < -1]
    if len(dual):
        abate_d = E_base - dual.emis_kt
        axes[0].plot(abate_d, -dual.pi_dual, "D", color=FS.ACCENT, ms=7, lw=0,
                     label=r"vertex dual $-\mu_{\mathrm{CAP}}$", zorder=5)
    axes[0].axhspan(17, 25, color="#BDD7EE", alpha=0.45, label="RGGI 17-25")
    axes[0].axhspan(55, 100, color="#D9D9D9", alpha=0.45, label="EU ETS 50-90")
    axes[0].axhspan(100, 250, color="#BFBFBF", alpha=0.40, label="VM0044/Puro 100-250")
    axes[0].set_xlabel("Gross emission abatement (kt CO2e/yr)")
    axes[0].set_ylabel("Marginal abatement cost (USD/tCO2e)")
    axes[0].set_title("Marginal abatement cost curve", fontweight="bold")
    FS.panel_label(axes[0], 0)
    axes[0].set_ylim(0, 680)
    axes[0].legend(fontsize=9, loc="lower right")
    axes[1].plot(b.cap_kt, b.profit_M, "s-", color=C_300, lw=2.2)
    axes[1].set_xlabel("Emission cap (kt CO2e/yr)")
    axes[1].set_ylabel("System surplus (M USD/yr)")
    axes[1].set_title("Surplus vs emission cap", fontweight="bold")
    axes[1].annotate("cap tightens →", xy=(b.cap_kt.min(), b.profit_M.min() + 5),
                     xytext=(b.cap_kt.min() + 40, b.profit_M.min() + 15),
                     fontsize=9, color=C_300, arrowprops=dict(arrowstyle="->", color=C_300, lw=1.0))
    FS.panel_label(axes[1], 1)
    fig.suptitle(f"Paradigm B: cap-and-trade with endogenous price ({scen})",
                 fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    fig.savefig(os.path.join(figdir, "fig7_policyB_MAC.png"))
    plt.close(fig)


# -----------------------------------------------------------------
# fig8: policy C - tech choice 300 vs 500
# -----------------------------------------------------------------
def fig_policyC():
    f = os.path.join(resdir, "policy_C2_tax_credit_v2.csv")
    if not os.path.exists(f):
        print("skip fig8: no policy C results")
        return
    c = pd.read_csv(f)
    fig, axes = plt.subplots(1, 2, figsize=(9.0, 3.9))
    x = np.arange(len(c))
    w = 0.36
    axes[0].bar(x - w / 2, c.bc300, w, color=C_300, label="T2-300C")
    axes[0].bar(x + w / 2, c.bc500, w, color=C_500, label="T2-500C")
    axes[0].set_xticks(x)
    axes[0].set_xticklabels([f"{int(p)}" for p in c.p_c])
    axes[0].set_xlabel("Credit price (USD/tCO2e)")
    axes[0].set_ylabel("Biochar (Mt/yr)")
    axes[0].set_title("Technology choice under credit", fontweight="bold")
    FS.panel_label(axes[0], 0)
    axes[0].legend(fontsize=9.5)
    axes[1].plot(c.p_c, c.profit, "o-", color=C_BC, lw=2)
    axes[1].set_xlabel("Credit price (USD/tCO2e)")
    axes[1].set_ylabel("Surplus (M USD/yr)")
    axes[1].set_title("Surplus with tiered tax + credit", fontweight="bold")
    FS.panel_label(axes[1], 1)
    fig.suptitle(f"Paradigm C: tiered tax (25/50/100) + VM0044 credit ({scen})",
                 fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    fig.savefig(os.path.join(figdir, "fig8_policyC_tech.png"))
    plt.close(fig)


if __name__ == "__main__":
    fig_economics()
    fig_demand()
    fig_econmarket_composite()
    fig_policyA()
    fig_policyB()
    fig_policyC()
    print("figures written to", figdir)
