# Review Guide — Wisconsin Biochar Supply Chain (v0.9, 2026-09-15)

Thanks for reviewing. This page tells you what is where, what to ignore, and
what we most want checked. Everything here is reproducible from the files in
this folder. **This revision responds to a full external review
(2026-09-13) whose verified findings are itemized in
`Paper/审稿回应书_v09.md`** (in Chinese); the key scientific changes are
summarized in Section 5 below.

## 1. Please note first (not a bug)

- **The author block is intentionally commented out** in `Paper/paper_draft/main.tex`
  (search for `Author block commented out`). The correct affiliation is kept in
  the comment and will be restored before submission. Overleaf will therefore
  show a harmless `No \author given` warning — ignore it.
- The manuscript is **shared in three equivalent forms**:
  | Form | Where | Use |
  |---|---|---|
  | Multi-file source | `Paper/paper_draft/` (main.tex + chapter files + references.bib/.bbl + figures/) | editing |
  | Single-file Overleaf bundle | `Paper/Overleaf_Upload_SINGLE_2026-09-15.zip` (one main.tex + 10 figures) | uploading to Overleaf |
  | Code + data repository | this folder / GitHub `YANGHanyu3/Biochar-Supply-Chain` | running the model |

## 2. What is in each folder

| Folder | Contents |
|---|---|
| `Code/` | Python data generation + figure scripts, Julia optimization models (v2 pooled and v2b quality-differentiated), the v0.9 experiment drivers (`run_v09_experiments.sh`), solver log, `requirements.txt`, `Project.toml`, `REPRODUCE.md`, generated data matrices (including the demand-family and gate-off variants) and result CSVs (including the certified re-solves, the net-cap frontier, and the Prop-3 basis check) |
| `Data/` | raw inputs (Wisconsin biomass workbook, BT23 agricultural/forestry downloads, NASS, GIS shapefiles) |
| `Graph/` | the 6 main figures and 4 supplementary figures (PNG 400 DPI), plus fig0 in PDF/SVG vector form |
| `Paper/` | the manuscript source, bibliography, figures, the Overleaf zip, and the review-response document |
| `PPT/` | two advisor progress decks |
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

The v0.9 experiments have dedicated drivers (all archived, all reproducible):
`run_v09_experiments.sh` (E2 frontier, Prop-3 check, E3 demand families, E1
gate-off ablation, E4 carbon grid, E5 certification, enriched regenerations),
`run_v2b_mature.sh` (v2b gap-recording reruns and mature-scenario fixups).

**Known caveat:** a few canonical result CSVs
(`policy_A_bnc_sweep_v2.csv`, `policy_C2_tax_credit_v2.csv`,
`policy_A_bnc_sweep_v2b.csv`) are post-processed/patched in place
(e.g., the mature A $p_c=\$100$ recertification `policy_A_recert2_v2.csv`) —
`REPRODUCE.md` documents this patch chain, so a bare rerun of the `.jl` files
will not reproduce those exact numbers without applying the patches.

## 4. What we would most like checked

**Model / theory**
1. The three propositions in Section 2 and their SI proofs — in particular the
   route-specific evaluation of Proposition 3 (SI Section A.11; the threshold
   is now $\approx$\$321/t with per-row marginal intensities, replacing the
   earlier fleet-average estimate) and the sign convention of the cap dual in
   Proposition 1 (SI Section A.9 now reports dual ranges at degenerate
   vertices).
2. The carbon-credit coefficient `C x permanence x (44/12) x biochar yield`
   (per tonne dry), the VM0044 H/C <= 0.7 gate, and the new carbon ledger
   (Table S6) with the identity `creditable quantity = B - N` (verified for
   every sweep point).
3. The net-cap frontier (SI Fig. S2, Section on the E2 experiment): loose net
   caps (>= -1000 kt) do not bind, but tightening below the baseline flux
   binds in two stages (expansion, then 500 C conversion) — this replaces the
   earlier "net caps are blind" claim.

**Numbers (spot checks)**
4. Table 1 (baseline), Table 2 (C1-free), Table 3 (v2b) against
   `Code/results_v2*/**.csv`; Table 3 now matches the gap-recorded v2b
   re-runs (2026-09-14).
5. The certified points (Table S3 "Certified re-solves" block) against the
   tagged CSVs (`policy_A_cert_v2.csv`, `policy_C2_certs0/1_v2.csv`,
   `policy_A_recert2_v2.csv`, `*_certrev_v2.csv`).
6. The demand-family results (SI Fig. S4) against `results_v2_df*`.
7. The cash-flow decomposition (Table S7): every row satisfies
   surplus = consumer payment + credit revenue - tax - resource cost.

**Presentation**
8. Whether the four SI figures now read as diagnostics (frontier,
   certificates, demand families, A-sweep detail) rather than duplicates of
   Fig. 4.
9. Figure captions versus figure content (terminology, units, segment names).

## 5. What changed in v0.9 (in response to the 2026-09-13 review)

- **Title and terminology**: "Endogenous Carbon Prices" is now "Shadow Carbon
  Prices"; the body uses "conditional fixed-layout shadow MAC" and a four-way
  price-concept definition (demand bid / inherent value / shadow MAC /
  administered benchmark, Methods Section 2.4).
- **Net caps**: the "never bind / blind" claim is replaced by the two-stage
  frontier result (bind below the baseline flux; expansion then durability
  mandate; near-term MAC $\approx$\$110 then $\approx$\$150--330/tCO$_2$e;
  N_min = -2602 kt).
- **Proposition 3**: now verified route-specifically ($\tau_{\max}\approx\$321$/t
  from per-demand-row basis perturbations, archived
  `prop3_basis_check_v2.csv`); the proposition survives.
- **Policy decomposition (E1)**: a gate-off ablation shows the 500 C
  conversion is driven by the H/C eligibility gate, not the credit basis
  (Table S8).
- **Demand families (E3)**: the $25/t L-segment activation is now explicitly
  conditional on the calibrated demand (SI Fig. S4).
- **Solver certification (E5)**: largest-gap points re-solved at 0.1% targets
  with seeds; forward/reverse sweeps agree within 0.2%; v2b gap percentages
  now recorded (Table S3).
- **Welfare accounting**: carbon ledger (Table S6) and cash-flow
  decomposition (Table S7) added; surplus is defined as the producer
  objective including policy transfers.
- **Benchmark hygiene**: RGGI/EU ETS bands now carry years (2024--2025) and
  currency conversion; the Figure 4 EU ETS band label matches its span.

## 6. Open items we already know about

- Author block commented out (deliberate, see section 1).
- Some policy points remain TIME_LIMIT incumbents (gaps as tabulated in
  Table S3; certified re-solves for the largest gaps).
- Figure file names are not the same as the printed figure numbers (LaTeX
  numbers them automatically): main text `fig2_baseline`...`fig6_sensitivity`
  (Figures 2-6); SI `sfig1_policyA`, `sfig2_netcap_frontier`,
  `sfig3_certificates`, `sfig4_demand_family` (S-Figures 1-4).
- The demand-curve price tiers are calibrated, not estimated (see Limitations
  and the demand data pack), and the $25/t activation threshold is stated
  conditionally on that calibration.
- The decomposition fraction (0.9) is a scenario assumption (upper bound),
  flagged as such in the Methods.
