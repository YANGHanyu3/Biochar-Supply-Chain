"""
generate_data_v2b.py — v2b: quality-differentiated biochar products
==================================================================
Extension of v2: biochar split into TWO products:
  BC300 (product 27): biochar from 300C pyrolysis (H/C 1.00-1.40, bulk quality)
  BC500 (product 28): biochar from 500C pyrolysis (H/C 0.40-0.52, CDR premium)
  CC    (product 29): carbon credit
Demand segments (quality-tiered bid stack):
  H ($800/t, 0.8 Mt): BC500 ONLY  (CDR premium market: low H/C, high permanence)
  M ($500/t, 1.5 Mt): BC300 + BC500 (industrial/quality ag)
  L ($250/t, 2.5 Mt): BC300 + BC500 (bulk agricultural)
  sink ($30/t):       BC300 + BC500
This makes the 300 vs 500 C technology choice a REAL economic tradeoff:
  300C: higher BC yield (0.38 vs 0.30), but no access to the $800 premium segment
  500C: lower yield, but access to CDR premium + higher CC per t dry
"""
import pandas as pd
import numpy as np
import os, json

# ═══════════════════════════════════════════════════
# 0. CONFIG (identical to v2 except product/demand structure)
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
SINK_PRICE, SINK_CAP = 30.0, 1.0e12
# VM0044 v1.2 Table 3 (IPCC 2019 4AP.2): 450-600C -> 0.80; 350-450C -> 0.65;
# 300C takes the conservative 0.65 default. (corrected from 0.69 placeholder)
PERM_300, PERM_500 = 0.65, 0.80
H_C_GATE = 0.7
C_500_SCALE = 0.55 / 0.45
Y_500_SCALE = 0.30 / 0.38
ELEC_300, ELEC_500 = 50.0, 65.0
WI_GRID = 0.57

# demand segments: (name, price, capacity_Mt, eligible_products)
DEMAND_SEGMENTS = [
    ("H", 800.0, 0.8, [28]),          # BC500 only (CDR premium)
    ("M", 500.0, 1.5, [27, 28]),
    ("L", 250.0, 2.5, [27, 28]),
]

# H/C values corrected 2026-09-03 (literature audit, hc_literature_report.md):
#   * 300 C chars are torrefaction-like: H:C 0.9-1.4 (Rafiq et al. 2016 PLOS ONE
#     11:e0156894; Ippolito et al. 2020 Biochar 2:421-438, doi 10.1007/s42773-020-00067-x)
#     -> ALL above the VM0044 H:Corg<=0.7 gate -> 300 C NEVER credit-eligible.
#   * 500 C chars: corn stover 0.49 (Rafiq 2016; Enders 2012 ~0.4-0.5),
#     lignocellulosic band 0.40-0.55 (Ippolito 2020) -> eligible.
#   * HC_SHIFT env var (default 0) shifts both H/C columns for the eligibility
#     stress test; +0.25 flips the ag-residue 500 C chars (0.49->0.74).
HC_SHIFT = float(os.environ.get("HC_SHIFT", "0.0"))

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
# 1. LOAD & DERIVE (same as v2)
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

def bt23_county(path, resource_filter, scenario):
    df = pd.read_csv(path)
    key = 'resource' if 'resource' in df.columns else 'resource_name'
    sc  = 'scenario_name' if 'scenario_name' in df.columns else 'scenario'
    df = df[(df[key].isin(resource_filter)) & (df[sc].str.lower() == scenario.lower())]
    g = df.groupby('fips')['production'].sum()
    fips_to_nid = dict(zip(raw['FIPS'].fillna(0).astype(int).astype(str).str.zfill(5),
                           raw['n_id'].astype(int)))
    out = {}
    for f, v in g.items():
        nid = fips_to_nid.get(str(f).zfill(5))
        if nid is not None:
            out[int(nid)] = v
    return out

