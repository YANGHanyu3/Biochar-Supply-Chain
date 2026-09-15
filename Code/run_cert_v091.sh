#!/bin/bash
# run_cert_v091.sh — v0.9.1 certification batch (worst-gap points) + v2b Step-1 gap.
# All runs 7-thread, 45-s cooldowns between heavy solves (thermal headroom).
# Outputs are tagged so canonical CSVs are never overwritten.
cd "$(dirname "$0")"
JL="julia --project=."
LOG=v091_cert.log
exec > >(tee -a $LOG) 2>&1
COOL() { echo "--- cooldown 45s ---"; sleep 45; }
echo "=== v0.9.1 certification batch start: $(date) ==="

# 1) v2b Step-1 MIP: record gap + runtime into S0_summary.txt
echo "=== v2b Step-1 near-term (gap recording) ==="
$JL 01_MIP_v2b.jl near-term || echo "v2b step1 near FAILED"
COOL
echo "=== v2b Step-1 mature (gap recording) ==="
$JL 01_MIP_v2b.jl "mature-market medium" || echo "v2b step1 mature FAILED"
COOL

# 2) Canonical C2 near-term p=100 (3.91% gap)
echo "=== CERT: C2 near p=100 (7200s) ==="
$JL 06_policy_C.jl near-term prices=100 gap=0.001 timelimit=7200 tag=cert100 || echo "C2 near p100 FAILED"
COOL

# 3) v2b C2 near-term p=100 (4.18%) and p=150 (3.25%)
echo "=== CERT: v2b C2 near p=100,150 (7200s) ==="
$JL 06_policy_C_v2b.jl near-term prices=100,150 gap=0.001 timelimit=7200 tag=cert || echo "v2b C2 near FAILED"
COOL

# 4) v2b A near-term p=0 (3.34%) — cleaner no-policy baseline
echo "=== CERT: v2b A near p=0 (3600s) ==="
$JL 04_policy_A_v2b.jl near-term pc-only=0 gap=0.001 tl=3600 || echo "v2b A near p0 FAILED"
COOL

# 5) v2b A mature p=50 (3.34%)
echo "=== CERT: v2b A mature p=50 (3600s) ==="
$JL 04_policy_A_v2b.jl "mature-market medium" pc-only=50 gap=0.001 tl=3600 || echo "v2b A mature p50 FAILED"
COOL

echo "=== v0.9.1 certification batch end: $(date) ==="
