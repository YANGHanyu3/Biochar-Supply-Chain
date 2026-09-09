"""
qgis_iv_maps.py — Inherent-value county choropleths (fig4/fig5) rendered in QGIS
per the group figure standard (QGIS maps, >=400 DPI, deep-blue ramp, legend +
scale bar + north arrow).
Run: E:\QGIS\bin\python-qgis-ltr.bat qgis_iv_maps.py [scenario]
"""
import sys, os, csv

from qgis.core import (
    QgsApplication, QgsProject, QgsVectorLayer, QgsField, QgsFeature,
    QgsGraduatedSymbolRenderer, QgsRendererRange, QgsSymbol,
    QgsGradientColorRamp, QgsGradientStop, QgsPrintLayout, QgsLayoutItemMap,
    QgsLayoutItemLegend, QgsLayoutItemScaleBar, QgsLayoutItemPicture,
    QgsLayoutPoint, QgsLayoutSize, QgsUnitTypes, QgsLayoutExporter,
    QgsLayoutItemLabel, QgsSimpleFillSymbolLayer, QgsRectangle, QgsReadWriteContext,
)
from qgis.PyQt.QtCore import QVariant, QSizeF
from qgis.PyQt.QtGui import QColor
from qgis.PyQt.QtXml import QDomDocument

ROOT = os.path.dirname(os.path.abspath(__file__))
SHP = os.path.join(ROOT, "WI_Counties.shp")
FIPS_CSV = os.path.join(ROOT, "node_fips.csv")

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
resdir = os.path.join(ROOT, "results_v2", scen)
iv_csv = os.path.join(resdir, "LP_duals_inherent_value_v2.csv")
outdir = os.path.join(resdir, "figures")
os.makedirs(outdir, exist_ok=True)

app = QgsApplication([], False)
app.initQgis()

