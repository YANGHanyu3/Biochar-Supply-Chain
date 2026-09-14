# ==============================================================================
# 05b_netcap_frontier.jl — E2: net-emission cap frontier (v0.9 review fix)
# ==============================================================================
# Replaces the old B2 claim ("net caps never bind") with a frontier experiment:
#   * the old B2 sweep only tested caps >= -1000 kt, all looser than the
#     baseline flux (-1595 kt), so non-binding was built into the design.
#   * PART 1 (fixed layout, LP): tighten CAP_net below the baseline flux in
#     100-kt steps; reports profit/net/BC/mix, the cap dual, and a dual
#     bracket (CAP +- 50 kt). Expectation from the baseline layout: T2-500
#     capacity is zero and T2-300 is saturated at the H+M demand, so the
#     fixed-layout frontier is nearly vertical (layout lock).
#   * PART 2 (free facilities, MIP): the same sweep with z free (warm-started
#     along the chain). This is the frontier that answers "do net caps bind
#     below the baseline flux, and at what shadow cost?" — free investment in
#     500 C capacity is the response channel. Reports gap/status/runtime and
#     the finite-difference MAC between consecutive feasible points.
#   * PART 3: N_min = minimum feasible net flux (min E+T+S, z free).
#
# Usage: julia 05b_netcap_frontier.jl [scenario] [datadir=...] [resdir=...] [tlimit=...]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = "near-term"
datadir = nothing
resdir = nothing
tlimit = 900.0
for a in ARGS
    if startswith(a, "datadir="); global datadir = split(a, '=')[2]; end
    if startswith(a, "resdir=");  global resdir  = split(a, '=')[2]; end
    if startswith(a, "tlimit=");  global tlimit  = parse(Float64, split(a, '=')[2]); end
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
z_warm0 = Dict{Tuple{Int,Int,Int}, Int}()
for row in eachrow(z_df)
    z_warm0[(row.node, row.tech, row.scale)] = row.count
end

# ── shared LP body (fixed layout) ────────────────────────────────────────────
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

# ── shared MIP body (free z) ─────────────────────────────────────────────────
function build_mip(z_warm)
    m = Model(Gurobi.Optimizer)
    set_optimizer_attribute(m, "TimeLimit", tlimit)
    set_optimizer_attribute(m, "MIPGap", 0.005)
    set_optimizer_attribute(m, "MIPFocus", 1)
    set_optimizer_attribute(m, "Threads", 7)   # 7/8 physical cores: thermal headroom
    set_optimizer_attribute(m, "OutputFlag", 0)
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
    profit_ex = @expression(m,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * sum(z[i,t,k] * tcs[(t,k)] for i in N, t in TECHS, k in SCL))
    return m, profit_ex, process_ghg, trans_ghg, seq_ghg
end

# baseline net flux
m0, pr0, E0_, T0_, S0_ = build_lp()
@objective(m0, Max, pr0)
optimize!(m0)
net_base = value(E0_ + T0_ + S0_)
println("Baseline net flux = $(round(net_base/1e6, digits=1)) kt CO2e/yr (negative => net removal)")

caps_kt = collect(-1600.0 : -100.0 : -2200.0)   # kt CO2e

# ════════════════════════════════════════════════════════════════════════════
# PART 1: fixed-layout LP frontier (layout lock diagnostic)
# ════════════════════════════════════════════════════════════════════════════
println("\n" * "="^112)
println("E2 PART 1: NET-CAP FRONTIER, FIXED LAYOUT LP ($scen)  [E+ + T + S <= CAP_net]")
println(@sprintf("%-12s %-11s %-11s %-9s %-9s %-9s %-11s %-10s %-10s %s",
    "Cap(kt)", "Pi(M\$)", "Net(kt)", "BC(Mt)", "BC300", "BC500", "pi(\$/t)", "pi@-50", "pi@+50", "status"))
