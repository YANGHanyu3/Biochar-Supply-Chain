# Biochar Supply Chain — Wisconsin carbon-policy model

Reproducible archive for the manuscript *Designing Carbon Policy for a Biochar
Supply Chain: Market Clearing, Endogenous Carbon Prices, and Technology Choice
in Wisconsin* (target: *Computers & Chemical Engineering*).

Code and data: <https://github.com/YANGHanyu3/Biochar-Supply-Chain>

---

## Categories

| Folder | Contents |
|---|---|
| `Code/` | **The runnable unit.** All model, data-generation and figure scripts (`.jl`, `.py`, `.ps1`), `requirements.txt`, `Project.toml`, `REPRODUCE.md`, the input files the scripts expect next to them (workbook, FIPS lookup, shapefiles), and the generated data matrices and results (`biochar_data_v2*/`, `results_v2*/`). Run everything from this folder. |
| `Data/raw/` | Raw public source data for provenance: BT23 agricultural and forestry county downloads, USDA NASS extracts, GIS shapefiles, the biomass workbook, and the BT23 wastes CSV. |
| `Graph/` | The eleven figures used in the manuscript (400 dpi PNG; `fig0_superstructure` also as PDF and SVG for vector editing) plus the panel components. |
| `Paper/` | The LaTeX manuscript (`paper_draft/`: `main.tex`, section files, `references.bib`/`.bbl`, `figures/`), the single-file `main_standalone.tex`, the compiled PDF, and the Overleaf upload bundles. The current bundle is `Overleaf_Upload_SINGLE_2026-09-09.zip`. |
| `PPT/` | The two 11-slide advisor progress decks (near-term and mature-market). |
| `References/` | The cited literature available locally (R1–R14 set: Sampat 2019, Tominac 2022, Ma 2023, Woolf 2010/2021, Roberts 2010, Cayuela 2014, Shabangu 2014, Searcy 2007, Wernet 2016, Fagernas 2010, Gebreegziabher 2014, the BT23 chapters, 45Q/RGGI/California-Québec policy documents) plus the Verra VM0044 v1.2 methodology. |
| `MANIFEST.csv` | Every archived file with size and SHA-1 prefix, for integrity checks. |

## Quick start

```bash
cd Code
pip install -r requirements.txt
julia --project=. -e 'using Pkg; Pkg.instantiate()'

python generate_data_v2.py            # pooled model, both scenarios
python generate_data_v2b.py           # quality-differentiated model
julia 01_MIP_v2.jl "near-term"        # facility location (15-30 min)
julia 00_run_all_v2.jl "near-term" --skip-mip
python visualize_v2.py "near-term"
```

Full command sequence, the post-processing patch chain (important: three
canonical CSVs are patched in place after the sweeps), and known gaps are
documented in `Code/REPRODUCE.md`.

## Figure ↔ manuscript map

| Manuscript | File |
|---|---|
| Fig. 1 superstructure | `Graph/fig0_superstructure.png` |
| Fig. 2 facility locations | `Graph/fig1_facility_map.png` |
| Fig. 3 economics + market clearing | `Graph/fig2_econmarket.png` |
| Fig. 4 inherent values | `Graph/fig4_iv_maps.png` |
| Fig. 5 paradigm A | `Graph/fig6_policyA.png` |
| Fig. 6 paradigm B (MAC) | `Graph/fig7_policyB_MAC.png` |
| Fig. 7 paradigm C | `Graph/fig8_policyC_tech.png` |
| Fig. 8 policy comparison | `Graph/fig9_policy_compare.png` |
| Fig. 9 quality-differentiated model | `Graph/fig11_v2b_mix.png` |
| Fig. 10 credit basis and crossover | `Graph/fig12_credit_basis.png` |
| S-Figure 1 tornado | `Graph/fig10_tornado.png` |

## Data sources and terms

- BT23 county downloads: DOE 2023 Billion-Ton Report, <https://bioenergykdf.ornl.gov>.
- NASS: USDA 2022 Census of Agriculture.
- Verra VM0044 v1.2: <https://verra.org/methodologies/vm0044-biochar-utilization-in-soil-and-non-soil-applications-v1-2/>.
- Gurobi is commercial software and requires a licence; it is not redistributed here.

## Note on the author block

The manuscript's author block is intentionally commented out in
`Paper/paper_draft/main.tex` (affiliation recorded in the comment) and will be
restored for submission.
