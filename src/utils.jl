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

const ENABLE_KW_HACK = true
# const ENABLE_KW_HACK = false

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
function Base.call(meth::BoundMethod, args::ANY...; kws...)
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
@inline function chain_invoke(f::Function, types::Tuple, args...; kws...)
    # FIXME, replace with the builtin invoke after it supports keyword arguments
    if isempty(kws)
        return invoke(f, types, args...)
    else
        return invoke(get_kwsorter(f), tuple(Array, types...),
                      pack_kwargs(;kws...), args...)
    end
end

@inline function chain_invoke(bm::BoundMethod, types::Tuple, args...; kws...)
    f = bm.func
    return chain_invoke(f, tuple(typeof(bm.self), types...), bm.self,
                        args...; kws...)
end

if ENABLE_KW_HACK
    @inline function chain_invoke(f::Function, types::Tuple, args...)
        return invoke(f, types, args...)
    end

    @inline function chain_invoke(bm::BoundMethod, types::Tuple, args...)
        f = bm.func
        return invoke(f, tuple(typeof(bm.self), types...), bm.self, args...)
    end

    const chain_invoke_kwsorter = chain_invoke.env.kwsorter

    @inline function chain_invoke.env.kwsorter(kws::Array, f::Function,
                                               types::Tuple, args...)
        return invoke(get_kwsorter(f), tuple(Array, types...),
                      kws, args...)
    end

    @inline function chain_invoke.env.kwsorter(kws::Array, bm::BoundMethod,
                                               types::Tuple, args...)
        f = bm.func
        return chain_invoke_kwsorter(kws, f, tuple(typeof(bm.self), types...),
                                     bm.self, args...)
    end
end

@inline function chain_invoke_nokw(f::Function, types::Tuple, args...)
    return invoke(f, types, args...)
end

@inline function chain_invoke_nokw(bm::BoundMethod, types::Tuple, args...)
    f = bm.func
    return invoke(f, tuple(typeof(bm.self), types...), bm.self, args...)
end

# Helper to generate arguments list that is evaluated in the correct order
@inline get_args(args::ANY...; kws...) = tuple(args..., kws)

if ENABLE_KW_HACK
    @inline get_args(args::ANY...) = args
    @inline get_args.env.kwsorter(kws::Array, args::ANY...) = tuple(args...,
                                                                    kws)
end

## Generic function and BoundMethod of a generic function is chainable
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
        # Handle non-generic function case if necessary
        const check_gf = Expr(:if, :(!$ischainable($efunc)),
                              esc(ex), Expr(:block))
        push!(ins_pos.args, check_gf)
        ins_pos = check_gf.args[3]
    end

    # construct a call to get_args() in order to evaluate all arguments and
    # type assertions in the builtin order
    const arg_types = Any[]
    const arg_vals = Any[]
    const get_args_res = Any[]
    const get_args_args = Any[]
    has_kw::Bool = false
    has_unpack::Bool = false

    for idx in 2:length(ex.args)
        arg = ex.args[idx]
        @gensym tmp_arg
        const etmp_arg = esc(tmp_arg)
        if isa(arg, Expr)
            if arg.head == :parameters || arg.head == :kw
                has_kw = true
                push!(get_args_args, arg)
                continue
            elseif arg.head == :(...)
                @assert length(arg.args) == 1
                has_unpack = true
                # Convert to tuple for typeof() and for iterating only once
                push!(get_args_args, :($tuple($arg)))
                push!(get_args_res, tmp_arg)
                push!(arg_types, Expr(:(...), :($typeof($tmp_arg))))
                push!(arg_vals, Expr(:(...), tmp_arg))
                continue
            elseif arg.head == :(::)
                @assert length(arg.args) == 2
                # Make sure both the value and the type are evaluated only once
                # The ::Any is added to make sure :(A...::B) (illegal now)
                # is handled properly
                push!(get_args_args, Expr(:(::), arg.args[1], Any))
                push!(get_args_res, tmp_arg)

                @gensym tmp_type
                const etmp_type = esc(tmp_type)
                push!(get_args_args, :($(arg.args[2])::$Type))
                push!(get_args_res, tmp_type)

                push!(arg_types, tmp_type)
                push!(arg_vals, tmp_arg)
                continue
            end
        end

        # Make sure the value is evaluated only once
        push!(get_args_args, arg)
        push!(get_args_res, tmp_arg)
        push!(arg_types, :($typeof($tmp_arg)))
        push!(arg_vals, tmp_arg)
    end

    const types_arg = if has_unpack
        Expr(:call, tuple, arg_types...)
    else
        Expr(:tuple, arg_types...)
    end

    if has_kw
        @gensym kwargs
        const ekwargs = esc(kwargs)

        push!(ins_pos.args,
              esc(Expr(:const, Expr(:(=), Expr(:tuple, get_args_res...,
                                               kwargs),
                                    Expr(:call, get_args,
                                         get_args_args...)))))
        if !ENABLE_KW_HACK
            push!(ins_pos.args, esc(Expr(:call, chain_invoke,
                                         Expr(:parameters,
                                              Expr(:(...), kwargs)),
                                         func, types_arg, arg_vals...)))
        else
            push!(ins_pos.args, esc(Expr(:call, chain_invoke_kwsorter, kwargs,
                                         func, types_arg, arg_vals...)))
        end
    else
        const pack_tuple = if has_unpack
            Expr(:call, tuple, get_args_args...)
        else
            Expr(:tuple, get_args_args...)
        end
        push!(ins_pos.args,
              esc(Expr(:const, Expr(:(=), Expr(:tuple, get_args_res...),
                                    pack_tuple))))
        push!(ins_pos.args, esc(Expr(:call, chain_invoke_nokw, func, types_arg,
                                     arg_vals...)))
    end

    return res
end

macro chain(args...)
    return gen_chain_ast(args...)
end

macro mchain(args...)
    error("@mchain can only be used in a class definition.")
end