println("-"^112)
rows1 = []
for cap_net in caps_kt .* 1e6
    m, pr, Ep, Tp, Sp = build_lp()
    @constraint(m, cap_c, Ep + Tp + Sp <= cap_net)
    @objective(m, Max, pr)
    optimize!(m)
    st = termination_status(m)
    if st == MOI.OPTIMAL
        bc300 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if N_FS < t <= 2*N_FS)
        bc500 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > 2*N_FS)
        pi_cap = has_duals(m) ? dual(cap_c) * 1000.0 : NaN
        pi_lo, pi_hi = NaN, NaN
        for (dcap, tag) in ((-50.0e6, :lo), (50.0e6, :hi))
            mm, prr, Ep2, Tp2, Sp2 = build_lp()
            @constraint(mm, cap_c2, Ep2 + Tp2 + Sp2 <= cap_net + dcap)
            @objective(mm, Max, prr)
            optimize!(mm)
            if termination_status(mm) == MOI.OPTIMAL && has_duals(mm)
                (tag == :lo) && (pi_lo = dual(cap_c2) * 1000.0)
                (tag == :hi) && (pi_hi = dual(cap_c2) * 1000.0)
            end
        end
        push!(rows1, (cap_net=cap_net/1e6, profit=objective_value(m)/1e6,
                      net=value(Ep+Tp+Sp)/1e6, bc=(bc300+bc500)/1e6,
                      bc300=bc300/1e6, bc500=bc500/1e6,
                      pi=pi_cap, pi_lo=pi_lo, pi_hi=pi_hi, status=string(st)))
        println(@sprintf("%-12.0f %-11.2f %-11.1f %-9.3f %-9.3f %-9.3f %-11.2f %-10.2f %-10.2f %s",
            rows1[end].cap_net, rows1[end].profit, rows1[end].net, rows1[end].bc,
            rows1[end].bc300, rows1[end].bc500, pi_cap, pi_lo, pi_hi, rows1[end].status))
    else
        push!(rows1, (cap_net=cap_net/1e6, profit=NaN, net=NaN, bc=NaN,
                      bc300=NaN, bc500=NaN, pi=NaN, pi_lo=NaN, pi_hi=NaN, status=string(st)))
        println(@sprintf("%-12.0f %-11s %-11s %-9s %-9s %-9s %-11s %-10s %-10s %s",
            cap_net/1e6, "-", "-", "-", "-", "-", "-", "-", "-", string(st)))
    end
end
CSV.write(joinpath(resdir, "netcap_frontier_fixedz_v2.csv"), DataFrame(rows1))
println("Saved: netcap_frontier_fixedz_v2.csv")

# ════════════════════════════════════════════════════════════════════════════
# PART 2: free-facility MIP frontier (warm-started chain)
# ════════════════════════════════════════════════════════════════════════════
println("\n" * "="^112)
println("E2 PART 2: NET-CAP FRONTIER, FREE-Z MIP ($scen)  [time_limit=$tlimit s, gap 0.5%]")
println(@sprintf("%-12s %-11s %-11s %-9s %-9s %-9s %-9s %-9s %s",
    "Cap(kt)", "Pi(M\$)", "Net(kt)", "BC(Mt)", "BC300", "BC500", "gap%", "runtime_s", "status"))
