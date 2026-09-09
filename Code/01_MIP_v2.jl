# ==============================================================================
# 01_MIP_v2.jl — Step 1: Facility Location MIP (S0 baseline, no carbon policy)
# ==============================================================================
# v2 rebuild (2026-09). Structural framework: Sampat et al. 2019 / Tominac 2022
# (multi-product market clearing; duals of mass balance = inherent values).
#
# v2 changes vs v1 (CodeWIFin):
#   * 39 technologies: 13 T1 dehydration + 13 T2-300C + 13 T2-500C
#   * 28 products: 13 wet + 13 dry + biochar(27) + carbon_credit(28)
#   * Step demand curve: segments H/M/L per county + sink rows (see demand_matrix)
#   * Carbon credit alpha rates are eligibility-gated (H/C <= 0.7, VM0044)
#     and unit-correct: CC = rho * C * permanence * 44/12 * yield  [tCO2/t_dry]
#   * No carbon policy here (S0). Policies implemented in 04/05/06.
#
# Usage: julia 01_MIP_v2.jl [scenario]   (scenario = near-term | mature-market medium)
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
# keyword overrides (v0.6): datadir=..., resdir=... (same convention as 04_policy_A.jl)
kw = Dict{String,String}()
for a in ARGS
    if occursin("=", a) && startswith(a, r"[a-z]")
        k, v = split(a, "=", limit=2)
        kw[k] = v
    end
end
datadir  = get(kw, "datadir", joinpath("biochar_data_v2", scen))
resdir   = get(kw, "resdir", joinpath("results_v2", scen))
mkpath(resdir)

println("="^78)
println("01_MIP_v2 | scenario = $scen | 39 technologies | 28 products")
println("="^78)

# ──────────────────────────────────────────────────────────────
# 1. LOAD MATRICES
# ──────────────────────────────────────────────────────────────
nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df  = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df  = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
tn_df   = CSV.read(joinpath(datadir, "technology_names.csv"), DataFrame)
ghg_df  = CSV.read(joinpath(datadir, "ghg_factors_v2.csv"), DataFrame)
alpha   = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

N      = Int.(nm[:,1])
P      = Int.(pm[:,1])
DS     = Int.(dem_df[:,1])
SS     = Int.(sup_df[:,1])
TECHS  = Int.(tech_df[:,1])
N_FS   = 13
BC_PROD = 2*N_FS + 1          # 27
CC_PROD = 2*N_FS + 2          # 28
SCL    = 1:3
af     = 0.1175

lat = Dict(zip(N, nm[:,3]));  lon = Dict(zip(N, nm[:,4]))
tvc = Dict(zip(P, pm[:,3]));  tfc = Dict(zip(P, pm[:,4]))
dnd = Dict(zip(DS, Int.(dem_df[:,2])));  dpr = Dict(zip(DS, Int.(dem_df[:,3])))
dbd = Dict(zip(DS, dem_df[:,5]));        dcp = Dict(zip(DS, dem_df[:,6]))
snd = Dict(zip(SS, Int.(sup_df[:,2])));  spr = Dict(zip(SS, Int.(sup_df[:,3])))
sbd = Dict(zip(SS, sup_df[:,5]));        scp = Dict(zip(SS, sup_df[:,6]))
trp = Dict(zip(TECHS, Int.(tech_df[:,3])))
top = Dict(zip(TECHS, tech_df[:,5]))     # OPEX $/t ref
tsz = Dict((TECHS[t],k) => tech_df[t,6+k] for t in 1:length(TECHS), k in SCL)
tcs = Dict((TECHS[t],k) => tech_df[t,9+k] for t in 1:length(TECHS), k in SCL)
tr  = Dict((TECHS[t], P[k]) => alpha[t,k] for t in 1:length(TECHS), k in 1:length(P))

# ──────────────────────────────────────────────────────────────
# 2. DISTANCES & ARCS
# ──────────────────────────────────────────────────────────────
Re = 6371.0
dists = Dict{Tuple{Int,Int}, Float64}()
for i in N, j in N
    dl = (lat[j]-lat[i])*pi/180; dn = (lon[j]-lon[i])*pi/180
    a = sin(dl/2)^2 + cos(lat[i]*pi/180)*cos(lat[j]*pi/180)*sin(dn/2)^2
    dists[(i,j)] = 2*Re*asin(sqrt(a))
end
MW, MD, MB = 150.0, 250.0, 400.0
arc_ok = Dict((i,j,p) => false for i in N, j in N, p in P)
for i in N, j in N
    d = dists[(i,j)]
    for f in 1:N_FS
        d <= MW && (arc_ok[(i,j,f)] = true)
        d <= MD && (arc_ok[(i,j,N_FS+f)] = true)
    end
    d <= MB && (arc_ok[(i,j,BC_PROD)] = true)
    arc_ok[(i,j,CC_PROD)] = (i == j)      # certificates: no physical arcs (zero cost AND zero transport GHG)
