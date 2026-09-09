"""v0.3 workbook citation/HC-value fixes (2026-09-03).
- 04_Moisture_GHG_Factors: replace unsourced 300C H/C values with literature
  values (Rafiq 2016 / Ippolito 2020 band); fix Primary Source strings.
- 03_Technology_TEA: fix 300C-row sources, H/C value, permanence 0.69->0.65,
  and the derived seq/credit arithmetic.
"""
import openpyxl

import os
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Wisconsin_Biomass_Data.xlsx")
wb = openpyxl.load_workbook(path)

# ---- 04_Moisture_GHG_Factors ----
# Excel rows: 4=header, 5..17 = the 13 feedstocks. Cols: J(10)=H/C, K(11)=source.
ws4 = wb["04_Moisture_GHG_Factors"]
assert ws4.cell(row=4, column=10).value == "H/C", ws4.cell(row=4, column=10).value
assert ws4.cell(row=5, column=2).value == "Corn Stover", ws4.cell(row=5, column=2).value
updates = {
    5:  (1.40, "Rafiq et al. 2016, PLOS ONE 11:e0156894 (300C H/C=1.41); V9 tech table (yield)"),
    6:  (1.30, "Ippolito et al. 2020, Biochar 2:421-438, doi:10.1007/s42773-020-00067-x (300C band)"),
    7:  (1.25, "Ippolito et al. 2020, Biochar 2:421-438 (300C band)"),
    8:  (1.25, "Ippolito et al. 2020, Biochar 2:421-438 (300C band)"),
    9:  (1.25, "Ippolito et al. 2020, Biochar 2:421-438 (300C band)"),
    10: (1.30, "Ippolito et al. 2020, Biochar 2:421-438 (300C band)"),
    11: (1.30, "Ippolito et al. 2020, Biochar 2:421-438 (300C band)"),
    12: (1.10, "Brammer & Bridgwater 1999 RSER (MC); Ippolito 2020 (300C H/C band). [Deng 2024 removed: unverifiable]"),
    13: (1.10, "Brammer & Bridgwater 1999 RSER (MC); Ippolito 2020 (300C H/C band). [Deng 2024 removed: unverifiable]"),
    14: (1.05, "Fagernas et al. 2010, Biomass Bioenergy 34(9):1267 (MC); Ippolito 2020 (H/C band)"),
    15: (1.05, "Roberts 2010 EST 44(2):827 (MC); Ippolito 2020 (H/C band). [Deng 2024 removed: unverifiable]"),
    16: (1.00, "Ippolito et al. 2020, Biochar 2:421-438 (300C band)"),
    17: (1.15, "Ippolito et al. 2020, Biochar 2:421-438 (300C band)"),
}
for row, (hc, src) in updates.items():
    ws4.cell(row=row, column=10, value=hc)
    ws4.cell(row=row, column=11, value=src)
# row 25 (pandas 24): slow pyrolysis 300C process-GHG source string (col 8 = source)
ws4.cell(row=25, column=8,
         value="Project TEA assumption (net of 50-65 kWh/t syngas electricity credit); "
               "Roberts 2010 is a 450C LCA - no 300C case exists (audit 2026-09-03)")
# audit note in the previously-empty row 3
ws4.cell(row=3, column=2,
         value="v0.3 audit 2026-09-03: 300C H/C corrected to literature band 1.00-1.40 "
               "(torrefaction-like -> ALL 300C chars fail the VM0044 H:Corg<=0.7 gate). "
               "Removed unverifiable 'Deng 2024 Nat Commun 15:1085' and 'Roberts 300C case' citations. "
               "See 03_Data/WI_Working_Files/hc_literature_report.md")

# ---- 03_Technology_TEA ----
# rows: 16=header, 17..26 = parameters. Cols: B(2)=value, E(5)=source.
ws3 = wb["03_Technology_TEA"]
assert ws3.cell(row=17, column=1).value == "Temperature", ws3.cell(row=17, column=1).value
ws3.cell(row=17, column=4, value="Advisor-confirmed project baseline (2026-06-20). "
        "NOTE 2026-09-03: Roberts 2010 is a 450 C slow-pyrolysis LCA and contains no 300 C case.")
ws3.cell(row=18, column=4, value="V9 technology table (Biochar_Supply_Chain_Data_V9.xlsx sheet 02); "
        "advisor-confirmed baseline. Roberts 2010/Woolf 2010 contain no such table (audit 2026-09-03).")
ws3.cell(row=19, column=4, value="Rafiq et al. 2016, PLOS ONE 11:e0156894 (300 C char C = 45.5%). "
        "[replaced 'Roberts 2010 Fig.2' citation]")
ws3.cell(row=20, column=2, value=1.40)
ws3.cell(row=20, column=4, value="Rafiq et al. 2016 (300 C H/C = 1.41); Ippolito et al. 2020, "
        "Biochar 2:421-438, doi:10.1007/s42773-020-00067-x. "
        "[replaced 'Woolf 2010 Table S2' citation; corrected from 0.65]")
ws3.cell(row=21, column=2, value=0.65)
ws3.cell(row=21, column=4, value="VM0044 v1.2 Table 3 (IPCC 2019 Table 4AP.2): 0.65 for 350-450 C band. "
        "[corrected from 0.69 placeholder 2026-09-02]")
ws3.cell(row=25, column=2, value="-1,072.6")
ws3.cell(row=25, column=4, value="0.45 x 0.65 x 3.667 x 1000 [FORMULA VERIFIED, permanence 0.65]")
ws3.cell(row=26, column=2, value="-1,124.6")
ws3.cell(row=26, column=4, value="Seq(-1,072.6) + N2O(-52.0) = -1,124.6 [VERIFIED]")

wb.save(path)
print("workbook updated:", path)