# ---------- data ----------
fips_by_node = {}
with open(FIPS_CSV, encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        fips_by_node[int(row["n_id"])] = row["FIPS5"]

def iv_map(product):
    m = {}
    with open(iv_csv, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            if int(row["product"]) == product:
                fips = fips_by_node.get(int(row["node"]))
                if fips:
                    m[fips] = float(row["inherent_value"])
    return m

# ---------- layer + join ----------
layer = QgsVectorLayer(SHP, "WI counties", "ogr")
dp = layer.dataProvider()
if layer.fields().indexFromName("iv") < 0:
    dp.addAttributes([QgsField("iv", QVariant.Double)])
    layer.updateFields()
idx = layer.fields().indexFromName("iv")

def render_map(product, title, unit, outfile, ramp_colors):
    vals = iv_map(product)
    layer.startEditing()
    for f in layer.getFeatures():
        v = vals.get(f["GEOID"])
        f["iv"] = v if v is not None else -9999.0
        layer.updateFeature(f)
    layer.commitChanges()

    lo, hi = min(vals.values()), max(vals.values())
    n = 5
    step = (hi - lo) / n
    ramp = QgsGradientColorRamp(QColor(ramp_colors[0]), QColor(ramp_colors[-1]))
    ramp.setStops([QgsGradientStop(i / (len(ramp_colors) - 1), QColor(c))
                   for i, c in enumerate(ramp_colors)])
    ranges = []
    for i in range(n):
        a = lo + i * step
        b = lo + (i + 1) * step
        color = ramp.color((i + 0.5) / n)
        sym = QgsSymbol.defaultSymbol(layer.geometryType())
        sym.setColor(color)
        sym.symbolLayer(0).setStrokeColor(QColor("#FFFFFF"))
        sym.symbolLayer(0).setStrokeWidth(0.4)
        lab = f"{a:.0f}–{b:.0f}" if i < n - 1 else f"{a:.0f}–{b:.0f}"
        ranges.append(QgsRendererRange(a, b if i < n - 1 else hi + 1e-6, sym, lab))
    # counties without data: light gray
    nodata_sym = QgsSymbol.defaultSymbol(layer.geometryType())
    nodata_sym.setColor(QColor("#E7E6E6"))
    nodata_sym.symbolLayer(0).setStrokeColor(QColor("#FFFFFF"))
    nodata_sym.symbolLayer(0).setStrokeWidth(0.4)
    renderer = QgsGraduatedSymbolRenderer("iv", ranges)
    renderer.setSourceSymbol(nodata_sym)
    layer.setRenderer(renderer)
    layer.triggerRepaint()

    # ---------- layout ----------
    prj = QgsProject.instance()
    prj.addMapLayer(layer)
    layout = QgsPrintLayout(prj)
    layout.initializeDefaults()
    pc = layout.pageCollection()
    page = pc.page(0)
    page.setPageSize(QgsLayoutSize(190, 152, QgsUnitTypes.LayoutMillimeters))

    m = QgsLayoutItemMap(layout)
    ms = QgsLayoutSize(190, 152, QgsUnitTypes.LayoutMillimeters)
    m.attemptResize(ms)
    m.attemptMove(QgsLayoutPoint(0, 0, QgsUnitTypes.LayoutMillimeters))
    m.zoomToExtent(layer.extent())
    ext = layer.extent()
    ext.scale(1.06)
    m.zoomToExtent(ext)
    layout.addLayoutItem(m)

    legend = QgsLayoutItemLegend(layout)
    legend.setLinkedMap(m)
    legend.setTitle(unit)
    ls = QgsLayoutSize(30, 40, QgsUnitTypes.LayoutMillimeters)
    legend.attemptResize(ls)
    layout.addLayoutItem(legend)
    legend.attemptMove(QgsLayoutPoint(4, 100, QgsUnitTypes.LayoutMillimeters))

    bar = QgsLayoutItemScaleBar(layout)
    bar.setLinkedMap(m)
    bar.setStyle("Line Ticks Up")
    bar.setUnits(QgsUnitTypes.DistanceKilometers)
    bar.setNumberOfSegments(2)
    bar.setNumberOfSegmentsLeft(0)
    bar.attemptResize(QgsLayoutSize(55, 8, QgsUnitTypes.LayoutMillimeters))
    layout.addLayoutItem(bar)
    bar.attemptMove(QgsLayoutPoint(4, 138, QgsUnitTypes.LayoutMillimeters))

    arrow = QgsLayoutItemPicture(layout)
    arrow.setPicturePath(r"E:\QGIS\apps\qgis\svg\arrows\NorthArrow_02.svg")
    arrow.attemptResize(QgsLayoutSize(10, 10, QgsUnitTypes.LayoutMillimeters))
    layout.addLayoutItem(arrow)
    arrow.attemptMove(QgsLayoutPoint(174, 4, QgsUnitTypes.LayoutMillimeters))

    title_item = QgsLayoutItemLabel(layout)
    title_item.setText(title)
    title_item.attemptResize(QgsLayoutSize(150, 8, QgsUnitTypes.LayoutMillimeters))
    layout.addLayoutItem(title_item)
    title_item.attemptMove(QgsLayoutPoint(4, 4, QgsUnitTypes.LayoutMillimeters))

    exporter = QgsLayoutExporter(layout)
    settings = QgsLayoutExporter.ImageExportSettings()
    settings.dpi = 400          # group standard: >=400 DPI
    out = os.path.join(outdir, outfile)
    exporter.exportToImage(out, settings)
    print(f"saved {out}  (range {lo:.1f}..{hi:.1f})")

# group-style GRAYSCALE choropleth (dark = high), per reference figure analysis
render_map(27, f"Inherent value of biochar (USD/t) — {scen}", "USD/t biochar",
           "fig4_iv_biochar.png", ["#FFFFFF", "#BFBFBF", "#7F7F7F", "#3F3F3F", "#1A1A1A"])
render_map(1, f"Inherent value of wet corn stover (USD/t) — {scen}", "USD/t wet biomass",
           "fig5_iv_biomass.png", ["#FFFFFF", "#BFBFBF", "#7F7F7F", "#3F3F3F", "#1A1A1A"])

app.exitQgis()
