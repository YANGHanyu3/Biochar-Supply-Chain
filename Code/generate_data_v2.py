"""
generate_data_v2.py — Biochar Supply Chain v2 data layer
========================================================
Replaces generate_data_wi.py (v1). Key changes vs v1:
  1. Dual pyrolysis temperatures: T2-300C (13 techs) + T2-500C (13 techs) => 39 techs
  2. Step demand curve: 3 segments (H/M/L) + sink, replacing flat 4.16Mt@$392
  3. VM0044 eligibility gate: carbon credit only for biochar with H/C <= 0.7
     -> 300C biochar from wheat/oats/barley/soybean (H/C>0.7) earns NO credits
     -> 500C biochar always eligible (H/C<=0.5)
  4. Correct CC accounting: CC co-production = rho * C * permanence * 44/12 * yield
     (v1 over-credited by 1/yield ~2.6x; fixed here)
  5. Dual BT23 scenarios: near-term (baseline) + mature-market medium (sensitivity)

Usage:
  python generate_data_v2.py               # generates both scenarios
Output: biochar_data_v2/{scenario}/*.csv
"""
import pandas as pd
import numpy as np
import os, json, sys

# ═══════════════════════════════════════════════════
# 0. CONFIG
# ═══════════════════════════════════════════════════
def _first_existing(*paths):
    for p in paths:
        if os.path.exists(p):
            return p
    return paths[0]


def _project_root(start):
    """Walk up from `start` to the folder holding 03_Data/Raw_Downloads/BT23."""
    d = os.path.abspath(start if os.path.isdir(start) else os.path.dirname(start))
    for _ in range(6):
        if os.path.isdir(os.path.join(d, "03_Data", "Raw_Downloads", "BT23")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return None


def _find_bt23(filename, env_var):
    """Locate a BT23 CSV: $env_var override, project-relative search, then a
    bounded search under the script's parent (covers the Code/Data delivery
    layout). No absolute path is hard-coded, so this is machine-portable."""
    import glob
    cands = []
    env = os.environ.get(env_var)
    if env:
        cands.append(env)
    root = _project_root(__file__)
    if root:
        base = os.path.join(root, "03_Data", "Raw_Downloads", "BT23")
        if os.path.isdir(base):
            for sub in sorted(os.listdir(base)):
                cands.append(os.path.join(base, sub, filename))
    here = os.path.dirname(os.path.abspath(__file__))
    cands += sorted(glob.glob(os.path.join(here, "..", "**", filename), recursive=True))
    for p in cands:
        if os.path.exists(p):
            return p
    raise FileNotFoundError(
        "Could not locate " + filename + ". Set " + env_var + " to its full path. "
        "Searched:\n  " + "\n  ".join(cands))


WB = _first_existing(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "Wisconsin_Biomass_Data.xlsx"))
BT23_AG = _find_bt23("billionton_23_agri_download20260618-105910.csv", "BIOCHAR_BT23_AG")
BT23_FO = _find_bt23("billionton_23_forestry_download20260618-105947.csv", "BIOCHAR_BT23_FO")

OP_DAYS, CRF, TARGET_MC = 330, 0.1175, 10.0

# Demand step curve (decision list 2026-09-02; calibration pending model run)
DEMAND_SEGMENTS = [
    # (segment, price $/t BC, capacity Mt/yr)
    ("H", 800.0, 0.8),
    ("M", 500.0, 1.5),
    ("L", 250.0, 2.5),
]
SINK_PRICE = 30.0          # $/t BC non-soil uses (construction/filtration)
SINK_CAP   = 1.0e12

