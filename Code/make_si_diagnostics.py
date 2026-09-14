# =============================================================================
# make_si_diagnostics.py — v0.9 SI diagnostic figures (replace old S2/S3)
#   sfig2_netcap_frontier.png : E2 net-cap frontier (fixed-z lock + free-z MIP)
#   sfig3_certificates.png    : E5 solver certification (gap reduction + path
#                               independence of forward/reverse sweeps)
#   sfig4_demand_family.png   : E3 demand-family scenarios
# Palette: black/white/gray/blue per project standard; 400 DPI; Calibri.
# =============================================================================
import os, re
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import figstyle as FS

FS.apply()
INK = "#262626"; GREY = "#7F7F7F"; GREY_L = "#D9D9D9"
BLUE = "#1F4E79"; MIDBLUE = "#5B9BD5"; LIGHT = "#9DC3E6"; PALE = "#DCE9F5"

RES = os.path.join("results_v2", "near-term")
FIG = "figures_si"
os.makedirs(FIG, exist_ok=True)

# ---------------------------------------------------------------------------
# S2: net-cap frontier
# ---------------------------------------------------------------------------
def sfig2():
    fix = pd.read_csv(os.path.join(RES, "netcap_frontier_fixedz_v2.csv"))
    free = pd.read_csv(os.path.join(RES, "netcap_frontier_v2.csv"))
    nmin_txt = open(os.path.join(RES, "netcap_Nmin_v2.txt")).read()
    nmin = float(re.search(r"nmin_kt=([-\d.]+)", nmin_txt).group(1))

    fig, axes = plt.subplots(1, 3, figsize=(13.2, 4.2),
                             gridspec_kw={"width_ratios": [1.05, 1, 1]})
    ax = axes[0]
    fe = fix.dropna(subset=["profit"])
    ax.plot(fe.cap_net, fe.profit, "o-", color=GREY, lw=1.6, ms=5,
            label="fixed layout (LP)")
    fr = free.dropna(subset=["profit"])
    ax.plot(fr.cap_net, fr.profit, "s-", color=BLUE, lw=2.0, ms=5,
            label="free facilities (MIP)")
    ax.axvline(-1595.1, color=INK, ls="--", lw=1.0)
    ax.text(-1595.1, ax.get_ylim()[1], "baseline flux\n-1595 kt",
            fontsize=8, ha="right", va="top", color=INK)
    ax.axvline(nmin, color=GREY, ls=":", lw=1.0)
    ax.text(nmin, 620, f"N_min = {nmin:.0f} kt\n(all 500 C)",
            fontsize=8, ha="left", va="center", color=GREY)
    ax.set_xlabel("Net-emission cap (kt CO2e / yr)")
    ax.set_ylabel("System surplus (M USD / yr)")
    ax.set_title("Profit vs cap", fontweight="bold")
    ax.legend(fontsize=8, loc="lower left")
    ax.invert_xaxis()
    FS.panel_label(ax, 0)

    ax = axes[1]
    x = fr.cap_net.values
    ax.bar(x, fr.bc300, width=55, color=GREY, label="300 C", edgecolor="white")
    ax.bar(x, fr.bc500, width=55, bottom=fr.bc300, color=BLUE, label="500 C",
           edgecolor="white")
    ax.set_xlabel("Net-emission cap (kt CO2e / yr)")
    ax.set_ylabel("Biochar (Mt / yr)")
    ax.set_title("Technology response", fontweight="bold")
    ax.legend(fontsize=8, loc="lower right")
    ax.invert_xaxis()
    FS.panel_label(ax, 1)

    ax = axes[2]
    mac = fr.mac_fd_dollar_per_t.dropna()
    caps = fr.cap_net[fr.mac_fd_dollar_per_t.notna()]
    ax.plot(caps, mac, "o-", color=INK, lw=1.8, ms=5)
    ax.axhline(0, color=GREY_L, lw=0.8)
    ax.annotate("expansion regime\n($\\approx$110 $/t)", xy=(-1650, 110),
                xytext=(-1800, 200), fontsize=8, color=INK,
                arrowprops=dict(arrowstyle="->", color=INK, lw=0.8))
    ax.annotate("durability regime\n($\\approx$150-330 $/t)", xy=(-1900, 324),
                xytext=(-2000, 430), fontsize=8, color=INK,
                arrowprops=dict(arrowstyle="->", color=INK, lw=0.8))
    ax.set_xlabel("Net-emission cap (kt CO2e / yr)")
    ax.set_ylabel("Marginal cost (USD / tCO2e)")
    ax.set_title("Finite-difference shadow cost", fontweight="bold")
    ax.invert_xaxis()
    FS.panel_label(ax, 2)

    fig.suptitle("Net-emission cap frontier (near-term, free facilities unless noted)",
                 fontweight="bold", fontsize=12)
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    fig.savefig(os.path.join(FIG, "sfig2_netcap_frontier.png"), dpi=400,
                bbox_inches="tight")
    plt.close(fig)
    print("saved sfig2_netcap_frontier.png")

