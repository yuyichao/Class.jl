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

using Class

function f(x; a=2)
    return x + a
end

function f(x::FloatingPoint; a=2)
    # Keyword argument support
    return (@chain f(x::Any; a=a)) + 2
end

ex = :(@chain f(a, b..., c=0, d, e..., f::Int; g=0, h...))

@assert f(1) == 3
@assert f(1.) == 5
# Non-generic function support
@assert (@chain ((x) -> x + 1)(2::Any)) == 3