end

# ──────────────────────────────────────────────────────────────
# 3. MIP
# ──────────────────────────────────────────────────────────────
m = Model(Gurobi.Optimizer)
set_optimizer_attribute(m, "MIPGap", 0.01)        # 1% (tighten later on HPC)
set_optimizer_attribute(m, "TimeLimit", 1800)
set_optimizer_attribute(m, "MIPFocus", 1)         # prioritize feasible solutions
set_optimizer_attribute(m, "NoRelHeurTime", 60)
set_optimizer_attribute(m, "Threads", 8)
set_optimizer_attribute(m, "OutputFlag", 0)

@variable(m, f[i in N, j in N, p in P; arc_ok[(i,j,p)]] >= 0)
@variable(m, dem[DS] >= 0);  @variable(m, sup[SS] >= 0)
@variable(m, d[N,P] >= 0);   @variable(m, s[N,P] >= 0)
@variable(m, x[N,P,TECHS]);  @variable(m, pp[N,P])
@variable(m, z[N,TECHS,SCL] >= 0, Int)
@constraint(m, [i in N, t in TECHS, k in SCL], z[i,t,k] <= 5)

@constraint(m, dmeq[n in N, p in P],
    d[n,p] == sum(dem[dd] for dd in DS if dpr[dd]==p && dnd[dd]==n))
@constraint(m, smeq[n in N, p in P],
    s[n,p] == sum(sup[ss] for ss in SS if spr[ss]==p && snd[ss]==n))
@constraint(m, tfl[i in N, t in TECHS], x[i, trp[t], t] <= 0)
@constraint(m, yld[i in N, t in TECHS, p in P],
    x[i,p,t] == tr[(t,p)]/tr[(t, trp[t])] * x[i, trp[t], t])
@constraint(m, pfl[i in N, p in P], pp[i,p] == sum(x[i,p,t] for t in TECHS))
@constraint(m, bal[i in N, p in P],
    s[i,p] + pp[i,p] + sum(f[j,i,p] for j in N if arc_ok[(j,i,p)]) ==
    d[i,p] + sum(f[i,j,p] for j in N if arc_ok[(i,j,p)]))
@constraint(m, dcap[i in DS], dem[i] <= dcp[i])
@constraint(m, scap[i in SS], sup[i] <= scp[i])
@constraint(m, fcap[i in N, t in TECHS],
    -x[i, trp[t], t] <= sum(z[i,t,k] * tsz[(t,k)] for k in SCL))

@objective(m, Max,
    sum(dem[dd] * dbd[dd] for dd in DS)                                    # demand revenue (bid stack)
    - sum(sup[i] * sbd[i] for i in SS)                                     # farmgate cost
    - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)              # OPEX (x_ref <= 0)
    - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p]
          for i in N, j in N, p in P if arc_ok[(i,j,p)])                   # transport
    - af * sum(z[i,t,k] * tcs[(t,k)] for i in N, t in TECHS, k in SCL))    # CAPEX

optimize!(m)
status = termination_status(m)
println("MIP status: $status | objective: $(objective_value(m)/1e6) M\$/yr")
println("  solve time: $(solve_time(m)) s | gap: $(relative_gap(m))")

# ──────────────────────────────────────────────────────────────
# 4. RESULTS
# ──────────────────────────────────────────────────────────────
total_wet = sum(-value(x[i,t,t]) for i in N for t in 1:N_FS)
total_bc  = sum(value(x[i,BC_PROD,t]) for i in N for t in TECHS if t > N_FS)
bc_ag     = sum(value(dem[dd]) for dd in DS if dpr[dd] == BC_PROD && dem_df[dd,:segment] != "sink")
bc_sink   = sum(value(dem[dd]) for dd in DS if dpr[dd] == BC_PROD && dem_df[dd,:segment] == "sink")

n_t1 = sum(round(Int, value(z[i,t,k])) > 0 for i in N, t in 1:N_FS, k in SCL)
n_t2_300 = sum(round(Int, value(z[i,t,k])) > 0 for i in N, t in (N_FS+1):(2*N_FS), k in SCL)
n_t2_500 = sum(round(Int, value(z[i,t,k])) > 0 for i in N, t in (2*N_FS+1):(3*N_FS), k in SCL)

