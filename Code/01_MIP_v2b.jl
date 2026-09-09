# ==============================================================================
# 01_MIP_v2b.jl — Step 1: Facility Location MIP (quality-differentiated v2b)
# ==============================================================================
# v2b: biochar split into BC300 (p=27) and BC500 (p=28); carbon credit p=29.
# Demand segments: H ($800) = BC500 only; M/L = both; sink = both.
# This makes the 300 vs 500 C technology choice a real economic tradeoff.
#
# Usage: julia 01_MIP_v2b.jl [scenario]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
datadir  = joinpath("biochar_data_v2b", scen)
resdir   = joinpath("results_v2b", scen)
mkpath(resdir)

println("="^78)
println("01_MIP_v2b (quality-differentiated) | scenario = $scen")
println("="^78)

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
BC300_PROD = 2*N_FS + 1          # 27
BC500_PROD = 2*N_FS + 2          # 28
CC_PROD    = 2*N_FS + 3          # 29
BC_PRODS   = (BC300_PROD, BC500_PROD)
SCL    = 1:3
af     = 0.1175

lat = Dict(zip(N, nm[:,3]));  lon = Dict(zip(N, nm[:,4]))
tvc = Dict(zip(P, pm[:,3]));  tfc = Dict(zip(P, pm[:,4]))
dnd = Dict(zip(DS, Int.(dem_df[:,2])));  dpr = Dict(zip(DS, Int.(dem_df[:,3])))
dbd = Dict(zip(DS, dem_df[:,5]));        dcp = Dict(zip(DS, dem_df[:,6]))
dseg = Dict(zip(DS, String.(dem_df[:,4])))
seg_df = CSV.read(joinpath(datadir, "segment_capacity.csv"), DataFrame)
seg_cap = Dict((Int(seg_df.node[i]), String(seg_df.segment[i])) => seg_df.capacity[i]
               for i in 1:nrow(seg_df))
snd = Dict(zip(SS, Int.(sup_df[:,2])));  spr = Dict(zip(SS, Int.(sup_df[:,3])))
sbd = Dict(zip(SS, sup_df[:,5]));        scp = Dict(zip(SS, sup_df[:,6]))
trp = Dict(zip(TECHS, Int.(tech_df[:,3])))
top = Dict(zip(TECHS, tech_df[:,5]))
tsz = Dict((TECHS[t],k) => tech_df[t,6+k] for t in 1:length(TECHS), k in SCL)
tcs = Dict((TECHS[t],k) => tech_df[t,9+k] for t in 1:length(TECHS), k in SCL)
tr  = Dict((TECHS[t], P[k]) => alpha[t,k] for t in 1:length(TECHS), k in 1:length(P))

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
    d <= MB && (arc_ok[(i,j,BC300_PROD)] = true)
    d <= MB && (arc_ok[(i,j,BC500_PROD)] = true)
    arc_ok[(i,j,CC_PROD)] = (i == j)      # certificates: no physical transport
end

m = Model(Gurobi.Optimizer)
set_optimizer_attribute(m, "MIPGap", 0.01)
set_optimizer_attribute(m, "TimeLimit", 1800)
set_optimizer_attribute(m, "MIPFocus", 1)
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
# shared segment capacity: free substitution of BC300/BC500 within a segment
@constraint(m, segcap[(n, sg) in keys(seg_cap)],
    sum(dem[dd] for dd in DS if dnd[dd]==n && dseg[dd]==sg) <= seg_cap[(n, sg)])
@constraint(m, scap[i in SS], sup[i] <= scp[i])
@constraint(m, fcap[i in N, t in TECHS],
    -x[i, trp[t], t] <= sum(z[i,t,k] * tsz[(t,k)] for k in SCL))

@objective(m, Max,
    sum(dem[dd] * dbd[dd] for dd in DS)
    - sum(sup[i] * sbd[i] for i in SS)
    - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
    - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p]
          for i in N, j in N, p in P if arc_ok[(i,j,p)])
    - af * sum(z[i,t,k] * tcs[(t,k)] for i in N, t in TECHS, k in SCL))

optimize!(m)
status = termination_status(m)
println("MIP status: $status | objective: $(objective_value(m)/1e6) M\$/yr")
println("  solve time: $(solve_time(m)) s | gap: $(relative_gap(m))")

total_wet = sum(-value(x[i,t,t]) for i in N for t in 1:N_FS)
bc300 = sum(value(x[i,BC300_PROD,t]) for i in N, t in TECHS if t > N_FS)
bc500 = sum(value(x[i,BC500_PROD,t]) for i in N, t in TECHS if t > N_FS)
total_bc = bc300 + bc500
bc_by_seg = Dict()
for seg in ("H","M","L","sink")
    bc_by_seg[seg] = sum(value(dem[dd]) for dd in DS if dem_df[dd,:segment] == seg &&
                          dpr[dd] in BC_PRODS)
