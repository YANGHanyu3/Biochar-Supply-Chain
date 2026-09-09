"""
fig0_superstructure.py - supply chain superstructure (v1.0, group line-art style)
=============================================================================
Follows the group's Paper Figure Standards for schematics:
  * black-and-white line art, white fills, black strokes, swallowtail arrowheads
  * consistent stroke weight (1.2) and font size (9 pt; box titles 10 pt)
  * boxes sized to their text (no label overflow), arrows land on their targets
  * composite layout with the carbon-accounting layer (our model's addition)
Outputs (per scenario):
  fig0_superstructure.png  400 dpi raster for LaTeX
  fig0_superstructure.pdf  vector (TrueType text) for Illustrator
  fig0_superstructure.svg  vector (text kept as text) for Illustrator
Usage: python fig0_superstructure.py [outdir]
"""
import sys, os, math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Ellipse, FancyBboxPatch, Polygon, Circle

outdir = sys.argv[1] if len(sys.argv) > 1 else "results_v2/near-term/figures"
os.makedirs(outdir, exist_ok=True)

import figstyle as FS
FS.apply(base_font_size=9)

# editable text in vector exports (Illustrator)
plt.rcParams["svg.fonttype"] = "none"
plt.rcParams["pdf.fonttype"] = 42

INK = "#000000"

W, H = 13.2, 7.6
FIGW = 6.7
FIGH = FIGW * H / W          # keep the data aspect ratio at the typeset width
DU_PER_PT = (W / FIGW) / 72.0   # data units per point (for text sizing)

# ---------------- helpers ----------------
def text_w(s, fs):
    """Rough width of a string in data units (Calibri, ~0.5 em average)."""
    return len(s) * 0.5 * fs * DU_PER_PT

def swallow(ax, x1, y1, x2, y2, lw=1.2, ls="-", head=0.30, z=5):
    """Straight line with an open swallowtail arrowhead at (x2, y2)."""
    dx, dy = x2 - x1, y2 - y1
    L = math.hypot(dx, dy)
    if L < 1e-9:
        return
    ux, uy = dx / L, dy / L
    px, py = -uy, ux
    hl = min(head, 0.55 * L)
    hw = hl * 0.60
    bx, by = x2 - hl * ux, y2 - hl * uy          # head base centre
    notch = (bx + 0.42 * hl * ux, by + 0.42 * hl * uy)
    ax.add_patch(Polygon([(x2, y2),
                          (bx + hw * px, by + hw * py),
                          notch,
                          (bx - hw * px, by - hw * py)],
                         closed=True, fc="white", ec=INK, lw=lw, zorder=z))
    ax.plot([x1, notch[0]], [y1, notch[1]], color=INK, lw=lw, ls=ls,
            zorder=z, solid_capstyle="butt")

def box(ax, x0, y0, x1, y1, lw=1.2, ls="-", r=0.12, z=3):
    ax.add_patch(FancyBboxPatch((x0, y0), x1 - x0, y1 - y0,
                 boxstyle=f"round,pad=0,rounding_size={r}",
                 fc="white", ec=INK, lw=lw, ls=ls, zorder=z))

def techbox(ax, cx, cy, label, fs=9, pad=0.20, h=0.56):
    """Technology box whose width fits its label."""
    w = text_w(label, fs) + 2 * pad
    box(ax, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, lw=1.2, r=0.10, z=4)
    ax.text(cx, cy, label, fontsize=fs, ha="center", va="center", zorder=6)
    return w

ROWS = [
    ("H: premium (CDR)",         "800 USD/t   0.80 Mt", 6.70),
    ("M: quality ag/industrial", "500 USD/t   1.50 Mt", 5.70),
    ("L: bulk agricultural",     "250 USD/t   2.50 Mt", 4.70),
    ("sink (non-soil)",          "30 USD/t",            3.70),
]

