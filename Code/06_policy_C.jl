# ==============================================================================
# 06_policy_C.jl — Paradigm C: Tiered Carbon Tax + VM0044 Credit + Allocation
# ==============================================================================
# v2 rebuild. Three sub-experiments:
#   C1  Tiered (convex piecewise-linear) tax on GROSS emissions:
#       E+ = sum_k t_k,  0 <= t_k <= T_k,  rates r1 < r2 < r3
#       (tiers calibrated INSIDE the emissions range; v1's 5Mt threshold was
#        outside the value range, which silently collapsed the tiers)
#   C2  Tiered tax + VM0044 CDR credit:
#       CC co-production (alpha, eligibility-gated H/C<=0.7) sold at p_c.
#       -> tests whether crediting shifts T2-300 -> T2-500 (quality upgrade)
#   C3  Allowance allocation rules (grandfathering vs benchmarking):
#       max  Pi - p_allow * (E+ - A)
#       grandfathering:  A = E_base          (fixed, surplus sellable)
#       benchmarking:    A = beta * q_total  (scales with output -> expansion
#                                             incentive; Energy Policy/EJOR lit.)
#
# Usage: julia 06_policy_C.jl [scenario]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
# keyword args: datadir=..., tag=..., prices=50,200 (comma list, C2 only)
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
_tag    = get(kw, "tag", "")
_plist  = haskey(kw, "prices") ? [parse(Float64, p) for p in split(kw["prices"], ",")] : Float64[]
_tlimit = haskey(kw, "timelimit") ? parse(Float64, kw["timelimit"]) : 600.0
_seed   = haskey(kw, "seed") ? parse(Int, kw["seed"]) : nothing
_mgap   = haskey(kw, "gap") ? parse(Float64, kw["gap"]) : 0.005
sens_only = !isempty(_tag) || haskey(kw, "datadir")   # skip C1/C1-free/C3 (unchanged by H/C shift)

nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df  = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df  = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
ghg_df  = CSV.read(joinpath(datadir, "ghg_factors_v2.csv"), DataFrame)
alpha   = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

N = Int.(nm[:,1]); P = Int.(pm[:,1]); DS0 = Int.(dem_df[:,1]); SS = Int.(sup_df[:,1])
TECHS = Int.(tech_df[:,1])
N_FS = 13; BC_PROD = 2*N_FS+1; CC_PROD = 2*N_FS+2; SCL = 1:3
af = 0.1175

lat = Dict(zip(N, nm[:,3])); lon = Dict(zip(N, nm[:,4]))
tvc = Dict(zip(P, pm[:,3])); tfc = Dict(zip(P, pm[:,4]))
snd = Dict(zip(SS, Int.(sup_df[:,2]))); spr = Dict(zip(SS, Int.(sup_df[:,3])))
sbd = Dict(zip(SS, sup_df[:,5])); scp = Dict(zip(SS, sup_df[:,6]))
dnd0 = Dict(zip(DS0, Int.(dem_df[:,2]))); dpr0 = Dict(zip(DS0, Int.(dem_df[:,3])))
dbd0 = Dict(zip(DS0, dem_df[:,5])); dcp0 = Dict(zip(DS0, dem_df[:,6]))
seg0 = Dict(zip(DS0, [String(s) for s in dem_df[:,4]]))
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

# ── generic builder ──
function build(tier_lims, rates, p_credit, alloc_mode, p_allow, beta)
    # demand: base + CC rows if p_credit > 0
    dem_rows = DataFrame(dem_id=Int[], node=Int[], product=Int[], segment=String[],
                         bid=Float64[], capacity=Float64[])
    for row in eachrow(dem_df)
        push!(dem_rows, (dem_id=row.dem_id, node=row.node, product=row.product,
                         segment=String(row.segment), bid=row.bid, capacity=row.capacity))
    end
    cc_start = maximum(dem_rows.dem_id) + 1
    if p_credit > 0
        for i in N
            push!(dem_rows, (dem_id=cc_start + (i-1), node=i, product=CC_PROD,
                             segment="cc", bid=p_credit, capacity=1.0e12))
        end
    end
    DS = dem_rows.dem_id
    dnd = Dict(zip(DS, dem_rows.node)); dpr = Dict(zip(DS, dem_rows.product))
    dbd = Dict(zip(DS, dem_rows.bid)); dcp = Dict(zip(DS, dem_rows.capacity))

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
    Egross = @expression(m, process_ghg + trans_ghg)
    throughput = @expression(m, sum(-x[i, trp[t], t] for i in N, t in TECHS if t > N_FS))

    profit_ex = @expression(m,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * fix_capex)

    @objective(m, Max, profit_ex)   # caller overrides with policy terms
    return m, profit_ex, Egross, seq_ghg, throughput, process_ghg, trans_ghg
