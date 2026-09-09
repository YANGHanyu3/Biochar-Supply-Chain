# ==============================================================================
# 04_policy_A.jl — Paradigm A: Baseline-and-Credit (B&C)
# ==============================================================================
# v2 rebuild. LCFS-style baseline-and-credit:
#   credit R = B - E+ - S   per tonne dry biomass processed:
#     B  = baseline decomposition avoided (b_f^dry, kg CO2e/t dry)
#     E+ = process GHG (T1 + T2, kg CO2e/t dry)
#     S  = biochar sequestration + N2O (kg CO2e/t dry, negative-valued)
#   CC co-production rate alpha[t2, CC] = (B - E+ - S)/1000  [tCC per t dry]
#   CC demand rows at bid p_c (voluntary market price, VM0044/Puro range)
#   sweep p_c in {25, 50, 100, 150, 200} USD/tCO2e
#
# Fixed z* from Step 1, LP (barrier). Policy revenue enters objective:
#   max  Π + p_c * CC_sold
# This CREDIT SCALES WITH THROUGHPUT -> changes facility utilization, feedstock
# mix and (via T2-300 vs T2-500 yields) technology choice. (v1's pseudo-tax
# could not do this because its "tax" was a constant shift.)
#
# Usage: julia 04_policy_A.jl [scenario] [decomp_fraction] [decomp-only]
#   decomp_fraction: 0.9 (default) | 0.7 | 0.5  -> scales the decomposition
#       baseline B(x) by frac/0.9 (sensitivity on the 0.9 decay assumption)
#   decomp-only: run only p_c = 200 (fast sensitivity sweep)
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
frac_d = length(ARGS) > 1 && !startswith(ARGS[2], "-") && !occursin("=", ARGS[2]) ? parse(Float64, ARGS[2]) : 0.9
decomp_only = "decomp-only" in ARGS
# keyword args: datadir=..., tag=..., prices=25,200 (comma list), timelimit=1800
kw = Dict{String,String}()
for a in ARGS
    if occursin("=", a) && startswith(a, r"[a-z]")
        k, v = split(a, "=", limit=2)
        kw[k] = v
    end
end
b_mult = frac_d / 0.9          # B(x) multiplier relative to the 0.9 default
datadir = get(kw, "datadir", joinpath("biochar_data_v2", scen))
resdir  = joinpath("results_v2", scen)
_tag    = get(kw, "tag", "")
_plist  = haskey(kw, "prices") ? [parse(Float64, p) for p in split(kw["prices"], ",")] : Float64[]
_tlimit = haskey(kw, "timelimit") ? parse(Float64, kw["timelimit"]) : 600.0
_mgap   = haskey(kw, "gap") ? parse(Float64, kw["gap"]) : 0.005

nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df  = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df  = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
tn_df   = CSV.read(joinpath(datadir, "technology_names.csv"), DataFrame)
ghg_df  = CSV.read(joinpath(datadir, "ghg_factors_v2.csv"), DataFrame)
alpha0  = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

N = Int.(nm[:,1]); P = Int.(pm[:,1]); DS0 = Int.(dem_df[:,1]); SS = Int.(sup_df[:,1])
TECHS = Int.(tech_df[:,1])
N_FS = 13; BC_PROD = 2*N_FS+1; CC_PROD = 2*N_FS+2; SCL = 1:3
af = 0.1175

lat = Dict(zip(N, nm[:,3])); lon = Dict(zip(N, nm[:,4]))
tvc = Dict(zip(P, pm[:,3])); tfc = Dict(zip(P, pm[:,4]))
snd = Dict(zip(SS, Int.(sup_df[:,2]))); spr = Dict(zip(SS, Int.(sup_df[:,3])))
sbd = Dict(zip(SS, sup_df[:,5])); scp = Dict(zip(SS, sup_df[:,6]))
trp = Dict(zip(TECHS, Int.(tech_df[:,3])))
top = Dict(zip(TECHS, tech_df[:,5]))
tsz = Dict((TECHS[t],k) => tech_df[t,6+k] for t in 1:length(TECHS), k in SCL)
tcs = Dict((TECHS[t],k) => tech_df[t,9+k] for t in 1:length(TECHS), k in SCL)
pghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,3]))
sghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,4] .+ ghg_df[:,5]))
bghg = Dict(zip(Int.(ghg_df[:,1]), ghg_df[:,8]))   # baseline_ghg_per_t_ref (col 8)
gtv  = ghg_df[1,7]                                  # ghg_transport_per_tkm (col 7)

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

