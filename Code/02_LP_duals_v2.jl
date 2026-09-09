# ==============================================================================
# 02_LP_duals_v2.jl — Step 2: LP Profit Maximization + Inherent Value Duals
# ==============================================================================
# v2 rebuild. Fixes z* from Step 1, solves LP (barrier), extracts duals of the
# mass-balance constraints -> spatial inherent values pi[n,p] (Sampat 2019).
# Duals are only read HERE in LP mode (never in the MIP) — v1 bug fixed.
#
# Usage: julia 02_LP_duals_v2.jl [scenario]
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
datadir = get(kw, "datadir", joinpath("biochar_data_v2", scen))
resdir  = get(kw, "resdir", joinpath("results_v2", scen))
mkpath(resdir)

# load matrices (same as 01)
nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df  = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df  = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
tn_df   = CSV.read(joinpath(datadir, "technology_names.csv"), DataFrame)
alpha   = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

N = Int.(nm[:,1]); P = Int.(pm[:,1]); DS = Int.(dem_df[:,1]); SS = Int.(sup_df[:,1])
TECHS = Int.(tech_df[:,1])
N_FS = 13; BC_PROD = 2*N_FS+1; CC_PROD = 2*N_FS+2; SCL = 1:3
af = 0.1175

lat = Dict(zip(N, nm[:,3])); lon = Dict(zip(N, nm[:,4]))
tvc = Dict(zip(P, pm[:,3])); tfc = Dict(zip(P, pm[:,4]))
dnd = Dict(zip(DS, Int.(dem_df[:,2]))); dpr = Dict(zip(DS, Int.(dem_df[:,3])))
dbd = Dict(zip(DS, dem_df[:,5])); dcp = Dict(zip(DS, dem_df[:,6]))
snd = Dict(zip(SS, Int.(sup_df[:,2]))); spr = Dict(zip(SS, Int.(sup_df[:,3])))
sbd = Dict(zip(SS, sup_df[:,5])); scp = Dict(zip(SS, sup_df[:,6]))
trp = Dict(zip(TECHS, Int.(tech_df[:,3])))
top = Dict(zip(TECHS, tech_df[:,5]))
tsz = Dict((TECHS[t],k) => tech_df[t,6+k] for t in 1:length(TECHS), k in SCL)
tcs = Dict((TECHS[t],k) => tech_df[t,9+k] for t in 1:length(TECHS), k in SCL)
tr  = Dict((TECHS[t], P[k]) => alpha[t,k] for t in 1:length(TECHS), k in 1:length(P))

# distances
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
    arc_ok[(i,j,CC_PROD)] = (i == j)      # certificates: no physical transport
end

# load fixed facility layout z*
z_df = CSV.read(joinpath(resdir, "z_star_MIP_v2.csv"), DataFrame)
installed_cap = Dict{Tuple{Int,Int}, Float64}()
for i in N, t in TECHS
    installed_cap[(i,t)] = 0.0
end
for row in eachrow(z_df)
    installed_cap[(row.node, row.tech)] += row.count * tsz[(row.tech, row.scale)]
end
fix_capex = sum(row.count * tcs[(row.tech, row.scale)] for row in eachrow(z_df))

m = Model(Gurobi.Optimizer)
set_optimizer_attribute(m, "Method", 1)          # dual simplex: exact vertex duals (shadow prices)
set_optimizer_attribute(m, "OutputFlag", 0)

@variable(m, f[i in N, j in N, p in P; arc_ok[(i,j,p)]] >= 0)
@variable(m, dem[DS] >= 0); @variable(m, sup[SS] >= 0)
@variable(m, d[N,P] >= 0);  @variable(m, s[N,P] >= 0)
@variable(m, x[N,P,TECHS]); @variable(m, pp[N,P])

@constraint(m, dmeq[n in N, p in P], d[n,p] == sum(dem[dd] for dd in DS if dpr[dd]==p && dnd[dd]==n))
@constraint(m, smeq[n in N, p in P], s[n,p] == sum(sup[ss] for ss in SS if spr[ss]==p && snd[ss]==n))
@constraint(m, tfl[i in N, t in TECHS], x[i, trp[t], t] <= 0)
@constraint(m, yld[i in N, t in TECHS, p in P], x[i,p,t] == tr[(t,p)]/tr[(t, trp[t])] * x[i, trp[t], t])
@constraint(m, pfl[i in N, p in P], pp[i,p] == sum(x[i,p,t] for t in TECHS))
@constraint(m, bal[i in N, p in P],
    s[i,p] + pp[i,p] + sum(f[j,i,p] for j in N if arc_ok[(j,i,p)]) ==
    d[i,p] + sum(f[i,j,p] for j in N if arc_ok[(i,j,p)]))
