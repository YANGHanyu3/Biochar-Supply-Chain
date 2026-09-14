#!/bin/bash
# E4 (v2, MIP): joint carbon-parameter grid — free-facility MIP via 04_policy_A.jl
# decomp fraction {0.5,0.7,0.9} x permanence multiplier {0.8,1.0,1.2}, p_c=200 only.
# Fixed-layout version (05c) is superseded: the baseline layout has zero 500C
# capacity and saturated 300C, so a fixed layout cannot respond (constant output).
cd "$(dirname "$0")"
JL="julia --project=."
LOG=v09_experiments.log
exec > >(tee -a $LOG) 2>&1
echo "=== E4-MIP carbon grid (free-z) start: $(date) ==="
for decomp in 0.5 0.7 0.9; do
  for perm in 0.8 1.0 1.2; do
    tag="e4_d${decomp/./}_p${perm/./}"
    echo "=== E4-MIP decomp=$decomp perm=$perm ==="
    $JL 04_policy_A.jl near-term $decomp decomp-only perm=$perm timelimit=900 tag=$tag || echo "E4-MIP $tag FAILED"
  done
done
echo "=== E4-MIP carbon grid end: $(date) ==="
