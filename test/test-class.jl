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

tic()
using Class
toc()

@class BaseClass begin
    __c::Int
    b::Float32
    function __class_init__(self, a::Int, b::Float32)
        self.__c = a
        self.b = b
        @mchain __class_init__(self::object)
    end
    function __class_init__(self, a::Int)
        @mchain __class_init__(self::BaseClass, a, Float32(a))
    end
    function __class_init__(self)
        @mchain __class_init__(self::BaseClass, 0)
    end
    function method(self)
        return BaseClass
    end
    function get_a(self)
        return self.__c
    end
    function get_b(self)
        return self.b
    end
end

const __global_sym = gensym()

derived_ex = quote
    @class DerivedClass <: BaseClass begin
        __c
        d
        function __class_init__(self)
            self.__class_init__(0, 0)
        end
        function __class_init__(self, c::Int64, d::Float32)
            @chain self.__class_init__(c::Any, d::Any)
        end
        function __class_init__(self, c, d, args...)
            self.__c = c
            self.d = d
            @mchain __class_init__(self::BaseClass, args...)
        end
        function method(self)
            return (@mchain method(self::BaseClass)), DerivedClass
        end
        function __get_c(self)
            return self.__c
        end
        function get_c(self)
            return self.__get_c()
        end
        function get_d(self)
            return self.d
        end

        function return_sym(self)
            return :(@__sym)
        end

        function return_global_sym(self)
            return @__global_sym
        end
    end
end

print("macroexpand: ")
@time expanded_derived_ast = macroexpand(derived_ex)

# println(expanded_derived_ast)

print("eval: ")
@time eval(expanded_derived_ast)

del_counter = 0
@class DelClass <: DerivedClass begin
    function __class_del__(self)
        global del_counter += 1
    end
end

@time d1 = DerivedClass()
@time d2 = DerivedClass(1, Float32(2))
@time d3 = DerivedClass(1, 2, 3)
@time d4 = DerivedClass(1, 2, 3, Float32(4))

println(d1)
println(d2)
println(d3)
println(d4)

gc()

@time for i in 1:10000
    DerivedClass()
end

gc()

@time for i in 1:10000
    BaseClass()
end

b = BaseClass(1, Float32(2))
d = DerivedClass(1, 2, 3, Float32(4))

println(b::object)
println(d::object)

@assert b.method() == BaseClass
@assert d.method() == (BaseClass, DerivedClass)

@assert b.get_a() == 1
@assert b.get_b() == 2

@assert d.get_a() == 3
@assert d.get_b() == 4
@assert d.get_c() == 1
@assert d.get_d() == 2

@assert d.return_sym() == :__sym
@assert d.return_global_sym() == __global_sym

@assert del_counter == 0
finalize(DelClass())
@assert del_counter == 1