# VM0044 v1.2 permanence factors (verified vs VM0044 v1.2 Table 3, drawn from
# IPCC 2019 Table 4AP.2 / Woolf et al. 2021):
#   450-600 C (500C): 0.80  |  350-450 C: 0.65  |  >600 C: 0.89
# 300C sits below the lowest published band, so it takes the conservative
# 350-450 C default of 0.65. (v2.1: was 0.69 placeholder; corrected 2026-09-02.)
PERM_300, PERM_500 = 0.65, 0.80
H_C_GATE = 0.7            # VM0044 eligibility threshold (v1.2 Section 4.4.2: H:Corg <= 0.7)
# 500C parameters — source audit 2026-09 (v0.3 review):
#   * Roberts et al. 2010 (EST 44:827, doi 10.1021/es902266r) is a 450 C slow-
#     pyrolysis LCA; it contains NO 300 C or 500 C case and NO H/C data. What it
#     does support: char yields of 28.8-33.0 wt% at 0.1 MPa (citing Antal &
#     Gronli 2003, Ind. Eng. Chem. Res. 42:1619) and an 80% stable-C fraction.
#     -> y500 = 0.30 for corn stover lies inside [28.8, 33.0] wt%  [verified]
#        (and matches Rafiq et al. 2016 corn-stover 500 C yield 29.2%)
#     -> PERM_500 = 0.80 matches Roberts' 80% stable-C assumption  [verified]
#   * H/C values corrected 2026-09-03 vs the literature audit (hc_literature_report.md):
#     - 300 C chars (torrefaction-like): H:C 0.9-1.4 (Rafiq 2016 PLOS ONE 11:e0156894;
#       Ippolito et al. 2020 Biochar 2:421-438 doi 10.1007/s42773-020-00067-x)
#       -> ALL above the VM0044 H:Corg<=0.7 gate -> 300 C NEVER credit-eligible.
#     - 500 C chars: corn stover 0.49 (Rafiq 2016; Enders 2012 ~0.4-0.5),
#       lignocellulosic band 0.40-0.55 (Ippolito 2020 meta) -> eligible.
#   * The 300/500 C yield and C-content pairs (0.38/0.30, 0.45/0.55) remain the
#     advisor-confirmed V9 technology-table values; C300 = 0.45 is independently
#     confirmed by Rafiq 2016 (300 C char C = 45.5%); C500 = 0.55 is conservative
#     vs the literature 62-65% (Ippolito 2020 mean 62.5%; Rafiq 2016 64.5%).
C_500_SCALE = 0.55 / 0.45     # scale C_dry(300C) -> C_dry(500C)   (V9 sheet 02 pair)
Y_500_SCALE = 0.30 / 0.38     # scale bc_yield(300C) -> bc_yield(500C) (V9 sheet 02 pair)
ELEC_300, ELEC_500 = 50.0, 65.0   # kWh/t dry electricity output
WI_GRID = 0.57              # kg CO2e/kWh (US EIA WI 2022)

# H/C eligibility sensitivity (v0.3 review): set HC_SHIFT to shift every H/C
# value (both 300 C and 500 C) before applying the VM0044 gate, writing to a
# separate data directory. With corrected base values, +-0.1 is inert (no flip:
# 0.49+0.1=0.59<0.7; 1.40-0.1=1.30>0.7); the first 500 C flip needs +0.25
# (corn stover 0.49->0.74). Default 0.0 = canonical data.
HC_SHIFT = float(os.environ.get("HC_SHIFT", "0.0"))

# Demand-geography sensitivity (v0.6 review): DEMAND_CONC concentrates the
# county demand allocation as area**DEMAND_CONC. Default 1.0 = proportional to
# farmland area (canonical). Larger values push demand into the largest
# counties, testing whether facility siting is demand- or feedstock-driven.
# Output is written to a separate data directory (biochar_data_v2_dc<alpha>).
DEMAND_CONC = float(os.environ.get("DEMAND_CONC", "1.0"))

