import pandas as pd
import os

d = "NewData/NASS_2022"

def load(f):
    df = pd.read_csv(os.path.join(d, f), dtype={"Value": str})
    df["v"] = pd.to_numeric(df["Value"].str.replace(",", "", regex=False), errors="coerce")
    return df

corn = load("corn_all_classes_2022.csv")
grain = corn[corn.util_practice_desc == "GRAIN"]["v"].sum()
silage = corn[corn.util_practice_desc == "SILAGE"]["v"].sum()
print(f"corn grain acres  = {grain:,.0f}")
print(f"corn silage acres = {silage:,.0f}")
print(f"silage/(grain+silage) = {silage/(grain+silage):.1%}  (SI claims 0.88M silage / 3.03M grain = 22.5%)")
print()
for name in ["soybeans_2022", "wheat_2022", "oats_2022", "barley_2022", "hay_alfalfa_2022", "potatoes_2022"]:
    df = load(name + ".csv")
    print(f"{name:20s} acres = {df['v'].sum():>12,.0f}   (rows {len(df)})")
cran = load("cranberries_all_statcats_2022.csv")
for sc in ["AREA BEARING", "AREA GROWN", "AREA NON-BEARING"]:
    sub = cran[cran.statisticcat_desc == sc]
    print(f"cranberries {sc:18s} acres = {sub['v'].sum():>10,.0f}")

# county-level grain/silage split by FIPS (for future silage-inclusive sensitivity)
corn["fips5"] = corn["state_fips_code"] + corn["county_code"]
out = corn[corn.util_practice_desc.isin(["GRAIN", "SILAGE"])][["fips5", "county_name", "util_practice_desc", "v"]].copy()
out.to_csv(os.path.join(d, "corn_grain_silage_county_2022.csv"), index=False)
print("\nsaved corn_grain_silage_county_2022.csv with", len(out), "county rows")
