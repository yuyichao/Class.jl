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

export @class

include("class-utils.jl")

function _transform_class_def!(ex::Symbol, prefix::String)
    sym_name = string(ex)
    name_len = length(sym_name)
    if (name_len >= 3 && sym_name[1:2] == "__" &&
        sym_name[name_len - 1:name_len] != "__")
        return Symbol("$prefix$sym_name")
    end
    return ex
end

function _transform_class_def!(ex::Expr, prefix::String)
    if ex.head == :macrocall
        # Transform @__XXX to :__XXX without mangling
        if length(ex.args) == 1 && isa(ex.args[1], Symbol)
            sym_name = string(ex.args[1])
            name_len = length(sym_name)
            if (name_len >= 4 && sym_name[1:3] == "@__" &&
                sym_name[name_len - 1:name_len] != "__")
                return Symbol(sym_name[2:end])
            end
        end

        # # Transform @method_chain(...) to @_method_chain(class, ...)
        # if length(ex.args) >= 1 && ex.args[1] == :method_chain
        #     ex.args[1] = :_method_chain
        # end
    end
    for i = 1:length(ex.args)
        ex.args[i] = _transform_class_def!(ex.args[i], prefix)
    end
    return ex
end

function _transform_class_def!(ex::QuoteNode, prefix::String)
    _transform_class_def!(ex.value, prefix)
    return ex
end

function _transform_class_def!(ex, prefix::String)
    return ex
end

macro class(head::Union(Symbol, Expr), body::Expr)
    # TODO? support parametrized type
    const cur_module::Module = current_module()
    if isa(head, Symbol)
        name = head::Symbol
        base_class = object::Type
    else
        if (head.head != :comparison || length(head.args) != 3 ||
            head.args[2] != :(<:))
            error("Invalid class declaration: $head.")
        end
        name = head.args[1]::Symbol
        base_class = cur_module.eval(head.args[3])::Type
        if !(base_class <: object)
            error("Base class $base_class is not a sub class of object")
        end
    end
    type_name::Symbol = gensym("class#$name")
    if body.head != :block
        error("Class body is not a block")
    end

    _transform_class_def!(body, "_$type_name")

    class_ast, func_names = gen_class_ast(cur_module, type_name,
                                          name, base_class, body)

    esc_name = esc(name)
    esc_type_name = esc(type_name)

    tmp_mems = gensym("members")

    return quote
        abstract $esc_name <: $base_class

        $(esc(class_ast))

        function Class._get_class_type(::Type{$esc_name})
            return $esc_type_name
        end

        function Class._get_class_methods(::Type{$esc_name})
            return $func_names
        end

        const $tmp_mems = _class_extract_members($esc_name, $func_names,
                                                 $esc_type_name)
        function Class._get_class_members(::Type{$esc_name})
            return $tmp_mems
        end

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

# This should work even if the way `A <: B` is parsed changes
function gen_type_head(typ, base)
    return :(abstract $typ <: $base).args[1]
end

function gen_class_ast(cur_module::Module, type_name::Symbol,
                       this_class::Symbol, base_class::Type, body::Expr)
    func_names = copy(_get_class_methods(base_class))
    funcs = Any[]
    const cur_module_name = fullname(cur_module)

    new_body = Expr(:block)
    for (m_name::Symbol, m_type::Type) in _get_class_members(base_class)
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
        push!(new_body.args, Expr(:(::), func_name, BoundMethod))
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
            $tmp_self.$fname = $BoundMethod($tmp_self, $meth_name)
        end
    end

    init_func = @class_method __class_init__

    constructor = quote
        function $type_name(args...; kwargs...)
            $tmp_self = new()
            $(Expr(:block,
                   [gen_mem_func_def(meth_name, func_module)
                    for (meth_name, func_module) in func_names]...))
            $init_func($tmp_self, args...; kwargs...)
            $finalizer($tmp_self, $_class_finalize)
            return $tmp_self
        end
    end

    push!(new_body.args, constructor)

    func_defs = Expr(:block, funcs...)
    type_def = Expr(:type, true,
                    gen_type_head(type_name, this_class), new_body)

    quote
        $type_def
        $func_defs
    end, func_names
end

end
