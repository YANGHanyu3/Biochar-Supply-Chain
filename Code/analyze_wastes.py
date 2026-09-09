import pandas as pd
import os

src = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "supplementary data", "billionton_23_wastes_download20260902.csv")
outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "03_Data", "WI_Working_Files")
os.makedirs(outdir, exist_ok=True)

df = pd.read_csv(src, dtype={"fips": str, "price_offered": float, "production_total": str})
df["prod"] = pd.to_numeric(df["production_total"].str.replace(",", "", regex=False), errors="coerce")
# normalize units: dt (dry ton, same as dry short ton) vs ton -> treat both as dt-equivalent
print("unit counts:", df.production_unit.value_counts().to_dict())
df["dry_t"] = df["prod"]  # BT23 wastes 'dt' = dry tons; 'ton' rows inspected below
# inspect which resources use 'ton'
print("\nresources with unit 'ton':", sorted(df[df.production_unit == "ton"].resource.unique()))

summary = []
for scen in ["near-term", "mature-market medium"]:
    for res, g in df[df.scenario_name == scen].groupby("resource"):
        sub = g[g.price_offered <= 70.0]
        tot = sub["dry_t"].sum()
        ncounty = sub.county.nunique()
        summary.append((scen, res, tot, ncounty))

s = pd.DataFrame(summary, columns=["scenario", "resource", "dry_t_at_70", "counties"])
print("\n=== WI wastes available at <= $70/dry-t (kt) ===")
piv = s.pivot_table(index="resource", columns="scenario", values="dry_t_at_70")
piv["near-term"] /= 1000
piv["mature-market medium"] /= 1000
print(piv.round(1).to_string())

s.to_csv(os.path.join(outdir, "bt23_wastes_WI_summary.csv"), index=False)
print("\nsaved ->", os.path.join(outdir, "bt23_wastes_WI_summary.csv"))
print("\nstate totals (kt at $70):")
print(s.groupby("scenario")["dry_t_at_70"].sum().div(1000).round(1))
