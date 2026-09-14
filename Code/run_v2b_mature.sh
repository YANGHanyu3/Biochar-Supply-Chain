#!/bin/bash
# v2b gap reruns + mature-scenario fixups (direct, no polling)
cd "$(dirname "$0")"
JL="julia --project=."
LOG=v09_experiments.log
exec > >(tee -a $LOG) 2>&1
echo "=== v2b+mature chain start: $(date) ==="
echo "=== v2b A sweep near ==="
$JL 04_policy_A_v2b.jl near-term || echo "v2b A near FAILED"
echo "=== v2b A sweep mature ==="
$JL 04_policy_A_v2b.jl "mature-market medium" || echo "v2b A mature FAILED"
echo "=== v2b C2 sweep near ==="
$JL 06_policy_C_v2b.jl near-term || echo "v2b C2 near FAILED"
echo "=== v2b C2 sweep mature ==="
$JL 06_policy_C_v2b.jl "mature-market medium" || echo "v2b C2 mature FAILED"
echo "=== E2 mature frontier ==="
$JL 05b_netcap_frontier.jl "mature-market medium" || echo "E2 mature FAILED"
echo "=== Prop3 mature ==="
$JL prop3_basis_check.jl "mature-market medium" || echo "Prop3 mature FAILED"
echo "=== v2b+mature chain end: $(date) ==="
