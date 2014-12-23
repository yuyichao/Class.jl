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

export @class, object, @chain, @method_chain, @is_toplevel

include("class-utils.jl")

eval(Expr(:export, _class_method(:__class_init__)))

function _transform_class_def!(prefix::String, ex::Symbol)
    sym_name = string(ex)
    name_len = length(sym_name)
    if (name_len >= 3 && sym_name[1:2] == "__" &&
        sym_name[name_len - 1:name_len] != "__")
        return Symbol("$prefix$sym_name")
    end
    return ex
end

function _transform_class_def!(prefix::String, ex::Expr)
    if (ex.head == :macrocall && length(ex.args) == 1 &&
        isa(ex.args[1], Symbol))
        sym_name = string(ex.args[1])
        name_len = length(sym_name)
        if (name_len >= 4 && sym_name[1:3] == "@__" &&
            sym_name[name_len - 1:name_len] != "__")
            return Expr(:quote, Symbol(sym_name[2:end]))
        end
    end
    for i = 1:length(ex.args)
        ex.args[i] = _transform_class_def!(prefix, ex.args[i])
    end
    return ex
end

function _transform_class_def!(prefix::String, ex::QuoteNode)
    _transform_class_def!(prefix, ex.value)
    return ex
end

function _transform_class_def!(prefix::String, ex)
    return ex
end

macro class(head::Union(Symbol, Expr), body::Expr)
    # TODO? support parametrized type
    const cur_module::Module = current_module()
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
        base_class = cur_module.eval(head.args[3])
    end
    type_name = gensym("class#$name")
    if body.head != :block
        error("Class body is not a block")
    end

    _transform_class_def!("_$type_name", body)

    class_ast, func_names = gen_class_ast(cur_module, type_name,
                                          name, base_class, body)

    esc_name = esc(name)
    esc_type_name = esc(type_name)

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

        function Base.convert(::Type{$esc_name}, v)
            return convert($esc_type_name, v)
        end

        function Base.call(::Type{$esc_name}, args...; kwargs...)
            return call($esc_type_name, args...; kwargs...)
        end

        function Base.show(io::Base.IO, ::Type{$esc_type_name})
            return show(io, $esc_name)
        end

        $esc_name
    end
end

function gen_class_ast(cur_module::Module, type_name::Symbol,
                       this_class::Symbol, base_class::Type, body::Expr)
    func_names = copy(class_methods[base_class])
    funcs = Any[]
    const cur_module_name = fullname(cur_module)

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
        if !haskey(func_names, func_name)
            push!(func_names, func_name, cur_module_name)
        end
    end
    for (func_name, func_module) in func_names
        push!(new_body.args, Expr(:(::), func_name, :(Main.Class.BoundMethod)))
    end

    function get_func_fullname(func_module, fname)
        meth_name = :Main
        for field in [func_module..., _class_method(fname)]
            meth_name = :($meth_name.$field)
        end
        return meth_name
    end

    for f in funcs
        sig = f.args[1].args

        func_module = func_names[sig[1]]
        if func_module != cur_module_name
            sig[1] = get_func_fullname(func_module, sig[1])
        else
            sig[1] = _class_method(sig[1])
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

    tmp_self = gensym("class#self")

    function gen_mem_func_def(fname, func_module)
        meth_name = get_func_fullname(func_module, fname)
        quote
            $tmp_self.$fname = Main.Class.BoundMethod($tmp_self, $meth_name)
        end
    end

    push!(new_body.args,
          :(function $type_name(args...; kwargs...)
            $tmp_self = new()
            $(Expr(:block,
                   [gen_mem_func_def(meth_name, func_module)
                    for (meth_name, func_module) in func_names]...))
            Main.Class.@class_method(__class_init__)($tmp_self, args...;
                                                     kwargs...)
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