end
n_t1 = sum(round(Int, value(z[i,t,k])) > 0 for i in N, t in 1:N_FS, k in SCL)
n_t2_300 = sum(round(Int, value(z[i,t,k])) > 0 for i in N, t in (N_FS+1):(2*N_FS), k in SCL)
n_t2_500 = sum(round(Int, value(z[i,t,k])) > 0 for i in N, t in (2*N_FS+1):(3*N_FS), k in SCL)

pghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,3]))
sghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,4] .+ ghg_df[:,5]))
gtv  = ghg_df[1,7]
proc_ghg = sum((-value(x[i,trp[t],t])) * pghg[t] for i in N, t in TECHS)
tran_ghg = sum(gtv * dists[(i,j)] * sum(value(f[i,j,p]) for p in P if arc_ok[(i,j,p)])
               for i in N, j in N if any(arc_ok[(i,j,p)] for p in P))
seq_ghg = sum(value(x[i,p,t]) * sghg[t] for i in N, p in BC_PRODS, t in TECHS if t > N_FS)
net_ghg = proc_ghg + tran_ghg + seq_ghg

bc_rev = sum(value(dem[dd]) * dbd[dd] for dd in DS if dpr[dd] in BC_PRODS)
farm_c = sum(value(sup[i]) * sbd[i] for i in SS)
opex_c = sum(-value(x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
trn_c  = sum((tvc[p]*dists[(i,j)] + tfc[p]) * value(f[i,j,p])
             for i in N, j in N, p in P if arc_ok[(i,j,p)])
cap_c  = af * sum(value(z[i,t,k]) * tcs[(t,k)] for i in N, t in TECHS, k in SCL)

z_rows = DataFrame(node=Int[], tech=Int[], scale=Int[], count=Int[])
for i in N, t in TECHS, k in SCL
    zi = round(Int, value(z[i,t,k]))
    if zi > 0
        push!(z_rows, (node=i, tech=t, scale=k, count=zi))
    end
end
CSV.write(joinpath(resdir, "z_star_MIP_v2b.csv"), z_rows)

println("\n=== S0 BASELINE SUMMARY ($scen, v2b) ===")
println(@sprintf("  Objective (SWF):        %10.2f M\$/yr", objective_value(m)/1e6))
println(@sprintf("  Wet biomass processed:  %10.3f Mt/yr", total_wet/1e6))
println(@sprintf("  Biochar: %0.3f Mt (BC300 %0.3f | BC500 %0.3f)", total_bc/1e6, bc300/1e6, bc500/1e6))
println(@sprintf("  Segments: H=%0.3f M=%0.3f L=%0.3f sink=%0.3f Mt", bc_by_seg["H"]/1e6,
        bc_by_seg["M"]/1e6, bc_by_seg["L"]/1e6, bc_by_seg["sink"]/1e6))
println(@sprintf("  Net GHG:                %10.2f Mt CO2e/yr", net_ghg/1e9))
println(@sprintf("  Facilities: T1=%d | T2-300=%d | T2-500=%d", n_t1, n_t2_300, n_t2_500))
println(@sprintf("  Revenue=%8.1fM | Farm=%7.1fM | OPEX=%7.1fM | Trans=%6.1fM | CAPEX=%6.1fM",
    bc_rev/1e6, farm_c/1e6, opex_c/1e6, trn_c/1e6, cap_c/1e6))

open(joinpath(resdir, "S0_summary.txt"), "w") do io
    println(io, "01_MIP_v2b scenario=$scen status=$status")
    println(io, @sprintf("objective_M = %.2f", objective_value(m)/1e6))
    println(io, @sprintf("wet_Mt = %.3f", total_wet/1e6))
    println(io, @sprintf("bc_Mt = %.3f (bc300 %.3f, bc500 %.3f)", total_bc/1e6, bc300/1e6, bc500/1e6))
    println(io, @sprintf("seg_H=%.3f seg_M=%.3f seg_L=%.3f sink=%.3f", bc_by_seg["H"]/1e6,
        bc_by_seg["M"]/1e6, bc_by_seg["L"]/1e6, bc_by_seg["sink"]/1e6))
    println(io, @sprintf("net_ghg_Mt = %.3f", net_ghg/1e9))
    println(io, @sprintf("nT1 = %d, nT2_300 = %d, nT2_500 = %d", n_t1, n_t2_300, n_t2_500))
    println(io, @sprintf("revenue_M=%.1f farm_M=%.1f opex_M=%.1f trans_M=%.1f capex_M=%.1f",
        bc_rev/1e6, farm_c/1e6, opex_c/1e6, trn_c/1e6, cap_c/1e6))
end
println("\nSaved: $(joinpath(resdir, "z_star_MIP_v2b.csv")) | S0_summary.txt")
