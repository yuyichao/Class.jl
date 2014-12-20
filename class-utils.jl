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

function __class_init__(::object)
end

function __class_del__(::object)
end

_reg_type(object, [(:__class_init__, current_module()),
                   (:__class_del__, current_module())], object)

function _class_finalize(self::object)
    t = (typeof(self),)
    for del_meth = methods(__class_del__, (object,))
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

macro chain(ex::Expr)
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
    tmp_meth = gensym("method_found")

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

    quote
        let
            ($tmp_types, $tmp_args, $tmp_kwargs) = $(esc(call_helper))
            if !isempty($tmp_kwargs)
                # Due to anonymous function
                error("Keyword argument is not supported yet.")
            end
            $tmp_types_l = Type[$tmp_types...]
            $patch_types
            # TODO more robust for abstract base types
            $tmp_meth = chain_get_method($(esc(ex.args[1])), $tmp_types,
                                         tuple($tmp_types_l...))
            $tmp_meth.func($tmp_args...)
        end
    end
end

function chain_get_method(f, orig_types, new_types)
    meths = methods(f, new_types)
    for idx = length(meths):-1:1
        if new_types <: meths[idx].sig
            return meths[idx]
        end
    end
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
