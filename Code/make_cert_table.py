"""make_cert_table.py — build Table S9 (solver certificates) from the archived
certificate CSVs (review R1-M7: report incumbent, best bound, gap, termination
status, runtime per certified point).

Best bound is derived from the incumbent and Gurobi's relative MIP gap, which
for a maximization is |ObjBound - ObjVal| / |ObjVal|; the derived value is
labelled as such in the caption. Runtime is the solve time recorded by the run.

Usage: python make_cert_table.py
"""
import os, glob
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "06_Model_LaTeX", "paper_draft",
                   "table_S9_certificates.tex")

# (label, scenario, path, profit column)
SPECS = [
    ("A, p=25", "near", "results_v2/near-term/policy_A_cert_v2.csv", "profit_M"),
    ("C2, p=100", "near", "results_v2/near-term/policy_C2_cert100_v2.csv", "profit"),
    ("C2, p=150 (seed 0)", "near", "results_v2/near-term/policy_C2_certs0_v2.csv", "profit"),
    ("C2, p=150 (seed 1)", "near", "results_v2/near-term/policy_C2_certs1_v2.csv", "profit"),
    ("A, p=100 (recert)", "mature", "results_v2/mature-market medium/policy_A_recert2_v2.csv", "profit_M"),
    ("C2, p=150", "mature", "results_v2/mature-market medium/policy_C2_cert_v2.csv", "profit"),
    ("C2, p=200", "mature", "results_v2/mature-market medium/policy_C2_cert_v2.csv", "profit"),
    ("v2b A, p=0", "near", "results_v2b/near-term/policy_A_hcap1.0_pc0.0_g0.001_tl3600_pc0.0_v2b.csv", "profit_M"),
    ("v2b A, p=50", "mature", "results_v2b/mature-market medium/policy_A_hcap1.0_pc50.0_g0.001_tl3600_pc50.0_v2b.csv", "profit_M"),
    ("v2b C2, p=100", "near", "results_v2b/near-term/policy_C2_cert_v2b.csv", "profit_M"),
    ("v2b C2, p=150", "near", "results_v2b/near-term/policy_C2_cert_v2b.csv", "profit_M"),
]
# the C2 mature file holds both p=150 and p=200 in one sweep
MULTI = {"C2, p=150": 150.0, "C2, p=200": 200.0,
         "v2b C2, p=100": 100.0, "v2b C2, p=150": 150.0}

# The certificate CSVs record gap and termination status but not wall-clock
# runtime, so report the enforced time limit and label the column accordingly.
LIMITS = {"A, p=25": 3600, "C2, p=100": 7200,
          "C2, p=150 (seed 0)": 3600, "C2, p=150 (seed 1)": 3600,
          "A, p=100 (recert)": 3600, "C2, p=150": 3600, "C2, p=200": 3600,
          "v2b A, p=0": 3600, "v2b A, p=50": 3600,
          "v2b C2, p=100": 7200, "v2b C2, p=150": 7200}

rows = []
for label, scen, rel, col in SPECS:
    p = os.path.join(HERE, rel)
    if not os.path.exists(p):
        print("missing:", rel)
        continue
    d = pd.read_csv(p)
    row = d
    if label in MULTI:
        row = d[d.p_c == MULTI[label]]
    if not len(row):
        continue
    r = row.iloc[0]
    inc = float(r[col])
    gap = float(r["gap"]) if "gap" in r and pd.notna(r["gap"]) else float("nan")
    bound = inc * (1.0 + gap)          # maximization: MIPGap = (UB-LB)/|LB|
    rt = LIMITS.get(label, float("nan"))
    rows.append((label, scen, inc, bound, gap * 100.0, rt, str(r.get("status", ""))))

