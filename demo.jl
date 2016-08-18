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
function call_hook(f, tt)
    if f == child
        return hacked_child
    end
    return nothing
end
hooks = Core.Inference.InferenceHooks(call_hook)

(linfo, rettyp, inferred) = Core.Inference.typeinf_uncached(m, sig, spvals, optimize=true, hooks=hooks)
inferred || error("inference not successful")
println("Returns: $rettyp")
replprint(linfo)


#
# IRgen
#

# TODO
