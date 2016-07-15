# This file is a part of Julia. License is MIT: http://julialang.org/license

function runtests(name, isolate=true)
    if isolate
        mod_name = Symbol("TestMain_", basename(name))
        m = eval(Main, :(module $mod_name end))
    else
        m = Main
    end
    eval(m, :(using Base.Test))
    @printf("     \033[1m*\033[0m \033[31m%-21s\033[0m", name)
    tt = @elapsed eval(m, :(include($"$name.jl")))
    rss = Sys.maxrss()
    @printf(" in %6.2f seconds, maxrss %7.2f MB\n", tt, rss / 2^20)
    rss
end

# looking in . messes things up badly
filter!(x->x!=".", LOAD_PATH)
nothing