# Demand-family sensitivity (v0.9 review, E3): DEMAND_FAMILY variants
#   "low":  capacities x0.7  (adoption below the calibrated baseline)
#   "high": capacities x1.4  (adoption above the calibrated baseline)
#   "pricestress": M price 450 $/t, L price 200 $/t (stress on the $25/t
#                  activation threshold of the bulk segment)
# Output is written to a separate data directory (biochar_data_v2_df<family>).
DEMAND_FAMILY = os.environ.get("DEMAND_FAMILY", "").strip()

# Policy-ablation sensitivity (v0.9 review, E1): GATE_OFF=1 makes every
# feedstock-temperature pair credit-eligible (no H/C gate), isolating the
# eligibility-gate effect inside Paradigm C2. Default "" = canonical gate.
GATE_OFF = os.environ.get("GATE_OFF", "") == "1"

# ═══════════════════════════════════════════════════
# 1. FEEDSTOCK DEFINITIONS (verified vs workbook 04_Moisture_GHG_Factors + v1)
# ═══════════════════════════════════════════════════
# (mc%, C_dry, bc_yield_300, fg_dry $/t, category, BT23 mapping)
# H/C values — v0.3 correction 2026-09-03 (literature audit, hc_literature_report.md):
#   * 300 C chars are torrefaction-like: published H:C ~ 0.9-1.4 (Rafiq et al. 2016,
#     PLOS ONE 11:e0156894: corn stover 300 C H:C ~1.41, C 45.5%; Ippolito et al. 2020,
#     Biochar 2:421-438, doi 10.1007/s42773-020-00067-x). ALL exceed the VM0044
#     H:Corg<=0.7 gate -> 300 C biochar is NEVER credit-eligible. (Previous values
#     0.30-0.73 were unsourced and ~2x too low; corrected.)
#   * 500 C chars: corn stover H:C 0.49 (Rafiq 2016, benchmarked vs Enders 2012);
#     lignocellulosics 0.40-0.55 (Ippolito 2020 meta, 500-599 C band H:C~0.54);
#     woody ~0.40 (Enders 2012 oak). All <= 0.7 -> eligible.
FEEDSTOCKS = {
    'Corn_Stover':         dict(mc=17.5, C=0.45, y300=0.38, fg=60, cat='ag',   hc300=1.40, hc500=0.49),
    'Soybean_Straw':       dict(mc=14.0, C=0.43, y300=0.36, fg=60, cat='ag',   hc300=1.30, hc500=0.50),
    'Wheat_Straw':         dict(mc=12.5, C=0.42, y300=0.35, fg=60, cat='ag',   hc300=1.25, hc500=0.51),
    'Oats_Straw':          dict(mc=13.0, C=0.41, y300=0.34, fg=60, cat='ag',   hc300=1.25, hc500=0.52),
    'Barley_Straw':        dict(mc=12.0, C=0.41, y300=0.34, fg=60, cat='ag',   hc300=1.25, hc500=0.51),
    'Switchgrass':         dict(mc=12.5, C=0.47, y300=0.38, fg=60, cat='ag',   hc300=1.30, hc500=0.47),
    'Miscanthus':          dict(mc=15.0, C=0.48, y300=0.37, fg=60, cat='ag',   hc300=1.30, hc500=0.45),
    'Poplar':              dict(mc=45.0, C=0.50, y300=0.35, fg=60, cat='for',  hc300=1.10, hc500=0.40),
    'Willow':              dict(mc=45.0, C=0.50, y300=0.35, fg=60, cat='for',  hc300=1.10, hc500=0.40),
    'Logging_Residues':    dict(mc=42.5, C=0.49, y300=0.33, fg=40, cat='for',  hc300=1.05, hc500=0.42),
    'SmallDiameter_Trees': dict(mc=45.0, C=0.49, y300=0.33, fg=60, cat='for',  hc300=1.05, hc500=0.41),
    'Mill_Residues':       dict(mc=35.0, C=0.50, y300=0.34, fg=50, cat='for',  hc300=1.00, hc500=0.40),
    'Other_Forest_Waste':  dict(mc=20.0, C=0.47, y300=0.35, fg=50, cat='for',  hc300=1.15, hc500=0.45),
}
FS = list(FEEDSTOCKS.keys())
N_FS = len(FS)

