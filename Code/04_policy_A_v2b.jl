# ==============================================================================
# 04_policy_A_v2b.jl — Paradigm A: Baseline-and-Credit (quality-differentiated v2b)
# ==============================================================================
# v2b: BC300 (p=27) + BC500 (p=28) + CC (p=29).
# B&C credit per t dry = (B - E+ - S)/1000, tech-specific.
# Free-z MIP, warm-started, sweep p_c in {0, 50, 100, 200} (3% gap, 900 s).
# Key question: does the credit price shift the BC300/BC500 mix further?
#
# Usage: julia 04_policy_A_v2b.jl [scenario] [hcap=0.5|1.5] [pc-only=0]
#   hcap: scales the H (CDR premium) segment capacity (sensitivity, Section 7.1)
#   pc-only: run a single credit price
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
hcap_mult = 1.0
for a in ARGS
    if startswith(a, "hcap=")
        global hcap_mult = parse(Float64, split(a, "=")[2])
    end
end
pc_only = [a for a in ARGS if startswith(a, "pc-only=")]
pc_only_val = isempty(pc_only) ? nothing : parse(Float64, split(pc_only[1], "=")[2])
gap_ov = [a for a in ARGS if startswith(a, "gap=")]
gap_override = isempty(gap_ov) ? nothing : parse(Float64, split(gap_ov[1], "=")[2])
tl_ov = [a for a in ARGS if startswith(a, "tl=")]
tl_override = isempty(tl_ov) ? nothing : parse(Int, split(tl_ov[1], "=")[2])
if gap_override !== nothing || tl_override !== nothing || pc_only_val !== nothing
    outname_suffix = "_g$(something(gap_override, 0.005))_tl$(something(tl_override, 0))_pc$(something(pc_only_val, -1))"
else
    outname_suffix = ""
end
datadir = joinpath("biochar_data_v2b", scen)
resdir  = joinpath("results_v2b", scen)
mkpath(resdir)

nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df  = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df  = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
tn_df   = CSV.read(joinpath(datadir, "technology_names.csv"), DataFrame)
ghg_df  = CSV.read(joinpath(datadir, "ghg_factors_v2.csv"), DataFrame)
alpha0  = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

N = Int.(nm[:,1]); P = Int.(pm[:,1]); SS = Int.(sup_df[:,1])
TECHS = Int.(tech_df[:,1])
N_FS = 13
BC300_PROD = 2*N_FS+1; BC500_PROD = 2*N_FS+2; CC_PROD = 2*N_FS+3
BC_PRODS = (BC300_PROD, BC500_PROD)
SCL = 1:3
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
    for bp in BC_PRODS
        d <= MB && (arc_ok[(i,j,bp)] = true)
    end
    arc_ok[(i,j,CC_PROD)] = (i == j)      # certificates: no physical transport
end

# B&C alpha rates: CC per t dry = (B - E+ - S)/1000  (T1 terms stored per t wet ref -> /eta)
alpha = copy(alpha0)
println("B&C credit rates (tCC/t dry):")
for f in 1:N_FS
    t1 = f; t2 = N_FS+f; t2b = 2*N_FS+f
    eta_f = alpha0[t1, N_FS + f]
    for (t2x, bc_prod, nm2) in ((t2, BC300_PROD, "300C"), (t2b, BC500_PROD, "500C"))
        y = alpha0[t2x, bc_prod]
        b = bghg[t1] / eta_f; e = pghg[t1] / eta_f + pghg[t2x]
        s = sghg[t2x] * y
        alpha[t2x, CC_PROD] = (b - e - s) / 1000.0
        if f == 1
            println("  corn $nm2: ", round((b-e-s)/1000.0, digits=3))
        end
    end
end

z_df = CSV.read(joinpath(resdir, "z_star_MIP_v2b.csv"), DataFrame)