def draw_content(ax):
    # ---------------- policy modules (top-left) ----------------
    box(ax, 0.30, 6.05, 3.60, 7.35)
    ax.text(1.95, 7.15, "Policy modules", fontsize=10, fontweight="bold",
            ha="center", va="center", zorder=6)
    for i, line in enumerate(["A baseline-and-credit", "B cap-and-trade",
                              "C tiered tax + VM0044"]):
        ax.text(1.95, 6.82 - i * 0.28, line, fontsize=8.5,
                ha="center", va="center", zorder=6)

    # ---------------- feedstock supply (left) ----------------
    box(ax, 0.30, 4.05, 3.25, 5.65)
    ax.text(1.775, 5.45, "RE (dashed)", fontsize=10, fontweight="bold",
            ha="center", va="center", zorder=6)
    for i, line in enumerate(["13 feedstocks", "(7 ag + 6 forestry)",
                              "farmgate 40–60 USD/t", "wet biomass"]):
        ax.text(1.775, 5.13 - i * 0.28, line, fontsize=8.5,
                ha="center", va="center", zorder=6)
    swallow(ax, 3.27, 4.85, 4.85, 5.75, ls=(0, (4, 3)))
    ax.text(3.95, 5.62, "wet", fontsize=8.5, ha="center", va="center", zorder=6)

    # ---------------- node n1 (representative county) ----------------
    ax.add_patch(Ellipse((6.00, 4.90), 5.40, 4.80, fc="white", ec=INK,
                         lw=1.4, zorder=2))
    ax.text(4.95, 6.60, r"$n_1$", fontsize=14, ha="center", va="center",
            zorder=6, fontstyle="italic")

    techbox(ax, 5.95, 6.15, "T1 dehydration")
    techbox(ax, 7.20, 4.25, "T2-300 °C")
    techbox(ax, 4.70, 4.25, "T2-500 °C")

    # dry-biomass flows into the two pyrolysis routes
    swallow(ax, 6.30, 5.85, 7.00, 4.55)
    swallow(ax, 5.60, 5.85, 4.90, 4.55)
    ax.text(5.95, 5.05, "dry", fontsize=8.5, ha="center", va="center", zorder=6)

    # ---------------- node n2 (replication) ----------------
    ax.add_patch(Circle((1.55, 1.55), 1.00, fc="white", ec=INK, lw=1.4, zorder=2))
    ax.text(1.20, 2.05, r"$n_2$", fontsize=11, ha="center", va="center",
            zorder=6, fontstyle="italic")
    box(ax, 0.90, 1.37, 1.35, 1.73, lw=1.1, r=0.06, z=4)
    box(ax, 1.75, 1.37, 2.20, 1.73, lw=1.1, r=0.06, z=4)
    ax.text(1.125, 1.55, "T1", fontsize=8.5, ha="center", va="center", zorder=6)
    ax.text(1.975, 1.55, "T2", fontsize=8.5, ha="center", va="center", zorder=6)
    swallow(ax, 1.37, 1.55, 1.73, 1.55, head=0.16)
    ax.text(1.55, 0.28, r"$\times$ 72 county nodes", fontsize=8.5,
            ha="center", va="center", zorder=6, fontstyle="italic")

    # ---------------- product flows to the bracket ----------------
    # arrows leave the node ellipse boundary; labels sit on the arrow with a
    # white background so the shaft does not run through the glyphs
    wb = dict(fc="white", ec="none", pad=0.8)
    swallow(ax, 7.60, 5.85, 9.05, 6.70)
    swallow(ax, 7.85, 5.30, 9.05, 5.70)
    swallow(ax, 8.05, 4.85, 9.05, 4.70)
    swallow(ax, 7.30, 3.80, 9.05, 3.70)
    ax.text(7.85, 6.35, r"$f^H$", fontsize=10, ha="center", va="center",
            zorder=7, fontstyle="italic", bbox=wb)
    ax.text(8.05, 5.62, r"$f^M$", fontsize=10, ha="center", va="center",
            zorder=7, fontstyle="italic", bbox=wb)
    ax.text(8.20, 5.00, r"$f^L$", fontsize=10, ha="center", va="center",
            zorder=7, fontstyle="italic", bbox=wb)
    ax.text(7.70, 3.58, r"$q^{sink}$", fontsize=9.5, ha="center", va="center",
            zorder=7, fontstyle="italic", bbox=wb)
    ax.text(9.45, 7.30, r"biochar $f$  ($d \leq 400$ km)", fontsize=8.5,
            ha="left", va="center", zorder=6)

    # ---------------- product bracket + rows ----------------
    ax.plot([9.10, 9.32], [6.95, 6.95], color=INK, lw=1.4, zorder=2)
    ax.plot([9.32, 9.32], [6.95, 3.40], color=INK, lw=1.4, zorder=2)
    ax.plot([9.10, 9.32], [3.40, 3.40], color=INK, lw=1.4, zorder=2)
    for name, val, y in ROWS:
        ax.text(9.45, y, name, fontsize=9, ha="left", va="center", zorder=6)
        ax.text(9.45, y - 0.26, val, fontsize=8.2, ha="left", va="center",
                color="#404040", zorder=6)

    # ---------------- carbon-credit layer (bottom band) ----------------
    swallow(ax, 4.70, 3.95, 4.70, 2.24, ls=(0, (4, 3)))
    ax.text(4.92, 3.10, "credits", fontsize=8.2, ha="left", va="center", zorder=6)

    box(ax, 3.40, 0.50, 7.40, 2.20)
    ax.text(5.40, 1.98, "Carbon credits (VM0044)", fontsize=9.5,
            fontweight="bold", ha="center", va="center", zorder=6)
    ax.text(5.40, 1.60, r"CC $= C\cdot perm\cdot(44/12)\cdot yield$",
            fontsize=8.2, ha="center", va="center", zorder=6)
    ax.text(5.40, 1.25, "only 500 °C chars eligible", fontsize=8.2,
            ha="center", va="center", zorder=6)
    ax.text(5.40, 0.90, r"credit price $p^{CC}$", fontsize=8.2,
            ha="center", va="center", zorder=6)

    box(ax, 7.80, 0.50, 11.00, 2.20)
    ax.text(9.40, 1.90, "Carbon market", fontsize=9.5, fontweight="bold",
            ha="center", va="center", zorder=6)
    ax.text(9.40, 1.50, r"credit price $p^{CC}$", fontsize=8.5,
            ha="center", va="center", zorder=6)
    ax.text(9.40, 1.15, "Paradigms A | B | C", fontsize=8.2,
            ha="center", va="center", zorder=6)
    swallow(ax, 7.46, 1.35, 7.74, 1.35)

# ---------------- render + export ----------------
fig, ax = plt.subplots(figsize=(FIGW, FIGH))
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
draw_content(ax)
for ext in ("png", "pdf", "svg"):
    fig.savefig(os.path.join(outdir, f"fig0_superstructure.{ext}"), dpi=400)
plt.close(fig)
print("saved fig0_superstructure.{png,pdf,svg} ->", outdir)
