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
