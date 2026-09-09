"""Patch policy_A_bnc_sweep_v2.csv rows for p_c=25,50 with the extended
(1800 s) incumbents, which strictly improved both scenarios."""
import pandas as pd
import os

_ROOT = os.path.dirname(os.path.abspath(__file__))
base = os.path.join(_ROOT, "results_v2")

for sc in ["near-term", "mature-market medium"]:
    canon_path = os.path.join(base, sc, "policy_A_bnc_sweep_v2.csv")
    ext_path = os.path.join(base, sc, "policy_A_extended_v2.csv")
    canon = pd.read_csv(canon_path)
    ext = pd.read_csv(ext_path)
    assert list(ext.columns) == list(canon.columns), (list(ext.columns), list(canon.columns))
    n_patch = 0
    for _, row in ext.iterrows():
        pc = row["p_c"]
        mask = canon["p_c"] == pc
        if mask.any():
            old = canon.loc[mask].iloc[0]
            improved = row["profit_M"] > old["profit_M"] + 1e-3
            print(f"[{sc}] pc={pc:g}: old profit={old['profit_M']:.2f} -> new {row['profit_M']:.2f} "
                  f"({'IMPROVED' if improved else 'not better'})")
            if improved:
                canon.loc[mask, :] = row.values
                n_patch += 1
    canon.to_csv(canon_path, index=False)
    print(f"[{sc}] patched {n_patch} rows -> {canon_path}")
