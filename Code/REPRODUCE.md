# Reproducing the results

Wisconsin biochar supply chain model — pooled-biochar (`v2`) and
quality-differentiated (`v2b`) variants, each under two biomass scenarios
(`near-term`, `mature-market medium`) and three carbon-policy paradigms
(A baseline-and-credit, B cap-and-trade, C tiered tax + VM0044).

Code and data: <https://github.com/YANGHanyu3/Biochar-Supply-Chain>

---

## 1. Environment

| Component | Version used | File |
|---|---|---|
| Python | 3.13 | `requirements.txt` |
| Julia | 1.12.6 | `Project.toml` |
| Gurobi | 13.0.2 (academic licence) | solver |

```bash
pip install -r requirements.txt
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Julia packages pinned in the results: JuMP 1.30.1, Gurobi 1.9.2,
CSV 0.10.16, DataFrames 1.8.2.

## 2. Input data

| Input | Location in the archive | Used by |
|---|---|---|
| Biomass workbook (county totals, NASS validation sheets) | `Code/Wisconsin_Biomass_Data.xlsx` | both generators |
| BT23 agricultural county download | `Data/Raw_Downloads/BT23/agri_*/billionton_23_agri_download20260618-105910.csv` | both |
| BT23 forestry county download | `Data/Raw_Downloads/BT23/forestry_*/billionton_23_forestry_download20260618-105947.csv` | both |
| County FIPS lookup | `Code/node_fips.csv` | figures |
| Wisconsin county / lake / state shapefiles | `Data/GIS_Shapefiles/` | maps |

The generators locate the BT23 CSVs **relative to the project** (no absolute
paths). If your layout differs, point at them explicitly:

```bash
export BIOCHAR_BT23_AG=/path/to/billionton_23_agri_download20260618-105910.csv
export BIOCHAR_BT23_FO=/path/to/billionton_23_forestry_download20260618-105947.csv
```

## 3. Pipeline

Run everything from the folder that holds the scripts (the archive's `Code/`).

```bash
# --- data layer (writes biochar_data_v2/ and biochar_data_v2b/) ---
python generate_data_v2.py          # pooled model, both scenarios
python generate_data_v2b.py         # quality-differentiated model, both scenarios

# --- H/C eligibility stress test (optional; writes biochar_data_v2_hc+0.25/) ---
HC_SHIFT=+0.25 python generate_data_v2.py

# --- models (per scenario) ---
julia 01_MIP_v2.jl "near-term"                 # Step 1 facility location MIP (~15-30 min)
julia 00_run_all_v2.jl "near-term" --skip-mip  # Steps 2-6 reusing z*
julia 01_MIP_v2b.jl "near-term"
julia 04_policy_A_v2b.jl "near-term"
julia 06_policy_C_v2b.jl "near-term"
julia 07_sensitivity_v2.jl "near-term"         # one-at-a-time tornado

# repeat the same block with "mature-market medium"
```

`00_run_all_v2.jl` runs Steps 1-6 in order; each script takes the scenario name
as its first argument and reads/writes
`biochar_data_v2/<scenario>/` and `results_v2/<scenario>/`.

## 4. ⚠ Canonical results are post-patched — read this before comparing

Three canonical CSVs are **overwritten in place** by small Python scripts after
the Julia sweeps, because the sweeps are time-limited and the best incumbent
was found by a separate longer run:

| Canonical file | Patched from | Script |
|---|---|---|
| `results_v2/<scen>/policy_A_bnc_sweep_v2.csv` | `policy_A_extended_v2.csv`, `policy_A_recert_v2.csv` | `patch_policyA_extended.py` |
| `results_v2/<scen>/policy_C2_tax_credit_v2.csv` | `policy_C2_extended_v2.csv` | `patch_policyC_extended.py` |
| `results_v2b/<scen>/policy_A_bnc_sweep_v2b.csv` | `policy_A_hcap*_*.csv` | `patch_v2b_mature.py` |

So a clean rerun of the `.jl` files alone will **not** reproduce the numbers in
the paper. Run the patch scripts afterwards:

```bash
python patch_policyA_extended.py
python patch_policyC_extended.py
python patch_v2b_mature.py
```

(The `policy_A_recert_v2.csv` patch for `p_c = $100`, mature-market, was applied
by hand on 2026-09-09 and is documented in the SI; the file is archived
alongside the canonical CSV.)

## 5. Figures

```bash
python fig0_superstructure.py results_v2/near-term/figures   # also .pdf/.svg
python fig1_facility_map.py "near-term"
python fig45_iv_maps.py "near-term"
python visualize_v2.py "near-term"          # fig2, fig3, fig6, fig7, fig8
python fig9_policy_compare.py "near-term"
python fig10_tornado.py "near-term"
python make_composites.py "near-term"       # fig2_econmarket, fig4_iv_maps
python fig11_v2b_mix.py
python fig12_credit_basis.py
```

`figstyle.py` holds the shared style (Calibri, 400 dpi, group palette).
Note `sync_figures.py` copies **from** the paper folder **to** the results
folders (the opposite of the intuitive direction); run the figure scripts first.

## 6. Paper

`Paper/paper_draft/` — `main.tex` (multi-file) and `main_standalone.tex`
(single-file, all sections + bibliography inlined, used for Overleaf).
`Paper/Overleaf_Upload_SINGLE_*.zip` is the ready-to-compile bundle.
Static checks: `python tex_static_check.py` (labels/refs/bib) and
`python dollar_scan.py` (math-delimiter pairing).

## 7. Known gaps

- Policy sweeps hit the time limit at some points; the reported gaps
  (0.5-4.7%) are documented in SI Table S3, and TIME_LIMIT rows are lower
  bounds. A full-gap certification requires HPC.
- The `near-term` v2b Step-1 MIP terminates at TIME_LIMIT (status only,
  no gap recorded).
- BT23 tonnages are theoretical availability; field collection losses and
  residue retention are not modelled (a -40% sensitivity is reported).
