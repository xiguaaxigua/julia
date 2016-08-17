@inline function child(x)
    x+1
end

@inline function hack(x)
    x+2
end

function kernel(x)
    return child(x)
end

a = [1]
b = [2]
c = similar(a)
# @call kernel(a,b,c)

replprint(x) = show(STDOUT, MIME"text/plain"(), x)

f = kernel
t = Tuple{Int}
tt = Base.to_tuple_type(t)

ms = Base._methods(f, tt, -1)
@assert length(ms) == 1
(sig, spvals, m) = first(ms)
@assert(!m.isstaged)
replprint(m.lambda_template)

# given a function (type?) and argtypes, return a different function type
# should still be resolvable with methods to look-up return type
function call_hook(f, tt)
    if f == child
        return (hack, typeof(hack))
    end
    return nothing
end
hooks = Core.Inference.InferenceHooks(call_hook)

(linfo, rettyp, inferred) = Core.Inference.typeinf_uncached(m, sig, spvals, optimize=true, hooks=hooks)
inferred || error("inference not successful")
println("Returns: $rettyp")
replprint(linfo)