# ═══════════════════════════════════════════════════
# 2. LOAD COUNTY-LEVEL DRY TONNAGE
# ═══════════════════════════════════════════════════
xl = pd.ExcelFile(WB)
raw = pd.read_excel(xl, sheet_name="01_WI_County_Biomass", header=3).iloc[0:72]
raw.columns = ['n_id','County','FIPS','LAT','LON','Area_sqmi',
    'Corn_Stover','Miscanthus','Switchgrass','Willow','Poplar',
    'Logging_Residues','SmallDiameter_Trees','Mill_Residues','Other_Forest_Waste',
    'TOTAL','Wheat_Straw','Oats_Straw']
nass = pd.read_excel(xl, sheet_name="02_NASS_Validation", header=3)
nass['n_id'] = pd.to_numeric(nass['n_id'], errors='coerce')
nass = nass[nass['n_id'].between(1, 72)]
raw['Soybean_Straw'] = raw['n_id'].map(dict(zip(nass['n_id'], nass['NASS_Soy_CENSUS_dt']))).fillna(0.0)
raw['Barley_Straw']  = raw['n_id'].map(dict(zip(nass['n_id'], nass['NASS_Barley_dt']))).fillna(0.0)
for c in raw.columns[5:]:
    raw[c] = pd.to_numeric(raw[c], errors='coerce').fillna(0.0)

# BT23 county-level by scenario
def bt23_county(path, resource_filter, scenario):
    df = pd.read_csv(path)
    key = 'resource' if 'resource' in df.columns else 'resource_name'
    sc  = 'scenario_name' if 'scenario_name' in df.columns else 'scenario'
    df = df[(df[key].isin(resource_filter)) & (df[sc].str.lower() == scenario.lower())]
    if 'production' not in df.columns:
        return {}
    g = df.groupby('fips')['production'].sum()
    # fips -> n_id (workbook n_id order: county list; fips has leading zero)
    fips_to_nid = dict(zip(raw['FIPS'].fillna(0).astype(int).astype(str).str.zfill(5),
                           raw['n_id'].astype(int)))
    out = {}
    for f, v in g.items():
        nid = fips_to_nid.get(str(f).zfill(5))
        if nid is not None:
            out[int(nid)] = v
    return out

AG_MAP = {
    'Corn_Stover': ['Corn stover'],
    'Miscanthus':  ['Miscanthus'],
    'Switchgrass': ['Switchgrass'],
    'Willow':      ['Willow'],
    'Poplar':      ['Poplar'],
}
FO_MAP = {
    'Logging_Residues':    ['Hardwood lowland logging residues','Hardwood upland logging residues',
                            'Mixedwood logging residues','Softwood natural logging residues',
                            'Softwood planted logging residues'],
    'SmallDiameter_Trees': ['Hardwood lowland small-diameter trees','Hardwood upland small-diameter trees',
                            'Softwood natural small-diameter trees','Softwood planted small-diameter trees'],
    'Mill_Residues':       ['Hardwood processing residues','Softwood processing residues'],
    'Other_Forest_Waste':  ['Forest waste human generated'],
}

def build_dry(scenario):
    """Return DataFrame[72 x 13] dry tons by scenario.
    BT23 resources -> BT23 mapping; wheat/oats/soybean/barley -> workbook (NASS-derived)."""
    dry = pd.DataFrame({'n_id': raw['n_id'].astype(int)})
    for fs_name, res_list in AG_MAP.items():
        m = bt23_county(BT23_AG, res_list, scenario)
        dry[fs_name] = dry['n_id'].map(m).fillna(0.0)
    for fs_name, res_list in FO_MAP.items():
        m = bt23_county(BT23_FO, res_list, scenario)
        dry[fs_name] = dry['n_id'].map(m).fillna(0.0)
    # NASS-derived straws from workbook (same in both scenarios; BT23 has ~0 for these)
    for c in ['Wheat_Straw','Oats_Straw','Soybean_Straw','Barley_Straw']:
        dry[c] = raw[c].values
    return dry

