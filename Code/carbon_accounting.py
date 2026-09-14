# =============================================================================
# carbon_accounting.py — Phase 1 (v0.9 review fix): carbon mass balance + cash
# flow decomposition.
#
# Answers the reviewer's C1/R1-M1/R2-M4 objections:
#   1. Per-dry-tonne carbon ledger (carbon in / char carbon / gas-liquid carbon /
#      process E+ / transport / N2O / durable S / baseline avoided B / net N /
#      credits under basis A (B - E+ + |S|) and basis C2 (|S|, H/C-gated)).
#   2. System-level reconciliation: credits_A = B - E+ + |S| = B - N, which is
#      why creditable quantity (~10.8-13.6 Mt) far exceeds net removal
#      (-1.60 to -1.96 Mt).
#   3. Cash-flow decomposition per policy point: consumer payment, credit
#      revenue, tax payment, resource cost, surplus, physical net removal,
#      creditable quantity.
#
# Outputs (to a per-scenario results dir):
#   carbon_balance_v2.csv, system_reconciliation_v2.txt,
#   cashflow_decomposition_v2.csv, table_S6_carbon.tex, table_S7_cashflow.tex
# =============================================================================
import os, sys
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_data_v2 as g

CO2_C = 44.0 / 12.0          # kg CO2e per kg C
N2O = 52.0                   # kg CO2e/t BC (Cayuela 2014)
DECOMP = 0.90

def load_data(scen, datadir=None, resdir=None):
    d = datadir or os.path.join("biochar_data_v2", scen)
    r = resdir or os.path.join("results_v2", scen)
    ghg = pd.read_csv(os.path.join(d, "ghg_factors_v2.csv"))
    tn = pd.read_csv(os.path.join(d, "technology_names.csv"))
    alpha = pd.read_csv(os.path.join(d, "alpha_matrix.csv"), header=None)
    return ghg, tn, alpha, r

def per_dry_tonne_ledger(scen, datadir=None, resdir=None):
    """Table 1 of the review's requested accounting: kg per t dry feedstock."""
    ghg, tn, alpha, r = load_data(scen, datadir, resdir)
    N_FS = 13
    rows = []
    for f in range(N_FS):
        name = g.FS[f]
        fd = g.FEEDSTOCKS[name]
        t1 = ghg.iloc[f]                      # T1 row
        t2_300 = ghg.iloc[N_FS + f]           # T2-300 row
        t2_500 = ghg.iloc[2 * N_FS + f]       # T2-500 row
        eta = fd['eta']                       # wet -> dry yield
        # carbon ledger (kg C per t dry)
        c_in = fd['C'] * 1000.0
        c_char_300 = fd['y300'] * fd['C'] * 1000.0
        c_char_500 = fd['y500'] * fd['C500'] * 1000.0
        c_gas_300 = c_in - c_char_300
        c_gas_500 = c_in - c_char_500
        # emissions / removal per t dry
        e1 = t1['process_ghg_per_t_ref'] / eta                 # T1 per t dry
        e2_300 = e1 + t2_300['process_ghg_per_t_ref']
        e2_500 = e1 + t2_500['process_ghg_per_t_ref']
        n2o_300 = N2O * fd['y300']; n2o_500 = N2O * fd['y500']
        s_300 = -(t2_300['ghg_seq_per_t_bc'] * fd['y300'] + n2o_300)   # |S| per t dry
        s_500 = -(t2_500['ghg_seq_per_t_bc'] * fd['y500'] + n2o_500)
        b = fd['baseline_ghg_dry']             # B per t dry (0.9 decay)
        n_300 = e2_300 - s_300                 # N = E+ - |S|
        n_500 = e2_500 - s_500
        cred_a_300 = (b - e2_300 + s_300) / 1000.0   # tCC per t dry (basis A)
        cred_a_500 = (b - e2_500 + s_500) / 1000.0
        cred_c2_300 = (s_300 / 1000.0) if fd['eligible_300'] else 0.0
        cred_c2_500 = (s_500 / 1000.0) if fd['eligible_500'] else 0.0
        rows.append(dict(
            feedstock=name.replace(" ", "_"), c_in=c_in,
            c_char_300=c_char_300, c_char_500=c_char_500,
            c_gas_300=c_gas_300, c_gas_500=c_gas_500,
            e_300=e2_300, e_500=e2_500, n2o_300=n2o_300, n2o_500=n2o_500,
            s_300=s_300, s_500=s_500, b=b,
            n_300=n_300, n_500=n_500,
            credit_A_300=cred_a_300, credit_A_500=cred_a_500,
            credit_C2_300=cred_c2_300, credit_C2_500=cred_c2_500,
            hc300=fd['hc300'], hc500=fd['hc500'],
            eligible_300=fd['eligible_300'], eligible_500=fd['eligible_500']))
    df = pd.DataFrame(rows)
    return df

