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

export @chain, @is_toplevel

# Check if the current scope is the global module scope
macro is_toplevel()
    @gensym toplevel_test
    quote
        $(esc(toplevel_test)) = true
        try
            current_module().$toplevel_test === true
        catch
            false
        end
    end
end

# TODO?? check ABI version at runtime
const class_abi_version = 1

## BoundMethod
# Object representing a class method bound to an instance

immutable BoundMethod
    self
    func::Function
end

# Proxy call to underlying function
function Base.call(meth::BoundMethod, args...; kws...)
    return meth.func(meth.self, args...; kws...)
end

## keyword arguments related helper functions
# Needed before invoke supports keyword arguments

# Pack keyword arguments, logic copied from jl_g_kwcall
function pack_kwargs(;kws...)
    kwlen = length(kws)
    ary = Array(Any, 2 * kwlen)

    for i in 1:kwlen
        ary[2 * i - 1] = kws[i][1]
        ary[2 * i] = kws[i][2]
    end
    return ary
end

function get_kwsorter(f::Function)
    if !isdefined(f.env, :kwsorter)
        error("function $(f.env.name) does not accept keyword arguments")
    end
    return f.env.kwsorter
end

## Custom implementation of `invoke`
# Supports keyword arguments and BoundMethod
function chain_invoke(f::Function, types::Tuple, args...; kws...)
    # FIXME, replace with the builtin invoke after it supports keyword arguments
    if isempty(kws)
        # FIXME, replace with the builtin invoke after it is fixed
        meth = _chain_get_method(f, types)
        return meth.func(args...)
    else
        meth = _chain_get_method(get_kwsorter(f), tuple(Array, types...))
        return meth.func(pack_kwargs(;kws...), args...)
    end
end

function chain_invoke(bm::BoundMethod, types::Tuple, args...; kws...)
    f = bm.func
    return chain_invoke(f, tuple(typeof(bm.self), types...), bm.self,
                        args...; kws...)
end

function _chain_get_method(f::Function, new_types::ANY)
    meths = methods(f, new_types)
    for idx = length(meths):-1:1
        if new_types <: meths[idx].sig
            return meths[idx]
        end
    end
    error("Cannot find method")
end

@inline function ischainable(v::BoundMethod)
    return isgeneric(v.func)
end

@inline function ischainable(v::Function)
    return isgeneric(v)
end

@inline function ischainable(::ANY)
    return false
end

function gen_chain_ast(ex::Expr, maybe_non_gf::Bool=true)
    if ex.head != :call
        error("Expect function call")
    end

    @gensym func
    const efunc = esc(func)

    ins_pos = quote
        const $efunc = $(esc(ex.args[1]))
    end
    const res = Expr(:let, ins_pos)
    ex.args[1] = func

    if maybe_non_gf
        const check_gf = Expr(:if, :(!$ischainable($efunc)),
                              esc(ex), Expr(:block))
        push!(ins_pos.args, check_gf)
        ins_pos = check_gf.args[3]
    end

    const arg_types = Any[]
    const arg_vals = Any[]
    sizehint!(arg_types, length(ex.args) - 1)
    sizehint!(arg_vals, length(ex.args) - 1)
    sizehint!(ins_pos.args, length(ex.args))

    start_idx::Int
    const invoke_kw::Array{Expr, 1} = Expr[]

    if isa(ex.args[2], Expr) && ex.args[2].head == :parameters
        start_idx = 3
        push!(invoke_kw, ex.args[2])
    else
        start_idx = 2
    end

    for idx in start_idx:length(ex.args)
        arg = ex.args[idx]
        @gensym tmp_arg
        const etmp_arg = esc(tmp_arg)
        if isa(arg, Expr) && arg.head == :(...)
            @assert length(arg.args) == 1
            push!(ins_pos.args,
                  :(const $etmp_arg = $tuple($(esc(arg.args[1]))...)))
            push!(arg_types, Expr(:(...), :($typeof($tmp_arg))))
            push!(arg_vals, Expr(:(...), tmp_arg))
        elseif isa(arg, Expr) && arg.head == :(::)
            @assert length(arg.args) == 2
            push!(ins_pos.args, :(const $etmp_arg = $(esc(arg.args[1]))))
            @gensym tmp_type
            const etmp_type = esc(tmp_type)
            push!(ins_pos.args,
                  :(const $etmp_type = $(esc(arg.args[2]))::$Type))
            push!(arg_types, tmp_type)
            push!(arg_vals, tmp_arg)
        else
            push!(ins_pos.args, :(const $etmp_arg = $(esc(arg))))
            push!(arg_types, :($typeof($tmp_arg)))
            push!(arg_vals, tmp_arg)
        end
    end

    push!(ins_pos.args, esc(Expr(:call, chain_invoke, invoke_kw...,
                                 func, Expr(:call, tuple, arg_types...),
                                 arg_vals...)))

    return res
end

macro chain(args...)
    # TODO support BoundMethod
    return gen_chain_ast(args...)
end

macro mchain(args...)
    error("@mchain can only be used in a class definition.")
end
