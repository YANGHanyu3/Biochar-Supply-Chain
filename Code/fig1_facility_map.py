"""
fig1_facility_map.py - optimal facility locations (colored Python map,
advisor-approved matplotlib style, group conventions: Calibri Light, 400 DPI).
County basemap light gray; facility markers: T1 gray, T2-300C deep blue,
T2-500C light blue; size by scale tier.
Usage: python fig1_facility_map.py [scenario]
"""
import sys, os
import numpy as np
import pandas as pd
import geopandas as gpd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
resdir = f"results_v2/{scen}"
figdir = os.path.join(resdir, "figures")
os.makedirs(figdir, exist_ok=True)

import figstyle as FS
FS.apply()
plt.rcParams["font.family"] = "Calibri"

z = pd.read_csv(os.path.join(resdir, "z_star_MIP_v2.csv"))
nm = pd.read_csv(os.path.join("biochar_data_v2", scen, "node_matrix.csv"))
z["tech_class"] = np.where(z.tech <= 13, "T1 drying",
                  np.where(z.tech <= 26, "T2 300C", "T2 500C"))
z = z.merge(nm[["node_id", "lat", "lon"]], left_on="node", right_on="node_id")
z["size"] = z.scale.map({1: 42, 2: 120, 3: 280}) * (0.6 + 0.4 * z["count"])

gdf = gpd.read_file(r"WI_Counties.shp").to_crs(epsg=4326)

# ---- county feedstock availability choropleth (light blue ramp) ----
sup = pd.read_csv(os.path.join("biochar_data_v2", scen, "supply_matrix.csv"))
avail = sup.groupby("node")["capacity"].sum() / 1e6          # Mt wet/yr per county
nm["avail"] = nm["node_id"].map(avail).fillna(0.0)
gdf["GEOID"] = gdf["GEOID"].astype(str)
nmf = pd.read_csv("node_fips.csv")
nmf["FIPS5"] = nmf["FIPS5"].astype(str)
nm = nm.merge(nmf[["n_id", "FIPS5"]], left_on="node_id", right_on="n_id", how="left")
gdf = gdf.merge(nm[["FIPS5", "avail"]], left_on="GEOID", right_on="FIPS5", how="left")
AV_RAMP = ["#F4F8FB", "#DCE9F5", "#B7D3E8", "#8BB3D1", "#5E8FB5"]
bins = [0, 0.05, 0.12, 0.22, 0.40, 0.60]
gdf["avail_bin"] = pd.cut(gdf["avail"].fillna(0), bins=bins, labels=False)

# ---- Great Lakes layer ----
lakes = gpd.read_file(r"WI_Lakes.shp").to_crs(epsg=4326)

fig, ax = plt.subplots(figsize=(8.6, 6.8))
for bi, col in enumerate(AV_RAMP):
    sub = gdf[gdf["avail_bin"] == bi]
    if len(sub):
        sub.plot(ax=ax, color=col, edgecolor="white", linewidth=0.5, zorder=1)
gdf.dissolve().boundary.plot(ax=ax, color="#8C8C8C", linewidth=1.1, zorder=2)
lakes.plot(ax=ax, color="#D6E4EE", edgecolor="#B8CAD8", linewidth=0.6, zorder=1)

# feedstock-availability legend handles (drawn as a figure strip below the map)
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
av_leg = [Patch(facecolor=c, edgecolor="white", label=f"{bins[i]:.2f}–{bins[i+1]:.2f}")
          for i, c in enumerate(AV_RAMP)]

colors = {"T1 drying": FS.GRAY, "T2 300C": FS.DEEP, "T2 500C": FS.LIGHT}
for cls, grp in z.groupby("tech_class"):
    ax.scatter(grp.lon, grp.lat, s=grp["size"], c=colors[cls], alpha=0.85,
               edgecolors="white", linewidths=0.6, label=cls, zorder=3)

ax.set_title(f"Optimal facility locations (S0 baseline, {scen})",
             fontweight="bold", fontsize=12)
ax.legend(loc="lower left", bbox_to_anchor=(0.0, -0.055), title="Technology",
          frameon=True, fontsize=9.5, title_fontsize=10,
          facecolor="white", edgecolor="#BFBFBF")
# availability legend as a figure-level strip below the map (avoids clashing)
fig.legend(handles=av_leg, loc="lower center", ncol=5,
           title="Feedstock availability (Mt wet/yr)", fontsize=7.6,
           title_fontsize=8.2, frameon=False)
ax.axis("off")
fig.savefig(os.path.join(figdir, "fig1_facility_map.png"), dpi=400, bbox_inches="tight")
plt.close(fig)
print("saved fig1_facility_map.png | facilities:", len(z))