# ── B&C alpha rates: CC per t dry = (B - E+ - S)/1000 ──
# B = bghg[t1]/eta (per t dry, stored per t wet ref -> divide by T1 wet->dry yield)
# E+ = pghg[t1]/eta + pghg[t2]   (T1 stored per t wet ref)
# S  = sghg[t2] * yield[t2]   (kg CO2e/t BC * t BC/t dry  -> kg/t dry, negative)
alpha = copy(alpha0)
println("B&C carbon credit rates (tCC per t dry biomass):")
for f in 1:N_FS
    t1 = f; t2 = N_FS + f; t2b = 2*N_FS + f
    eta_f = alpha0[t1, N_FS + f]          # T1 wet->dry yield
    for (t2x, tname) in ((t2, "300C"), (t2b, "500C"))
        y = alpha0[t2x, BC_PROD]
        b = bghg[t1] / eta_f * b_mult      # baseline decomposition avoided, per t dry
        e = pghg[t1] / eta_f + pghg[t2x]  # process GHG per t dry
        s = sghg[t2x] * y                 # seq+N2O per t dry (negative)
        rate = (b - e - s) / 1000.0
        alpha[t2x, CC_PROD] = rate
        if f <= 4
            println("  $(rpad(tn_df[t2x,:name],28)) $(round(rate, digits=3))")
        end
    end
end

