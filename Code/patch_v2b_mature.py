import pandas as pd

f = "results_v2b/mature-market medium/policy_A_bnc_sweep_v2b.csv"
df = pd.read_csv(f)
for pc, src in [(100.0, "results_v2b/mature-market medium/policy_A_hcap1.0_pc100.0_g0.001_tl1800_pc100.0_v2b.csv"),
                (200.0, "results_v2b/mature-market medium/policy_A_hcap1.0_pc200.0_g0.001_tl1800_pc200.0_v2b.csv")]:
    t = pd.read_csv(src)
    assert len(t) == 1, src
    for col in ["profit_M", "bc300_Mt", "bc500_Mt", "bc_Mt", "cc_Mt", "seg_H", "seg_M", "seg_L", "sink_Mt", "ghg_Mt", "gap", "status"]:
        df.loc[df.p_c == pc, col] = t.iloc[0][col]
df.to_csv(f, index=False)
print(df[df.p_c.isin([100.0, 200.0])][["p_c", "profit_M", "bc300_Mt", "bc500_Mt", "bc_Mt", "gap", "status"]].to_string(index=False))
print("patched", f)
