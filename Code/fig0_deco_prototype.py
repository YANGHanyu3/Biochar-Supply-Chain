"""Proof of concept: auto-insert group-native icons into the fig0 layout
at the ICON slots, producing a decorated prototype figure.
This validates placement/scale before the final Illustrator/AI pass.
"""
import os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import image as mpimg
import numpy as np

outdir = sys.argv[1] if len(sys.argv) > 1 else "results_v2/near-term/figures"
ICONS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "07_Plans_Notes", "Asset_Pack_Biochar_Superstructure", "icons")

# source: reuse fig0 module logic by patching slots -> icon images
import importlib.util
spec = importlib.util.spec_from_file_location("fig0mod", "fig0_superstructure.py")
mod = importlib.util.module_from_spec(spec)
sys.argv = ["fig0_superstructure.py"]
spec.loader.exec_module(mod)

# rebuild: import figstyle, re-draw content and inject icons
import figstyle as FS
FS.apply(base_font_size=10.5)
W, H = 13.2, 8.1
fig, ax = plt.subplots(figsize=(W, H))
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
mod.draw_content(ax)
# hide slot boxes (they exist only in template version); draw icons at positions
def place_icon(img_path, x, y, w):
    img = mpimg.imread(img_path)
    im = ax.imshow(img, extent=(x, x + w, y - w * img.shape[0] / img.shape[1] / 1.0, y),
                   zorder=7, aspect="auto", alpha=0.95)

# ICON-1 feedstock area
place_icon(os.path.join(ICONS, "fluff_shredded.png"), 0.30, 6.05, 1.05)
# ICON-2 county/n2  (left of n2, clear of the node label)
place_icon(os.path.join(ICONS, "bin_white.png"), 0.20, 3.15, 0.62)
# ICON-3 biochar transport (above the credit box, between flows)
place_icon(os.path.join(ICONS, "barrel_gray.png"), 6.35, 2.85, 0.62)
# ICON-4 CO2 / credit group (left of the credit box)
place_icon(os.path.join(ICONS, "container_blue_textured.png"), 3.75, 0.80, 0.85)
# ICON-5 market
place_icon(os.path.join(ICONS, "molecule_C3H8.png"), 12.10, 4.40, 0.95)

fig.savefig(os.path.join(outdir, "fig0_deco_prototype.png"))
plt.close(fig)
print("saved fig0_deco_prototype.png ->", outdir)
