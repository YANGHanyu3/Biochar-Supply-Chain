# ==============================================================================
# 05c_carbon_grid.jl — E4 (v0.9 review fix): joint carbon-parameter scenarios,
# fixed-layout LP only (the cheap version agreed with the user).
#
# Grid: decomposition fraction {0.5, 0.7, 0.9} x permanence multiplier
# {0.8, 1.0, 1.2}, with Paradigm-A credit rows at p_c = 200 $/tCO2e and the
# baseline layout fixed. For each cell we recompute the CC co-production rates
#   rate = (b_mult*B - E+ + perm_mult*|S|)/1000     [tCC per t dry]
# (permanence scales sequestration only; decomposition scales the avoided
# baseline only; N2O untouched) and report profit, biochar, creditable
# quantity, net flux, and the 300/500 C mix.
#
# Usage: julia 05c_carbon_grid.jl [scenario] [datadir=...] [resdir=...]
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
alpha0  = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

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
tr  = Dict((TECHS[t], P[k]) => alpha0[t,k] for t in 1:length(TECHS), k in 1:length(P))
pghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,3]))
sghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,4] .+ ghg_df[:,5]))
bghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,8]))
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

function build_lp(alpha_cc)
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
    @constraint(m, yld[i in N, t in TECHS, p in P], x[i,p,t] == alpha_cc[t,p]/tr[(t, trp[t])] * x[i, trp[t], t])
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

P_C = 200.0
rows = []
println("E4 CARBON-PARAMETER GRID ($scen)  [fixed layout LP, p_c = $P_C \$/tCO2e]")
println(@sprintf("%-8s %-8s %-11s %-9s %-9s %-9s %-9s %-9s %s",
    "decomp", "perm", "Pi(M\$)", "BC(Mt)", "CC(Mt)", "BC300", "BC500", "Net(Mt)", "status"))
println("-"^96)
for decomp in (0.5, 0.7, 0.9), perm_mult in (0.8, 1.0, 1.2)
    b_mult = decomp / 0.9
    alpha_cc = copy(alpha0)
    for f in 1:N_FS
        t1 = f; t2 = N_FS + f; t2b = 2*N_FS + f
        eta_f = alpha0[t1, N_FS + f]
        for (t2x, tname) in ((t2, "300C"), (t2b, "500C"))
            y = alpha0[t2x, BC_PROD]
            b = bghg[t1] / eta_f * b_mult          # B per t dry (scaled decomp)
            e = pghg[t1] / eta_f + pghg[t2x]       # E+ per t dry
            s = -sghg[t2x] * y * perm_mult         # |S| per t dry (scaled permanence)
            # keep the canonical eligibility gating embedded in alpha0's CC column:
            # a zero CC rate in the canonical data means the char is ineligible,
            # and a joint scenario must not re-qualify it.
            canon = alpha0[t2x, CC_PROD]
            alpha_cc[t2x, CC_PROD] = canon > 1e-12 ? (b - e + s) / 1000.0 : 0.0
        end
    end
    m, pr, Ep, Tp, Sp = build_lp(alpha_cc)
    @objective(m, Max, pr)
    optimize!(m)
    st = termination_status(m)
    if st == MOI.OPTIMAL
        bc300 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if N_FS < t <= 2*N_FS)
        bc500 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > 2*N_FS)
        cc = sum(value(m[:x][i,CC_PROD,t]) for i in N, t in TECHS if t > N_FS)
        net = value(Ep + Tp + Sp)
        push!(rows, (decomp=decomp, perm_mult=perm_mult, profit=objective_value(m)/1e6,
                     bc=(bc300+bc500)/1e6, cc=cc/1e6, bc300=bc300/1e6, bc500=bc500/1e6,
                     net_Mt=net/1e9, status=string(st)))
        println(@sprintf("%-8.1f %-8.1f %-11.2f %-9.3f %-9.3f %-9.3f %-9.3f %-9.3f %s",
            decomp, perm_mult, rows[end].profit, rows[end].bc, rows[end].cc,
            rows[end].bc300, rows[end].bc500, rows[end].net_Mt, rows[end].status))
    else
        push!(rows, (decomp=decomp, perm_mult=perm_mult, profit=NaN, bc=NaN, cc=NaN,
                     bc300=NaN, bc500=NaN, net_Mt=NaN, status=string(st)))
    end
end
CSV.write(joinpath(resdir, "carbon_grid_v2.csv"), DataFrame(rows))
println("Saved: carbon_grid_v2.csv")
