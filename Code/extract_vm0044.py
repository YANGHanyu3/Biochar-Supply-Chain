import sys, re, os

pdf = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "03_Data", "Raw_Downloads", "VM44_v1.2_clean-1.pdf")

text = None
try:
    import pypdf
    r = pypdf.PdfReader(pdf)
    text = "\n".join((p.extract_text() or "") for p in r.pages)
    print("[using pypdf]", len(r.pages), "pages")
except ImportError:
    try:
        import fitz
        d = fitz.open(pdf)
        text = "\n".join(pg.get_text() for pg in d)
        print("[using PyMuPDF]", len(d), "pages")
    except ImportError:
        try:
            import pdfplumber
            with pdfplumber.open(pdf) as pdf_:
                text = "\n".join((pg.extract_text() or "") for pg in pdf_.pages)
            print("[using pdfplumber]")
        except ImportError as e:
            print("NO PDF LIBRARY:", e)
            sys.exit(1)

open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "vm0044_text.txt"), "w", encoding="utf-8").write(text)
print("chars:", len(text))

for kw in ["permanence", "Permanence", "durability", "100-year", "100 year", "0.7", "H/C", "discount", "stability factor"]:
    hits = [m.start() for m in re.finditer(re.escape(kw), text)]
    print(f"{kw}: {len(hits)} hits")
