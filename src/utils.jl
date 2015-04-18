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

macro top(sym::Symbol)
    TopNode(sym)
end

stagedfunction cat_tt{T<:Tuple}(t, ::Type{T})
    Tuple{t.parameters[1], T.parameters...}
end

stagedfunction cat_tt{T1<:Tuple, T2<:Tuple}(::Type{T1}, ::Type{T2})
    Tuple{T1.parameters..., T2.parameters...}
end

const ENABLE_KW_HACK = true
# const ENABLE_KW_HACK = false

@doc "Check if the current scope is the global module scope" ->
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

@doc "Object representing a class method bound to an instance" ->
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

function get_kwsorter(f::Function)
    if !isdefined(f.env, :kwsorter)
        error("function $(f.env.name) does not accept keyword arguments")
    end
    return f.env.kwsorter
end

## Custom implementation of `invoke`
# Supports keyword arguments and BoundMethod

function chain_invoke_nokw{T<:Tuple}(f::Function, types::Type{T}, args...)
    return invoke(f, types, args...)
end

function chain_invoke_nokw{T<:Tuple}(bm::BoundMethod, types::Type{T}, args...)
    const f::Function = bm.func
    const self = bm.self
    return invoke(f, cat_tt(typeof(self), types), self, args...)
end

function chain_invoke_kw{T<:Tuple}(kws::Array, f::Function,
                                   types::Type{T}, args...)
    return invoke(get_kwsorter(f), cat_tt(Array, types), kws, args...)
end

function chain_invoke_kw{T<:Tuple}(kws::Array, bm::BoundMethod,
                                   types::Type{T}, args...)
    const f::Function = bm.func
    const self = bm.self
    return invoke(get_kwsorter(f), cat_tt(Tuple{Array, typeof(self)}, types...),
                  kws, self, args...)
end

# Pack keyword arguments, logic copied from jl_g_kwcall
function pack_kwargs(kws::Array)
    const kwlen = length(kws)
    const ary = Array(Any, 2 * kwlen)

    for i in 1:kwlen
        const (key::Symbol, val) = kws[i]
        @inbounds ary[2 * i - 1] = key
        @inbounds ary[2 * i] = val
    end
    return ary
end

stagedfunction pack_kwargs{Ts<:Tuple}(kws::Ts)
    const kwlen = length(kws.parameters)
    ex = quote
        const ary = $(@top Array)($(@top Any), $(2 * kwlen))
        key::$(@top Symbol)
    end
    for i in 1:kwlen
        push!(ex.args, :((key, val) = kws[$i]))
        push!(ex.args, :(@inbounds ary[$(2 * i - 1)] = key))
        push!(ex.args, :(@inbounds ary[$(2 * i)] = val))
    end
    push!(ex.args, :(return ary))
    return ex
end

function pack_kwargs(kws)
    return pack_kwargs!(Any[], kws)
end

function pack_kwargs!(ary::Array, kws::Array)
    const orig_len = length(ary)
    const kwlen = length(kws)
    ccall(:jl_array_grow_end, Void, (Any, UInt), ary, kwlen * 2)

    for i in 1:kwlen
        const (key::Symbol, val) = kws[i]
        @inbounds ary[orig_len + 2 * i - 1] = key
        @inbounds ary[orig_len + 2 * i] = val
    end
    return ary
end

stagedfunction pack_kwargs!{Ts<:Tuple}(ary::Array, kws::Ts)
    const kwlen = length(kws.parameters)
    ex = quote
        const orig_len = length(ary)
        ccall(:jl_array_grow_end, Void, (Any, UInt), ary, $(kwlen * 2))
        key::$(@top Symbol)
    end
    for i in 1:kwlen
        push!(ex.args, :((key, val) = kws[$i]))
        push!(ex.args, :(@inbounds ary[orig_len + $(2 * i - 1)] = key))
        push!(ex.args, :(@inbounds ary[orig_len + $(2 * i)] = val))
    end
    push!(ex.args, :(return ary))
    return ex
end

function pack_kwargs!(ary::Array, kws)
    for kw in kws
        const (key::Symbol, val) = kw
        push!(ary, key)
        push!(ary, val)
    end
    return ary
end

if ENABLE_KW_HACK
    # Making forwarding of keyword arguments and generating keyword argument
    # pack much faster by directly define the kwsorter
    const chain_invoke = chain_invoke_nokw
    chain_invoke.env.kwsorter = chain_invoke_kw
else
    function chain_invoke{T<:Tuple}(f::Function, types::Type{T},
                                    args...; kws...)
        # FIXME, replace with the builtin invoke after it supports keyword
        # arguments
        if isempty(kws)
            return invoke(f, types, args...)
        else
            return invoke(get_kwsorter(f), cat_tt(Array, types),
                          pack_kwargs(kws), args...)
        end
    end

    function chain_invoke{T<:Tuple}(bm::BoundMethod, types::Type{T},
                                    args...; kws...)
        f = bm.func
        return chain_invoke(f, cat_tt(typeof(bm.self), types), bm.self,
                            args...; kws...)
    end
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

stagedfunction argtype(t)
    t
end

function argtypes(arg)
    map(argtype, arg)
end