AG_MAP = {
    'Corn_Stover': ['Corn stover'], 'Miscanthus': ['Miscanthus'],
    'Switchgrass': ['Switchgrass'], 'Willow': ['Willow'], 'Poplar': ['Poplar'],
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
    dry = pd.DataFrame({'n_id': raw['n_id'].astype(int)})
    for fs_name, res_list in AG_MAP.items():
        m = bt23_county(BT23_AG, res_list, scenario)
        dry[fs_name] = dry['n_id'].map(m).fillna(0.0)
    for fs_name, res_list in FO_MAP.items():
        m = bt23_county(BT23_FO, res_list, scenario)
        dry[fs_name] = dry['n_id'].map(m).fillna(0.0)
    for c in ['Wheat_Straw','Oats_Straw','Soybean_Straw','Barley_Straw']:
        dry[c] = raw[c].values
    return dry

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
    # T1 ref product is WET tonnes: store per-t-REF values (per wet t)
    fd['t1_ghg_per_wet'] = fd['t1_ghg_per_dry'] * eta
    fd['baseline_ghg_wet'] = fd['baseline_ghg_dry'] * eta
    fd['y500'] = fd['y300'] * Y_500_SCALE
    fd['C500'] = fd['C'] * C_500_SCALE
    fd['hc500'] = fd['hc500']   # explicit per-feedstock literature value (no artificial formula)
    hc300_eff = fd['hc300'] + HC_SHIFT
    hc500_eff = fd['hc500'] + HC_SHIFT
    fd['cc_per_bc_300'] = fd['C']  * PERM_300 * 44/12
    fd['cc_per_bc_500'] = fd['C500'] * PERM_500 * 44/12
    fd['eligible_300'] = hc300_eff <= H_C_GATE
    fd['eligible_500'] = hc500_eff <= H_C_GATE
    fd['cc_per_dry_300'] = fd['y300'] * fd['cc_per_bc_300'] if fd['eligible_300'] else 0.0
    fd['cc_per_dry_500'] = fd['y500'] * fd['cc_per_bc_500'] if fd['eligible_500'] else 0.0
    fd['seq300'] = -fd['C'] * PERM_300 * 44/12 * 1000.0
    fd['seq500'] = -fd['C500'] * PERM_500 * 44/12 * 1000.0
    fd['n2o'] = -52.0

# ═══════════════════════════════════════════════════
# 2. WRITE MATRICES (29 products: wet 1-13, dry 14-26, BC300 27, BC500 28, CC 29)
# ═══════════════════════════════════════════════════
S1 = {1: 100*OP_DAYS, 2: 500*OP_DAYS, 3: 2000*OP_DAYS}
C1 = {1: 0.8e6, 2: 2.5e6, 3: 7.0e6}
S2 = {1: 182*OP_DAYS, 2: 600*OP_DAYS, 3: 2000*OP_DAYS}
C2 = {1: 9.0e6, 2: 21.5e6, 3: 51.0e6}

BC300_PROD = 2*N_FS + 1   # 27
BC500_PROD = 2*N_FS + 2   # 28
CC_PROD    = 2*N_FS + 3   # 29
N_PROD     = 2*N_FS + 3   # 29

def write_scenario(dry, scenario, outdir):
    os.makedirs(outdir, exist_ok=True)
    N = N_FS
    nm = raw[['n_id','County','LAT','LON']].copy()
    nm.columns = ['node_id','alias','lat','lon']
    nm['alias'] = nm['alias'].str.replace(' County','',regex=False)
    nm.to_csv(f"{outdir}/node_matrix.csv", index=False)
    prod = []
    for i, n in enumerate(FS):
        prod.append(dict(product_id=i+1, name=f'wet_{n}', trans_vc_truck=0.15, trans_fc_truck=4.0))
    for i, n in enumerate(FS):
        prod.append(dict(product_id=N+i+1, name=f'dry_{n}', trans_vc_truck=0.10, trans_fc_truck=4.0))
    prod.append(dict(product_id=BC300_PROD, name='biochar300', trans_vc_truck=0.08, trans_fc_truck=3.5))
    prod.append(dict(product_id=BC500_PROD, name='biochar500', trans_vc_truck=0.08, trans_fc_truck=3.5))
    prod.append(dict(product_id=CC_PROD, name='carbon_credit', trans_vc_truck=0.0, trans_fc_truck=0.0))
    pd.DataFrame(prod).to_csv(f"{outdir}/product_matrix.csv", index=False)
    # supply (wet t) — same as v2
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
    pd.DataFrame(sup_rows).to_csv(f"{outdir}/supply_matrix.csv", index=False)
    # demand: quality-tiered segments with SHARED capacity across BC products.
    # Per-product rows are unlimited; a segment_capacity table enforces the
    # shared segment total at each node (correct market clearing: the model may
    # freely substitute BC300/BC500 within a segment).
    v1_dem = raw['Area_sqmi'] * 640 * 0.20 * 0.15 * 4.0
    share = (v1_dem / v1_dem.sum()).values
    dem_rows = []
    did = 1
    for seg, price, cap, prods in DEMAND_SEGMENTS:
        for i, nid in enumerate(raw['n_id']):
            for p in prods:
                dem_rows.append(dict(dem_id=did, node=int(nid), product=p,
                                     segment=seg, bid=price,
                                     capacity=1.0e12))
                did += 1
    for p in (BC300_PROD, BC500_PROD):
        for i, nid in enumerate(raw['n_id']):
            dem_rows.append(dict(dem_id=did, node=int(nid), product=p,
                                 segment='sink', bid=SINK_PRICE, capacity=SINK_CAP))
            did += 1
    for i, nid in enumerate(raw['n_id']):
        dem_rows.append(dict(dem_id=did, node=int(nid), product=CC_PROD,
                             segment='cc', bid=0.0, capacity=1.0e12))
        did += 1
    pd.DataFrame(dem_rows).to_csv(f"{outdir}/demand_matrix.csv", index=False)
    seg_rows = []
    for seg, price, cap, prods in DEMAND_SEGMENTS:
        for i, nid in enumerate(raw['n_id']):
            seg_rows.append(dict(node=int(nid), segment=seg,
                                 capacity=round(share[i]*cap*1e6, 2)))
    pd.DataFrame(seg_rows).to_csv(f"{outdir}/segment_capacity.csv", index=False)
    # technology (same 39 techs as v2)
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
    # alpha: 39 x 29
    alpha = np.zeros((3*N, N_PROD))
    for i, n in enumerate(FS):
        fd = FEEDSTOCKS[n]
        alpha[i, i] = -1.0
        alpha[i, N+i] = fd['eta']
        alpha[N+i, N+i] = -1.0                      # T2-300
        alpha[N+i, BC300_PROD-1] = fd['y300']
        alpha[N+i, CC_PROD-1] = fd['cc_per_dry_300']
        alpha[2*N+i, N+i] = -1.0                    # T2-500
        alpha[2*N+i, BC500_PROD-1] = fd['y500']
        alpha[2*N+i, CC_PROD-1] = fd['cc_per_dry_500']
    pd.DataFrame(alpha).to_csv(f"{outdir}/alpha_matrix.csv", index=False, header=False)
    # site
    site_rows = []
    tp = 1
    for _, r in raw.iterrows():
        for t in range(1, 3*N+1):
            site_rows.append(dict(tp_id=tp, node=int(r['n_id']), indicator=1, unused=0, tech_type=t))
            tp += 1
    pd.DataFrame(site_rows).to_csv(f"{outdir}/site_matrix_MIP.csv", index=False)
    # ghg (same as v2)
    ghg_rows = []
    for i, n in enumerate(FS):
        fd = FEEDSTOCKS[n]
        ghg_rows.append(dict(tech_id=i+1, tech_name=f'T1_Dehyd_{n}',
            process_ghg_per_t_ref=round(fd['t1_ghg_per_wet'],1),
            ghg_seq_per_t_bc=0.0, ghg_n2o_per_t_bc=0.0,
            net_ghg_credit_per_t_bc=0.0, ghg_transport_per_tkm=0.0902,
            baseline_ghg_per_t_ref=round(fd['baseline_ghg_wet'],1), hc=fd['hc300']))
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
                ghg_transport_per_tkm=0.0902, baseline_ghg_per_t_ref=0.0, hc=fd[hc_k]))
    pd.DataFrame(ghg_rows).to_csv(f"{outdir}/ghg_factors_v2.csv", index=False)
    tot_dry = sum(dry[n].sum() for n in FS)
    bc_pot = sum(dry[n].sum()*FEEDSTOCKS[n]['y300'] for n in FS)
    summary = dict(scenario=scenario, feedstocks=N, technologies=3*N, products=N_PROD,
                   total_dry_Mt=round(tot_dry/1e6,3), bc_potential_300C_Mt=round(bc_pot/1e6,3),
                   demand_segments=DEMAND_SEGMENTS, sink_price=SINK_PRICE,
                   perm_300=PERM_300, perm_500=PERM_500, hc_gate=H_C_GATE, hc_shift=HC_SHIFT,
                   notes=("v2b: quality-differentiated BC300/BC500 products; H segment = BC500 only "
                          "(CDR premium); 300C never credit-eligible (H/C 0.9-1.4), 500C eligible "
                          "(H/C 0.40-0.52); see SI A.3" +
                          (f"; HC_SHIFT={HC_SHIFT:+.2f}" if HC_SHIFT != 0 else "")))
    with open(f"{outdir}/summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=str)
    print(f"[{scenario}] dry={tot_dry/1e6:.2f}Mt | BC potential={bc_pot/1e6:.2f}Mt | products={N_PROD} | -> {outdir}")

if __name__ == "__main__":
    basedir = "biochar_data_v2b" if HC_SHIFT == 0 else f"biochar_data_v2b_hc{HC_SHIFT:+.2f}"
    for sc in ['near-term', 'mature-market medium']:
        dry = build_dry(sc)
        write_scenario(dry, sc, f"{basedir}/{sc}")
    print(f"\nv2b data generation complete ({basedir}). Next: julia 01_MIP_v2b.jl [scenario]")