def system_reconciliation(scen, resdir=None):
    """Check credits = B - E+ + |S| = B - N at the system level (near-term)."""
    r = resdir or os.path.join("results_v2", scen)
    a = pd.read_csv(os.path.join(r, "policy_A_bnc_sweep_v2.csv"))
    s3 = open(os.path.join(r, "S3_summary.txt")).read()
    out = []
    out.append(f"# System-level carbon reconciliation ({scen})")
    out.append(s3.strip())
    out.append(f"{'p_c':>5} {'BC(Mt)':>8} {'CC_A(Mt)':>9} {'B(Mt)':>7} {'E+(kt)':>7} {'|S|(kt)':>8} {'N(Mt)':>7} {'identity':>12}")
    # E+ and |S| per point: E+ grows with throughput; |S| = sum of seq over BC.
    # From the A CSV we have cc_Mt (creditable qty), baseline_Mt (B), ghg_Mt (net N).
    # Identity: cc = B - E+ + |S|  and N = E+ - |S|  =>  cc = B - N.
    ok = True
    for _, row in a.iterrows():
        cc = row.cc_Mt; B = row.baseline_Mt; N = row.ghg_Mt
        lhs = cc; rhs = B - N
        err = abs(lhs - rhs)
        flag = "OK" if err < 0.05 else f"DIFF {err:.3f}"
        if err >= 0.05:
            ok = False
        out.append(f"{row.p_c:>5.0f} {row.bc_Mt:>8.3f} {cc:>9.3f} {B:>7.3f} "
                   f"{'-':>7} {'-':>8} {N:>7.3f} {flag:>12}")
    out.append("IDENTITY cc = B - N: " + ("PASS" if ok else "FAIL"))
    return "\n".join(out), a

def cashflow_decomposition(scen, resdir=None, a_csv="policy_A_regen_v2.csv",
                           c2_csv="policy_C2_regen_v2.csv"):
    """Per policy point: consumer payment, credit revenue, tax, resource cost,
    surplus, physical net removal, creditable quantity. Uses the enriched
    (regen) sweeps so every row is internally consistent: the identity
    surplus = consumer + credit revenue - tax - resource cost holds row-wise.
    Canonical CSVs without the cost columns fall back to the identity residual."""
    r = resdir or os.path.join("results_v2", scen)
    rows = []
    # ── Paradigm A (enriched regen sweep has seg split + cost columns) ──
    a = pd.read_csv(os.path.join(r, a_csv))
    for _, row in a.iterrows():
        consumer = (800.0 * row.seg_H + 500.0 * row.seg_M + 250.0 * row.seg_L
                    + 30.0 * row.sink_Mt) / 1e6               # segs in t -> M$
        credit_rev = row.cc_sold_Mt * row.p_c                  # M$
        if "farmgate_M" in a.columns:
            resource = row.farmgate_M + row.opex_M + row.transport_M + row.capex_M
        else:
            resource = consumer + credit_rev - row.profit_M    # identity
        rows.append(dict(policy="A", p_c=row.p_c, consumer_M=consumer,
                         credit_rev_M=credit_rev, tax_M=0.0, resource_M=resource,
                         surplus_M=row.profit_M, net_Mt=row.ghg_Mt,
                         cc_Mt=row.cc_Mt, status=row.status))
    # ── Paradigm C2 ──
    c2path = os.path.join(r, c2_csv)
    if os.path.exists(c2path):
        c2 = pd.read_csv(c2path)
        E0 = 1002.79          # baseline gross emissions in kt (tiers at 0.4/0.7 E0)
        t1, t2 = 0.4 * E0, 0.7 * E0
        for _, row in c2.iterrows():
            E = row.emis                       # kt (06 reports value(Eg)/1e6)
            a1 = min(E, t1); a2 = min(max(E - t1, 0.0), t2 - t1); a3 = max(E - t2, 0.0)
            tax = (25.0 * a1 + 50.0 * a2 + 100.0 * a3) / 1000.0   # M$ (a_i in kt)
            if "rev_bc_M" in c2.columns:
                consumer = row.rev_bc_M
                resource = row.farmgate_M + row.opex_M + row.transport_M + row.capex_M
                credit_rev = row.credit_rev_M
                tax = row.tax_M
            else:
                consumer = float("nan")        # segment split unknown pre-enrichment
                credit_rev = row.cc * row.p_c
                resource = float("nan")
            net_mt = row.net_Mt if "net_Mt" in c2.columns else float("nan")
            rows.append(dict(policy="C2", p_c=row.p_c, consumer_M=consumer,
                             credit_rev_M=credit_rev, tax_M=tax, resource_M=resource,
                             surplus_M=row.profit, net_Mt=net_mt,
                             cc_Mt=row.cc, status=row.status))
    # ── override points with certified re-solves (internally consistent rows) ──
    for cert_fn, pol in (("policy_A_cert_v2.csv", "A"),
                         ("policy_C2_certs0_v2.csv", "C2")):
        certp = os.path.join(r, cert_fn)
        if os.path.exists(certp):
            cc_df = pd.read_csv(certp)
            for _, row in cc_df.iterrows():
                for i, d in enumerate(rows):
                    if d["policy"] != pol or d["p_c"] != row.p_c:
                        continue
                    if pol == "A":
                        consumer = (800.0 * row.seg_H + 500.0 * row.seg_M +
                                    250.0 * row.seg_L + 30.0 * row.sink_Mt) / 1e6  # segs in t
                    else:
                        consumer = (800.0 * row.seg_H + 500.0 * row.seg_M +
                                    250.0 * row.seg_L + 30.0 * row.sink_Mt)       # segs in Mt
                    resource = (row.farmgate_M + row.opex_M + row.transport_M +
                                row.capex_M)
                    net_mt = row.ghg_Mt if pol == "A" else row.net_Mt
                    cc_val = row.cc_Mt if "cc_Mt" in cc_df.columns else row.cc
                    rows[i] = dict(policy=pol, p_c=row.p_c, consumer_M=consumer,
                                   credit_rev_M=row.credit_rev_M,
                                   tax_M=(0.0 if pol == "A" else row.tax_M),
                                   resource_M=resource,
                                   surplus_M=(row.profit_M if pol == "A" else row.profit),
                                   net_Mt=net_mt, cc_Mt=cc_val,
                                   status=row.status + " (cert)")
                    break
    return pd.DataFrame(rows)

