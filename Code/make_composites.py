"""
make_composites.py — composites are now built data-level (single figures, no
raster re-sampling):
  fig2_econmarket.png : visualize_v2.fig_econmarket_composite (panels I/II)
  fig4_iv_maps.png    : fig45_iv_maps.fig_iv_maps_composite   (panels I/II)
This script keeps the final_postprocess.ps1 call point and simply delegates.
Usage: python make_composites.py [scenario]
"""
import sys
import matplotlib
matplotlib.use("Agg")

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"

import visualize_v2  # noqa: F401  (figures guarded by __main__)
import fig45_iv_maps  # noqa: F401

visualize_v2.fig_econmarket_composite()
fig45_iv_maps.fig_iv_maps_composite()
print("composites written (data-level)")