# ---------------------------------------------------------------------------
# S3: solver certification
# ---------------------------------------------------------------------------
def sfig3():
    a = pd.read_csv(os.path.join(RES, "policy_A_bnc_sweep_v2.csv"))
    acert = pd.read_csv(os.path.join(RES, "policy_A_cert_v2.csv"))
    arev = pd.read_csv(os.path.join(RES, "policy_A_certrev_v2.csv"))
    c2 = pd.read_csv(os.path.join(RES, "policy_C2_tax_credit_v2.csv"))
    c2s0 = pd.read_csv(os.path.join(RES, "policy_C2_certs0_v2.csv"))
    c2s1 = pd.read_csv(os.path.join(RES, "policy_C2_certs1_v2.csv"))
    c2rev = pd.read_csv(os.path.join(RES, "policy_C2_certrev_v2.csv"))
    r2 = pd.read_csv(os.path.join("results_v2", "mature-market medium",
                                  "policy_A_recert2_v2.csv"))

    fig, axes = plt.subplots(1, 2, figsize=(10.8, 4.0))
    ax = axes[0]
    cases = [
        ("A p=25", a[a.p_c == 25].profit_M.iloc[0], acert.profit_M.iloc[0]),
        ("C2 p=150 s0", c2[c2.p_c == 150].profit.iloc[0], c2s0.profit.iloc[0]),
        ("C2 p=150 s1", c2[c2.p_c == 150].profit.iloc[0], c2s1.profit.iloc[0]),
    ]
    labels = [c[0] for c in cases]
    before = [c[1] for c in cases]
    after = [c[2] for c in cases]
    y = np.arange(len(cases))
    ax.barh(y + 0.2, before, height=0.32, color=GREY, label="original sweep")
    ax.barh(y - 0.2, after, height=0.32, color=BLUE, label="certified (0.1%, 3600 s)")
    ax.set_yticks(y); ax.set_yticklabels(labels, fontsize=9)
    ax.set_xlabel("Surplus (M USD / yr)")
    ax.set_title("Incumbent improvement", fontweight="bold")
    ax.legend(fontsize=8, loc="lower right")
    FS.panel_label(ax, 0)

    ax = axes[1]
    pts = [("A", a, arev, "profit_M", [25, 100, 200]),
           ("C2", c2, c2rev, "profit", [100, 200])]
    for name, fw, rv, col, plist in pts:
        xs = [fw[fw.p_c == p][col].iloc[0] for p in plist]
        ys = [rv[rv.p_c == p][col].iloc[0] for p in plist]
        ax.plot(xs, ys, "o", ms=7, color=BLUE if name == "A" else GREY,
                label=f"{name} forward vs reverse")
    lo = min(ax.get_xlim()[0], ax.get_ylim()[0])
    hi = max(ax.get_xlim()[1], ax.get_ylim()[1])
    ax.plot([lo, hi], [lo, hi], "k--", lw=0.9, label="identity")
    ax.set_xlabel("Forward sweep surplus (M USD / yr)")
    ax.set_ylabel("Reverse sweep surplus (M USD / yr)")
    ax.set_title("Warm-start path independence", fontweight="bold")
    ax.legend(fontsize=8, loc="upper left")
    FS.panel_label(ax, 1)

    fig.suptitle("Solver certification (near-term; mature A p=100 recert = "
                 f"{r2.profit_M.iloc[0]:.1f} M$, BC500 {r2.bc_500_Mt.iloc[0]:.2f} Mt)",
                 fontweight="bold", fontsize=11)
    fig.tight_layout(rect=[0, 0, 1, 0.90])
    fig.savefig(os.path.join(FIG, "sfig3_certificates.png"), dpi=400,
                bbox_inches="tight")
    plt.close(fig)
    print("saved sfig3_certificates.png")

