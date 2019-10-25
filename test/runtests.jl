using LuaCall
using Test

f(x, y) = (x^2 * sin(y)) / (1 - x)
lua"""
    function f(x, y)
        return (x^2 * math.sin(y)) / (1 - x)
    end
"""
@test luacall(:f, Float64, 2.0, 3.0) == f(2.0, 3.0)
