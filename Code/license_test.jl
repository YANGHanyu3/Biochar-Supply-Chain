using JuMP, Gurobi
m = Model(Gurobi.Optimizer)
set_optimizer_attribute(m, "OutputFlag", 0)
@variable(m, x >= 0)
@objective(m, Max, x)
@constraint(m, x <= 3)
optimize!(m)
println("LICENSE OK, x = ", value(x))
