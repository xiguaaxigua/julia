#
# Functions
#

@inline function child(x)
    x+1
end

@inline function hacked_child(x)
    x+2.
end

function kernel(x)
    return child(x)
end


#
# Auxiliary
#

replprint(x) = show(STDOUT, MIME"text/plain"(), x)


#
# Inference
#

f = kernel
t = Tuple{Int}
tt = Base.to_tuple_type(t)

ms = Base._methods(f, tt, -1)
@assert length(ms) == 1
(sig, spvals, m) = first(ms)
@assert(!m.isstaged)
replprint(m.lambda_template)

# given a function and the argument tuple type (incl. the function type)
# return a tuple of the replacement function and its type, or nothing
# IDEA: define multiple hook methods, eg. `call_hook(f::child, tt)`
function call_hook(f, tt)
    if f == child
        return hacked_child
    end
    return nothing
end
hooks = Core.Inference.InferenceHooks(call_hook)

# raise limits on inference parameters, performing a more exhaustive search
params = Core.Inference.InferenceParams(7, 15, 16, 4, 4)

(linfo, rettyp, inferred) =
    Core.Inference.typeinf_uncached(m, sig, spvals, optimize=true,
                                    params=params, hooks=hooks)
inferred || error("inference not successful")
println("Returns: $rettyp")
replprint(linfo)


#
# IRgen
#

# TODO