# ── CC demand rows (bid = p_c, per scenario) ──
# FREE-Z MIP: facilities can expand/relocate in response to credit price
# (fixed-z LP cannot expand beyond baseline capacity -> no behavioral change,
#  which was the v2 design lesson of the first run: BC stayed at 2.3 Mt).
# Warm start from baseline z* for each successive p_c.
function solve_bnc(p_c, z_warm; time_limit=_tlimit, mipgap=0.005, verbose=true)
    # base demand + CC rows at p_c
    dem_rows = DataFrame(dem_id=Int[], node=Int[], product=Int[], segment=String[],
                         bid=Float64[], capacity=Float64[])
    for row in eachrow(dem_df)
        push!(dem_rows, (dem_id=row.dem_id, node=row.node, product=row.product,
                         segment=String(row.segment), bid=row.bid, capacity=row.capacity))
    end
    # CC rows already in base demand at bid 0; override bid to p_c
    for i in 1:nrow(dem_rows)
        if dem_rows[i, :segment] == "cc"
            dem_rows[i, :bid] = p_c
        end
    end
    DS = dem_rows.dem_id
    dnd = Dict(zip(DS, dem_rows.node)); dpr = Dict(zip(DS, dem_rows.product))
    dbd = Dict(zip(DS, dem_rows.bid)); dcp = Dict(zip(DS, dem_rows.capacity))

    m = Model(Gurobi.Optimizer)
    set_optimizer_attribute(m, "TimeLimit", time_limit)
    set_optimizer_attribute(m, "MIPGap", mipgap)
    set_optimizer_attribute(m, "MIPFocus", 1)
    set_optimizer_attribute(m, "Threads", 8)
    set_optimizer_attribute(m, "OutputFlag", 0)

    @variable(m, f[i in N, j in N, p in P; arc_ok[(i,j,p)]] >= 0)
    @variable(m, dem[DS] >= 0); @variable(m, sup[SS] >= 0)
    @variable(m, d[N,P] >= 0);  @variable(m, s[N,P] >= 0)
    @variable(m, x[N,P,TECHS]); @variable(m, pp[N,P])
    @variable(m, z[N,TECHS,SCL] >= 0, Int)
    @constraint(m, [i in N, t in TECHS, k in SCL], z[i,t,k] <= 5)

    # warm start from previous layout
    for i in N, t in TECHS, k in SCL
        zv = get(z_warm, (i,t,k), 0)
        if zv > 0
            set_start_value(z[i,t,k], zv)
        end
    end

    @constraint(m, dmeq[n in N, p in P], d[n,p] == sum(dem[dd] for dd in DS if dpr[dd]==p && dnd[dd]==n))
    @constraint(m, smeq[n in N, p in P], s[n,p] == sum(sup[ss] for ss in SS if spr[ss]==p && snd[ss]==n))
    @constraint(m, tfl[i in N, t in TECHS], x[i, trp[t], t] <= 0)
    @constraint(m, yld[i in N, t in TECHS, p in P], x[i,p,t] == alpha[t,p]/alpha[t, trp[t]] * x[i, trp[t], t])
    @constraint(m, pfl[i in N, p in P], pp[i,p] == sum(x[i,p,t] for t in TECHS))
    @constraint(m, bal[i in N, p in P],
        s[i,p] + pp[i,p] + sum(f[j,i,p] for j in N if arc_ok[(j,i,p)]) ==
        d[i,p] + sum(f[i,j,p] for j in N if arc_ok[(i,j,p)]))
    @constraint(m, dcap[i in DS], dem[i] <= dcp[i])
    @constraint(m, scap[i in SS], sup[i] <= scp[i])
    @constraint(m, fcap[i in N, t in TECHS],
        -x[i, trp[t], t] <= sum(z[i,t,k] * tsz[(t,k)] for k in SCL))

    @objective(m, Max,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * sum(z[i,t,k] * tcs[(t,k)] for i in N, t in TECHS, k in SCL))

    optimize!(m)

    total_bc  = sum(value(x[i,BC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    total_cc  = sum(value(x[i,CC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    cc_sold   = sum(value(dem[dd]) for dd in DS if dpr[dd] == CC_PROD)
    bc_by_seg = Dict()
    for seg in ("H","M","L","sink")
        bc_by_seg[seg] = sum(value(dem[dd]) for dd in DS if dpr[dd] == BC_PROD && dem_rows[dem_rows.dem_id .== dd, :segment][1] == seg)
    end
    wet = sum(-value(x[i,t,t]) for i in N for t in 1:N_FS)
    bc_300 = sum(value(x[i,BC_PROD,t]) for i in N, t in (N_FS+1):(2*N_FS))
    bc_500 = sum(value(x[i,BC_PROD,t]) for i in N, t in (2*N_FS+1):(3*N_FS))
    # GHG
    proc = sum((-value(x[i,trp[t],t])) * pghg[t] for i in N, t in TECHS)
    tran = sum(gtv * dists[(i,j)] * sum(value(f[i,j,p]) for p in P if arc_ok[(i,j,p)])
               for i in N, j in N if any(arc_ok[(i,j,p)] for p in P))
    seqg = sum(value(x[i,BC_PROD,t]) * sghg[t] for i in N, t in TECHS if t > N_FS)
    basl = sum((-value(x[i,trp[t],t])) * bghg[t] for i in N, t in 1:N_FS)

    # facility layout at this solution (for warm start of next p_c)
    z_layout = Dict{Tuple{Int,Int,Int}, Int}()
    for i in N, t in TECHS, k in SCL
        zi = round(Int, value(z[i,t,k]))
        if zi > 0
            z_layout[(i,t,k)] = zi
        end
    end

    (; p_c, profit_M=objective_value(m)/1e6, bc_Mt=total_bc/1e6, cc_Mt=total_cc/1e6,
       cc_sold_Mt=cc_sold/1e6, wet_Mt=wet/1e6, bc_300_Mt=bc_300/1e6, bc_500_Mt=bc_500/1e6,
       seg=bc_by_seg, ghg_Mt=(proc+tran+seqg)/1e9, baseline_Mt=basl/1e9,
       gap=relative_gap(m),
       status=string(termination_status(m)), z_layout=z_layout)
end

prices = decomp_only ? [200.0] : (isempty(_plist) ? [0.0, 25.0, 50.0, 100.0, 150.0, 200.0] : _plist)
println("\n" * "="^100)
println("PARADIGM A: BASELINE-AND-CREDIT SWEEP ($scen)  [FREE-Z MIP, warm-started]" *
        (isempty(_tag) ? "" : "  [tag=$_tag]") * "  [time_limit=$_tlimit s]")
println(@sprintf("%-8s %-12s %-9s %-9s %-8s %-8s %-8s %-8s %-9s %-9s %s",
    "p_c", "Profit(M)", "BC(Mt)", "CC(Mt)", "segH", "segM", "segL", "sink", "BC300", "BC500", "status"))
println("-"^100)
function run_sweep()
    results = []
    z_warm = Dict{Tuple{Int,Int,Int}, Int}()
    for row in eachrow(z_df)
        z_warm[(row.node, row.tech, row.scale)] = row.count
    end
    for pc in prices
        r = solve_bnc(pc, z_warm; time_limit=_tlimit, mipgap=_mgap)
        push!(results, r)
        z_warm = r.z_layout
        println(@sprintf("%-8.0f %-12.2f %-9.3f %-9.3f %-8.3f %-8.3f %-8.3f %-8.3f %-9.3f %-9.3f %s",
            pc, r.profit_M, r.bc_Mt, r.cc_Mt, r.seg["H"], r.seg["M"], r.seg["L"], r.seg["sink"],
            r.bc_300_Mt, r.bc_500_Mt, r.status))
    end
    return results
end

results = run_sweep()

df = DataFrame(
    p_c = [r.p_c for r in results],
    profit_M = [r.profit_M for r in results],
    bc_Mt = [r.bc_Mt for r in results],
    cc_Mt = [r.cc_Mt for r in results],
    cc_sold_Mt = [r.cc_sold_Mt for r in results],
    wet_Mt = [r.wet_Mt for r in results],
    seg_H = [r.seg["H"] for r in results], seg_M = [r.seg["M"] for r in results],
    seg_L = [r.seg["L"] for r in results], sink_Mt = [r.seg["sink"] for r in results],
    bc_300_Mt = [r.bc_300_Mt for r in results], bc_500_Mt = [r.bc_500_Mt for r in results],
    ghg_Mt = [r.ghg_Mt for r in results], baseline_Mt = [r.baseline_Mt for r in results],
    gap = [r.gap for r in results],
    status = [r.status for r in results])
outfile = isempty(_tag) ? (frac_d == 0.9 ? "policy_A_bnc_sweep_v2.csv" : "policy_A_decomp_frac$(frac_d)_v2.csv") :
                            "policy_A_$(_tag)_v2.csv"
CSV.write(joinpath(resdir, outfile), df)
println("\nSaved: $outfile")
