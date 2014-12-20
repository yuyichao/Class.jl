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

module Class

using Base

include("class-utils.jl")

export @class, object, @chain, @is_toplevel, __class_init__

macro class(head::Union(Symbol, Expr), body::Expr)
    # TODO? support parametrized type
    if isa(head, Symbol)
        name = head
        esc_base_name = :(object)
        base_class = object
    else
        if (head.head != :comparison || length(head.args) != 3 ||
            head.args[2] != :<:)
            error("Invalid class declaration: $head.")
        end
        esc_base_name = esc(head.args[3])
        name = head.args[1]::Symbol
        base_class = current_module().eval(head.args[3])
    end
    type_name = gensym("$name")
    if body.head != :block
        error("Class body is not a block")
    end

    class_ast, func_names = gen_class_ast(type_name, name, base_class, body)

    esc_name = esc(name)
    esc_type_name = esc(type_name)

    def_tmp = gensym()
    names_tmp = gensym()

    return quote
        if !@is_toplevel
            error("Class can only be defined at module top level.")
        end

        $esc_base_name::Type
        if ! ($esc_base_name <: object && $esc_base_name.abstract)
            error(string("Base class ", $esc_base_name,
                         " is not a sub class of object"))
        end
        abstract $esc_name <: $esc_base_name

        $(esc(class_ast))
        _reg_type($esc_name, $func_names, $esc_type_name)

        function Base.convert(T::Type{$esc_name}, v)
            return convert($esc_type_name, v)
        end

        function Base.call(T::Type{$esc_name}, args...; kwargs...)
            return call($esc_type_name, args...; kwargs...)
        end

        function Base.show(io::Base.IO, x::Type{$esc_type_name})
            return show(io, $esc_name)
        end

        $esc_name
    end
end

function gen_class_ast(type_name, this_class, base_class, body)
    func_names = copy(class_methods[base_class])
    funcs = Any[]

    new_body = Expr(:block)
    for (m_name::Symbol, m_type::Type) in class_members[base_class]
        push!(new_body.args, Expr(:(::), m_name, Symbol(string(m_type.name))))
    end
    for expr in body.args
        if !(isa(expr, Expr) &&
             (expr.head == :(=) || expr.head == :function) &&
             expr.args[1].head == :call)
            push!(new_body.args, expr)
            continue
        end
        func_name = expr.args[1].args[1]
        push!(funcs, expr)
        if !any(map((f) -> (f[1] == func_name), func_names))
            push!(func_names, (func_name, current_module()))
        end
    end
    for (func_name, func_module) in func_names
        push!(new_body.args, Expr(:(::), func_name, :Function))
    end

    function get_func_module(fname)
        idx = findfirst((f) -> (f[1] == fname), func_names)
        return func_names[idx][2]
    end

    function get_func_fullname(func_module, fname)
        meth_name = :Main
        for field in [fullname(func_module)..., fname]
            meth_name = :($meth_name.$field)
        end
        return meth_name
    end

    function get_func_fullname(fname)
        return get_func_fullname(get_func_module(fname), fname)
    end

    for f in funcs
        sig = f.args[1].args

        func_module = get_func_module(sig[1])
        if func_module != current_module()
            sig[1] = get_func_fullname(func_module, sig[1])
        end

        if length(sig) < 2
            error("Too few arguments for member function")
        elseif isa(sig[2], Symbol)
            sig[2] = :($(sig[2])::$this_class)
        elseif isa(sig[2], Expr) && sig[2].head == :parameters
            if length(sig) < 3
                error("Too few arguments for member function")
            elseif isa(sig[3], Symbol)
                sig[3] = :($(sig[3])::$this_class)
            end
        end
    end

    tmp_self = gensym()

    function gen_mem_func_def(fname)
        tmp_func_name = gensym()
        meth_name = get_func_fullname(fname)
        # Hack because anonymous function does not allow keyword argument yet
        quote
            function $tmp_func_name(_args...; _kwargs...)
                return $meth_name($tmp_self, _args...; _kwargs...)
            end
            $tmp_self.$fname = $tmp_func_name;
        end
    end

    push!(new_body.args,
          :(function $type_name(args...; kwargs...)
            $tmp_self = new()
            $(Expr(:block,
                   [gen_mem_func_def(meth_name)
                    for (meth_name, func_module) in func_names]...))
            Main.Class.__class_init__($tmp_self, args...; kwargs...)
            finalizer($tmp_self, Main.Class._class_finalize)
            return $tmp_self
            end))

    func_defs = Expr(:block, funcs...)
    type_def = Expr(:type, true, Expr(:<:, type_name, this_class), new_body)

    quote
        $type_def
        $func_defs
    end, func_names
end

end
