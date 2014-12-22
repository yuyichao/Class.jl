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

# Use array to keep the order for now
class_methods = Dict{Type, Array{(Symbol, Module), 1}}()
class_members = Dict{Type, Array{(Symbol, Type), 1}}()
class_types = Dict{Type, Type}()

function _reg_type(t::Type, meths::Array{(Symbol, Module), 1}, real_type)
    class_types[t] = real_type
    class_methods[t] = meths
    class_members[t] = members = (Symbol, Type)[]
    for (m_name::Symbol, m_type::Type) in zip(real_type.names,
                                              real_type.types)
        if any(map((f) -> (f[1] == m_name), meths))
            continue
        end
        push!(members, (m_name, m_type))
    end
end

function @class_method(__class_init__)(::object)
end

function @class_method(__class_del__)(::object)
end

_reg_type(object, [(:__class_init__, current_module()),
                   (:__class_del__, current_module())], object)

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

function chain_convert_type(t::Type)
    if isa(t, Tuple)
        return tuple([chain_convert_type(sub_t) for sub_t in t]...)
    else
        try
            return class_types[t]
        catch
            return t
        end
    end
end

function _method_chain_gen(ex::Expr)
    if ex.head != :call
        error("Expect function call")
    end
    ex.args[1] = _class_method(ex.args[1])
    return _chain_gen(ex)
end

function _chain_gen(ex::Expr)
    # TODO, arguments with default value is not supported yet
    # just too lazy to do it
    # TODO handle non-generic functions
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

    patch_types = quote
    end

    for idx in 1:length(args)
        arg = args[idx]
        if isa(arg, Expr) && arg.head == :(::)
            push!(patch_types.args, quote
                  $tmp_types_l[$idx] = chain_convert_type($(esc(arg.args[2])))
                  end)
        end
    end

    call_non_generic = copy(ex)
    call_non_generic.args[1] = tmp_func

    quote
        let
            $etmp_func = $(esc(ex.args[1]))
            if !isgeneric($etmp_func)
                $(esc(call_non_generic))
            else
                ($tmp_types, $tmp_args, $tmp_kwargs) = $(esc(call_helper))
                $tmp_types_l = Type[$tmp_types...]
                $patch_types
                chain_call_with_types($etmp_func, $tmp_types,
                                      tuple($tmp_types_l...),
                                      $tmp_args, $tmp_kwargs)
            end
        end
    end
end

function chain_call_with_types(f, orig_types, new_types, args, kwargs)
    if isempty(kwargs)
        meth = chain_get_method(f, orig_types, new_types)
        return meth.func(args...)
    end

    # The following code is translated from c code in jl_f_kwcall (builtins.c)
    # This is necessary to manually handle the keyword arguments before
    # non-generic function support keyword arguments.
    if !isdefined(f.env, :kwsorter)
        error("function $(f.env.name) does not accept keyword arguments")
    end
    sorter = f.env.kwsorter
    meth = chain_get_method(sorter, tuple(Array, orig_types...),
                            tuple(Array, new_types...))
    func = meth.func

    kwlen = length(kwargs)
    ary = Array(Any, 2 * kwlen)

    for i in 1:kwlen
        ary[2 * i - 1] = kwargs[i][1]
        ary[2 * i] = kwargs[i][2]
    end

    return ccall(func.fptr, Any, (Any, Ptr{Void}, UInt32),
                 func, Any[ary, args...], length(args) + 1)
end

macro chain(ex::Expr)
    return _chain_gen(ex)
end

macro method_chain(ex::Expr)
    return _method_chain_gen(ex)
end

function chain_get_method(f, orig_types, new_types)
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

    mems = class_members[super(t)]

    show(io, t)
    print(io, '(')

    oid = object_id(x)
    shown_set = get(task_local_storage(), :SHOWNSET, nothing)
    if shown_set == nothing
        shown_set = Set()
        task_local_storage(:SHOWNSET, shown_set)
    end

    if oid in shown_set
        print(io, "#= circular reference =#")
    else
        push!(shown_set, oid)

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
    print(io,')')
end