println("-"^112)
rows2 = []
z_warm = copy(z_warm0)
for cap_net in caps_kt .* 1e6
    m, pr, Ep, Tp, Sp = build_mip(z_warm)
    @constraint(m, cap_c, Ep + Tp + Sp <= cap_net)
    @objective(m, Max, pr)
    t0 = time()
    optimize!(m)
    rt = time() - t0
    st = termination_status(m)
    if st in (MOI.OPTIMAL, MOI.TIME_LIMIT)
        bc300 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if N_FS < t <= 2*N_FS)
        bc500 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > 2*N_FS)
        push!(rows2, (cap_net=cap_net/1e6, profit=objective_value(m)/1e6,
                      net=value(Ep+Tp+Sp)/1e6, bc=(bc300+bc500)/1e6,
                      bc300=bc300/1e6, bc500=bc500/1e6,
                      gap=round(relative_gap(m), digits=4), runtime_s=round(rt, digits=1),
                      status=string(st)))
        # refresh warm start from this incumbent
        for i in N, t in TECHS, k in SCL
            zi = round(Int, value(m[:z][i,t,k]))
            z_warm[(i,t,k)] = zi
        end
        println(@sprintf("%-12.0f %-11.2f %-11.1f %-9.3f %-9.3f %-9.3f %-9.3f %-9.1f %s",
            rows2[end].cap_net, rows2[end].profit, rows2[end].net, rows2[end].bc,
            rows2[end].bc300, rows2[end].bc500, rows2[end].gap, rows2[end].runtime_s,
            rows2[end].status))
    else
        push!(rows2, (cap_net=cap_net/1e6, profit=NaN, net=NaN, bc=NaN,
                      bc300=NaN, bc500=NaN, gap=NaN, runtime_s=round(rt, digits=1),
                      status=string(st)))
        println(@sprintf("%-12.0f %-11s %-11s %-9s %-9s %-9s %-9s %-9.1f %s",
            cap_net/1e6, "-", "-", "-", "-", "-", "-", rows2[end].runtime_s,
            rows2[end].status))
    end
end
# finite-difference MAC between consecutive feasible points (M$/kt -> $/t)
feas = [r for r in rows2 if !isnan(r.profit)]
mac = [NaN]
for i in 2:length(feas)
    dpi = (feas[i].profit - feas[i-1].profit) / (feas[i].cap_net - feas[i-1].cap_net)
    push!(mac, 1000.0 * dpi)
end
df2 = DataFrame(rows2)
df2.mac_fd_dollar_per_t = [isnan(r.profit) ? NaN : mac[findfirst(isequal(r), feas)] for r in rows2]
CSV.write(joinpath(resdir, "netcap_frontier_v2.csv"), df2)
println("Saved: netcap_frontier_v2.csv (free-z MIP, with finite-difference MAC)")

# ════════════════════════════════════════════════════════════════════════════
# PART 3: N_min — minimum feasible net flux (free z)
# ════════════════════════════════════════════════════════════════════════════
println("\n" * "="^112)
println("E2 PART 3: N_min = min (E+ + T + S) s.t. free z  [$tlimit s]")
m, pr, Ep, Tp, Sp = build_mip(z_warm)
@objective(m, Min, Ep + Tp + Sp)
t0 = time()
optimize!(m)
rt = time() - t0
st = termination_status(m)
if st in (MOI.OPTIMAL, MOI.TIME_LIMIT)
    bc300 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if N_FS < t <= 2*N_FS)
    bc500 = sum(value(m[:x][i,BC_PROD,t]) for i in N, t in TECHS if t > 2*N_FS)
    nmin = (value(Ep+Tp+Sp), (bc300+bc500)/1e6, bc300/1e6, bc500/1e6,
            round(relative_gap(m), digits=4), round(rt, digits=1), string(st))
    println(@sprintf("N_min = %.1f kt | BC = %.3f Mt (300: %.3f, 500: %.3f) | gap %s | %.1f s | %s",
        nmin[1]/1e6, nmin[2], nmin[3], nmin[4], nmin[5], nmin[6], nmin[7]))
    open(joinpath(resdir, "netcap_Nmin_v2.txt"), "w") do io
        println(io, "nmin_kt=$(round(nmin[1]/1e6, digits=1))")
        println(io, "bc_Mt=$(round(nmin[2], digits=3))")
        println(io, "bc300_Mt=$(round(nmin[3], digits=3))")
        println(io, "bc500_Mt=$(round(nmin[4], digits=3))")
        println(io, "gap=$(nmin[5]) runtime_s=$(nmin[6]) status=$(nmin[7])")
    end
else
    println("N_min solve: $st after $(round(rt, digits=1)) s")
end
println("Saved: netcap_Nmin_v2.txt")
