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
    tmp_var = gensym("toplevel_test")
    quote
        $(esc(tmp_var)) = true
        try
            current_module().$tmp_var === true
        catch
            false
        end
    end
end

const _method_prefix = gensym("class_method")
function _class_method(ex::Symbol)
    Symbol("$_method_prefix:#$ex")
end

function _class_method(ex)
    error("Expect symbol")
end

macro class_method(ex::Symbol)
    esc(_class_method(ex))
end

immutable BoundMethod
    self
    func::Function
end

function Base.call(meth::BoundMethod, args...; kws...)
    return meth.func(meth.self, args...; kws...)
end

@inline function _chain_get_method(f::Function, new_types)
    meths = methods(f, new_types)
    for idx = length(meths):-1:1
        if new_types <: meths[idx].sig
            return meths[idx]
        end
    end
    # TODO use no_method_error
    error("Cannot find method")
end

function _chain_call_with_types(f::Function, new_types::Array{Type},
                                args, kwargs)
    if !isempty(kwargs)
        # The following code is translated from c code in jl_f_kwcall
        # from (builtins.c). It is necessary to manually handle the keyword
        # arguments before non-generic function support keyword arguments.
        if !isdefined(f.env, :kwsorter)
            error("function $(f.env.name) does not accept keyword arguments")
        end
        f = f.env.kwsorter
        kwlen = length(kwargs)
        ary = Array(Any, 2 * kwlen)

        for i in 1:kwlen
            ary[2 * i - 1] = kwargs[i][1]
            ary[2 * i] = kwargs[i][2]
        end

        insert!(new_types, 1, Array)
        args = tuple(ary, args...)
    end

    meth = _chain_get_method(f, tuple(new_types...))
    return meth.func(args...)
end

function _chain_args_and_types(args...; kwargs...)
    return Base.typesof(args...), args, kwargs
end

function _chain_gen(ex::Expr, maybe_non_gf::Bool=true)
    if ex.head != :call
        error("Expect function call")
    end
    call_helper = copy(ex)
    call_helper.args[1] = _chain_args_and_types

    start_idx = (isa(ex.args[2], Expr) &&
                 ex.args[2].head == :parameters) ? 3 : 2

    args = ex.args[start_idx:end]

    tmp_types = gensym("orig_arg_types")
    tmp_types_l = gensym("requested_types")
    tmp_args = gensym("positional_arguments")
    tmp_kwargs = gensym("keyword_arguments")
    tmp_func = gensym("func")
    etmp_func = esc(tmp_func)

    patch_types = Expr(:block)

    for idx in 1:length(args)
        arg = args[idx]
        if isa(arg, Expr) && arg.head == :(::)
            push!(patch_types.args, quote
                  $tmp_types_l[$idx] = $(esc(arg.args[2]))
                  end)
        end
    end

    if isempty(patch_types.args)
        return ex
    end

    call_gf = quote
        const ($tmp_types, $tmp_args, $tmp_kwargs) = $(esc(call_helper))
        const $tmp_types_l = Type[$tmp_types...]
        $patch_types
        _chain_call_with_types($etmp_func, $tmp_types_l,
                               $tmp_args, $tmp_kwargs)
    end

    return if maybe_non_gf
        call_non_generic = copy(ex)
        call_non_generic.args[1] = tmp_func
        quote
            let
                const $etmp_func = $(esc(ex.args[1]))
                if !isgeneric($etmp_func)
                    $(esc(call_non_generic))
                else
                    $call_gf
                end
            end
        end
    else
        quote
            let
                const $etmp_func = $(esc(ex.args[1]))
                $call_gf
            end
        end
    end
end

macro chain(ex::Expr)
    return _chain_gen(ex)
end

macro mchain(ex::Expr)
    error("@mchain can only be used in a class definition.")
end