end

# ── FREE-Z MIP builder (for C2: policy can change facility layout & tech) ──
function build_mip(p_credit, z_warm; time_limit=_tlimit, mipgap=_mgap)
    dem_rows = DataFrame(dem_id=Int[], node=Int[], product=Int[], segment=String[],
                         bid=Float64[], capacity=Float64[])
    for row in eachrow(dem_df)
        push!(dem_rows, (dem_id=row.dem_id, node=row.node, product=row.product,
                         segment=String(row.segment), bid=row.bid, capacity=row.capacity))
    end
    for i in 1:nrow(dem_rows)
        if dem_rows[i, :segment] == "cc"
            dem_rows[i, :bid] = p_credit
        end
    end
    DS = dem_rows.dem_id
    dnd = Dict(zip(DS, dem_rows.node)); dpr = Dict(zip(DS, dem_rows.product))
    dbd = Dict(zip(DS, dem_rows.bid)); dcp = Dict(zip(DS, dem_rows.capacity))

    m = Model(Gurobi.Optimizer)
    set_optimizer_attribute(m, "TimeLimit", time_limit)
    set_optimizer_attribute(m, "MIPGap", mipgap)
    set_optimizer_attribute(m, "MIPFocus", 1)
    set_optimizer_attribute(m, "Threads", 7)   # 7/8 physical cores: thermal headroom
    set_optimizer_attribute(m, "OutputFlag", 0)
    _seed === nothing || set_optimizer_attribute(m, "Seed", _seed)
    @variable(m, f[i in N, j in N, p in P; arc_ok[(i,j,p)]] >= 0)
    @variable(m, dem[DS] >= 0); @variable(m, sup[SS] >= 0)
    @variable(m, d[N,P] >= 0);  @variable(m, s[N,P] >= 0)
    @variable(m, x[N,P,TECHS]); @variable(m, pp[N,P])
    @variable(m, z[N,TECHS,SCL] >= 0, Int)
    @constraint(m, [i in N, t in TECHS, k in SCL], z[i,t,k] <= 5)
    for i in N, t in TECHS, k in SCL
        zv = get(z_warm, (i,t,k), 0)
        if zv > 0
            set_start_value(z[i,t,k], zv)
        end
    end
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
    @constraint(m, fcap[i in N, t in TECHS],
        -x[i, trp[t], t] <= sum(z[i,t,k] * tsz[(t,k)] for k in SCL))

    arc_pairs = [(i,j) for i in N for j in N if any(arc_ok[(i,j,p)] for p in P)]
    process_ghg = @expression(m, sum((-x[i, trp[t], t]) * pghg[t] for i in N, t in TECHS))
    trans_ghg   = @expression(m, sum(gtv * dists[(i,j)] * sum(f[i,j,p] for p in P if arc_ok[(i,j,p)])
                                     for (i,j) in arc_pairs))
    seq_ghg     = @expression(m, sum(x[i, BC_PROD, t] * sghg[t] for i in N, t in TECHS if t > N_FS))
    Egross = @expression(m, process_ghg + trans_ghg)

    profit_ex = @expression(m,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * sum(z[i,t,k] * tcs[(t,k)] for i in N, t in TECHS, k in SCL))

    @objective(m, Max, profit_ex)
    return m, profit_ex, Egross, seq_ghg, process_ghg, trans_ghg
end

# ──────────────────────────────────────────────────────────────
# C1: tiered tax sweep (no credit)
# ──────────────────────────────────────────────────────────────
m0, pr0, E0, S0, q0, P0, T0 = build(Float64[], [0.0], 0.0, "none", 0.0, 0.0)
@objective(m0, Max, pr0)
optimize!(m0)
E_base = value(E0)
q_base = value(q0)
println("Baseline gross emissions: $(round(E_base/1e6, digits=1)) kt | throughput: $(round(q_base/1e6, digits=2)) Mt dry")

