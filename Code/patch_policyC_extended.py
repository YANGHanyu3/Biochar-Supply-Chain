"""Patch policy_C2_tax_credit_v2.csv rows with extended (1800 s) incumbents
where they improved. Column layout of the C2 CSVs:
p_c, profit, emis, bc, cc, bc300, bc500, gap, status"""
import pandas as pd
import os

_ROOT = os.path.dirname(os.path.abspath(__file__))
base = os.path.join(_ROOT, "results_v2")

for sc in ["near-term", "mature-market medium"]:
    canon_path = os.path.join(base, sc, "policy_C2_tax_credit_v2.csv")
    ext_path = os.path.join(base, sc, "policy_C2_extended_v2.csv")
    if not os.path.exists(ext_path):
        print(f"[{sc}] no extended file yet; skip")
        continue
    canon = pd.read_csv(canon_path)
    ext = pd.read_csv(ext_path)
    n_patch = 0
    for _, row in ext.iterrows():
        pc = row["p_c"]
        mask = canon["p_c"] == pc
        if mask.any():
            old = canon.loc[mask].iloc[0]
            improved = row["profit"] > old["profit"] + 1e-3
            print(f"[{sc}] pc={pc:g}: old profit={old['profit']:.2f} (gap {old['gap']:.3f}) "
                  f"-> new {row['profit']:.2f} (gap {row['gap']:.3f}) {'IMPROVED' if improved else 'not better'}")
            if improved:
                canon.loc[mask, :] = row.values
                n_patch += 1
    canon.to_csv(canon_path, index=False)
    print(f"[{sc}] patched {n_patch} rows -> {canon_path}")
