"""Re-sync the delivery archive after the v0.6 edits."""
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


def sha1(p):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()[:16]


def copytree(src, dst, ignore=None):
    if not os.path.exists(src):
        print("  skip (missing):", src)
        return
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst, ignore=ignore)


print("== Code/ ==")
for f in sorted(os.listdir(CODE_SRC)):
    p = os.path.join(CODE_SRC, f)
    if os.path.isfile(p) and f.endswith((".py", ".jl", ".ps1", ".toml", ".txt", ".md",
                                         ".csv", ".xlsx", ".shp", ".dbf", ".prj", ".shx")):
        shutil.copy2(p, os.path.join(OUT, "Code", f))
for d in ("biochar_data_v2", "biochar_data_v2b", "biochar_data_v2_hc+0.25",
          "biochar_data_v2b_hc+0.25", "biochar_data_v2_dc3", "biochar_data_v2_dc10",
          "results_v2", "results_v2b", "results_v2_dc3", "results_v2_dc10"):
    copytree(os.path.join(CODE_SRC, d), os.path.join(OUT, "Code", d),
             ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    print("   synced", d)

print("== Graph/ ==")
for f in ("fig0_superstructure.png", "fig0_superstructure.pdf", "fig0_superstructure.svg"):
    shutil.copy2(os.path.join(PAPER_SRC, "figures", f), os.path.join(OUT, "Graph", f))

print("== Paper/ ==")
copytree(PAPER_SRC, os.path.join(OUT, "Paper", "paper_draft"),
         ignore=shutil.ignore_patterns("__pycache__", "*.aux", "*.log", "*.out"))
for f in os.listdir(os.path.join(ROOT, "07_Plans_Notes")):
    if f.startswith("Overleaf_Upload_") and f.endswith(".zip"):
        shutil.copy2(os.path.join(ROOT, "07_Plans_Notes", f), os.path.join(OUT, "Paper", f))

# rebuild manifest
rows = []
for dp, dns, fs in os.walk(OUT):
    dns[:] = [d for d in dns if d != ".git"]
    for f in fs:
        if f == "MANIFEST.csv":
            continue
        p = os.path.join(dp, f)
        rows.append([os.path.relpath(p, OUT).replace("\\", "/"),
                     str(os.path.getsize(p)), sha1(p)])
with open(os.path.join(OUT, "MANIFEST.csv"), "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["path", "bytes", "sha1_16"])
    w.writerows(sorted(rows))
print(f"\nmanifest rows: {len(rows)}  total: {sum(int(r[1]) for r in rows)/1e6:.1f} MB")
