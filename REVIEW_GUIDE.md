# Review Guide — Wisconsin Biochar Supply Chain (v0.7, 2026-09-09)

Thanks for reviewing. This page tells you what is where, what to ignore, and
what we most want checked. Everything here is reproducible from the files in
this folder.

## 1. Please note first (not a bug)

- **The author block is intentionally commented out** in `Paper/paper_draft/main.tex`
  (search for `Author block commented out`). The correct affiliation is kept in
  the comment and will be restored before submission. Overleaf will therefore
  show a harmless `No \author given` warning — ignore it.
- The manuscript is **shared in three equivalent forms**; they contain the same
  text and figures, just packaged differently:
  | Form | Where | Use |
  |---|---|---|
  | Multi-file source | `Paper/paper_draft/` (`main.tex` + 8 chapter files + `references.bib/.bbl` + `figures/`) | editing |
  | Single-file Overleaf bundle | `Paper/Overleaf_Upload_SINGLE_2026-09-09.zip` (one `main.tex` with everything inlined + 8 figures) | uploading to Overleaf |
  | Code + data repository | this folder / GitHub `YANGHanyu3/Biochar-Supply-Chain` | running the model |

## 2. What is in each folder

| Folder | Contents |
|---|---|
| `Code/` | Python data generation + figure scripts, Julia optimization models (v2 pooled and v2b quality-differentiated), PowerShell drivers, `requirements.txt`, `Project.toml`, `REPRODUCE.md`, generated data matrices and result CSVs |
| `Data/` | raw inputs (Wisconsin biomass workbook, BT23 agricultural/forestry downloads, NASS, GIS shapefiles) |
| `Graph/` | the 6 main figures (PNG 400 DPI) plus fig0 in PDF/SVG vector form |
| `Paper/` | the manuscript source, bibliography, figures, and the Overleaf zip |
| `PPT/` | two 11-slide advisor progress decks |
| `References/` | the cited PDFs we hold locally (VM0044, Rafiq 2016, Ippolito 2020, Sampat 2019, Tominac 2022, BT23, ...) |

## 3. How to reproduce

See `Code/REPRODUCE.md` for the full command sequence. Short version:

```bash
cd Code
python generate_data_v2.py            # writes biochar_data_v2/{near-term,mature-market medium}
python generate_data_v2b.py           # quality-differentiated variant
julia 00_run_all_v2.jl near-term      # Steps 1-6 (MIP, LP duals, GHG LP, policies A/B/C)
julia 07_sensitivity_v2.jl near-term  # one-at-a-time sensitivity
julia 07b_demand_grid.jl near-term    # demand price x capacity grid (Fig. 6 II)
python make_main_figures.py near-term # the 6 main figures
```

**Known caveat:** the shipped canonical result CSVs
(`policy_A_bnc_sweep_v2.csv`, `policy_C2_tax_credit_v2.csv`,
`policy_A_bnc_sweep_v2b.csv`) were post-processed in place from the
`*_extended*`, `*_recert*`, and `*_hcap*` runs — `REPRODUCE.md` documents this
patch chain, so a bare rerun of the `.jl` files will not reproduce those exact
numbers without applying the patches.

## 4. What we would most like checked

**Model / theory**
1. The three propositions in Section 2 and their SI proofs — especially the
   reduced-cost argument of Proposition 3 (tax invariance) and the sign
   convention of the cap dual in Proposition 1.
2. The carbon-credit coefficient `C x permanence x (44/12) x biochar yield`
   (per tonne dry) and the VM0044 H/C <= 0.7 gate (all 300 C chars
   ineligible, all 500 C chars eligible).
3. The market-clearing interpretation of the mass-balance duals (inherent
   values) and the two-regime crossover prices ($61/t demand-bound,
   $239/t supply-bound).

**Numbers (spot checks)**
4. Table 1 (baseline), Table 2 (C1-free), Table 3 (v2b) against
   `Code/results_v2*/**.csv`.
5. Section 3.4's mature-market $p_c = $100 point against
   `results_v2/mature-market medium/policy_A_recert_v2.csv`.
6. The demand-geography sensitivity in SI (alpha = 1/3/10) against
   `results_v2_dc3/`, `results_v2_dc10/`.

**Presentation**
7. Whether the 6 consolidated main figures read clearly and whether any panel
   is redundant.
8. Figure captions versus figure content (terminology, units, segment names).

## 5. Open items we already know about

- Author block commented out (deliberate, see section 1).
- Policy sweeps are reported at 0.5-4.7% MIP optimality gaps; TIME_LIMIT points
  are feasible incumbents and are labelled as lower bounds throughout.
- One citation (`senadheera2025`, Renewable and Sustainable Energy Reviews) has
  its full author list and DOI flagged for verification before submission.
- N2O suppression, the decomposition fraction, and BT23 collectability are
  literature defaults, not locally calibrated (documented in Limitations).
