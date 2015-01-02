## Class.jl

Class.jl is a package that provide certain python-like OO functions.

### License

Class.jl is a free software released under LGPLv3.

### Examples

1. Function chaining

    The macro `@chain` provides similar function with the julia builtin
    function `invoke` with an interface that is easier to use.

    ```julia
    function f(x; kw...)
        println("ANY: $x, $kw")
    end
    function f(x::Number; kw...)
        println("Number: $x, $kw")
    end
    f(1, a=1; b=2) # Number: 1, Any[(:a,1),(:b,2)]
    @chain f(2::Any, b=2; c=3) # ANY: 2, Any[(:b,2),(:c,3)]
    ```

    All types of parameters are supported and the parameters are evaluated
    in the same way with a normal function call. There shouldn't be any
    noticeable overhead compare to using `invoke` directly either.

2. Check if the current scope is at module toplevel

    The macro `@is_toplevel` returns `true` if the current scope is at the
    toplevel of a module.

    ```julia
    julia> using Class
    julia> @is_toplevel
    true
    julia> (() -> @is_toplevel)()
    false
    ```

3. Defining classes

    The macro `@class` defines a new class

    ```julia
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
    ```
