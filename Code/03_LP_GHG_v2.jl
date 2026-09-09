# ==============================================================================
# 03_LP_GHG_v2.jl — Step 3: LP GHG Minimization + GHG Shadow Prices
# ==============================================================================
# v2 rebuild. Same LP as Step 2 (fixed z*) with GHG objective.
# GHG accounting (kg CO2e/yr):
#   E+ = process (T1+T2, per t ref) + transport (per t-km)
#   S  = biochar sequestration (per t BC, tech-specific: 300C vs 500C differ)
#        + N2O suppression (per t BC)
#   net = E+ + S  (S < 0)
# Duals of mass balance = GHG shadow prices (marginal GHG of one more t at node)
#
# Usage: julia 03_LP_GHG_v2.jl [scenario]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
datadir = joinpath("biochar_data_v2", scen)
resdir  = joinpath("results_v2", scen)

nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df  = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df  = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
ghg_df  = CSV.read(joinpath(datadir, "ghg_factors_v2.csv"), DataFrame)
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
@constraint(m, scap[i in SS], sup[i] <= scp[i])
@constraint(m, fcap[i in N, t in TECHS], -x[i, trp[t], t] <= installed_cap[(i,t)])

# Pin demand at the Step-2 equilibrium quantities so that the GHG shadow
# prices below are marginal values AT the market equilibrium (not at the
# GHG-minimum dispatch).
demf_path = joinpath(resdir, "dem_star_v2.csv")
if isfile(demf_path)
    dfx = CSV.read(demf_path, DataFrame)
    demfix = Dict(Int(dfx.dem_id[i]) => dfx.served[i] for i in 1:nrow(dfx))
    @constraint(m, dfix[i in DS], dem[i] == demfix[i])
    println("  demand pinned to Step-2 equilibrium (", nrow(dfx), " rows)")
else
    println("  WARNING: dem_star_v2.csv missing - GHG LP runs free (not at equilibrium)")
end

# GHG expressions
arc_pairs = [(i,j) for i in N for j in N if any(arc_ok[(i,j,p)] for p in P)]
process_ghg = @expression(m, sum((-x[i, trp[t], t]) * pghg[t] for i in N, t in TECHS))
trans_ghg   = @expression(m, sum(gtv * dists[(i,j)] * sum(f[i,j,p] for p in P if arc_ok[(i,j,p)])
                                 for (i,j) in arc_pairs))
seq_ghg     = @expression(m, sum(x[i, BC_PROD, t] * sghg[t] for i in N, t in TECHS if t > N_FS))
net_ghg     = @expression(m, process_ghg + trans_ghg + seq_ghg)

@objective(m, Min, net_ghg)
optimize!(m)
println("GHG LP status: $(termination_status(m))")

if termination_status(m) != MOI.OPTIMAL
    # e.g. INFEASIBLE when dem_star was generated under a DIFFERENT z* layout:
    # rerun 02_LP_duals_v2.jl first so the pinned demand matches this layout.
    println("WARNING: GHG LP not optimal ($(termination_status(m))).")
    println("  If INFEASIBLE, dem_star_v2.csv is stale relative to z_star: rerun 02 first.")
    println("  Falling back to the FREE GHG-min LP (no demand pinning).")
    # remove the pinning constraint and re-solve free
    if haskey(m, :dfix)
        delete(m, m[:dfix])
        unregister(m, :dfix)
    end
    optimize!(m)
    println("Free GHG LP status: $(termination_status(m))")
end
st3 = termination_status(m)

println("\n=== STEP 3 SUMMARY ($scen) ===")
if st3 == MOI.OPTIMAL
println(@sprintf("  Net GHG:      %10.2f kt CO2e/yr = %.3f Mt", value(net_ghg)/1e6, value(net_ghg)/1e9))
println(@sprintf("    Process:    %10.2f kt", value(process_ghg)/1e6))
println(@sprintf("    Transport:  %10.2f kt", value(trans_ghg)/1e6))
println(@sprintf("    Sequestr.:  %10.2f kt", value(seq_ghg)/1e6))
total_bc = sum(value(x[i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
println(@sprintf("  Biochar:      %10.3f Mt/yr", total_bc/1e6))
else
total_bc = NaN
end

# GHG shadow prices (duals of bal) for biochar & wet biomass
if st3 == MOI.OPTIMAL
sh_rows = DataFrame(node=Int[], product=Int[], ghg_shadow_kg_per_t=Float64[])
for i in N, f in 1:N_FS
    push!(sh_rows, (node=i, product=f, ghg_shadow_kg_per_t=dual(bal[i,f])))
end
for i in N
    push!(sh_rows, (node=i, product=BC_PROD, ghg_shadow_kg_per_t=dual(bal[i,BC_PROD])))
end
CSV.write(joinpath(resdir, "LP_GHG_shadow_v2.csv"), sh_rows)

v_bc = [dual(bal[i, BC_PROD]) for i in N]
println(@sprintf("  GHG shadow BC:  %8.0f .. %8.0f kg CO2e/t", minimum(v_bc), maximum(v_bc)))
else
sh_rows = DataFrame(node=Int[], product=Int[], ghg_shadow_kg_per_t=Float64[])
CSV.write(joinpath(resdir, "LP_GHG_shadow_v2.csv"), sh_rows)
end

open(joinpath(resdir, "S3_summary.txt"), "w") do io
    println(io, "03_LP_GHG_v2 scenario=$scen status=$st3")
    if st3 == MOI.OPTIMAL
        println(io, @sprintf("net_ghg_kt = %.1f (proc %.1f, trans %.1f, seq %.1f)",
            value(net_ghg)/1e6, value(process_ghg)/1e6, value(trans_ghg)/1e6, value(seq_ghg)/1e6))
        println(io, @sprintf("bc_Mt = %.3f", total_bc/1e6))
    else
        println(io, "net_ghg_kt = NaN | bc_Mt = NaN (not optimal; rerun 02 then 03)")
    end
end
println("Saved: LP_GHG_shadow_v2.csv | S3_summary.txt")