def write_latex_tables(ledger, cash, outdir):
    os.makedirs(outdir, exist_ok=True)
    # Table S6: carbon ledger (rows = feedstocks; 300/500 columns)
    with open(os.path.join(outdir, "table_S6_carbon.tex"), "w") as f:
        f.write("% Auto-generated carbon ledger (per t dry feedstock, kg CO2e or kg C)\n")
        f.write("\\begin{tabular}{lrrrrrrrrr}\n\\toprule\n")
        f.write("Feedstock & $C^{in}$ & $S_{300}$ & $S_{500}$ & $E^{+}_{300}$ & $E^{+}_{500}$ & $B$ & $N_{300}$ & $N_{500}$ & $R^{A}_{500}$ (tCC)\\\\\n\\midrule\n")
        for _, r in ledger.iterrows():
            f.write(f"{r.feedstock.replace('_',' ')} & {r.c_in:.0f} & {r.s_300:.0f} & {r.s_500:.0f} & "
                    f"{r.e_300:.0f} & {r.e_500:.0f} & {r.b:.0f} & {r.n_300:.0f} & {r.n_500:.0f} & {r.credit_A_500:.3f}\\\\\n")
        f.write("\\bottomrule\n\\end{tabular}\n")
    # Table S7: cash-flow decomposition
    with open(os.path.join(outdir, "table_S7_cashflow.tex"), "w") as f:
        f.write("% Auto-generated cash-flow decomposition (M$/yr)\n")
        f.write("\\begin{tabular}{lrrrrrrr}\n\\toprule\n")
        f.write("Policy & $p_c$ & Consumer payment & Credit revenue & Tax & Resource cost & Surplus & Net removal (Mt)\\\\\n\\midrule\n")
        for _, r in cash.iterrows():
            f.write(f"{r.policy} & {r.p_c:.0f} & {r.consumer_M:.1f} & {r.credit_rev_M:.1f} & {r.tax_M:.1f} & "
                    f"{r.resource_M:.1f} & {r.surplus_M:.1f} & {r.net_Mt:.3f}\\\\\n")
        f.write("\\bottomrule\n\\end{tabular}\n")

if __name__ == "__main__":
    scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
    resdir = os.path.join("results_v2", scen)
    ledger = per_dry_tonne_ledger(scen)
    ledger.to_csv(os.path.join(resdir, "carbon_balance_v2.csv"), index=False)
    recon, a = system_reconciliation(scen)
    print(recon)
    open(os.path.join(resdir, "system_reconciliation_v2.txt"), "w").write(recon + "\n")
    cash = cashflow_decomposition(scen)
    cash.to_csv(os.path.join(resdir, "cashflow_decomposition_v2.csv"), index=False)
    print("\nCash-flow decomposition (M$/yr):")
    print(cash.to_string(index=False, float_format=lambda x: f"{x:.1f}"))
    write_latex_tables(ledger, cash, resdir)
    print(f"\nSaved: carbon_balance_v2.csv, system_reconciliation_v2.txt, "
          f"cashflow_decomposition_v2.csv, table_S6_carbon.tex, table_S7_cashflow.tex -> {resdir}")
