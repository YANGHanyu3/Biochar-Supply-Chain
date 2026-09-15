# ==============================================================================
# v091_extras.jl — v0.9.1 follow-ups for two blocking review items, LP only.
#
# Part A (R1-M4): numeric dual ranges / left-right derivatives for Proposition 1.
#   The paper reported one bracket at a single cap; the review asked for the
#   degenerate-vertex intervals to be tabulated. For each gross cap on the B1
#   grid we re-solve at CAP +- 50 kt and report the dual interval.
#
# Part B (R1-M1): N2O factor sensitivity. The joint carbon grid covers the
#   decomposition fraction and permanence but holds N2O at 52 kg/t; here we
#   scale it by {0.5, 1.0, 1.5} on the fixed-layout LP at p_c = 200 $/t and
#   report profit, creditable quantity, and net flux.
#
# Usage: julia v091_extras.jl [scenario]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = "near-term"
for a in ARGS
    if !occursin("=", a); global scen = a; end
end
datadir = joinpath("biochar_data_v2", scen)
resdir  = joinpath("results_v2", scen)

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
pghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,3]))
seqghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,4]))
n2oghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,5]))
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

# alpha_cc[t, CC_PROD] is supplied per run (credit basis depends on the scenario).
# p_credit overrides the CC demand rows' bid (they carry bid 0 in the base data).
function build_lp(alpha_cc; p_credit=nothing)
    dbd_u = copy(dbd)
    if p_credit !== nothing
        for dd in DS
            if dpr[dd] == CC_PROD; dbd_u[dd] = p_credit; end
        end
    end
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
    @constraint(m, yld[i in N, t in TECHS, p in P], x[i,p,t] == alpha_cc[t,p]/alpha_cc[t, trp[t]] * x[i, trp[t], t])
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
    seq_ghg     = @expression(m, sum(x[i, BC_PROD, t] * seqghg[t] for i in N, t in TECHS if t > N_FS))
    n2o_ghg     = @expression(m, sum(x[i, BC_PROD, t] * n2oghg[t] for i in N, t in TECHS if t > N_FS))
    profit_ex = @expression(m,
        sum(dem[dd] * dbd_u[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * fix_capex)
    return m, profit_ex, process_ghg, trans_ghg, seq_ghg, n2o_ghg
end

α = copy(alpha0)   # canonical (no credit rows active in Part A)

# ════════════════════════════════════════════════════════════════════════════
# Part A — Prop 1 dual ranges (R1-M4)
# ════════════════════════════════════════════════════════════════════════════
println("="^100)
println("PART A: gross-cap dual ranges ($scen)  [fixed layout, dual simplex]")
println(@sprintf("%-11s %-11s %-11s %-11s %-11s %s",
    "CAP(kt)", "Pi(M\$)", "pi(\$/t)", "pi@-50", "pi@+50", "bracket width (% of |pi|)"))
println("-"^100)
m0, pr0, E0_, T0_, S0_, N0_ = build_lp(α)
@objective(m0, Max, pr0)
optimize!(m0)
E_base = value(E0_ + T0_)
rowsA = []
for frac in (1.00, 0.98, 0.95, 0.90, 0.80, 0.70)
    cap = frac * E_base
    m, pr, Ep, Tp, Sp, Np = build_lp(α)
    @constraint(m, cap_c, Ep + Tp <= cap)
    @objective(m, Max, pr); optimize!(m)
    pi_pt = has_duals(m) ? dual(cap_c) * 1000.0 : NaN
    lo, hi = NaN, NaN
    for (dc, tag) in ((-50.0e6, :lo), (50.0e6, :hi))
        mm, prr, Ep2, Tp2, Sp2, Np2 = build_lp(α)
        @constraint(mm, cc2, Ep2 + Tp2 <= cap + dc)
        @objective(mm, Max, prr); optimize!(mm)
        if termination_status(mm) == MOI.OPTIMAL && has_duals(mm)
            tag == :lo ? (lo = dual(cc2) * 1000.0) : (hi = dual(cc2) * 1000.0)
        end
    end
    width = (abs(hi - lo) / max(abs(pi_pt), 1e-9)) * 100.0
    push!(rowsA, (cap_kt=cap/1e6, profit_M=objective_value(m)/1e6,
                  pi_dollar_per_t=pi_pt, pi_at_minus50=lo, pi_at_plus50=hi,
                  bracket_pct=width, status=string(termination_status(m))))
    println(@sprintf("%-11.1f %-11.2f %-11.2f %-11.2f %-11.2f %.1f",
        cap/1e6, rowsA[end].profit_M, pi_pt, lo, hi, width))
end
CSV.write(joinpath(resdir, "prop1_dual_range_v2.csv"), DataFrame(rowsA))
println("Saved: prop1_dual_range_v2.csv")

# ════════════════════════════════════════════════════════════════════════════
# Part B — N2O factor sensitivity (R1-M1), fixed layout, p_c = 200 $/t
# ════════════════════════════════════════════════════════════════════════════
println("\n" * "="^100)
println("PART B: N2O factor sensitivity ($scen)  [fixed layout LP, p_c = 200 \$/t]")
println(@sprintf("%-10s %-11s %-9s %-9s %-9s %-9s %s",
    "N2O x", "Pi(M\$)", "BC(Mt)", "CC(Mt)", "Net(Mt)", "BC500", "status"))
println("-"^100)
P_C = 200.0
rowsB = []
for n2o_mult in (0.5, 1.0, 1.5)
    # Paradigm-A basis (no eligibility gate): every 300/500 C route co-produces
    # credits. This matters because the baseline layout holds only 300 C
    # capacity, and the C2 basis would gate 300 C credits to zero -- an N2O
    # sensitivity must therefore be run on the ungated basis.
    a_cc = copy(alpha0)
    for f in 1:N_FS
        t1 = f
        eta_f = alpha0[t1, N_FS + f]
        for t2x in (N_FS + f, 2*N_FS + f)
            y = alpha0[t2x, BC_PROD]
            b_ = bghg[t1] / eta_f
            e_ = pghg[t1] / eta_f + pghg[t2x]
            # |S| per t dry, positive: sequestration + N2O suppression, with the
            # N2O factor scaled (both terms are stored as negative numbers)
            s_pos = -(seqghg[t2x] + n2oghg[t2x] * n2o_mult) * y
            a_cc[t2x, CC_PROD] = (b_ - e_ + s_pos) / 1000.0
        end
    end
    m, pr, Ep, Tp, Sp, Np = build_lp(a_cc; p_credit=P_C)
    @objective(m, Max, pr)
    optimize!(m)
    bc = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    bc5 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > 2*N_FS)
    cc = sum(value(m[:x][i,CC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    net = value(Ep + Tp + Sp + Np)
    push!(rowsB, (n2o_mult=n2o_mult, profit_M=objective_value(m)/1e6, bc_Mt=bc/1e6,
                  cc_Mt=cc/1e6, net_Mt=net/1e9, bc500_Mt=bc5/1e6,
                  status=string(termination_status(m))))
    println(@sprintf("%-10.1f %-11.2f %-9.3f %-9.3f %-9.3f %-9.3f %s",
        n2o_mult, rowsB[end].profit_M, rowsB[end].bc_Mt, rowsB[end].cc_Mt,
        rowsB[end].net_Mt, rowsB[end].bc500_Mt, rowsB[end].status))
end
CSV.write(joinpath(resdir, "n2o_sensitivity_v2.csv"), DataFrame(rowsB))
println("Saved: n2o_sensitivity_v2.csv")
