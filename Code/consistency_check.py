"""consistency_check.py — cross-check headline numbers in the manuscript
against the archived result CSVs (review R1-M9: automated table/figure
consistency check).

Checks the numbers that appear in the abstract, results text, and captions
against the CSVs they are derived from. Prints PASS/FAIL per check and exits
non-zero if any check fails, so it can be run in CI.

Usage: python consistency_check.py [scen]   (default: near-term)
"""
import os, re, sys, csv

HERE = os.path.dirname(os.path.abspath(__file__))
PAPER = os.path.join(HERE, "..", "06_Model_LaTeX", "paper_draft")
SCEN = sys.argv[1] if len(sys.argv) > 1 else "near-term"
RES = os.path.join(HERE, "results_v2", SCEN)
RESB = os.path.join(HERE, "results_v2b", SCEN)


def tex(name):
    return open(os.path.join(PAPER, name), encoding="utf-8").read()


def num(path, key, row=0):
    """Read a `key = value` line from a summary txt, or a CSV column."""
    if path.endswith(".txt"):
        t = open(path).read()
        m = re.search(rf"{key}\s*=\s*([-\d.]+)", t)
        return float(m.group(1)) if m else None
    rows = list(csv.DictReader(open(path)))
    return float(rows[row][key])


def csv_row(path, **match):
    for r in csv.DictReader(open(path)):
        if all(abs(float(r[k]) - v) < 1e-6 for k, v in match.items()):
            return r
    return None


checks = []


def check(label, claimed, actual, tol=0.02):
    ok = actual is not None and abs(claimed - actual) <= tol * max(1.0, abs(actual))
    checks.append((ok, label, claimed, actual))


# ---- baseline -------------------------------------------------------------
s0 = os.path.join(RES, "S0_summary.txt")
abs_t = tex("abstract.tex")
res_t = tex("results.tex")

check("abstract: 2.30 Mt biochar", 2.30, num(s0, "bc_Mt"), 0.01)
check("abstract: $708 M/yr surplus", 708.0, num(s0, "objective_M"), 0.01)
check("results: net removal -1.60 Mt", -1.60, num(s0, "net_ghg_Mt"), 0.02)

# ---- Paradigm A extremes --------------------------------------------------
a = None
pa = os.path.join(RES, "policy_A_regen_v2.csv")
if os.path.exists(pa):
    a = csv_row(pa, p_c=200.0)
    check("abstract: $3.36 B/yr surplus at p_c=200",
          3360.0, float(a["profit_M"]), 0.01)
    check("results: A p_c=0 surplus 708.6", 708.6, float(csv_row(pa, p_c=0.0)["profit_M"]), 0.01)

# ---- net-cap frontier -----------------------------------------------------
nm = os.path.join(RES, "netcap_Nmin_v2.txt")
if os.path.exists(nm):
    check("results: N_min = -2602 kt", -2602.0, num(nm, "nmin_kt"), 0.01)

# ---- Prop 3 ---------------------------------------------------------------
# tau is stored in $/kg and was rounded in early runs, so derive it from the
# stored margin ($/t biochar) and e_d (kg CO2e/t biochar) columns instead.
for scen_dir, claimed in ((RES, 318.0),
                          (os.path.join(HERE, "results_v2", "mature-market medium"), 464.0)):
    p3 = os.path.join(scen_dir, "prop3_basis_check_v2.csv")
    if os.path.exists(p3):
        p3rows = list(csv.DictReader(open(p3)))
        taus = [float(r["margin"]) / float(r["e_d"]) * 1000.0 for r in p3rows]
        tag = "near" if scen_dir == RES else "mature"
        check(f"methods: tau_max ({tag}) ~= {claimed:.0f} $/t",
              claimed, min(taus), 0.02)

# ---- mature-market recertification ----------------------------------------
r2 = os.path.join(HERE, "results_v2", "mature-market medium", "policy_A_recert2_v2.csv")
if os.path.exists(r2):
    check("results: mature recert BC500 2.81 Mt", 2.81,
          num(r2, "bc_500_Mt"), 0.02)

# ---- v2b Table 3 (mature-market rows) -------------------------------------
pv = os.path.join(HERE, "results_v2b", "mature-market medium",
                  "policy_A_bnc_sweep_v2b.csv")
if os.path.exists(pv):
    check("results: v2b no-policy surplus 675", 675.0,
          float(csv_row(pv, p_c=0.0)["profit_M"]), 0.01)
    check("results: v2b BC500 mature 2.83 Mt", 2.83,
          float(csv_row(pv, p_c=200.0)["bc500_Mt"]), 0.02)

# ---- tex must not contain retired claims ----------------------------------
retired = ["net caps are blind", "VM0044-compliant", "endogenous carbon price"]
for pat in retired:
    present = any(pat in tex(f) for f in
                  ("abstract.tex", "introduction.tex", "methods.tex",
                   "results.tex", "discussion.tex", "conclusion.tex", "si.tex"))
    checks.append((not present, f"retired phrasing absent: '{pat}'", 0, 0))

# ---- report ---------------------------------------------------------------
fails = 0
for ok, label, claimed, actual in checks:
    tag = "PASS" if ok else "FAIL"
    if not ok:
        fails += 1
    av = "n/a" if actual is None else f"{actual:g}"
    print(f"[{tag}] {label:52s} claimed={claimed:<10g} found={av}")
print(f"\n{len(checks) - fails}/{len(checks)} checks passed")
sys.exit(1 if fails else 0)
