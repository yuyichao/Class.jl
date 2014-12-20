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

include("Class.jl")

using Class

@class BaseClass begin
    a::Int
    b::Float32
    function __class_init__(self, a::Int, b::Float32)
        self.a = a
        self.b = b
    end
    function __class_init__(self, a::Int)
        self.a = a
        self.b = a
    end
    function __class_init__(self)
        self.a = 0
        self.b = 0
    end
    function method(self)
        return BaseClass
    end
    function get_a(self)
        return self.a
    end
    function get_b(self)
        return self.b
    end
end

@class DerivedClass <: BaseClass begin
    c
    d
    function __class_init__(self)
        self.__class_init__(0, 0)
    end
    function __class_init__(self, c::Int64, d::Float32)
        @chain __class_init__(self, c::Any, d::Any)
    end
    function __class_init__(self, c, d, args...)
        self.c = c
        self.d = d
        @chain __class_init__(self::BaseClass, args...)
    end
    function method(self)
        return (@chain method(self::BaseClass)), DerivedClass
    end
    function get_c(self)
        return self.c
    end
    function get_d(self)
        return self.d
    end
end

@time d1 = DerivedClass()
@time d2 = DerivedClass(1, float32(2))
@time d3 = DerivedClass(1, 2, 3)
@time d4 = DerivedClass(1, 2, 3, float32(4))

println(d1)
println(d2)
println(d3)
println(d4)

@time for i in 1:10000
    DerivedClass()
end

b = BaseClass(1, float32(2))
d = DerivedClass(1, 2, 3, float32(4))

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
