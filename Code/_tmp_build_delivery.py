"""Build the categorized, reproducible delivery package.

Layout (the user's six categories, under Biochar Supply Chain/):
  Code/       scripts + env files + REPRODUCE.md + inputs needed next to the
              scripts + the generated data and results (the runnable unit)
  Data/raw/   raw public source data (BT23, NASS, GIS, workbook, wastes)
  Graph/      the paper figures (PNG, plus fig0 PDF/SVG)
  Paper/      the LaTeX manuscript (paper_draft/) + Overleaf bundle
  PPT/        the two advisor decks
  References/ the cited literature that is available locally
"""
import os
import shutil
import hashlib
import sys
import csv

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"E:\hhy\Desktop\BIochar Supply Chain"
CODE_SRC = os.path.join(ROOT, "01_Current_Code")
PAPER_SRC = os.path.join(ROOT, "06_Model_LaTeX", "paper_draft")
OUT = os.path.join(ROOT, "Biochar Supply Chain")
MANIFEST = []


def sha1(p):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:16]


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    MANIFEST.append((os.path.relpath(dst, OUT).replace("\\", "/"),
                     os.path.getsize(dst), sha1(dst)))


def copytree(src, dst, ignore=None):
    if not os.path.exists(src):
        print("  skip (missing):", src)
        return
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst, ignore=ignore)
    for dirpath, _, files in os.walk(dst):
        for f in files:
            p = os.path.join(dirpath, f)
            MANIFEST.append((os.path.relpath(p, OUT).replace("\\", "/"),
                             os.path.getsize(p), sha1(p)))


print("== Code/ ==")
for f in sorted(os.listdir(CODE_SRC)):
    p = os.path.join(CODE_SRC, f)
    if os.path.isfile(p) and (
            f.endswith((".py", ".jl", ".ps1", ".toml", ".txt", ".md", ".csv", ".xlsx",
                        ".shp", ".dbf", ".prj", ".shx"))
            or f in ("requirements.txt", "Project.toml", "REPRODUCE.md")):
        copy(p, os.path.join(OUT, "Code", f))
for d in ("biochar_data_v2", "biochar_data_v2b", "biochar_data_v2_hc+0.25",
          "biochar_data_v2b_hc+0.25", "results_v2", "results_v2b"):
    copytree(os.path.join(CODE_SRC, d), os.path.join(OUT, "Code", d),
             ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))

print("== Data/raw/ ==")
raw = os.path.join(OUT, "Data", "raw")
copytree(os.path.join(ROOT, "03_Data", "Raw_Downloads", "BT23"),
         os.path.join(raw, "BT23"))
copytree(os.path.join(ROOT, "03_Data", "NASS_USDA"), os.path.join(raw, "NASS_USDA"),
         ignore=shutil.ignore_patterns("*.xlsx~*"))
copytree(os.path.join(ROOT, "03_Data", "GIS_Shapefiles"),
         os.path.join(raw, "GIS_Shapefiles"))
copy(os.path.join(ROOT, "03_Data", "Raw_Downloads", "VM44_v1.2_clean-1.pdf"),
     os.path.join(OUT, "References", "VM0044_v1.2_methodology.pdf"))
copy(os.path.join(CODE_SRC, "Wisconsin_Biomass_Data.xlsx"),
     os.path.join(raw, "Wisconsin_Biomass_Data.xlsx"))
wastes = os.path.join(ROOT, "supplementary data",
                      "billionton_23_wastes_download20260902.csv")
if os.path.exists(wastes):
    copy(wastes, os.path.join(raw, "supplementary",
                              "billionton_23_wastes_download20260902.csv"))

print("== Graph/ ==")
PAPER_FIGS = ["fig0_superstructure.png", "fig0_superstructure.pdf",
              "fig0_superstructure.svg", "fig1_facility_map.png",
              "fig2_econmarket.png", "fig4_iv_maps.png", "fig6_policyA.png",
              "fig7_policyB_MAC.png", "fig8_policyC_tech.png",
              "fig9_policy_compare.png", "fig10_tornado.png",
              "fig11_v2b_mix.png", "fig12_credit_basis.png",
              "fig2_economics.png", "fig3_demand_curve.png",
              "fig4_iv_biochar.png", "fig5_iv_biomass.png",
              "fig0_layout_template.png"]
for f in PAPER_FIGS:
    src = os.path.join(PAPER_SRC, "figures", f)
    if os.path.exists(src):
        copy(src, os.path.join(OUT, "Graph", f))
    else:
        print("  missing figure:", f)

print("== Paper/ ==")
copytree(PAPER_SRC, os.path.join(OUT, "Paper", "paper_draft"),
         ignore=shutil.ignore_patterns("__pycache__", "*.aux", "*.log", "*.out"))
for f in os.listdir(os.path.join(ROOT, "07_Plans_Notes")):
    if f.startswith("Overleaf_Upload_") and f.endswith(".zip"):
        copy(os.path.join(ROOT, "07_Plans_Notes", f),
             os.path.join(OUT, "Paper", f))

print("== PPT/ ==")
for f in ("Biochar_Progress_near-term_v03.pptx",
          "Biochar_Progress_mature-market_v03.pptx"):
    src = os.path.join(ROOT, "05_PPT", f)
    if os.path.exists(src):
        copy(src, os.path.join(OUT, "PPT", f))
    else:
        print("  missing ppt:", f)

print("== References/ ==")
refsrc = os.path.join(ROOT, "99_Raw_Archive", "NewData_Reference_Complete")
if os.path.isdir(refsrc):
    for f in sorted(os.listdir(refsrc)):
        if f.lower().endswith(".pdf"):
            copy(os.path.join(refsrc, f), os.path.join(OUT, "References", f))
for f in ("Apoorva M. Sampat-2019-Coordination framework.pdf",
          "Spatio-temporal economic properties of multi-product supply chains.pdf",
          "Jiaze Ma-2023-thermochemical upcycling of post-consumer.pdf"):
    src = os.path.join(ROOT, "02_Papers", "Supply_Chain_Modeling", f)
    if os.path.exists(src):
        copy(src, os.path.join(OUT, "References", f))
for f in ("Life Cycle Assessment of Biochar Systems_ Estimating the Energetic, "
          "Economic, and Climate Change Potential.pdf",):
    src = os.path.join(ROOT, "02_Papers", "Biochar_TEA_LCA", f)
    if os.path.exists(src):
        copy(src, os.path.join(OUT, "References", f))

# ---- manifest ----
mp = os.path.join(OUT, "MANIFEST.csv")
with open(mp, "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["path", "bytes", "sha1_16"])
    w.writerows(sorted(MANIFEST))

total = sum(m[1] for m in MANIFEST)
print(f"\nfiles: {len(MANIFEST)}  total: {total/1e6:.1f} MB")
print("manifest:", mp)