# tiers inside the range: [40%, 70%] of baseline
tier_lims = [0.40 * E_base, 0.70 * E_base]
rate_sets = [(25.0, 50.0, 100.0), (50.0, 100.0, 200.0), (25.0, 25.0, 25.0)]

if !sens_only
println("\n" * "="^100)
println("PARADIGM C1: TIERED TAX SWEEP ($scen)  tiers=[40%,70%] of baseline E+")
println(@sprintf("%-22s %-11s %-11s %-9s %-9s %-9s %s",
    "rates(r1,r2,r3)", "Pi(M\$)", "E+(kt)", "BC(Mt)", "t1(kt)", "t3(kt)", "status"))
println("-"^100)
rows1 = []
for (r1, r2, r3) in rate_sets
    m, pr, Eg, Sg, qg, Pg, Tg = build(tier_lims, [r1, r2, r3], 0.0, "none", 0.0, 0.0)
    @variable(m, tier[1:3] >= 0)
    @constraint(m, Eg == tier[1] + tier[2] + tier[3])
    @constraint(m, tier[1] <= tier_lims[1])
    @constraint(m, tier[2] <= tier_lims[2] - tier_lims[1])
    # no explicit fill-order constraints: with convex increasing rates any
    # solution using a higher tier before a lower one is never optimal (the
    # tax is minimized by filling low tiers first). For the flat rate set
    # (25,25,25) the tier decomposition is arbitrary but the tax total is
    # identical, so reported t1/t2/t3 there are notional.
    tax = @expression(m, (r1 * tier[1] + r2 * tier[2] + r3 * tier[3]) / 1000.0)
    @objective(m, Max, pr - tax)
    optimize!(m)
    total_bc = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    push!(rows1, (r1=r1, r2=r2, r3=r3, profit=objective_value(m)/1e6,
                  emis=value(Eg)/1e6, bc=total_bc/1e6,
                  t1=value(tier[1])/1e6, t2=value(tier[2])/1e6, t3=value(tier[3])/1e6,
                  status=string(termination_status(m))))
    println(@sprintf("%-22s %-11.2f %-11.1f %-9.3f %-9.1f %-9.1f %s",
        "($r1,$r2,$r3)", rows1[end].profit, rows1[end].emis, rows1[end].bc,
        rows1[end].t1, rows1[end].t3, rows1[end].status))
end
CSV.write(joinpath(resdir, "policy_C1_tiered_tax_v2.csv"), DataFrame(rows1))
end # !sens_only

# ──────────────────────────────────────────────────────────────
# C1-free: tiered tax with FREE facilities (MIP, warm-started) —
# robustness check that the fixed-layout approximation does not
# drive the C1 result (reviewer point: fixed z* may mask
# relocation / capacity responses to the tax). Note that the
# (25,25,25) rate set is a linear tax, so this also re-tests the
# "linear tax leaves the optimum unchanged" claim with free z.
# ──────────────────────────────────────────────────────────────
if !sens_only
println("\n" * "="^100)
println("PARADIGM C1-FREE: TIERED TAX WITH FREE FACILITIES ($scen)  [FREE-Z MIP]")
println(@sprintf("%-22s %-11s %-11s %-9s %-9s %-9s %s",
    "rates(r1,r2,r3)", "Pi(M\$)", "E+(kt)", "BC(Mt)", "nT1", "nT2", "status"))
println("-"^100)
rows1f = []
z_warm1f = Dict{Tuple{Int,Int,Int}, Int}()
for row in eachrow(z_df)
    z_warm1f[(row.node, row.tech, row.scale)] = row.count
