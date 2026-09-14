# ==============================================================================
# 06_policy_C_v2b.jl — Paradigm C2: Tiered tax + VM0044 credit (v2b model)
# ==============================================================================
# v2b: BC300 (p=27, H/C up to 0.73) + BC500 (p=28, H/C <= 0.5) + CC (p=29).
# VM0044 eligibility gate already embedded in the alpha matrix:
#   BC300 earns CC only for eligible feedstocks (corn, switchgrass, miscanthus,
#   forestry); wheat/oats/barley/soybean 300C biochar -> CC = 0.
#   BC500 earns CC for ALL feedstocks.
# C2 = tiered tax (25/50/100 on gross emissions) + CC sold at p_c, FREE-Z MIP,
# warm-started. Key question: does the H/C gate + credit price shift the
# BC300/BC500 mix?
#
# Usage: julia 06_policy_C_v2b.jl [scenario]
# ==============================================================================
using JuMP, Gurobi, CSV, DataFrames
import Printf: @sprintf

scen = length(ARGS) > 0 ? ARGS[1] : "near-term"
datadir = joinpath("biochar_data_v2b", scen)
resdir  = joinpath("results_v2b", scen)

nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df  = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df  = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
ghg_df  = CSV.read(joinpath(datadir, "ghg_factors_v2.csv"), DataFrame)
alpha   = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

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
    for bp in BC_PRODS
        d <= MB && (arc_ok[(i,j,bp)] = true)
    end
    arc_ok[(i,j,CC_PROD)] = (i == j)      # certificates: no physical transport
end

z_df = CSV.read(joinpath(resdir, "z_star_MIP_v2b.csv"), DataFrame)

# baseline gross emissions (LP, fixed z) for tier calibration
function build_lp_fixed()
    DS = Int.(dem_df[:,1])
    dnd = Dict(zip(DS, Int.(dem_df[:,2]))); dpr = Dict(zip(DS, Int.(dem_df[:,3])))
    dbd = Dict(zip(DS, dem_df[:,5])); dcp = Dict(zip(DS, dem_df[:,6]))
    installed = Dict{Tuple{Int,Int}, Float64}()
    for i in N, t in TECHS; installed[(i,t)] = 0.0; end
    for row in eachrow(z_df)
        installed[(row.node, row.tech)] += row.count * tsz[(row.tech, row.scale)]
    end
    fix_cap = sum(row.count * tcs[(row.tech, row.scale)] for row in eachrow(z_df))
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
    @constraint(m, fcap[i in N, t in TECHS], -x[i, trp[t], t] <= installed[(i,t)])
    @objective(m, Max,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * fix_cap)
    optimize!(m)
    arc_pairs = [(i,j) for i in N for j in N if any(arc_ok[(i,j,p)] for p in P)]
    E = sum((-value(x[i,trp[t],t])) * pghg[t] for i in N, t in TECHS)
    T = sum(gtv * dists[(i,j)] * sum(value(f[i,j,p]) for p in P if arc_ok[(i,j,p)])
            for (i,j) in arc_pairs)
    return E + T
end

E_base = build_lp_fixed()
println("Baseline gross emissions (v2b, $scen): ", round(E_base/1e6, digits=1), " kt")
tier_lims = [0.40 * E_base, 0.70 * E_base]

function solve_c2(p_c, z_warm; time_limit=900, mipgap=0.005)
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
    seg_cap = Dict((Int(seg_df.node[i]), String(seg_df.segment[i])) => seg_df.capacity[i]
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
    @constraint(m, yld[i in N, t in TECHS, p in P], x[i,p,t] == tr[(t,p)]/tr[(t, trp[t])] * x[i, trp[t], t])
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

    arc_pairs = [(i,j) for i in N for j in N if any(arc_ok[(i,j,p)] for p in P)]
    process_ghg = @expression(m, sum((-x[i, trp[t], t]) * pghg[t] for i in N, t in TECHS))
    trans_ghg   = @expression(m, sum(gtv * dists[(i,j)] * sum(f[i,j,p] for p in P if arc_ok[(i,j,p)])
                                     for (i,j) in arc_pairs))
    Egross = @expression(m, process_ghg + trans_ghg)
    @variable(m, tier[1:3] >= 0)
    @constraint(m, Egross == tier[1] + tier[2] + tier[3])
    @constraint(m, tier[1] <= tier_lims[1])
    @constraint(m, tier[2] <= tier_lims[2] - tier_lims[1])
    tax = @expression(m, (25.0 * tier[1] + 50.0 * tier[2] + 100.0 * tier[3]) / 1000.0)

    @objective(m, Max,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * sum(z[i,t,k] * tcs[(t,k)] for i in N, t in TECHS, k in SCL)
        - tax)
    optimize!(m)

    bc300 = sum(value(x[i,BC300_PROD,t]) for i in N, t in TECHS if t > N_FS)
    bc500 = sum(value(x[i,BC500_PROD,t]) for i in N, t in TECHS if t > N_FS)
    cc    = sum(value(x[i,CC_PROD,t]) for i in N, t in TECHS if t > N_FS)
    z_layout = Dict{Tuple{Int,Int,Int}, Int}()
    for i in N, t in TECHS, k in SCL
        zi = round(Int, value(z[i,t,k]))
        if zi > 0
            z_layout[(i,t,k)] = zi
        end
    end
    (; p_c, profit_M=objective_value(m)/1e6, bc300_Mt=bc300/1e6, bc500_Mt=bc500/1e6,
       bc_Mt=(bc300+bc500)/1e6, cc_Mt=cc/1e6, emis_kt=value(Egross)/1e6,
       status=string(termination_status(m)), gap=relative_gap(m), z_layout=z_layout)
end

println("\n" * "="^100)
println("PARADIGM C2 (v2b): TIERED TAX (25/50/100) + VM0044 CREDIT ($scen) [FREE-Z MIP]")
println(@sprintf("%-8s %-12s %-9s %-9s %-9s %-9s %-10s %s",
    "p_c", "Profit(M\$)", "BC(Mt)", "BC300", "BC500", "CC(Mt)", "E+(kt)", "status"))
println("-"^100)
function run_c2_sweep()
    results = []
    z_warm = Dict{Tuple{Int,Int,Int}, Int}()
    for row in eachrow(z_df)
        z_warm[(row.node, row.tech, row.scale)] = row.count
    end
    for pc in [50.0, 100.0, 150.0, 200.0]
        r = solve_c2(pc, z_warm)
        push!(results, r)
        z_warm = r.z_layout
        println(@sprintf("%-8.0f %-12.2f %-9.3f %-9.3f %-9.3f %-9.3f %-10.1f %s",
            pc, r.profit_M, r.bc_Mt, r.bc300_Mt, r.bc500_Mt, r.cc_Mt, r.emis_kt, r.status))
    end
    return results
end
results = run_c2_sweep()
df = DataFrame(
    p_c = [r.p_c for r in results], profit_M = [r.profit_M for r in results],
    bc_Mt = [r.bc_Mt for r in results], bc300_Mt = [r.bc300_Mt for r in results],
    bc500_Mt = [r.bc500_Mt for r in results], cc_Mt = [r.cc_Mt for r in results],
    emis_kt = [r.emis_kt for r in results], status = [r.status for r in results],
    gap = [r.gap for r in results])
CSV.write(joinpath(resdir, "policy_C2_tax_credit_v2b.csv"), df)
println("\nSaved: policy_C2_tax_credit_v2b.csv")