# ---------------------------------------------------------------------------
# S4: demand family
# ---------------------------------------------------------------------------
def sfig4():
    def s0(path):
        t = open(path).read()
        m = re.search(r"objective_M\s*=\s*([\d.]+)", t)
        b = re.search(r"bc_Mt\s*=\s*([\d.]+)", t)
        return float(m.group(1)), float(b.group(1))

    fams = [("low", "results_v2_dflow/near-term", "policy_A_dflow_v2.csv"),
            ("canonical", "results_v2/near-term", "policy_A_bnc_sweep_v2.csv"),
            ("pricestress", "results_v2_dfpricestress/near-term", "policy_A_dfpricestress_v2.csv"),
            ("high", "results_v2_dfhigh/near-term", "policy_A_dfhigh_v2.csv")]
    base_profit, base_bc, l25, p200 = [], [], [], []
    labels = [f[0] for f in fams]
    for name, dd, fn in fams:
        p0, b0 = s0(os.path.join(dd, "S0_summary.txt"))
        a = pd.read_csv(os.path.join(dd, fn))
        base_profit.append(p0); base_bc.append(b0)
        l25.append(a[a.p_c == 25].seg_L.iloc[0] / 1e6)
        p200.append(a[a.p_c == 200].profit_M.iloc[0])

    fig, axes = plt.subplots(1, 2, figsize=(10.4, 4.0))
    ax = axes[0]
    x = np.arange(len(labels))
    ax.bar(x, base_bc, width=0.55, color=MIDBLUE, edgecolor="white")
    for i, v in enumerate(base_bc):
        ax.text(i, v + 0.06, f"{v:.2f}", ha="center", fontsize=9)
    ax.axhline(2.30, color=INK, ls="--", lw=0.9)
    ax.text(2.6, 2.32, "calibrated H+M boundary", fontsize=8, color=INK)
    ax.set_xticks(x); ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("No-policy biochar (Mt / yr)")
    ax.set_ylim(0, 3.3)
    ax.set_title("Baseline output follows demand capacity", fontweight="bold")
    FS.panel_label(ax, 0)

    ax = axes[1]
    ax.bar(x - 0.2, l25, width=0.4, color=BLUE, edgecolor="white",
           label="L segment served at $p_c$=25 (Mt)")
    ax.set_xticks(x); ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("L served at $p_c$=25 (Mt / yr)")
    ax.set_ylim(0, 1.25)
    ax.set_title("$25 activation is scenario-conditional", fontweight="bold")
    ax2 = ax.twinx()
    ax2.plot(x, p200, "s-", color=INK, lw=1.8, ms=6, label="surplus at $p_c$=200")
    ax2.set_ylabel("Surplus at $p_c$=200 (M USD / yr)")
    lines1, labels1 = ax.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax.legend(lines1 + lines2, labels1 + labels2, fontsize=8, loc="upper left")
    FS.panel_label(ax, 1)

    fig.suptitle("Demand-family scenarios (near-term): capacities x0.7 / x1.0 / "
                 "x1.0 with M=450,L=200 / x1.4",
                 fontweight="bold", fontsize=11)
    fig.tight_layout(rect=[0, 0, 1, 0.90])
    fig.savefig(os.path.join(FIG, "sfig4_demand_family.png"), dpi=400,
                bbox_inches="tight")
    plt.close(fig)
    print("saved sfig4_demand_family.png")

if __name__ == "__main__":
    sfig2()
    sfig3()
    sfig4()
