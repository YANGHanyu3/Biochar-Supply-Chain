# check_syntax_all.jl — parse-only syntax check for all edited model scripts
files = ["01_MIP_v2.jl", "02_LP_duals_v2.jl", "03_LP_GHG_v2.jl", "04_policy_A.jl",
         "05_policy_B.jl", "06_policy_C.jl", "07_sensitivity_v2.jl",
         "01_MIP_v2b.jl", "04_policy_A_v2b.jl", "06_policy_C_v2b.jl"]
allok = true
for f in files
    try
        Meta.parseall(read(f, String))
        println("SYNTAX OK: ", f)
    catch e
        global allok = false
        println("PARSE ERROR in ", f, ": ", sprint(showerror, e))
    end
end
println(allok ? "ALL OK" : "FAILURES PRESENT")
