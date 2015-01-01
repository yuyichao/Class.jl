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

function transform_class_def!(ex::Symbol, prefix::String, base_class::Type)
    const sym_name = string(ex)
    const name_len = length(sym_name)
    if (name_len >= 3 && sym_name[1:2] == "__" &&
        sym_name[name_len - 1:name_len] != "__")
        return Symbol("$prefix$sym_name")
    end
    return ex
end

function transform_class_def!(ex::Expr, prefix::String, base_class::Type)
    if ex.head == :macrocall
        # Transform @__XXX to :__XXX without mangling
        if length(ex.args) == 1 && isa(ex.args[1], Symbol)
            const sym_name = string(ex.args[1])
            const name_len = length(sym_name)
            if (name_len >= 4 && sym_name[1:3] == "@__" &&
                sym_name[name_len - 1:name_len] != "__")
                return Symbol(sym_name[2:end])
            end
        end

        # Transform @mchain(...)
        if ex.args[1] == Symbol("@mchain")
            if length(ex.args) != 2
                error("Wrong number of arguments to @mchain")
            end
            ex.args[1] = Symbol("@chain")
            const chain_ex::Expr = ex.args[2]
            if chain_ex.head != :call
                error("Expect function call")
            end
            push!(ex.args, false)
            const meth_name::Symbol = chain_ex.args[1]
            const class_methods = get_class_methods(base_class)
            if haskey(class_methods, meth_name)
                chain_ex.args[1] = gen_func_fullname(class_methods[meth_name],
                                                     meth_name)
            else
                chain_ex.args[1] = _class_method(meth_name)
            end
            for i = 2:length(chain_ex.args)
                chain_ex.args[i] = transform_class_def!(chain_ex.args[i],
                                                        prefix, base_class)
            end
            return ex
        end
    end
    for i = 1:length(ex.args)
        ex.args[i] = transform_class_def!(ex.args[i], prefix, base_class)
    end
    return ex
end

function transform_class_def!(ex::QuoteNode, prefix::String, base_class::Type)
    transform_class_def!(ex.value, prefix, base_class)
    return ex
end

function transform_class_def!(ex::ANY, prefix::String, base_class::Type)
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
    const type_name::Symbol = gensym("class#$name")
    if body.head != :block
        error("Class body is not a block")
    end

    transform_class_def!(body, "_$type_name", base_class)

    const class_ast, func_names = gen_class_ast(cur_module, type_name,
                                                name, base_class, body)

    const esc_name = esc(name)
    const esc_type_name = esc(type_name)

    const tmp_mems::Symbol = gensym("members")

    return quote
        abstract $esc_name <: $base_class

        $(esc(class_ast))

        @inline function Class.get_class_type(::Type{$esc_name})
            return $esc_type_name
        end

        @inline function Class.get_class_methods(::Type{$esc_name})
            return $func_names
        end

        const $tmp_mems = _class_extract_members($esc_name, $func_names,
                                                 $esc_type_name)
        @inline function Class.get_class_members(::Type{$esc_name})
            return $tmp_mems
        end

        function Base.convert(::Type{$esc_name}, v)
            $(esc(Expr(:meta, :inline)))
            return convert($esc_type_name, v)
        end

        function Base.call(::Type{$esc_name}, args...; kwargs...)
            $(esc(Expr(:meta, :inline)))
            return call($esc_type_name, args...; kwargs...)
        end

        function Base.show(io::Base.IO, ::Type{$esc_type_name})
            $(esc(Expr(:meta, :inline)))
            return show(io, $esc_name)
        end

        $esc_name
    end
end

# This should work even if the way `A <: B` is parsed changes
@inline function gen_type_head(typ, base)
    return :(abstract $typ <: $base).args[1]
end

function gen_func_fullname(func_mod::(Symbol...), fname::Symbol)
    meth_name = :Main
    for field in [func_mod..., _class_method(fname)]
        meth_name = :($meth_name.$field)
    end
    return meth_name
end

function gen_mem_func_def(self::Symbol, func_mod::(Symbol...), fname::Symbol)
    const meth_name = gen_func_fullname(func_mod, fname)
    quote
        $self.$fname = $BoundMethod($self, $meth_name)
    end
end

function gen_class_ast(cur_module::Module, type_name::Symbol,
                       this_class::Symbol, base_class::Type, body::Expr)
    const func_names = copy(get_class_methods(base_class))
    const funcs = Any[]
    const cur_module_name = fullname(cur_module)

    const new_body = Expr(:block)
    for (m_name::Symbol, m_type::Type) in get_class_members(base_class)
        push!(new_body.args, Expr(:(::), m_name, Symbol(string(m_type.name))))
    end
    for expr in body.args
        if !(isa(expr, Expr) &&
             (expr.head == :(=) || expr.head == :function) &&
             expr.args[1].head == :call)
            push!(new_body.args, expr)
            continue
        end
        const func_name = expr.args[1].args[1]
        push!(funcs, expr)
        if !haskey(func_names, func_name)
            push!(func_names, func_name, cur_module_name)
        end
    end
    for (func_name, func_mod) in func_names
        push!(new_body.args, Expr(:(::), func_name, BoundMethod))
    end

    for f in funcs
        sig = f.args[1].args

        const func_mod = func_names[sig[1]]
        if func_mod != cur_module_name
            sig[1] = gen_func_fullname(func_mod, sig[1])
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

    const tmp_self = gensym("class#self")
    const init_func = @class_method __class_init__
    const constructor = quote
        function $type_name(args...; kwargs...)
            const $tmp_self = new()
            $(Expr(:block,
                   [gen_mem_func_def(tmp_self, func_mod, meth_name)
                    for (meth_name, func_mod) in func_names]...))
            $init_func($tmp_self, args...; kwargs...)
            $finalizer($tmp_self, $_class_finalize)
            return $tmp_self
        end
    end

    push!(new_body.args, constructor)

    const func_defs = Expr(:block, funcs...)
    const type_def = Expr(:type, true,
                          gen_type_head(type_name, this_class), new_body)

    quote
        $type_def
        $func_defs
    end, func_names
end

include("precompile.jl")

end
