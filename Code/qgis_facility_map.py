"""
qgis_facility_map.py — fig1: optimal facility locations (QGIS, group standard).
County basemap (light gray fill, white outlines) + facility points
categorized by technology (T1 drying = gray, T2 300C = deep blue,
T2 500C = light blue), sized by scale tier via data-defined size.
Run: E:\QGIS\bin\python-qgis-ltr.bat qgis_facility_map.py [scenario]
"""
import sys, os, csv

from qgis.core import (
    QgsApplication, QgsProject, QgsVectorLayer, QgsPrintLayout, QgsLayoutItemMap,
    QgsLayoutItemLegend, QgsLayoutItemScaleBar, QgsLayoutItemPicture,
    QgsLayoutPoint, QgsLayoutSize, QgsUnitTypes, QgsLayoutExporter,
    QgsLayoutItemLabel, QgsCategorizedSymbolRenderer, QgsRendererCategory,
    QgsSymbol, QgsProperty, QgsWkbTypes,
)
from qgis.PyQt.QtGui import QColor

ROOT = os.path.dirname(os.path.abspath(__file__))
SHP = os.path.join(ROOT, "WI_Counties.shp")

scen = sys.argv[1] if len(sys.argv) > 1 else "near-term"
resdir = os.path.join(ROOT, "results_v2", scen)
outdir = os.path.join(resdir, "figures")
os.makedirs(outdir, exist_ok=True)

app = QgsApplication([], False)
app.initQgis()

# ---- build facility points CSV (lon,lat,techclass,scale,count) ----
import pandas as pd
z = pd.read_csv(os.path.join(resdir, "z_star_MIP_v2.csv"))
nm = pd.read_csv(os.path.join(ROOT, "biochar_data_v2", scen, "node_matrix.csv"))
z = z.merge(nm[["node_id", "lat", "lon"]], left_on="node", right_on="node_id")
z["techclass"] = z.tech.map(lambda t: "T1 drying" if t <= 13 else ("T2 300C" if t <= 26 else "T2 500C"))
pts_csv = os.path.join(outdir, "_facilities.csv")
z[["lon", "lat", "techclass", "scale", "count"]].to_csv(pts_csv, index=False)

# ---- county basemap ----
county = QgsVectorLayer(SHP, "WI counties", "ogr")
sym = QgsSymbol.defaultSymbol(county.geometryType())
sym.setColor(QColor("#EDEDED"))
sym.symbolLayer(0).setStrokeColor(QColor("#FFFFFF"))
sym.symbolLayer(0).setStrokeWidth(0.4)
county.renderer().setSymbol(sym)

# ---- facility points ----
uri = (f"file:///{pts_csv.replace(os.sep, '/')}?type=csv&delimiter=,&xField=lon&yField=lat"
       f"&crs=EPSG:4326&detectTypes=yes&wktField=")
pts = QgsVectorLayer(uri, "facilities", "delimitedtext")

colors = {"T1 drying": "#7F7F7F", "T2 300C": "#1F4E79", "T2 500C": "#9DC3E6"}
cats = []
for cls, hexc in colors.items():
    s = QgsSymbol.defaultSymbol(QgsWkbTypes.PointGeometry)
    s.setColor(QColor(hexc))
    s.symbolLayer(0).setStrokeColor(QColor("#FFFFFF"))
    s.symbolLayer(0).setStrokeWidth(0.5)
    cats.append(QgsRendererCategory(cls, s, cls))
renderer = QgsCategorizedSymbolRenderer("techclass", cats)
pts.setRenderer(renderer)
# data-defined size: scale tier 1/2/3 -> 4/8/13 map units
from qgis.core import QgsSymbolLayer
for cat in cats:
    cat.symbol().symbolLayer(0).setDataDefinedProperty(
        QgsSymbolLayer.PropertySize,
        QgsProperty.fromExpression('CASE WHEN "scale"=1 THEN 4 WHEN "scale"=2 THEN 8 ELSE 13 END'))
pts.triggerRepaint()

# ---- layout ----
prj = QgsProject.instance()
prj.addMapLayer(county)
prj.addMapLayer(pts)

layout = QgsPrintLayout(prj)
layout.initializeDefaults()
page = layout.pageCollection().page(0)
page.setPageSize(QgsLayoutSize(190, 152, QgsUnitTypes.LayoutMillimeters))

m = QgsLayoutItemMap(layout)
m.attemptResize(QgsLayoutSize(190, 152, QgsUnitTypes.LayoutMillimeters))
m.attemptMove(QgsLayoutPoint(0, 0, QgsUnitTypes.LayoutMillimeters))
ext = county.extent()
ext.scale(1.06)
m.zoomToExtent(ext)
layout.addLayoutItem(m)

legend = QgsLayoutItemLegend(layout)
legend.setLinkedMap(m)
legend.setTitle("Technology")
legend.attemptResize(QgsLayoutSize(28, 26, QgsUnitTypes.LayoutMillimeters))
layout.addLayoutItem(legend)
legend.attemptMove(QgsLayoutPoint(4, 118, QgsUnitTypes.LayoutMillimeters))

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

title = QgsLayoutItemLabel(layout)
title.setText(f"Optimal facility locations (S0 baseline, {scen})")
title.attemptResize(QgsLayoutSize(150, 8, QgsUnitTypes.LayoutMillimeters))
layout.addLayoutItem(title)
title.attemptMove(QgsLayoutPoint(4, 4, QgsUnitTypes.LayoutMillimeters))

out = os.path.join(outdir, "fig1_facility_map.png")
settings = QgsLayoutExporter.ImageExportSettings()
settings.dpi = 400
QgsLayoutExporter(layout).exportToImage(out, settings)
print("saved", out, "| facilities:", len(z))
app.exitQgis()