# ═══════════════════════════════════════════════════
# 3. PER-FEEDSTOCK DERIVED PARAMS
# ═══════════════════════════════════════════════════
for name, fd in FEEDSTOCKS.items():
    eta = (100 - fd['mc']) / (100 - TARGET_MC)
    water_per_wet = 1.0 - eta
    fd['eta'] = eta
    fd['t1_opex_wet'] = 5.0 + water_per_wet * (10.0 if fd['cat'] == 'ag' else 15.0)
    fd['t2_opex_dry'] = 30.0
    fd['fg_wet'] = fd['fg'] * (1 - fd['mc']/100)
    fd['t1_ghg_per_dry'] = 35.0 + water_per_wet/eta * 25.0
    fd['t2_ghg_per_dry_300'] = 150.0 - ELEC_300 * WI_GRID
    fd['t2_ghg_per_dry_500'] = 150.0 - ELEC_500 * WI_GRID
    fd['baseline_ghg_dry'] = fd['C'] * 0.90 * 44/12 * 1000.0
    # T1 ref product is WET tonnes: store per-t-REF values (per wet t), not per dry t
    # (v2.1 fix: previously the per-dry values were applied to wet tonnes,
    #  overstating T1 process GHG and the decomposition baseline by 1/eta)
    fd['t1_ghg_per_wet'] = fd['t1_ghg_per_dry'] * eta
    fd['baseline_ghg_wet'] = fd['baseline_ghg_dry'] * eta
    # 500C params (placeholders flagged)
    fd['y500'] = fd['y300'] * Y_500_SCALE
    fd['C500'] = fd['C'] * C_500_SCALE
    fd['hc500'] = fd['hc500']   # explicit per-feedstock literature value (no artificial formula)
    # H/C sensitivity shift (before the gate): applies to BOTH temperatures
    hc300_eff = fd['hc300'] + HC_SHIFT
    hc500_eff = fd['hc500'] + HC_SHIFT
    # carbon credit per t BC (tCO2/t BC): C * permanence * 44/12
    fd['cc_per_bc_300'] = fd['C']  * PERM_300 * 44/12
    fd['cc_per_bc_500'] = fd['C500'] * PERM_500 * 44/12
    # eligibility: 300 C chars are torrefaction-like (H/C 0.9-1.4) -> never eligible;
    # 500 C chars (H/C 0.40-0.52) -> eligible unless the shift stress test flips them
    fd['eligible_300'] = hc300_eff <= H_C_GATE
    fd['eligible_500'] = hc500_eff <= H_C_GATE
    if GATE_OFF:   # E1 ablation: no H/C eligibility gate
        fd['eligible_300'] = True
        fd['eligible_500'] = True
    # CC per t dry: yield * cc_per_bc * eligible
    fd['cc_per_dry_300'] = fd['y300'] * fd['cc_per_bc_300'] if fd['eligible_300'] else 0.0
    fd['cc_per_dry_500'] = fd['y500'] * fd['cc_per_bc_500'] if fd['eligible_500'] else 0.0
    # seq per t BC for GHG module (kg/t BC)
    fd['seq300'] = -fd['C'] * PERM_300 * 44/12 * 1000.0
    fd['seq500'] = -fd['C500'] * PERM_500 * 44/12 * 1000.0
    fd['n2o'] = -52.0

# ═══════════════════════════════════════════════════
# 4. WRITE MATRICES FOR ONE SCENARIO
# ═══════════════════════════════════════════════════
S1 = {1: 100*OP_DAYS, 2: 500*OP_DAYS, 3: 2000*OP_DAYS}      # T1 t/yr
C1 = {1: 0.8e6, 2: 2.5e6, 3: 7.0e6}
S2 = {1: 182*OP_DAYS, 2: 600*OP_DAYS, 3: 2000*OP_DAYS}      # T2 t/yr
C2 = {1: 9.0e6, 2: 21.5e6, 3: 51.0e6}

