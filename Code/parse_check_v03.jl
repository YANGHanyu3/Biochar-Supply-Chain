for f in ["04_policy_A.jl", "05_policy_B.jl", "06_policy_C.jl"]
    src = read(joinpath("E:\\hhy\\Desktop\\BIochar Supply Chain\\01_Current_Code", f), String)
    try
        Meta.parseall(src)
        println(f, ": PARSE OK")
    catch e
        println(f, ": PARSE ERROR -> ", sprint(showerror, e)[1:min(end,300)])
    end
end
