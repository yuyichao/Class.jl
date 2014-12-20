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