@constraint(m, dcap[i in DS], dem[i] <= dcp[i])
@constraint(m, scap[i in SS], sup[i] <= scp[i])
@constraint(m, fcap[i in N, t in TECHS], -x[i, trp[t], t] <= installed_cap[(i,t)])

@objective(m, Max,
    sum(dem[dd] * dbd[dd] for dd in DS)
    - sum(sup[i] * sbd[i] for i in SS)
    - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
    - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
    - af * fix_capex)

optimize!(m)
println("LP status: $(termination_status(m)) | objective: $(objective_value(m)/1e6) M\$/yr")

# save equilibrium demand quantities (Step 2) -> 03 pins the GHG LP to these
# so that GHG shadow prices are marginal values AT the market equilibrium
dem_star = DataFrame(dem_id = DS, served = [value(dem[dd]) for dd in DS])
CSV.write(joinpath(resdir, "dem_star_v2.csv"), dem_star)

# ── inherent values (duals of bal) ──
iv_wet  = [dual(bal[i, f]) for i in N for f in 1:N_FS]
iv_bc   = [dual(bal[i, BC_PROD]) for i in N]
iv_rows = DataFrame(node=Int[], product=Int[], inherent_value=Float64[])
for i in N, f in 1:N_FS
    push!(iv_rows, (node=i, product=f, inherent_value=dual(bal[i,f])))
end
for i in N
    push!(iv_rows, (node=i, product=BC_PROD, inherent_value=dual(bal[i,BC_PROD])))
end
CSV.write(joinpath(resdir, "LP_duals_inherent_value_v2.csv"), iv_rows)

total_bc = sum(value(x[i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
bc_ag    = sum(value(dem[dd]) for dd in DS if dpr[dd] == BC_PROD && dem_df[dd,:segment] != "sink")
bc_sink  = sum(value(dem[dd]) for dd in DS if dpr[dd] == BC_PROD && dem_df[dd,:segment] == "sink")

# segment fill (how much of each demand step is served)
for seg in ("H", "M", "L", "sink")
    q = sum(value(dem[dd]) for dd in DS if dpr[dd] == BC_PROD && dem_df[dd,:segment] == seg)
    cap = sum(dcp[dd] for dd in DS if dpr[dd] == BC_PROD && dem_df[dd,:segment] == seg)
    println(@sprintf("  segment %-5s served %9.3f / %9.3f Mt", seg, q/1e6, cap/1e6))
end

println("\n=== STEP 2 SUMMARY ($scen) ===")
println(@sprintf("  Profit:          %10.2f M\$/yr", objective_value(m)/1e6))
println(@sprintf("  Biochar:         %10.3f Mt/yr (ag %.3f | sink %.3f)", total_bc/1e6, bc_ag/1e6, bc_sink/1e6))
v = filter(!isnan, iv_wet)
println(@sprintf("  IV wet biomass:  %8.1f .. %8.1f (mean %.1f) \$/t", minimum(v), maximum(v), sum(v)/length(v)))
v2 = filter(!isnan, iv_bc)
println(@sprintf("  IV biochar:      %8.1f .. %8.1f (mean %.1f) \$/t", minimum(v2), maximum(v2), sum(v2)/length(v2)))

open(joinpath(resdir, "S2_summary.txt"), "w") do io
    println(io, "02_LP_duals_v2 scenario=$scen status=$(termination_status(m))")
    println(io, @sprintf("profit_M = %.2f", objective_value(m)/1e6))
    println(io, @sprintf("bc_Mt = %.3f (ag %.3f, sink %.3f)", total_bc/1e6, bc_ag/1e6, bc_sink/1e6))
    println(io, @sprintf("iv_wet_min=%.2f iv_wet_max=%.2f iv_wet_mean=%.2f", minimum(v), maximum(v), sum(v)/length(v)))
    println(io, @sprintf("iv_bc_min=%.2f iv_bc_max=%.2f iv_bc_mean=%.2f", minimum(v2), maximum(v2), sum(v2)/length(v2)))
end
println("Saved: LP_duals_inherent_value_v2.csv | S2_summary.txt")