def write_scenario(dry, scenario, outdir):
    os.makedirs(outdir, exist_ok=True)
    N = N_FS
    # --- node ---
    nm = raw[['n_id','County','LAT','LON']].copy()
    nm.columns = ['node_id','alias','lat','lon']
    nm['alias'] = nm['alias'].str.replace(' County','',regex=False)
    nm.to_csv(f"{outdir}/node_matrix.csv", index=False)
    # --- products: 13 wet + 13 dry + BC(27) + CC(28) ---
    prod = []
    for i, n in enumerate(FS):
        prod.append(dict(product_id=i+1, name=f'wet_{n}', trans_vc_truck=0.15, trans_fc_truck=4.0))
    for i, n in enumerate(FS):
        prod.append(dict(product_id=N+i+1, name=f'dry_{n}', trans_vc_truck=0.10, trans_fc_truck=4.0))
    prod.append(dict(product_id=2*N+1, name='biochar', trans_vc_truck=0.08, trans_fc_truck=3.5))
    prod.append(dict(product_id=2*N+2, name='carbon_credit', trans_vc_truck=0.0, trans_fc_truck=0.0))
    pd.DataFrame(prod).to_csv(f"{outdir}/product_matrix.csv", index=False)
    # --- supply (wet t) ---
    sup_rows = []
    sid = 1
    for _, r in dry.iterrows():
        for i, n in enumerate(FS):
            fd = FEEDSTOCKS[n]
            dt = r[n]
            if dt > 0:
                wet = dt / (1 - fd['mc']/100)
                sup_rows.append(dict(sup_id=sid, node=int(r['n_id']), product=i+1,
                                     feedstock=n, bid=round(fd['fg_wet'],2),
                                     capacity=round(wet,2)))
                sid += 1
    sup = pd.DataFrame(sup_rows)
    sup.to_csv(f"{outdir}/supply_matrix.csv", index=False)
    # --- demand: 3 segments x 72 + sink 72 ---
    # county allocation ∝ area**DEMAND_CONC (1.0 = farmland-area proportional)
    w = raw['Area_sqmi'] ** DEMAND_CONC
    share = (w / w.sum()).values
    dem_rows = []
    did = 1
    for seg, price, cap in DEMAND_SEGMENTS:
        price_e, cap_e = price, cap
        if DEMAND_FAMILY == "low":
            cap_e = cap * 0.7
        elif DEMAND_FAMILY == "high":
            cap_e = cap * 1.4
        elif DEMAND_FAMILY == "pricestress":
            if seg == "M":
                price_e = 450.0
            if seg == "L":
                price_e = 200.0
        for i, nid in enumerate(raw['n_id']):
            dem_rows.append(dict(dem_id=did, node=int(nid), product=2*N+1,
                                 segment=seg, bid=price_e,
                                 capacity=round(share[i]*cap_e*1e6, 2)))
            did += 1
    for i, nid in enumerate(raw['n_id']):
        dem_rows.append(dict(dem_id=did, node=int(nid), product=2*N+1,
                             segment='sink', bid=SINK_PRICE,
                             capacity=SINK_CAP))
        did += 1
    # CC "no-market" rows (bid=0): baseline absorbs CC co-production at zero value.
    # Policy files (04/06) override these bids with p_c > 0. WITHOUT these rows the
    # mass balance has no CC sink and all CC-eligible technology chains become
    # structurally infeasible (v2 fix of a subtle base-model design flaw).
    for i, nid in enumerate(raw['n_id']):
        dem_rows.append(dict(dem_id=did, node=int(nid), product=2*N+2,
                             segment='cc', bid=0.0,
                             capacity=1.0e12))
        did += 1
    pd.DataFrame(dem_rows).to_csv(f"{outdir}/demand_matrix.csv", index=False)
    # --- technology: 13 T1 + 13 T2-300 + 13 T2-500 ---
    tech_rows, tn_rows = [], []
    tid = 1
    for i, n in enumerate(FS):
        fd = FEEDSTOCKS[n]
        tech_rows.append(dict(tech_id=tid, cap=S1[3]*5, ref_prod=i+1, inv=C1[3],
                              bid=round(fd['t1_opex_wet'],2), bc_price=0.0,
                              size_1=S1[1], size_2=S1[2], size_3=S1[3],
                              cost_1=C1[1], cost_2=C1[2], cost_3=C1[3]))
        tn_rows.append(dict(tech_id=tid, name=f'T1_Dehyd_{n}'))
        tid += 1
    for temp in (300, 500):
        for i, n in enumerate(FS):
            fd = FEEDSTOCKS[n]
            tech_rows.append(dict(tech_id=tid, cap=S2[3]*5, ref_prod=N+i+1, inv=C2[3],
                                  bid=fd['t2_opex_dry'], bc_price=round(300+fd['C']*200,0),
                                  size_1=S2[1], size_2=S2[2], size_3=S2[3],
                                  cost_1=C2[1], cost_2=C2[2], cost_3=C2[3]))
            tn_rows.append(dict(tech_id=tid, name=f'T2{temp}C_Pyrol_{n}'))
            tid += 1
    pd.DataFrame(tech_rows).to_csv(f"{outdir}/technology_matrix.csv", index=False)
    pd.DataFrame(tn_rows).to_csv(f"{outdir}/technology_names.csv", index=False)
    # --- alpha: 39 x 28 ---
    alpha = np.zeros((3*N, 2*N+2))
    for i, n in enumerate(FS):
        fd = FEEDSTOCKS[n]
        alpha[i, i] = -1.0
        alpha[i, N+i] = fd['eta']                       # T1: wet -> dry
        alpha[N+i, N+i] = -1.0                          # T2-300
        alpha[N+i, 2*N] = fd['y300']
        alpha[N+i, 2*N+1] = fd['cc_per_dry_300']        # CC (eligibility-gated)
        alpha[2*N+i, N+i] = -1.0                        # T2-500
        alpha[2*N+i, 2*N] = fd['y500']
        alpha[2*N+i, 2*N+1] = fd['cc_per_dry_500']
    pd.DataFrame(alpha).to_csv(f"{outdir}/alpha_matrix.csv", index=False, header=False)
    # --- site ---
    site_rows = []
    tp = 1
    for _, r in raw.iterrows():
        for t in range(1, 3*N+1):
            site_rows.append(dict(tp_id=tp, node=int(r['n_id']), indicator=1, unused=0, tech_type=t))
            tp += 1
    pd.DataFrame(site_rows).to_csv(f"{outdir}/site_matrix_MIP.csv", index=False)
    # --- ghg factors: 39 rows (column order matches v1 convention) ---
    ghg_rows = []
    for i, n in enumerate(FS):
        fd = FEEDSTOCKS[n]
        ghg_rows.append(dict(tech_id=i+1, tech_name=f'T1_Dehyd_{n}',
            process_ghg_per_t_ref=round(fd['t1_ghg_per_wet'],1),
            ghg_seq_per_t_bc=0.0, ghg_n2o_per_t_bc=0.0,
            net_ghg_credit_per_t_bc=0.0,
            ghg_transport_per_tkm=0.0902,
            baseline_ghg_per_t_ref=round(fd['baseline_ghg_wet'],1),
            hc=fd['hc300']))
    for k, (temp, hc_k) in enumerate((('300', 'hc300'), ('500', 'hc500'))):
        for i, n in enumerate(FS):
            fd = FEEDSTOCKS[n]
            tid = N + (k*N) + i + 1
            seq = fd['seq300'] if temp == '300' else fd['seq500']
            pghg = fd['t2_ghg_per_dry_300'] if temp == '300' else fd['t2_ghg_per_dry_500']
            ghg_rows.append(dict(tech_id=tid, tech_name=f'T2{temp}C_Pyrol_{n}',
                process_ghg_per_t_ref=round(pghg,1),
                ghg_seq_per_t_bc=round(seq,1), ghg_n2o_per_t_bc=fd['n2o'],
                net_ghg_credit_per_t_bc=round(seq + fd['n2o'],1),
                ghg_transport_per_tkm=0.0902, baseline_ghg_per_t_ref=0.0,
                hc=fd[hc_k]))
    ghg = pd.DataFrame(ghg_rows)
    ghg.to_csv(f"{outdir}/ghg_factors_v2.csv", index=False)
    # --- summary json ---
    tot_dry = sum(dry[n].sum() for n in FS)
    bc_pot = sum(dry[n].sum()*FEEDSTOCKS[n]['y300'] for n in FS)
    summary = dict(scenario=scenario, feedstocks=N, technologies=3*N, products=2*N+2,
                   total_dry_Mt=round(tot_dry/1e6,3), bc_potential_300C_Mt=round(bc_pot/1e6,3),
                   demand_segments=DEMAND_SEGMENTS, sink_price=SINK_PRICE,
                   perm_300=PERM_300, perm_500=PERM_500, hc_gate=H_C_GATE,
                   hc_shift=HC_SHIFT,
                   notes=("CC= C*perm*44/12*yield, eligibility H/C<=0.7; 300C never eligible "
                          "(H/C 0.9-1.4, torrefaction-like, Rafiq 2016/Ippolito 2020); "
                          "500C eligible (H/C 0.40-0.52, Rafiq 2016/Enders 2012/Ippolito 2020); "
                          "see SI A.3" +
                          (f"; HC_SHIFT={HC_SHIFT:+.2f} sensitivity" if HC_SHIFT != 0 else "")))
    with open(f"{outdir}/summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=str)
    print(f"[{scenario}] dry={tot_dry/1e6:.2f}Mt | BC potential={bc_pot/1e6:.2f}Mt | files -> {outdir}")

# ═══════════════════════════════════════════════════
# 5. MAIN
# ═══════════════════════════════════════════════════
if __name__ == "__main__":
    scenarios = ['near-term', 'mature-market medium']
    basedir = f"biochar_data_v2" if HC_SHIFT == 0 else f"biochar_data_v2_hc{HC_SHIFT:+.2f}"
    if DEMAND_CONC != 1.0:
        basedir += f"_dc{DEMAND_CONC:g}"
        print(f"[demand-geography sensitivity] DEMAND_CONC={DEMAND_CONC:g} -> {basedir}")
    if DEMAND_FAMILY:
        basedir += f"_df{DEMAND_FAMILY}"
        print(f"[demand-family sensitivity] DEMAND_FAMILY={DEMAND_FAMILY} -> {basedir}")
    if GATE_OFF:
        basedir += "_gateoff"
        print(f"[policy ablation E1] GATE_OFF -> {basedir}")
    for sc in scenarios:
        dry = build_dry(sc)
        write_scenario(dry, sc, f"{basedir}/{sc}")
    # eligibility report
    print("\n=== VM0044 eligibility report ===")
    for n in FS:
        fd = FEEDSTOCKS[n]
        print(f"  {n:22s} H/C300={fd['hc300']:.2f} {'ELIGIBLE' if fd['eligible_300'] else 'INELIGIBLE'} "
              f"| H/C500={fd['hc500']:.2f} {'ELIGIBLE' if fd['eligible_500'] else 'INELIGIBLE'} | "
              f"CC300={fd['cc_per_dry_300']:.3f} CC500={fd['cc_per_dry_500']:.3f} tCO2/t_dry")