function solve(p_c, z_warm; time_limit = something(tl_override, 900),
               mipgap = something(gap_override, 0.005))
    dem_rows = DataFrame(dem_id=Int[], node=Int[], product=Int[], segment=String[],
                         bid=Float64[], capacity=Float64[])
    for row in eachrow(dem_df)
        push!(dem_rows, (dem_id=row.dem_id, node=row.node, product=row.product,
                         segment=String(row.segment), bid=row.bid, capacity=row.capacity))
    end
    for i in 1:nrow(dem_rows)
        if dem_rows[i, :segment] == "cc"
            dem_rows[i, :bid] = p_c
        end
    end
    DS = dem_rows.dem_id
    dnd = Dict(zip(DS, dem_rows.node)); dpr = Dict(zip(DS, dem_rows.product))
    dbd = Dict(zip(DS, dem_rows.bid)); dcp = Dict(zip(DS, dem_rows.capacity))
    dseg = Dict(zip(DS, dem_rows.segment))
    seg_df = CSV.read(joinpath(datadir, "segment_capacity.csv"), DataFrame)
    seg_cap = Dict((Int(seg_df.node[i]), String(seg_df.segment[i])) =>
                   (String(seg_df.segment[i]) == "H" ? seg_df.capacity[i] * hcap_mult
                                                      : seg_df.capacity[i])
                   for i in 1:nrow(seg_df))

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
    @constraint(m, segcap[(n, sg) in keys(seg_cap)],
        sum(dem[dd] for dd in DS if dnd[dd]==n && dseg[dd]==sg) <= seg_cap[(n, sg)])
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

    bc300 = sum(value(x[i,BC300_PROD,t]) for i in N, t in TECHS if t > N_FS)
    bc500 = sum(value(x[i,BC500_PROD,t]) for i in N, t in TECHS if t > N_FS)
    cc    = sum(value(x[i,CC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    seg = Dict()
    for sg in ("H","M","L","sink")
        seg[sg] = sum(value(dem[dd]) for dd in DS if dem_rows[dem_rows.dem_id .== dd, :segment][1] == sg
                      && dpr[dd] in BC_PRODS)
    end
    proc = sum((-value(x[i,trp[t],t])) * pghg[t] for i in N, t in TECHS)
    tran = sum(gtv * dists[(i,j)] * sum(value(f[i,j,p]) for p in P if arc_ok[(i,j,p)])
               for i in N, j in N if any(arc_ok[(i,j,p)] for p in P))
    seqg = sum(value(x[i,p,t]) * sghg[t] for i in N, p in BC_PRODS, t in TECHS if t > N_FS)

    z_layout = Dict{Tuple{Int,Int,Int}, Int}()
    for i in N, t in TECHS, k in SCL
        zi = round(Int, value(z[i,t,k]))
        if zi > 0
            z_layout[(i,t,k)] = zi
        end
    end
    (; p_c, profit_M=objective_value(m)/1e6, bc300_Mt=bc300/1e6, bc500_Mt=bc500/1e6,
       bc_Mt=(bc300+bc500)/1e6, cc_Mt=cc/1e6, seg=seg,
       ghg_Mt=(proc+tran+seqg)/1e9, status=string(termination_status(m)),
       gap=termination_status(m)==MOI.OPTIMAL ? relative_gap(m) : NaN,
       z_layout=z_layout)
end

function run_sweep()
    prices = pc_only_val === nothing ? [0.0, 50.0, 100.0, 200.0] : [pc_only_val]
    println("\n" * "="^100)
    println("PARADIGM A (v2b): BASELINE-AND-CREDIT SWEEP ($scen) [FREE-Z MIP]")
    println(@sprintf("%-8s %-12s %-9s %-9s %-9s %-8s %-8s %-8s %-9s %s",
        "p_c", "Profit(M)", "BC(Mt)", "BC300", "BC500", "segH", "segM", "segL", "CC(Mt)", "status"))
    println("-"^100)
    results = []
    z_warm = Dict{Tuple{Int,Int,Int}, Int}()
    for row in eachrow(z_df)
        z_warm[(row.node, row.tech, row.scale)] = row.count
    end
    for pc in prices
        r = solve(pc, z_warm)
        push!(results, r)
        z_warm = r.z_layout
        println(@sprintf("%-8.0f %-12.2f %-9.3f %-9.3f %-9.3f %-8.3f %-8.3f %-8.3f %-9.3f %s",
            pc, r.profit_M, r.bc_Mt, r.bc300_Mt, r.bc500_Mt, r.seg["H"], r.seg["M"], r.seg["L"],
            r.cc_Mt, r.status))
    end
    return results
end

results = run_sweep()
df = DataFrame(
    p_c = [r.p_c for r in results],
    profit_M = [r.profit_M for r in results],
    bc_Mt = [r.bc_Mt for r in results],
    bc300_Mt = [r.bc300_Mt for r in results],
    bc500_Mt = [r.bc500_Mt for r in results],
    cc_Mt = [r.cc_Mt for r in results],
    seg_H = [r.seg["H"] for r in results], seg_M = [r.seg["M"] for r in results],
    seg_L = [r.seg["L"] for r in results], sink_Mt = [r.seg["sink"] for r in results],
    ghg_Mt = [r.ghg_Mt for r in results], gap = [r.gap for r in results],
    status = [r.status for r in results])
outfile = (hcap_mult == 1.0 && pc_only_val === nothing && outname_suffix == "") ?
    "policy_A_bnc_sweep_v2b.csv" :
    "policy_A_hcap$(hcap_mult)_pc$(pc_only_val)" * outname_suffix * "_v2b.csv"
CSV.write(joinpath(resdir, outfile), df)
println("\nSaved: $outfile")
