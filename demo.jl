function kernel(a, b, c)
    c[1] = a[1] + b[1]

    return nothing
end

a = [1]
b = [2]
c = similar(a)
# @call kernel(a,b,c)

f = kernel
t = Tuple{Array{Int}, Array{Int}, Array{Int}}
tt = Base.to_tuple_type(t)

ms = Base._methods(f, tt, -1)
@assert length(ms) == 1
(sig, spvals, m) = first(ms)
@assert(!m.isstaged)

function call_hook(f)

end
hooks = Core.Inference.InferenceHooks(call_hook)

(linfo, rettyp, inferred) = Core.Inference.typeinf_uncached(m, sig, spvals, optimize=true, hooks=hooks)
inferred || error("inference not successful")
println(linfo)
println(rettyp)

# ok cool this works, hook allows us to override rettype of function calls
# but then how does this end up in the linfo
