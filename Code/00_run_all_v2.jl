# ==============================================================================
# 00_run_all_v2.jl — Master runner for the v2 Wisconsin biochar model
# ==============================================================================
# Usage:
#   julia 00_run_all_v2.jl [scenario]     # scenario: near-term | mature-market medium
#   julia 00_run_all_v2.jl [scenario] --skip-mip    # reuse existing z* (skip Step 1)
#
# Pipeline:
#   01_MIP_v2.jl          facility location (MIP, ~15-30 min)
#   02_LP_duals_v2.jl     profit LP + inherent values
#   03_LP_GHG_v2.jl       GHG LP + shadow prices
#   04_policy_A.jl        baseline-and-credit sweep (free-z MIP, ~1 h)
#   05_policy_B.jl        cap-and-trade + endogenous price (LP)
#   06_policy_C.jl        tiered tax + VM0044 + allocation (C2 free-z MIP)
# ==============================================================================
using Printf

scen = length(ARGS) > 0 && !startswith(ARGS[1], "-") ? ARGS[1] : "near-term"
skip_mip = "--skip-mip" in ARGS

steps = ["01_MIP_v2.jl", "02_LP_duals_v2.jl", "03_LP_GHG_v2.jl",
         "04_policy_A.jl", "05_policy_B.jl", "06_policy_C.jl"]

t_total = 0.0
for (i, s) in enumerate(steps)
    (skip_mip && i == 1) && (println("SKIP: $s"); continue)
    println("\n" * "="^78)
    println("RUNNING [$i/6] $s ($scen)")
    println("="^78)
    t0 = time()
    include(s)
    dt = time() - t0
    t_total += dt
    println(@sprintf("[%d/6] %s done in %.1f s", i, s, dt))
end
println("\n" * "="^78)
println(@sprintf("ALL STEPS COMPLETE in %.1f min (scenario = %s)", t_total/60, scen))
println("Results in results_v2/$scen/  |  Figures: python visualize_v2.py $scen")