function gen_chain_ast(ex::Expr, maybe_non_gf::Bool=true,
                       maybe_non_func::Bool=true)
    if ex.head != :call
        error("Expect function call")
    end

    @gensym func
    const efunc = esc(func)

    ins_pos = quote
        const $func = $(ex.args[1])
    end
    const res = esc(Expr(:let, ins_pos))
    ex.args[1] = func

    if maybe_non_gf
        # Handle non-generic function case if necessary
        # TODO: do not embed function directly
        const check_gf = Expr(:if, :(!$ischainable($func)), ex, Expr(:block))
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
                # Convert to tuple for typeof() and for iterating only once
                push!(get_args_args, Expr(:tuple, arg))
                push!(get_args_res, tmp_arg)
                # TODO: do not embed function directly
                push!(arg_types, Expr(:(...), :($argtypes($tmp_arg))))
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
                push!(get_args_args, :($(arg.args[2])::$(@top Type)))
                push!(get_args_res, tmp_type)

                push!(arg_types, tmp_type)
                push!(arg_vals, tmp_arg)
                continue
            end
        end

        # Make sure the value is evaluated only once
        push!(get_args_args, arg)
        push!(get_args_res, tmp_arg)
        # TODO: do not embed function directly
        push!(arg_types, :($argtype($tmp_arg)))
        push!(arg_vals, tmp_arg)
    end

    const types_arg = :(Tuple{$(arg_types...)})

    if has_kw
        @gensym kwargs
        const ekwargs = esc(kwargs)
        const call_get_args = Expr(:tuple, sort_kwargs(ins_pos.args,
                                                       get_args_args)...)
        push!(ins_pos.args,
              Expr(:const, Expr(:(=), Expr(:tuple, kwargs, get_args_res...),
                                call_get_args)))
        push!(ins_pos.args, Expr(:call, chain_invoke_kw, kwargs,
                                 func, types_arg, arg_vals...))
    else
        const pack_tuple = Expr(:tuple, get_args_args...)
        push!(ins_pos.args,
              Expr(:const, Expr(:(=), Expr(:tuple, get_args_res...),
                                pack_tuple)))
        call_invoke = Expr(:call, invoke, :($func::$(@top Function)),
                           types_arg, arg_vals...)
        # TODO: Do not embed type directly in AST
        if maybe_non_func
            call_invoke = Expr(:if, :($(@top isa)($func, $(@top Function))),
                               call_invoke,
                               Expr(:call, chain_invoke_nokw,
                                    :($func::$BoundMethod),
                                    types_arg, arg_vals...))
        end
        push!(ins_pos.args, call_invoke)
    end

    return res
end

@doc "Chaing function call to a more generic method" ->
macro chain(args...)
    return gen_chain_ast(args...)
end

@doc "Chaing class method call to a more generic method" ->
macro mchain(args...)
    error("@mchain can only be used in a class definition.")
end

function sort_kwargs(ins_pos, call_args)
    # This function does not handle unpacking positional argument specially
    paras_ins_pos = Any[]
    paras_kws_ins_pos = Any[]
    kws_ins_pos = Any[]

    kws_kw = Any[]
    paras_kws_kw = Any[]
    paras_kw = Any[]

    pos_args = Any[]

    for idx in 1:length(call_args)
        arg = call_args[idx]
        if !isa(arg, Expr)
            push!(pos_args, arg)
            continue
        end
        if arg.head == :kw
            @assert length(arg.args) == 2
            @gensym tmp_arg
            push!(kws_ins_pos, :(const $tmp_arg = $(arg.args[2])))
            push!(kws_kw, Expr(:quote, arg.args[1]::Symbol))
            push!(kws_kw, tmp_arg)
            continue
        elseif arg.head != :parameters
            push!(pos_args, arg)
            continue
        end
        for sub_i in 1:length(arg.args)
            sub_arg::Expr = arg.args[sub_i]
            @gensym tmp_arg
            if sub_arg.head == :kw
                @assert length(sub_arg.args) == 2
                push!(paras_kws_ins_pos,
                      :(const $tmp_arg = $(sub_arg.args[2])))
                push!(paras_kws_kw, Expr(:quote, sub_arg.args[1]::Symbol))
                push!(paras_kws_kw, tmp_arg)
                continue
            elseif sub_arg.head == :(...)
                @assert length(sub_arg.args) == 1
                push!(paras_ins_pos, :(const $tmp_arg = $(sub_arg.args[1])))
                push!(paras_kw, tmp_arg)
                continue
            else
                # Not sure if this is the most efficient way to do this...
                push!(paras_ins_pos, :(const $tmp_arg = $(sub_arg)))
                push!(paras_kw, Expr(:tuple, tmp_arg))
                continue
            end
        end
    end

    append!(kws_kw, paras_kws_kw)
    if isempty(paras_kw) && isempty(kws_kw)
        return Any[Any[], pos_args...]
    end

    append!(kws_ins_pos, paras_kws_ins_pos)
    append!(ins_pos, kws_ins_pos)
    append!(ins_pos, paras_ins_pos)

    @gensym tmp_kws

    if isempty(paras_kw)
        push!(ins_pos, :(const $tmp_kws = $(@top Any)[$(kws_kw...)]))
    else
        # TODO: do not embed function directly
        if isempty(kws_kw) && length(paras_kw) == 1
            paras_ex = :($pack_kwargs($(paras_kw[1])))
        else
            paras_ex = :($Any[$(kws_kw...)])
            for pack in paras_kw
                paras_ex = :($pack_kwargs!($paras_ex, $pack))
            end
        end
        push!(ins_pos, :(const $tmp_kws = $paras_ex))
    end
    return Any[tmp_kws, pos_args...]
end
