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

include("utils.jl")

using DataStructures

export object
eval(Expr(:export, _class_method(:__class_init__)))

abstract object

function @class_method(__class_init__)(::object)
end

function @class_method(__class_del__)(::object)
end

function _get_class_type(::Type{object})
    return object
end

function _get_class_members(::Type{object})
    return (Symbol, Type)[]
end

let cur_module_name = fullname(current_module())
    global _get_class_methods
    local func_names = OrderedDict{Symbol, (Symbol...)}()
    push!(func_names, :__class_init__, cur_module_name)
    push!(func_names, :__class_del__, cur_module_name)
    function _get_class_methods(::Type{object})
        return func_names
    end
end

function _class_extract_members(t::Type,
                                meths::OrderedDict{Symbol, (Symbol...)},
                                real_type::Type)
    members = (Symbol, Type)[]
    for (m_name::Symbol, m_type::Type) in zip(real_type.names,
                                              real_type.types)
        if haskey(meths, m_name)
            continue
        end
        push!(members, (m_name, m_type))
    end
    return members
end

function _class_finalize(self::object)
    t = (typeof(self),)
    for del_meth = methods(@class_method(__class_del__), (object,))
        if t <: del_meth.sig
            del_meth.func(self)
        end
    end
end

function Base.show(io::IO, x::object)
    t = typeof(x)::DataType
    class_base = super(t)
    try
        _get_class_type(class_base)
    catch
        return @chain show(io, x::ANY)
    end

    mems = _get_class_members(class_base)

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
