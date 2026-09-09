"""
figstyle.py - shared publication style module for ALL biochar paper figures.
Complies with the group's Paper Figure Standards:
  * >=400 DPI output, Calibri font family, sizes consistent with body text
  * consistent colour scheme: deep blue / light blue / gray (+ restrained accents)
  * composite multi-panel figures, shared legends, clean spines
Usage: import figstyle; figstyle.apply()
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ---- group palette (v0.7: restricted to black/white/gray/blue) ----
DEEP   = "#1F4E79"   # primary series / emphasis
MID    = "#5B9BD5"   # secondary series
LIGHT  = "#9DC3E6"   # tertiary series
PALE   = "#DCE9F5"   # light fill
GRAY   = "#7F7F7F"   # neutral / baselines
GRAY_L = "#D9D9D9"   # light gray fills / grids / zero lines
INK    = "#262626"   # text / axes
# legacy aliases kept so older scripts inherit the restricted palette
ACCENT = MID
GREEN  = DEEP

SERIES = [DEEP, MID, LIGHT, GRAY, GRAY_L]
# sequential ramp for heatmaps (pale -> deep blue)
BLUE_RAMP = ["#F2F7FB", "#DCE9F5", "#B7D3E8", "#9DC3E6", "#5B9BD5", "#2F5597", "#1F3864"]

def apply(base_font_size=10.5):
    plt.rcParams.update({
        "font.family": "Calibri",
        "font.size": base_font_size,
        "axes.titlesize": base_font_size + 1.5,
        "axes.labelsize": base_font_size,
        "xtick.labelsize": base_font_size - 1,
        "ytick.labelsize": base_font_size - 1,
        "legend.fontsize": base_font_size - 1.5,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.linewidth": 0.9,
        "axes.edgecolor": INK,
        "text.color": INK,
        "axes.labelcolor": INK,
        "xtick.color": INK,
        "ytick.color": INK,
        "axes.grid": False,
        "figure.dpi": 200,
        "savefig.dpi": 400,          # >=400 DPI per group standard
        "savefig.bbox": "tight",
        "savefig.facecolor": "white",
        "lines.linewidth": 2.0,
        "patch.linewidth": 0.8,
        "legend.frameon": False,
        "font.sans-serif": ["Calibri"],
        "mathtext.default": "regular",
    })

ROMANS = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

def panel_label(ax, idx, x=-0.10, y=1.06, size=None):
    """Panel label as a Roman numeral (group convention: 'Case I/II' -> 'I/II')."""
    ax.text(x, y, ROMANS[idx], transform=ax.transAxes,
            fontsize=(size or plt.rcParams["font.size"]) + 1,
            fontweight="bold", va="bottom", ha="right", color=INK)

def style_axes(ax):
    for s in ["top", "right"]:
        ax.spines[s].set_visible(False)
    return ax

BLUE_RAMP = ["#F2F2F2", "#9DC3E6", "#5B9BD5", "#2F5597", "#1F3864"]  # choropleth: light -> deep blue
GRAY_RAMP = ["#FFFFFF", "#BFBFBF", "#7F7F7F", "#3F3F3F", "#1A1A1A"]  # group-style grayscale maps (dark = high)
DASHES = ["", (6, 2), (2, 2), (1, 1)]  # solid / dashed / dotted series patterns
