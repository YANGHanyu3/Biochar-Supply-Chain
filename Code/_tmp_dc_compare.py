"""Compare the baseline demand allocation (alpha=1) with the concentrated
demand-geography sensitivities (alpha=3, 10). Reports facility counts,
surplus, wet-biomass use, and the spatial overlap of the chosen counties.
"""
import os
import sys
import pandas as pd

sys.stdout.reconfigure(encoding="utf-8")
BASE = r"E:\hhy\Desktop\BIochar Supply Chain\01_Current_Code"
SCEN = "near-term"

runs = {
    1: os.path.join(BASE, "results_v2", SCEN),
    3: os.path.join(BASE, "results_v2_dc3", SCEN),
    10: os.path.join(BASE, "results_v2_dc10", SCEN),
}

info = {}
for a, d in runs.items():
    zf = os.path.join(d, "z_star_MIP_v2.csv")
    sf = os.path.join(d, "S0_summary.txt")
    if not (os.path.exists(zf) and os.path.exists(sf)):
        print(f"alpha={a}: MISSING results in {d}")
        continue
    z = pd.read_csv(zf)
    z["techclass"] = z.tech.map(lambda t: "T1" if t <= 13 else ("T2_300" if t <= 26 else "T2_500"))
    counts = z.groupby("techclass")["count"].sum().to_dict()
    counties = sorted(z["node"].unique())
    txt = open(sf, encoding="utf-8").read()
    obj = float([l for l in txt.splitlines() if l.startswith("objective_M")][0].split("=")[1])
    wet = float([l for l in txt.splitlines() if l.startswith("wet_Mt")][0].split("=")[1])
    bc = float([l for l in txt.splitlines() if l.startswith("bc_Mt")][0].split("=")[1].split("(")[0])
    info[a] = dict(counts=counts, counties=set(counties), obj=obj, wet=wet, bc=bc)

print(f"{'alpha':>6} {'T1':>5} {'T2_300':>7} {'T2_500':>7} {'surplus M$':>11} {'wet Mt':>8} {'BC Mt':>7} {'counties':>9}")
for a in sorted(info):
    i = info[a]
    c = i["counts"]
    print(f"{a:>6} {c.get('T1',0):>5} {c.get('T2_300',0):>7} {c.get('T2_500',0):>7} "
          f"{i['obj']:>11.1f} {i['wet']:>8.2f} {i['bc']:>7.3f} {len(i['counties']):>9}")

if 1 in info:
    base_c = info[1]["counties"]
    for a in sorted(info):
        if a == 1:
            continue
        s = info[a]["counties"]
        inter = len(base_c & s)
        print(f"alpha={a}: {inter}/{len(s)} counties overlap with baseline "
              f"({100*inter/len(s):.0f}%); {inter}/{len(base_c)} of baseline "
              f"({100*inter/len(base_c):.0f}%)")
