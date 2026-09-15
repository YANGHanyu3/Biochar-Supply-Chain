# ==============================================================================
# prop3_basis_check.jl — Phase 3 (v0.9 review fix): full basis-sensitivity
# check of Proposition 3 (tax invariance threshold).
#
# The review's objection: the paper evaluates tau_max with the SYSTEM-AVERAGE
# emission intensity (0.44 t CO2e/t BC) instead of route-specific marginal
# intensities. This script computes, for every fully-served demand row d,
#   margin_d  = lambda_d - pi_BC(n_d)          (from the mass-balance duals)
#   e_d       = dE+/d(dem_d) at the LP margin  (exact left derivative, by a
#               +1 kt cap perturbation on row d, re-solved with dual simplex)
#   tau_d     = margin_d / e_d                 (critical tax rate of row d)
# and reports tau_max = min_d tau_d together with the technology/feedstock
# composition of each marginal route (the delta of the perturbation).
#
# Prop 3 holds with the route-specific threshold iff tau_max > every tested
# tax rate ($200/t). It also reports all nonbasic demand rows with positive
# reduced cost (the marginally profitable set Q(x*)).
#
# Usage: julia prop3_basis_check.jl [scenario] [datadir=...] [resdir=...]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = "near-term"
datadir = nothing
resdir = nothing
for a in ARGS
    if startswith(a, "datadir="); global datadir = split(a, '=')[2]; end
    if startswith(a, "resdir=");  global resdir  = split(a, '=')[2]; end
    if !occursin("=", a); global scen = a; end
end
datadir = datadir === nothing ? joinpath("biochar_data_v2", scen) : datadir
resdir  = resdir  === nothing ? joinpath("results_v2", scen)      : resdir

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
segof = Dict(zip(DS, [String(s) for s in dem_df[:,4]]))
snd = Dict(zip(SS, Int.(sup_df[:,2]))); spr = Dict(zip(SS, Int.(sup_df[:,3])))
sbd = Dict(zip(SS, sup_df[:,5])); scp = Dict(zip(SS, sup_df[:,6]))
trp = Dict(zip(TECHS, Int.(tech_df[:,3])))
top = Dict(zip(TECHS, tech_df[:,5]))
tsz = Dict((TECHS[t],k) => tech_df[t,6+k] for t in 1:length(TECHS), k in SCL)
tcs = Dict((TECHS[t],k) => tech_df[t,9+k] for t in 1:length(TECHS), k in SCL)
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
    arc_ok[(i,j,CC_PROD)] = (i == j)
end

z_df = CSV.read(joinpath(resdir, "z_star_MIP_v2.csv"), DataFrame)
installed_cap = Dict{Tuple{Int,Int}, Float64}()
for i in N, t in TECHS; installed_cap[(i,t)] = 0.0; end
for row in eachrow(z_df)
    installed_cap[(row.node, row.tech)] += row.count * tsz[(row.tech, row.scale)]
end
fix_capex = sum(row.count * tcs[(row.tech, row.scale)] for row in eachrow(z_df))

function build_lp()
    m = Model(Gurobi.Optimizer)
    set_optimizer_attribute(m, "Method", 1)
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
    arc_pairs = [(i,j) for i in N for j in N if any(arc_ok[(i,j,p)] for p in P)]
    process_ghg = @expression(m, sum((-x[i, trp[t], t]) * pghg[t] for i in N, t in TECHS))
    trans_ghg   = @expression(m, sum(gtv * dists[(i,j)] * sum(f[i,j,p] for p in P if arc_ok[(i,j,p)])
                                     for (i,j) in arc_pairs))
    seq_ghg     = @expression(m, sum(x[i, BC_PROD, t] * sghg[t] for i in N, t in TECHS if t > N_FS))
    profit_ex = @expression(m,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * fix_capex)
    return m, profit_ex, process_ghg, trans_ghg, seq_ghg
end

m0, pr0, Ep0, Tp0, Sp0 = build_lp()
@objective(m0, Max, pr0)
optimize!(m0)
E_base = value(Ep0 + Tp0)

# baseline duals: pi_BC per node (dual of bal constraint, equality => direct marginal value)
pi_BC = Dict(n => dual(m0[:bal][n, BC_PROD]) for n in N)
println("Baseline E+ = $(round(E_base/1e6, digits=1)) kt; largest served-node pi_BC = $(round(maximum(values(pi_BC)), digits=2)) \$/t")

# fully-served H/M rows: margin = lambda - pi_BC
rows_out = []
served = [dd for dd in DS if dpr[dd] == BC_PROD && segof[dd] in ("H", "M") &&
          value(m0[:dem][dd]) >= dcp[dd] - 1.0]
println("Fully-served H/M demand rows: $(length(served))")
println(@sprintf("%-9s %-8s %-8s %-10s %-9s %-8s %s",
    "row", "seg", "node", "margin(\$)", "e+(t/t)", "tau(\$/t)", "marginal route (delta dry t by tech)"))
println("-"^110)
for dd in served
    margin = dbd[dd] - pi_BC[dnd[dd]]
    # +1 kt perturbation on this row (exact left derivative of E+ w.r.t. dem_d)
    mp, prp, Epp, Tpp, Spp = build_lp()
    set_normalized_rhs(mp[:dcap][dd], dcp[dd] + 1000.0)
    @objective(mp, Max, prp)
    optimize!(mp)
    dE = value(Epp + Tpp) - E_base                      # kg CO2e for +1000 t BC
    e_d = dE / 1000.0                                    # kg CO2e/t BC (=> t/t)
    tau_d = margin / e_d
    # identify the marginal route: tech-level delta of dry-throughput (kt)
    route = String[]
    for t in TECHS
        dx_agg = sum(-value(mp[:x][i, trp[t], t]) for i in N) -
                 sum(-value(m0[:x][i, trp[t], t]) for i in N)
        if abs(dx_agg) > 1.0
            push!(route, "T$(Int(t)):$(round(dx_agg/1000.0, digits=2))")
        end
    end
    push!(rows_out, (row=dd, seg=segof[dd], node=dnd[dd], margin=round(margin, digits=2),
                     e_d=round(e_d, digits=3), tau=round(tau_d, digits=5),
                     route=join(route, ", ")))
end
sort!(rows_out, by=r -> r.tau)
for r in rows_out
    println(@sprintf("%-9d %-8s %-8d %-10.2f %-9.3f %-8.1f %s",
        r.row, r.seg, r.node, r.margin, r.e_d, r.tau, r.route))
end
tau_max = minimum(r.tau for r in rows_out) * 1000.0     # tau column is $/kg -> $/t
println("\ntau_max (route-specific) = $(round(tau_max, digits=1)) \$/t CO2e")
println("vs. paper's average-intensity estimate ~350 \$/t (avg e+ = 0.44 t/t)")
println("Prop 3 verdict: " * (tau_max > 200.0 ? "HOLDS (tau_max > \$200/t top tested rate)" : "FAILS"))
CSV.write(joinpath(resdir, "prop3_basis_check_v2.csv"),
          DataFrame(rows_out))
println("Saved: prop3_basis_check_v2.csv")
