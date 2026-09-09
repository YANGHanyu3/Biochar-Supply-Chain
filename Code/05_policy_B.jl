# ==============================================================================
# 05_policy_B.jl — Paradigm B: Cap-and-Trade with ENDOGENOUS clearing price
# ==============================================================================
# v2 rebuild. THE core methodological contribution:
#   * B1: gross-emissions cap   E+ <= CAP  (sweep CAP)
#         LP (fixed z*) -> dual of the cap constraint = ENDOGENOUS carbon price
#         pi_CAP = d Pi* / d CAP  (marginal cost of the cap = MAC curve)
#         Compare pi_CAP with RGGI ($17-25), EU ETS (EUR 50-90), CCA ($30-40).
#   * B2: net-emissions cap     E+ + S <= CAP_net
#         With biochar sequestration S<0, net is always negative -> constraint
#         never binds -> proves "net caps are blind to negative emissions".
#   * B3 (optional extension): allowances + trading (exogenous allowance price)
#
# Contrast with v1 (CodeWIFin): v1 set cc_mkt_price = carbon_price (a fake
# "market clearing"). Here the price EMERGES from the model as a dual.
#
# Usage: julia 05_policy_B.jl [scenario]
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
    arc_ok[(i,j,CC_PROD)] = (i == j)      # certificates: no physical transport
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

# ──────────────────────────────────────────────────────────────
# B1: GROSS EMISSIONS CAP SWEEP -> endogenous carbon price (dual)
# ──────────────────────────────────────────────────────────────
# baseline gross emissions first (no cap)
m0, pr0, E0_, T0_, S0_ = build_lp()
@objective(m0, Max, pr0)
optimize!(m0)
E_base = value(E0_ + T0_)
println("Baseline gross emissions E+ = $(round(E_base/1e6, digits=1)) kt CO2e/yr")

# caps include NON-BINDING points above baseline (1.05/1.02/1.00 x E_base):
# dual = 0 there -> the MAC curve's horizontal zero segment is explicit.
# (v0.3 review fix: previously the sweep started at 0.98 x E_base, so the
#  figure could not show where abatement = 0.)
caps = [1.05, 1.02, 1.00, 0.98, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.60, 0.50] .* E_base
println("\n" * "="^100)
println("PARADIGM B1: GROSS-EMISSION CAP SWEEP ($scen)  [endogenous price = dual of cap]")
println(@sprintf("%-12s %-12s %-12s %-12s %-9s %s",
    "Cap(kt)", "Pi(M\$)", "E+(kt)", "BC(Mt)", "pi_cap", "status"))
println("-"^100)
rows = []
for cap in caps
    m, pr, Ep, Tp, Sp = build_lp()
    @constraint(m, cap_c, Ep + Tp <= cap)
    @objective(m, Max, pr)
    optimize!(m)
    # dual is $ per kg CO2e (constraint in kg, objective in $) -> $/t by *1000.
    # Gurobi's sign convention for a <= constraint in a MAXIMIZATION problem
    # reports the NEGATIVE of the marginal value: pi_dual = -d Pi / d CAP.
    # The endogenous carbon price is therefore -pi_dual, which matches the
    # finite-difference MAC (pi_fd) to numerical tolerance.
    pi_cap = has_duals(m) ? dual(cap_c) * 1000.0 : NaN     # $ per t CO2e (negative-valued)
    total_bc = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    push!(rows, (cap=cap/1e6, profit=objective_value(m)/1e6,
                 emis=value(Ep+Tp)/1e6, bc=total_bc/1e6,
                 pi=pi_cap, status=string(termination_status(m))))
    println(@sprintf("%-12.0f %-12.2f %-12.1f %-12.3f %-9.2f %s",
        cap/1e6, rows[end].profit, rows[end].emis, rows[end].bc, pi_cap, rows[end].status))
end
CSV.write(joinpath(resdir, "policy_B1_cap_sweep_v2.csv"), DataFrame(rows))
# finite-difference marginal abatement cost (robust, for MAC figure)
pi_fd = [NaN]
for i in 2:length(rows)
    dpi = (rows[i].profit - rows[i-1].profit) / (rows[i].cap - rows[i-1].cap)
    push!(pi_fd, 1000.0 * dpi)      # $/t CO2e (profit in M$, cap in kt)
end
df_mac = DataFrame(cap_kt = [r.cap for r in rows],
                   profit_M = [r.profit for r in rows],
                   emis_kt = [r.emis for r in rows],
                   bc_Mt = [r.bc for r in rows],
                   pi_dual = [r.pi for r in rows],
                   pi_fd_dollar_per_t = pi_fd,
                   status = [r.status for r in rows])
CSV.write(joinpath(resdir, "policy_B1_cap_sweep_MAC_v2.csv"), df_mac)
println("Saved: policy_B1_cap_sweep_v2.csv | policy_B1_cap_sweep_MAC_v2.csv (finite-difference price)")

# ──────────────────────────────────────────────────────────────
# B2: NET EMISSIONS CAP (proves net caps are blind to negative emissions)
# ──────────────────────────────────────────────────────────────
println("\n" * "="^100)
println("PARADIGM B2: NET-EMISSION CAP SWEEP  [E+ + S <= CAP_net]")
net_base = value(S0_) + E_base
println("Baseline net GHG = $(round(net_base/1e6, digits=1)) kt (negative => cap never binds)")
println(@sprintf("%-14s %-12s %-12s %-12s %-9s %s", "Cap_net(kt)", "Pi(M\$)", "Net(kt)", "BC(Mt)", "pi", "status"))
println("-"^100)
rows2 = []
for cap_net in [-2000.0e6, -1000.0e6, 0.0e6, 500.0e6, 1000.0e6]
    m, pr, Ep, Tp, Sp = build_lp()
    @constraint(m, cap_c, Ep + Tp + Sp <= cap_net)
    @objective(m, Max, pr)
    optimize!(m)
    st = termination_status(m)
    if st == MOI.OPTIMAL
        total_bc = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
        pi_cap = has_duals(m) ? dual(cap_c) * 1000.0 : NaN   # kg -> $/t, same convention as B1
        push!(rows2, (cap_net=cap_net/1e6, profit=objective_value(m)/1e6,
                      net=value(Ep+Tp+Sp)/1e6, bc=total_bc/1e6, pi=pi_cap,
                      status=string(st)))
        println(@sprintf("%-14.0f %-12.2f %-12.1f %-12.3f %-9.2f %s",
            cap_net/1e6, rows2[end].profit, rows2[end].net, rows2[end].bc, pi_cap, rows2[end].status))
    else
        push!(rows2, (cap_net=cap_net/1e6, profit=NaN, net=NaN, bc=NaN, pi=NaN, status=string(st)))
        println(@sprintf("%-14.0f %-12s %-12s %-12s %-9s %s",
            cap_net/1e6, "-", "-", "-", "-", string(st)))
    end
end
CSV.write(joinpath(resdir, "policy_B2_netcap_sweep_v2.csv"), DataFrame(rows2))
println("\nSaved: policy_B1_cap_sweep_v2.csv | policy_B2_netcap_sweep_v2.csv")
println("Next: julia 06_policy_C.jl $scen")
