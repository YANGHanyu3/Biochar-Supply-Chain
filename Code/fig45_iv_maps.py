"""
fig45_iv_maps.py - Inherent value maps (colored Python choropleths, advisor-approved style)
fig4: biochar inherent value  (Blues ramp)
fig5: wet corn stover inherent value (Reds ramp)
Group conventions: Calibri Light, white county outlines, colorbar, 400 DPI.
Usage: python fig45_iv_maps.py [scenario]
"""
import sys, os
import numpy as np
import pandas as pd
import geopandas as gpd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.cm as cm
from mpl_toolkits.axes_grid1 import make_axes_locatable

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
resdir = f"results_v2/{scen}"
figdir = os.path.join(resdir, "figures")
os.makedirs(figdir, exist_ok=True)

import figstyle as FS
FS.apply()
plt.rcParams["font.family"] = "Calibri"

shp = r"WI_Counties.shp"
iv = pd.read_csv(os.path.join(resdir, "LP_duals_inherent_value_v2.csv"))
fips_map = pd.read_csv("node_fips.csv")
fips_map["FIPS5"] = fips_map["FIPS5"].astype(str)
iv = iv.merge(fips_map[["n_id", "FIPS5"]], left_on="node", right_on="n_id")

gdf = gpd.read_file(shp).to_crs(epsg=4326)
gdf["GEOID"] = gdf["GEOID"].astype(str)
lakes = gpd.read_file(r"WI_Lakes.shp").to_crs(epsg=4326)

def draw_iv(ax, product, title, cmap_name, label, annotate=False):
    d = iv[iv["product"] == product].copy()
    g = gdf.merge(d[["FIPS5", "inherent_value"]], left_on="GEOID", right_on="FIPS5",
                  how="left")
    vmin, vmax = d.inherent_value.min(), d.inherent_value.max()
    g.plot(ax=ax, column="inherent_value", cmap=cmap_name, vmin=vmin, vmax=vmax,
           edgecolor="white", linewidth=0.45, legend=False, zorder=0,
           missing_kwds=dict(color="#E7E6E6"))
    # zoom to the state boundary (v0.8: no lakes layer, tighter framing)
    x0, y0, x1, y1 = gdf.total_bounds
    mx, my = 0.03 * (x1 - x0), 0.03 * (y1 - y0)
    ax.set_xlim(x0 - mx, x1 + mx)
    ax.set_ylim(y0 - my, y1 + my)
    if annotate:
        top = d.nlargest(3, "inherent_value")
        bot = d.nsmallest(3, "inherent_value")
        fips_to_geom = dict(zip(gdf.GEOID, gdf.geometry))
        for _, r in top.iterrows():
            pt = fips_to_geom.get(r["FIPS5"])
            if pt is not None:
                ax.annotate(f"{r['inherent_value']:.0f}", (pt.representative_point().x, pt.representative_point().y),
                            ha="center", fontsize=8.2, color="#1A1A1A", fontweight="bold")
        for _, r in bot.iterrows():
            pt = fips_to_geom.get(r["FIPS5"])
            if pt is not None:
                ax.annotate(f"{r['inherent_value']:.0f}", (pt.representative_point().x, pt.representative_point().y),
                            ha="center", fontsize=8.2, color="#404040")
    ax.set_title(title, fontweight="bold", fontsize=12)
    ax.axis("off")
    return vmin, vmax

def add_colorbar(fig, ax, vmin, vmax, cmap_name, label):
    sm = cm.ScalarMappable(cmap=cmap_name, norm=plt.Normalize(vmin, vmax))
    sm.set_array([])
    cbar = fig.colorbar(sm, ax=ax, shrink=0.72, pad=0.02)
    cbar.set_label(label, fontsize=11)
    cbar.ax.tick_params(labelsize=10)

def plot_iv(product, title, cmap_name, label, filename, annotate=False):
    fig, ax = plt.subplots(figsize=(7.4, 5.9))
    vmin, vmax = draw_iv(ax, product, title, cmap_name, label, annotate)
    add_colorbar(fig, ax, vmin, vmax, cmap_name, label)
    fig.savefig(os.path.join(figdir, filename), dpi=400, bbox_inches="tight")
    plt.close(fig)
    print(f"saved {filename} (range {vmin:.1f}..{vmax:.1f})")

# ---- data-level composite (paper Fig. 4: two IV maps side by side) ----
def fig_iv_maps_composite():
    fig, axes = plt.subplots(1, 2, figsize=(11.6, 5.0))
    v1 = draw_iv(axes[0], 27, f"Inherent value of biochar (USD/t) — {scen}", "YlOrRd",
                 "USD/t biochar", annotate=False)
    v2 = draw_iv(axes[1], 1, f"Inherent value of wet corn stover (USD/t) — {scen}",
                 "YlGnBu", "USD/t wet biomass", annotate=False)
    add_colorbar(fig, axes[0], v1[0], v1[1], "YlOrRd", "USD/t biochar")
    add_colorbar(fig, axes[1], v2[0], v2[1], "YlGnBu", "USD/t wet biomass")
    FS.panel_label(axes[0], 0)
    FS.panel_label(axes[1], 1)
    fig.savefig(os.path.join(figdir, "fig4_iv_maps.png"), dpi=400, bbox_inches="tight")
    plt.close(fig)
    print("saved fig4_iv_maps.png (data-level composite)")

if __name__ == "__main__":
    plot_iv(27, f"Inherent value of biochar (USD/t) — {scen}", "YlOrRd",
            "USD/t biochar", "fig4_iv_biochar.png")
    plot_iv(1, f"Inherent value of wet corn stover (USD/t) — {scen}", "YlGnBu",
            "USD/t wet biomass", "fig5_iv_biomass.png")
    fig_iv_maps_composite()
