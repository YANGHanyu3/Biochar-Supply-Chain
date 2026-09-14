#!/bin/bash
# =============================================================================
# run_v09_experiments.sh — v0.9 review-driven experiment chain (v3, thermal-safe)
# Sequential (Gurobi 7 threads per solve); 60-s cooldown pauses between heavy
# MIP blocks after the machine thermally tripped once (2026-09-14).
# Log: v09_experiments.log
# =============================================================================
cd "$(dirname "$0")"
JL="julia --project=."
PY="python"
LOG=v09_experiments.log
exec > >(tee -a $LOG) 2>&1
COOL() { echo "--- cooldown pause 60s (thermal headroom) ---"; sleep 60; }
echo "=== v0.9 experiment chain (v3 thermal-safe) start: $(date) ==="

# ── E2: net-cap frontier (fixed-z LP diagnostic + free-z MIP frontier + N_min)
echo "=== E2 near-term ==="
$JL 05b_netcap_frontier.jl near-term || echo "E2 near-term FAILED"
COOL
echo "=== E2 mature ==="
$JL 05b_netcap_frontier.jl "mature-market medium" || echo "E2 mature FAILED"
COOL

# ── Prop 3: route-specific basis sensitivity check (LP, fast)
echo "=== Prop3 check near-term ==="
$JL prop3_basis_check.jl near-term || echo "Prop3 near FAILED"
echo "=== Prop3 check mature ==="
$JL prop3_basis_check.jl "mature-market medium" || echo "Prop3 mature FAILED"
COOL

# ── E3: demand family (low / high / pricestress) — near-term; high also mature
for fam in low high pricestress; do
  echo "=== E3 $fam step1 ==="
  $JL 01_MIP_v2.jl near-term datadir=biochar_data_v2_df$fam/near-term resdir=results_v2_df$fam/near-term || echo "E3 $fam step1 FAILED"
  echo "=== E3 $fam step2 ==="
  $JL 02_LP_duals_v2.jl near-term datadir=biochar_data_v2_df$fam/near-term resdir=results_v2_df$fam/near-term || echo "E3 $fam step2 FAILED"
  echo "=== E3 $fam policyA ==="
  $JL 04_policy_A.jl near-term datadir=biochar_data_v2_df$fam/near-term resdir=results_v2_df$fam/near-term prices=25,100,200 tag=df$fam || echo "E3 $fam policyA FAILED"
  COOL
done
echo "=== E3 high mature (step1/2/policyA) ==="
$JL 01_MIP_v2.jl "mature-market medium" datadir="biochar_data_v2_dfhigh/mature-market medium" resdir="results_v2_dfhigh/mature-market medium" || echo "E3 high mature step1 FAILED"
$JL 02_LP_duals_v2.jl "mature-market medium" datadir="biochar_data_v2_dfhigh/mature-market medium" resdir="results_v2_dfhigh/mature-market medium" || echo "E3 high mature step2 FAILED"
$JL 04_policy_A.jl "mature-market medium" datadir="biochar_data_v2_dfhigh/mature-market medium" resdir="results_v2_dfhigh/mature-market medium" prices=25,100,200 tag=dfhigh || echo "E3 high mature policyA FAILED"
COOL

# ── E1: policy ablation — C2 without the H/C gate
echo "=== E1 gateoff near ==="
$JL 01_MIP_v2.jl near-term datadir=biochar_data_v2_gateoff/near-term resdir=results_v2_gateoff/near-term || echo "E1 step1 near FAILED"
$JL 06_policy_C.jl near-term datadir=biochar_data_v2_gateoff/near-term resdir=results_v2_gateoff/near-term prices=50,100,150,200 tag=gateoff || echo "E1 C2 near FAILED"
COOL
echo "=== E1 gateoff mature ==="
$JL 01_MIP_v2.jl "mature-market medium" datadir="biochar_data_v2_gateoff/mature-market medium" resdir="results_v2_gateoff/mature-market medium" || echo "E1 step1 mature FAILED"
$JL 06_policy_C.jl "mature-market medium" datadir="biochar_data_v2_gateoff/mature-market medium" resdir="results_v2_gateoff/mature-market medium" prices=50,100,150,200 tag=gateoff || echo "E1 C2 mature FAILED"
COOL

# ── E4: joint carbon-parameter grid (fixed-layout LP, fast)
echo "=== E4 carbon grid near-term ==="
$JL 05c_carbon_grid.jl near-term || echo "E4 near FAILED"
echo "=== E4 carbon grid mature ==="
$JL 05c_carbon_grid.jl "mature-market medium" || echo "E4 mature FAILED"
COOL

# ── E5: solver certification (trimmed: 2 seeds, 3-point reverse sweeps)
echo "=== E5 C2 near p=150 cert seeds 0,1 ==="
for s in 0 1; do
  $JL 06_policy_C.jl near-term prices=150 gap=0.001 timelimit=3600 seed=$s tag=certs$s || echo "E5 C2 near 150 seed$s FAILED"
  COOL
done
echo "=== E5 C2 mature p=150,200 cert ==="
$JL 06_policy_C.jl "mature-market medium" prices=150,200 gap=0.001 timelimit=3600 tag=cert || echo "E5 C2 mature cert FAILED"
COOL
echo "=== E5 A near p=25 cert ==="
$JL 04_policy_A.jl near-term prices=25 gap=0.001 timelimit=3600 tag=cert || echo "E5 A near 25 FAILED"
COOL
echo "=== E5 A near reverse sweep ==="
$JL 04_policy_A.jl near-term prices=200,100,25 gap=0.005 timelimit=1800 tag=certrev || echo "E5 A rev FAILED"
COOL
echo "=== E5 C2 near reverse sweep ==="
$JL 06_policy_C.jl near-term prices=200,100 gap=0.005 timelimit=1800 tag=certrev || echo "E5 C2 rev FAILED"
COOL
echo "=== E5 A mature p=100 recert (enriched) ==="
$JL 04_policy_A.jl "mature-market medium" prices=100 gap=0.001 timelimit=3600 tag=recert2 || echo "E5 A mature recert FAILED"
COOL

# ── Enriched canonical regeneration (exact cash-flow columns; tagged, no overwrite)
echo "=== Regen A sweep near ==="
$JL 04_policy_A.jl near-term prices=0,25,50,100,150,200 gap=0.005 timelimit=600 tag=regen || echo "Regen A near FAILED"
COOL
echo "=== Regen A sweep mature ==="
$JL 04_policy_A.jl "mature-market medium" prices=0,25,50,100,150,200 gap=0.005 timelimit=600 tag=regen || echo "Regen A mature FAILED"
COOL
echo "=== Regen C2 sweep near ==="
$JL 06_policy_C.jl near-term prices=50,100,150,200 gap=0.005 timelimit=600 tag=regen || echo "Regen C2 near FAILED"
COOL
echo "=== Regen C2 sweep mature ==="
$JL 06_policy_C.jl "mature-market medium" prices=50,100,150,200 gap=0.005 timelimit=600 tag=regen || echo "Regen C2 mature FAILED"
COOL

# ── Phase-1 accounting for canonical scenarios
for d in "near-term" "mature-market medium"; do
  $PY carbon_accounting.py "$d" || echo "accounting $d FAILED"
done

echo "=== v0.9 experiment chain (v3) end: $(date) ==="
