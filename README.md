## Class.jl

Class.jl is a package that provide certain python-like OO functions.

### License

Class.jl is a free software released under LGPLv3.

### Example

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
    f(1; a=1) # Number: 1, Any[(:a,1)]
    @chain f(2::Any; b=2) # ANY: 2, Any[(:b,2)]
    ```
