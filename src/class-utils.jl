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

const _method_prefix = gensym("class_method")

using DataStructures

function _class_method(ex::Symbol)
    Symbol("$_method_prefix:#$ex")
end

macro class_method(ex::Symbol)
    esc(_class_method(ex))
end

macro is_toplevel()
    tmp_var = gensym("toplevel_test")
    quote
        $(esc(tmp_var)) = true
        try
            current_module().$tmp_var
            true
        catch
            false
        end
    end
end

abstract object

immutable BoundMethod
    self::object
    func::Function
end

function Base.call(meth::BoundMethod, args...; kws...)
    return meth.func(meth.self, args...; kws...)
end

# Use array to keep the order for now
class_methods = Dict{Type, OrderedDict{Symbol, (Symbol...)}}()
class_members = Dict{Type, Array{(Symbol, Type), 1}}()
class_types = Dict{Type, Type}()

function _reg_type(t::Type, meths::OrderedDict{Symbol, (Symbol...)},
                   real_type::Type)
    class_types[t] = real_type
    class_methods[t] = meths
    class_members[t] = members = (Symbol, Type)[]
    for (m_name::Symbol, m_type::Type) in zip(real_type.names,
                                              real_type.types)
        if haskey(meths, m_name)
            continue
        end
        push!(members, (m_name, m_type))
    end
end

function @class_method(__class_init__)(::object)
end

function @class_method(__class_del__)(::object)
end

let cur_module_name = fullname(current_module())
    local func_names = OrderedDict{Symbol, (Symbol...)}()
    push!(func_names, :__class_init__, cur_module_name)
    push!(func_names, :__class_del__, cur_module_name)
    _reg_type(object, func_names, object)
end

function _class_finalize(self::object)
    t = (typeof(self),)
    for del_meth = methods(@class_method(__class_del__), (object,))
        if t <: del_meth.sig
            del_meth.func(self)
        end
    end
end

function chain_args_and_types(args...; kwargs...)
    return Base.typesof(args...), args, kwargs
end

function _method_chain_gen(ex::Expr)
    if ex.head != :call
        error("Expect function call")
    end
    ex.args[1] = _class_method(ex.args[1])
    return _chain_gen(ex, false)
end

function _chain_gen(ex::Expr, maybe_non_gf::Bool=true)
    # TODO, arguments with default value is not supported yet
    # just too lazy to do it
    if ex.head != :call
        error("Expect function call")
    end
    call_helper = copy(ex)
    call_helper.args[1] = :(Main.Class.chain_args_and_types)

    start_idx = (isa(ex.args[2], Expr) &&
                 ex.args[2].head == :parameters) ? 3 : 2

    args = ex.args[start_idx:end]

    tmp_types = gensym("orig_arg_types")
    tmp_types_l = gensym("requested_types")
    tmp_args = gensym("positional_arguments")
    tmp_kwargs = gensym("keyword_arguments (not supported yet)")
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
        ($tmp_types, $tmp_args, $tmp_kwargs) = $(esc(call_helper))
        $tmp_types_l = Type[$tmp_types...]
        $patch_types
        chain_call_with_types($etmp_func, $tmp_types, $tmp_types_l,
                              $tmp_args, $tmp_kwargs)
    end

    if maybe_non_gf
        call_non_generic = copy(ex)
        call_non_generic.args[1] = tmp_func
        quote
            $etmp_func = $(esc(ex.args[1]))
            if !isgeneric($etmp_func)
                $(esc(call_non_generic))
            else
                $call_gf
            end
        end
    else
        quote
            $etmp_func = $(esc(ex.args[1]))
            $call_gf
        end
    end
end

function chain_call_with_types(f::Function, orig_types, new_types::Array{Type},
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

        orig_types = tuple(Array, orig_types...)
        insert!(new_types, 1, Array)
        args = tuple(ary, args...)
    end

    meth = chain_get_method(f, orig_types, tuple(new_types...))
    return meth.func(args...)
end

macro chain(ex::Expr)
    return _chain_gen(ex)
end

macro method_chain(ex::Expr)
    return _method_chain_gen(ex)
end

function chain_get_method(f::Function, orig_types, new_types)
    meths = methods(f, new_types)
    for idx = length(meths):-1:1
        if new_types <: meths[idx].sig
            return meths[idx]
        end
    end
    # TODO use no_method_error
    error("Cannot find method")
end

function Base.show(io::IO, x::object)
    t = typeof(x)::DataType
    class_base = super(t)
    if !haskey(class_types, class_base) || t != class_types[class_base]
        return @chain show(io, x::ANY)
    end

    mems = class_members[class_base]

    show(io, t)
    print(io, '(')

    recorded = false
    oid = object_id(x)
    shown_set = get(task_local_storage(), :SHOWNSET, nothing)
    if shown_set == nothing
        shown_set = Set()
        task_local_storage(:SHOWNSET, shown_set)
    end

    try
        if oid in shown_set
            print(io, "#= circular reference =#")
        else
            push!(shown_set, oid)
            recorded = true

            n = length(mems)
            for i = 1:n
                f = mems[i][1]

                if !isdefined(x, f)
                    print(io, undef_ref_str)
                else
                    show(io, x.(f))
                end
                if i < n
                    print(io, ',')
                end
            end
        end
    finally
        if recorded
            delete!(shown_set, oid)
        end
    end
    print(io,')')
end
