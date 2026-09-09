# ==============================================================================
# 07_sensitivity_v2.jl — Sensitivity analysis (LP, fixed z*)
# ==============================================================================
# One-at-a-time sensitivity of the baseline (S0) solution:
#   farmgate price   x {0.8, 1.0, 1.2}
#   transport cost   x {0.8, 1.2}
#   demand capacity  x {0.8, 1.2}   (all BC segments scaled)
#   demand price     x {0.8, 1.2}   (all segment bids scaled)
#   sink price       x {0, 30, 60}
# Outputs: profit, BC, net GHG. LP with fixed z* (seconds per case).
# Usage: julia 07_sensitivity_v2.jl [scenario]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
datadir = joinpath("biochar_data_v2", scen)
resdir  = joinpath("results_v2", scen)

nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df0 = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df0 = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
ghg_df  = CSV.read(joinpath(datadir, "ghg_factors_v2.csv"), DataFrame)
alpha   = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

N = Int.(nm[:,1]); P = Int.(pm[:,1]); SS = Int.(sup_df0[:,1])
TECHS = Int.(tech_df[:,1])
N_FS = 13; BC_PROD = 2*N_FS+1; CC_PROD = 2*N_FS+2; SCL = 1:3
af = 0.1175

lat = Dict(zip(N, nm[:,3])); lon = Dict(zip(N, nm[:,4]))
tvc0 = Dict(zip(P, pm[:,3])); tfc0 = Dict(zip(P, pm[:,4]))
snd = Dict(zip(SS, Int.(sup_df0[:,2]))); spr = Dict(zip(SS, Int.(sup_df0[:,3])))
sbd0 = Dict(zip(SS, sup_df0[:,5])); scp = Dict(zip(SS, sup_df0[:,6]))
trp = Dict(zip(TECHS, Int.(tech_df[:,3])))
top = Dict(zip(TECHS, tech_df[:,5]))
tsz = Dict((TECHS[t],k) => tech_df[t,6+k] for t in 1:length(TECHS), k in SCL)
tr  = Dict((TECHS[t], P[k]) => alpha[t,k] for t in 1:length(TECHS), k in 1:length(P))
pghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,3]))
sghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,4] .+ ghg_df[:,5]))
gtv  = ghg_df[1,7]

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

z_df = CSV.read(joinpath(resdir, "z_star_MIP_v2.csv"), DataFrame)
installed_cap = Dict{Tuple{Int,Int}, Float64}()
for i in N, t in TECHS; installed_cap[(i,t)] = 0.0; end
for row in eachrow(z_df)
    installed_cap[(row.node, row.tech)] += row.count * tsz[(row.tech, row.scale)]
end
# note: fix_capex is the UNannualized CAPEX; the objective applies af exactly once
# (v2.1 fix: previously af appeared both here and in the objective -> double af)
fix_capex = sum(row.count * tech_df[row.tech, 9 + row.scale] for row in eachrow(z_df))

function solve_case(farm_mult, trans_mult, cap_mult, price_mult, sink_val, sup_mult)
    dem_df = copy(dem_df0)
    sup_df = copy(sup_df0)
    # apply multipliers
    is_sink = dem_df[:,4] .== "sink"
    dem_df[:,5] = dem_df[:,5] .* ifelse.(is_sink, 1.0, price_mult)
    dem_df[is_sink, 5] .= sink_val
    dem_df[:,6] = dem_df[:,6] .* ifelse.(is_sink, 1.0, cap_mult)
    sup_df[:,5] = sup_df[:,5] .* farm_mult
    sup_df[:,6] = sup_df[:,6] .* sup_mult
    tvc = Dict(zip(P, pm[:,3] .* trans_mult)); tfc = Dict(zip(P, pm[:,4] .* trans_mult))
    scp2 = Dict(zip(SS, sup_df[:,6]))

    DS = Int.(dem_df[:,1])
    dnd = Dict(zip(DS, Int.(dem_df[:,2]))); dpr = Dict(zip(DS, Int.(dem_df[:,3])))
    dbd = Dict(zip(DS, dem_df[:,5])); dcp = Dict(zip(DS, dem_df[:,6]))
    sbd = Dict(zip(SS, sup_df[:,5]))

    m = Model(Gurobi.Optimizer)
    set_optimizer_attribute(m, "Method", 1)          # dual simplex: exact vertex duals
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
    @constraint(m, scap[i in SS], sup[i] <= scp2[i])
    @constraint(m, fcap[i in N, t in TECHS], -x[i, trp[t], t] <= installed_cap[(i,t)])
    @objective(m, Max,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * fix_capex)
    optimize!(m)
    bc = sum(value(x[i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    proc = sum((-value(x[i,trp[t],t])) * pghg[t] for i in N, t in TECHS)
    tran = sum(gtv * dists[(i,j)] * sum(value(f[i,j,p]) for p in P if arc_ok[(i,j,p)])
               for i in N, j in N if any(arc_ok[(i,j,p)] for p in P))
    seqg = sum(value(x[i,BC_PROD,t]) * sghg[t] for i in N, t in TECHS if t > N_FS)
    (; profit_M=objective_value(m)/1e6, bc_Mt=bc/1e6, ghg_Mt=(proc+tran+seqg)/1e9,
       status=string(termination_status(m)))
end

println("SENSITIVITY ANALYSIS ($scen) — LP with fixed z*")
cases = [
    ("baseline", 1.0, 1.0, 1.0, 1.0, 30.0, 1.0),
    ("farmgate -20%", 0.8, 1.0, 1.0, 1.0, 30.0, 1.0),
    ("farmgate +20%", 1.2, 1.0, 1.0, 1.0, 30.0, 1.0),
    ("farmgate +100%", 2.0, 1.0, 1.0, 1.0, 30.0, 1.0),
    ("transport -20%", 1.0, 0.8, 1.0, 1.0, 30.0, 1.0),
    ("transport +20%", 1.0, 1.2, 1.0, 1.0, 30.0, 1.0),
    ("demand cap -20%", 1.0, 1.0, 0.8, 1.0, 30.0, 1.0),
    ("demand cap +20%", 1.0, 1.0, 1.2, 1.0, 30.0, 1.0),
    ("demand price -20%", 1.0, 1.0, 1.0, 0.8, 30.0, 1.0),
    ("demand price +20%", 1.0, 1.0, 1.0, 1.2, 30.0, 1.0),
    ("sink \$0", 1.0, 1.0, 1.0, 1.0, 0.0, 1.0),
    ("sink \$60", 1.0, 1.0, 1.0, 1.0, 60.0, 1.0),
    ("supply cap -40%", 1.0, 1.0, 1.0, 1.0, 30.0, 0.6),
]
println(@sprintf("%-18s %-12s %-10s %-10s %s", "case", "Profit(M\$)", "BC(Mt)", "GHG(Mt)", "status"))
rows = []
for (name, fm, tm, cm, pm_, sv, sm) in cases
    r = solve_case(fm, tm, cm, pm_, sv, sm)
    push!(rows, (case=name, profit_M=r.profit_M, bc_Mt=r.bc_Mt, ghg_Mt=r.ghg_Mt, status=r.status))
    println(@sprintf("%-18s %-12.2f %-10.3f %-10.3f %s", name, r.profit_M, r.bc_Mt, r.ghg_Mt, r.status))
end
CSV.write(joinpath(resdir, "sensitivity_v2.csv"), DataFrame(rows))
println("Saved: sensitivity_v2.csv")