end
for (r1, r2, r3) in rate_sets
    m, pr, Eg, Sg, Pg, Tg = build_mip(0.0, z_warm1f)
    @variable(m, tier[1:3] >= 0)
    @constraint(m, Eg == tier[1] + tier[2] + tier[3])
    @constraint(m, tier[1] <= tier_lims[1])
    @constraint(m, tier[2] <= tier_lims[2] - tier_lims[1])
    tax = @expression(m, (r1 * tier[1] + r2 * tier[2] + r3 * tier[3]) / 1000.0)
    @objective(m, Max, pr - tax)
    optimize!(m)
    total_bc = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    n_t1 = sum(round(Int, value(m[:z][i,t,k])) > 0 for i in N, t in 1:N_FS, k in SCL)
    n_t2 = sum(round(Int, value(m[:z][i,t,k])) > 0 for i in N, t in (N_FS+1):(3*N_FS), k in SCL)
    for i in N, t in TECHS, k in SCL
        z_warm1f[(i,t,k)] = round(Int, value(m[:z][i,t,k]))
    end
    push!(rows1f, (r1=r1, r2=r2, r3=r3, profit=objective_value(m)/1e6,
                   emis=value(Eg)/1e6, bc=total_bc/1e6,
                   nT1=n_t1, nT2=n_t2, gap=relative_gap(m),
                   status=string(termination_status(m))))
    println(@sprintf("%-22s %-11.2f %-11.1f %-9.3f %-9d %-9d %s",
        "($r1,$r2,$r3)", rows1f[end].profit, rows1f[end].emis, rows1f[end].bc,
        rows1f[end].nT1, rows1f[end].nT2, rows1f[end].status))
end
CSV.write(joinpath(resdir, "policy_C1_free_tax_v2.csv"), DataFrame(rows1f))
end # !sens_only

# ──────────────────────────────────────────────────────────────
# C2: tiered tax + VM0044 credit (FREE-Z MIP: policy can switch T2-300 -> T2-500
#     and expand facilities; warm-started from baseline layout)
# ──────────────────────────────────────────────────────────────
println("\n" * "="^100)
println("PARADIGM C2: TIERED TAX (25/50/100) + VM0044 CREDIT ($scen)  [FREE-Z MIP]" *
        (isempty(_tag) ? "" : "  [tag=$_tag]"))
println(@sprintf("%-8s %-11s %-11s %-9s %-9s %-9s %-9s %s",
    "p_c", "Pi(M\$)", "E+(kt)", "BC(Mt)", "CC(Mt)", "BC300", "BC500", "status"))
println("-"^100)
rows2 = []
z_warm = Dict{Tuple{Int,Int,Int}, Int}()
for row in eachrow(z_df)
    z_warm[(row.node, row.tech, row.scale)] = row.count
