# Copyright (c) 2014-2014, Yichao Yu <yyc1992@gmail.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 3.0 of the License, or (at your option) any later version.
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
# You should have received a copy of the GNU Lesser General Public
# License along with this library.

using Class

function f(x; a=2)
    return x + a
end

function f(x::FloatingPoint; a=2)
    # Keyword argument support
    return (@chain f(x::Any; a=a)) + 2
end

ex = :(@chain f(a, b..., c=0, d, e..., f::Int; g=0, h...))

@assert f(1) == 3
@assert f(1.) == 5
# Non-generic function support
@assert (@chain ((x) -> x + 1)(2::Any)) == 3

function g(x; kw...)
    return (x, kw)
end

function call_g()
    return g(1)
end

function call_g_kw()
    return g(1, b=2)
end

function chain_g()
    return @chain g(1::Any)
end

function chain_g_kw()
    return @chain g(1::Any, b=2)
end

function invoke_g()
    return invoke(g, (Any,), 1)
end

function invoke_g_kw()
    return invoke(g.env.kwsorter, (Array, Any), [:b, 2], 1)
end

function chain_invoke_g()
    return Class.chain_invoke_nokw(g, (Any,), 1)
end

function chain_invoke_g_kw()
    return Class.chain_invoke(g, (Any,), 1, b=2)
end

function time_func(f::Function)
    println(f)
    gc()
    @time for i in 1:1000000
        f()
    end
    gc()
end

# println(macroexpand(:(@chain g(1::Any))))

println("No keyword")
time_func(call_g)
time_func(invoke_g)
time_func(chain_g)
time_func(chain_invoke_g)

println()

println("With keyword")
time_func(call_g_kw)
time_func(invoke_g_kw)
time_func(chain_g_kw)
time_func(chain_invoke_g_kw)
