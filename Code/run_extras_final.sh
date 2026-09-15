#!/bin/bash
# run_extras_final.sh — waits for the elastic chain, then re-runs the fixed
# v091_extras.jl for both scenarios (R1-M4 dual ranges + R1-M1 N2O).
# The heartbeat echo keeps this script from being reaped while it polls.
cd "$(dirname "$0")"
JL="julia --project=."
LOG=v091_cert.log
exec > >(tee -a $LOG) 2>&1
COOL() { echo "--- cooldown 45s ---"; sleep 45; }
echo "=== extras-final waiting for elastic chain: $(date) ==="
while ! grep -qa "extras2 end" $LOG; do
  echo "  [heartbeat $(date +%H:%M:%S)] waiting for elastic chain"
  sleep 120
done
echo "=== extras-final start: $(date) ==="
echo "=== R1-M4/R1-M1 near-term ==="
$JL v091_extras.jl near-term || echo "extras near FAILED"
COOL
echo "=== R1-M4/R1-M1 mature ==="
$JL v091_extras.jl "mature-market medium" || echo "extras mature FAILED"
echo "=== extras-final end: $(date) ==="