# net GHG (post-processing, consistent with 03_LP_GHG)
pghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,3]))
sghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,4] .+ ghg_df[:,5]))
gtv  = ghg_df[1,7]
proc_ghg = sum((-value(x[i,trp[t],t])) * pghg[t] for i in N, t in TECHS)
tran_ghg = sum(gtv * dists[(i,j)] * sum(value(f[i,j,p]) for p in P if arc_ok[(i,j,p)])
               for i in N, j in N if any(arc_ok[(i,j,p)] for p in P))
seq_ghg = sum(value(x[i,BC_PROD,t]) * sghg[t] for i in N, t in TECHS if t > N_FS)
net_ghg = proc_ghg + tran_ghg + seq_ghg
println("  [ghg parts] proc=", round(proc_ghg/1e6, digits=1), " tran=", round(tran_ghg/1e6, digits=1),
        " seq=", round(seq_ghg/1e6, digits=1), " kt")

# revenue / cost breakdown
bc_rev = sum(value(dem[dd]) * dbd[dd] for dd in DS if dpr[dd] == BC_PROD)
farm_c = sum(value(sup[i]) * sbd[i] for i in SS)
opex_c = sum(-value(x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
trn_c  = sum((tvc[p]*dists[(i,j)] + tfc[p]) * value(f[i,j,p])
             for i in N, j in N, p in P if arc_ok[(i,j,p)])
cap_c  = af * sum(value(z[i,t,k]) * tcs[(t,k)] for i in N, t in TECHS, k in SCL)

# feedstock mix
fs_mix = Float64[]
for fid in 1:N_FS
    push!(fs_mix, sum(-value(x[i,fid,fid]) for i in N))
end

# save z* (facility layout) for LP steps
z_rows = DataFrame(node=Int[], tech=Int[], scale=Int[], count=Int[])
for i in N, t in TECHS, k in SCL
    zi = round(Int, value(z[i,t,k]))
    if zi > 0
        push!(z_rows, (node=i, tech=t, scale=k, count=zi))
    end
end
CSV.write(joinpath(resdir, "z_star_MIP_v2.csv"), z_rows)

println("\n=== S0 BASELINE SUMMARY ($scen) ===")
println(@sprintf("  Objective (SWF):        %10.2f M\$/yr", objective_value(m)/1e6))
println(@sprintf("  Wet biomass processed:  %10.3f Mt/yr", total_wet/1e6))
println(@sprintf("  Biochar produced:       %10.3f Mt/yr  (ag %0.3f | sink %0.3f)", total_bc/1e6, bc_ag/1e6, bc_sink/1e6))
println(@sprintf("  Net GHG:                %10.2f Mt CO2e/yr", net_ghg/1e9))
println(@sprintf("  Facilities: T1=%d | T2-300=%d | T2-500=%d", n_t1, n_t2_300, n_t2_500))
println(@sprintf("  Revenue=%8.1fM | Farm=%7.1fM | OPEX=%7.1fM | Trans=%6.1fM | CAPEX=%6.1fM",
    bc_rev/1e6, farm_c/1e6, opex_c/1e6, trn_c/1e6, cap_c/1e6))

feedstock_names = [tn_df[t,:name] |> x -> replace(x, r"^T1_Dehyd_" => "") for t in 1:N_FS]
println("\n  Feedstock mix (wet kt):")
for fid in 1:N_FS
    if fs_mix[fid] > 1.0
        println(@sprintf("    %-24s %10.1f", feedstock_names[fid], fs_mix[fid]/1e3))
    end
end

open(joinpath(resdir, "S0_summary.txt"), "w") do io
    println(io, "01_MIP_v2 scenario=$scen status=$status")
    println(io, @sprintf("objective_M = %.2f", objective_value(m)/1e6))
    println(io, @sprintf("wet_Mt = %.3f", total_wet/1e6))
    println(io, @sprintf("bc_Mt = %.3f (ag %.3f, sink %.3f)", total_bc/1e6, bc_ag/1e6, bc_sink/1e6))
    println(io, @sprintf("net_ghg_Mt = %.3f", net_ghg/1e9))
    println(io, @sprintf("nT1 = %d, nT2_300 = %d, nT2_500 = %d", n_t1, n_t2_300, n_t2_500))
    println(io, @sprintf("revenue_M=%.1f farm_M=%.1f opex_M=%.1f trans_M=%.1f capex_M=%.1f",
        bc_rev/1e6, farm_c/1e6, opex_c/1e6, trn_c/1e6, cap_c/1e6))
    println(io, "feedstock_wet_kt = " * join([@sprintf("%s=%.1f", feedstock_names[fid], fs_mix[fid]/1e3) for fid in 1:N_FS], ", "))
end
println("\nSaved: $(joinpath(resdir, "z_star_MIP_v2.csv"))")
println("Saved: $(joinpath(resdir, "S0_summary.txt"))")
println("\nNext: julia 02_LP_duals_v2.jl $scen")
