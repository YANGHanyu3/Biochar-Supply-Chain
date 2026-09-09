using JuMP, Gurobi, CSV, DataFrames

scen = "near-term"
datadir = joinpath("biochar_data_v2", scen)
resdir  = joinpath("results_v2", scen)

nm      = CSV.read(joinpath(datadir, "node_matrix.csv"), DataFrame)
pm      = CSV.read(joinpath(datadir, "product_matrix.csv"), DataFrame)
dem_df0 = CSV.read(joinpath(datadir, "demand_matrix.csv"), DataFrame)
sup_df0 = CSV.read(joinpath(datadir, "supply_matrix.csv"), DataFrame)
tech_df = CSV.read(joinpath(datadir, "technology_matrix.csv"), DataFrame)
alpha   = Matrix(CSV.read(joinpath(datadir, "alpha_matrix.csv"), DataFrame, header=false))

N = Int.(nm[:,1]); P = Int.(pm[:,1]); SS = Int.(sup_df0[:,1])
TECHS = Int.(tech_df[:,1]); N_FS = 13; BC_PROD = 2*N_FS+1; CC_PROD = 2*N_FS+2; SCL = 1:3
af = 0.1175
lat = Dict(zip(N, nm[:,3])); lon = Dict(zip(N, nm[:,4]))
snd = Dict(zip(SS, Int.(sup_df0[:,2]))); spr = Dict(zip(SS, Int.(sup_df0[:,3])))
trp = Dict(zip(TECHS, Int.(tech_df[:,3])))
top = Dict(zip(TECHS, tech_df[:,5]))
tsz = Dict((TECHS[t],k) => tech_df[t,6+k] for t in 1:length(TECHS), k in SCL)
tr  = Dict((TECHS[t], P[k]) => alpha[t,k] for t in 1:length(TECHS), k in 1:length(P))

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
fix_capex = af * sum(row.count * tech_df[row.tech, 9 + row.scale] for row in eachrow(z_df))
println("fix_capex (af*CAPEX) = ", fix_capex)

function solve_case(farm_mult, trans_mult, cap_mult, price_mult, sink_val, sup_mult)
    dem_df = copy(dem_df0)
    sup_df = copy(sup_df0)
    is_sink = dem_df[:,4] .== "sink"
    dem_df[:,5] = dem_df[:,5] .* ifelse.(is_sink, 1.0, price_mult)
    dem_df[is_sink, 5] .= sink_val
    dem_df[:,6] = dem_df[:,6] .* ifelse.(is_sink, 1.0, cap_mult)
    sup_df[:,5] = sup_df[:,5] .* farm_mult
    sup_df[:,6] = sup_df[:,6] .* sup_mult
    tvc = Dict(zip(P, pm[:,3] .* trans_mult)); tfc = Dict(zip(P, pm[:,4] .* trans_mult))
    scp2 = Dict(zip(SS, sup_df[:,6]))
    DS = Int.(dem_df[:,1])
    dnd = Dict(zip(DS, Int.(dem_df[:,2]))); dpr = Dict(zip(DS, Int.(dem_df[:,3])))
    dbd = Dict(zip(DS, dem_df[:,5])); dcp = Dict(zip(DS, dem_df[:,6]))
    sbd = Dict(zip(SS, sup_df[:,5]))
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
    @constraint(m, scap[i in SS], sup[i] <= scp2[i])
    @constraint(m, fcap[i in N, t in TECHS], -x[i, trp[t], t] <= installed_cap[(i,t)])
    @objective(m, Max,
        sum(dem[dd] * dbd[dd] for dd in DS)
        - sum(sup[i] * sbd[i] for i in SS)
        - sum((-x[i, trp[t], t]) * top[t] for i in N, t in TECHS)
        - sum((tvc[p]*dists[(i,j)] + tfc[p]) * f[i,j,p] for i in N, j in N, p in P if arc_ok[(i,j,p)])
        - af * fix_capex)
    optimize!(m)
    rev = sum(value(dem[dd]) * dbd[dd] for dd in DS)
    farm = sum(value(sup[i]) * sbd[i] for i in SS)
    opex = sum((-value(x[i,trp[t],t])) * top[t] for i in N, t in TECHS)
    trn  = sum((tvc[p]*dists[(i,j)] + tfc[p]) * value(f[i,j,p]) for i in N, j in N, p in P if arc_ok[(i,j,p)])
    println("obj=", objective_value(m))
    println("  revenue=", rev, " farm=", farm, " opex=", opex, " trans=", trn, " capex=", af*fix_capex)
    m
end

m = solve_case(1.0, 1.0, 1.0, 1.0, 30.0, 1.0)