end
for p_c in (isempty(_plist) ? [50.0, 100.0, 150.0, 200.0] : _plist)
    m, pr, Eg, Sg, Pg, Tg = build_mip(p_c, z_warm)
    @variable(m, tier[1:3] >= 0)
    @constraint(m, Eg == tier[1] + tier[2] + tier[3])
    @constraint(m, tier[1] <= tier_lims[1])
    @constraint(m, tier[2] <= tier_lims[2] - tier_lims[1])
    tax = @expression(m, (25.0 * tier[1] + 50.0 * tier[2] + 100.0 * tier[3]) / 1000.0)
    @objective(m, Max, pr - tax)
    optimize!(m)
    total_bc = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    total_cc = sum(value(m[:x][i,CC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    bc300 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in (N_FS+1):(2*N_FS))
    bc500 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in (2*N_FS+1):(3*N_FS))
    # cost/transfer decomposition (E6 welfare accounting)
    cc_sold = sum(value(m[:dem][dd]) for dd in DS0 if dpr0[dd] == CC_PROD)
    rev_bc  = sum(value(m[:dem][dd]) * dbd0[dd] for dd in DS0 if dpr0[dd] == BC_PROD)
    credit_rev = cc_sold * p_c
    farmgate  = sum(value(m[:sup][i]) * sbd[i] for i in SS)
    opex      = sum((-value(m[:x][i,trp[t],t])) * top[t] for i in N, t in TECHS)
    transport = sum((tvc[p]*dists[(i,j)] + tfc[p]) * value(m[:f][i,j,p])
                    for i in N, j in N, p in P if arc_ok[(i,j,p)])
    capex     = af * sum(value(m[:z][i,t,k]) * tcs[(t,k)] for i in N, t in TECHS, k in SCL)
    tax_M     = value(tax) / 1e6
    segH = sum(value(m[:dem][dd]) for dd in DS0 if dpr0[dd] == BC_PROD && seg0[dd] == "H")
    segM = sum(value(m[:dem][dd]) for dd in DS0 if dpr0[dd] == BC_PROD && seg0[dd] == "M")
    segL = sum(value(m[:dem][dd]) for dd in DS0 if dpr0[dd] == BC_PROD && seg0[dd] == "L")
    segS = sum(value(m[:dem][dd]) for dd in DS0 if dpr0[dd] == BC_PROD && seg0[dd] == "sink")
    # update warm start
    for i in N, t in TECHS, k in SCL
        zi = round(Int, value(m[:z][i,t,k]))
        z_warm[(i,t,k)] = zi
    end
    push!(rows2, (p_c=p_c, profit=objective_value(m)/1e6, emis=value(Eg)/1e6,
                  bc=total_bc/1e6, cc=total_cc/1e6, bc300=bc300/1e6, bc500=bc500/1e6,
                  net_Mt=value(Eg + Sg)/1e9,
                  seg_H=segH/1e6, seg_M=segM/1e6, seg_L=segL/1e6, sink_Mt=segS/1e6,
                  rev_bc_M=rev_bc/1e6, credit_rev_M=credit_rev/1e6, tax_M=tax_M,
                  farmgate_M=farmgate/1e6, opex_M=opex/1e6, transport_M=transport/1e6,
                  capex_M=capex/1e6,
                  gap=relative_gap(m),
                  status=string(termination_status(m))))
    println(@sprintf("%-8.0f %-11.2f %-11.1f %-9.3f %-9.3f %-9.3f %-9.3f %s",
        p_c, rows2[end].profit, rows2[end].emis, rows2[end].bc, rows2[end].cc,
        rows2[end].bc300, rows2[end].bc500, rows2[end].status))
end
CSV.write(joinpath(resdir, isempty(_tag) ? "policy_C2_tax_credit_v2.csv" : "policy_C2_$(_tag)_v2.csv"),
          DataFrame(rows2))

# ──────────────────────────────────────────────────────────────
# C3: allowance allocation — grandfathering vs benchmarking
# ──────────────────────────────────────────────────────────────
if !sens_only
println("\n" * "="^100)
println("PARADIGM C3: ALLOWANCE ALLOCATION ($scen)")
println("  grandfathering: A = E_base | benchmarking: A = beta*q (beta=E_base/q_base)")
println(@sprintf("%-14s %-8s %-11s %-11s %-9s %-9s %s",
    "mode", "p_allow", "Pi(M\$)", "E+(kt)", "BC(Mt)", "surplus", "status"))
println("-"^100)
rows3 = []
for mode in ["grandfather", "benchmark"], p_allow in [30.0, 80.0]
    m, pr, Eg, Sg, qg, Pg, Tg = build(Float64[], [0.0], 0.0, mode, p_allow, E_base/q_base)
    A_ex = mode == "grandfather" ?
        @expression(m, 0.0 * Eg) :             # A constant; cost = p*(E - A) => linear
        @expression(m, 0.0 * Eg)
    if mode == "grandfather"
        @objective(m, Max, pr - (p_allow/1000.0) * (Eg - E_base))
    else
        beta = E_base / q_base
        @objective(m, Max, pr - (p_allow/1000.0) * (Eg - beta * qg))
    end
    optimize!(m)
    total_bc = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    beta = E_base / q_base
    A = mode == "grandfather" ? E_base : beta * value(qg)
    push!(rows3, (mode=mode, p_allow=p_allow, profit=objective_value(m)/1e6,
                  emis=value(Eg)/1e6, bc=total_bc/1e6,
                  surplus=(A - value(Eg))/1e6, status=string(termination_status(m))))
    println(@sprintf("%-14s %-8.0f %-11.2f %-11.1f %-9.3f %-9.1f %s",
        mode, p_allow, rows3[end].profit, rows3[end].emis, rows3[end].bc,
        rows3[end].surplus, rows3[end].status))
end
CSV.write(joinpath(resdir, "policy_C3_allocation_v2.csv"), DataFrame(rows3))
println("\nSaved: policy_C1_tiered_tax_v2.csv | policy_C2_tax_credit_v2.csv | policy_C3_allocation_v2.csv")
end # !sens_only