with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("% Auto-generated solver certificate table (make_cert_table.py)\n")
    f.write("\\begin{tabular}{llrrrrl}\n\\toprule\n")
    f.write("Point & Scenario & Incumbent (M\\$) & Best bound (M\\$) & Gap (\\%) & Limit (s) & Status\\\\\n\\midrule\n")
    for label, scen, inc, bound, gap, rt, st in rows:
        rts = "--" if rt != rt else f"{rt:.0f}"
        f.write(f"{label} & {scen} & {inc:,.1f} & {bound:,.1f} & {gap:.1f} & {rts} & {st}\\\\\n")
    f.write("\\bottomrule\n\\end{tabular}\n")
print(f"wrote {OUT} with {len(rows)} rows")
for r in rows:
    print("  ", r)

# ---------------------------------------------------------------------------
# Table S10: gross-cap dual ranges (review R1-M4). The dual of a degenerate
# vertex is an interval, so report the left/right re-solves at CAP +- 50 kt.
# ---------------------------------------------------------------------------
OUT10 = os.path.join(HERE, "..", "06_Model_LaTeX", "paper_draft",
                     "table_S10_dualrange.tex")
with open(OUT10, "w", encoding="utf-8", newline="\n") as f:
    f.write("% Auto-generated gross-cap dual ranges (make_cert_table.py)\n")
    f.write("\\begin{tabular}{llrrrrr}\n\\toprule\n")
    f.write("Scenario & Cap (kt) & $\\Pi^{*}$ (M\\$) & $-\\mu_{\\mathrm{CAP}}$ (\\$/t) "
            "& at $-50$ kt & at $+50$ kt & width (\\%)\\\\\n\\midrule\n")
    for scen_dir, tag in (("results_v2/near-term", "near-term"),
                          ("results_v2/mature-market medium", "mature")):
        p = os.path.join(HERE, scen_dir, "prop1_dual_range_v2.csv")
        if not os.path.exists(p):
            continue
        d = pd.read_csv(p)
        for _, r in d.iterrows():
            # at a non-binding cap the dual is ~0 and the relative width is
            # meaningless, so print n/a rather than a huge ratio
            wid = "n/a" if abs(r.pi_dollar_per_t) < 1.0 else f"{r.bracket_pct:,.1f}"
            f.write(f"{tag} & {r.cap_kt:,.1f} & {r.profit_M:,.2f} & "
                    f"{r.pi_dollar_per_t:,.2f} & {r.pi_at_minus50:,.2f} & "
                    f"{r.pi_at_plus50:,.2f} & {wid}\\\\\n")
    f.write("\\bottomrule\n\\end{tabular}\n")
print("wrote", OUT10)

# ---------------------------------------------------------------------------
# Table S11: N2O factor sensitivity (review R1-M1), Paradigm-A basis, fixed
# layout at p_c = 200 $/t.
# ---------------------------------------------------------------------------
OUT11 = os.path.join(HERE, "..", "06_Model_LaTeX", "paper_draft",
                     "table_S11_n2o.tex")
with open(OUT11, "w", encoding="utf-8", newline="\n") as f:
    f.write("% Auto-generated N2O sensitivity (make_cert_table.py)\n")
    f.write("\\begin{tabular}{llrrrr}\n\\toprule\n")
    f.write("Scenario & N$_2$O factor & Surplus (M\\$) & Credits (Mt) & Net flux (Mt) & Biochar (Mt)\\\\\n\\midrule\n")
    for scen_dir, tag in (("results_v2/near-term", "near-term"),
                          ("results_v2/mature-market medium", "mature")):
        p = os.path.join(HERE, scen_dir, "n2o_sensitivity_v2.csv")
        if not os.path.exists(p):
            continue
        for _, r in pd.read_csv(p).iterrows():
            f.write(f"{tag} & $\\times${r.n2o_mult:.1f} & {r.profit_M:,.1f} & "
                    f"{r.cc_Mt:.3f} & {r.net_Mt:.3f} & {r.bc_Mt:.3f}\\\\\n")
    f.write("\\bottomrule\n\\end{tabular}\n")
print("wrote", OUT11)
