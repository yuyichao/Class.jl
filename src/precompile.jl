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

precompile(BoundMethod, ())
precompile(get_kwsorter, (Function,))
precompile(gen_chain_ast, (Expr, Bool))
precompile(pack_kwargs, (Array,))
precompile(pack_kwargs!, (Array{Any, 1}, Array,))

precompile(_class_method, (Symbol,))
precompile(@class_method(__class_init__), (object,))
precompile(@class_method(__class_del__), (object,))
precompile(get_class_type, (Type{object},))
precompile(get_class_members, (Type{object},))
precompile(get_class_methods, (Type{object},))
precompile(_class_extract_members,
           (Type, OrderedDict{Symbol, (Symbol...)}, Type))

precompile(transform_class_def!, (Symbol, String, Type))
precompile(transform_class_def!, (Expr, String, Type))
precompile(transform_class_def!, (QuoteNode, String, Type))
precompile(transform_class_def!, (ANY, String, Type))
precompile(gen_class_ast, (Module, Symbol, Symbol, Type, Expr))
precompile(_class, (Symbol, Expr))
precompile(_class, (Expr, Expr))
