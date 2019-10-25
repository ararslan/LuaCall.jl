module LuaCall

let deps = joinpath(dirname(@__DIR__), "deps", "deps.jl")
    if isfile(deps)
        include(deps)
    else
        error("The LuaCall package is not properly installed. Run `using Pkg; ",
              "Pkg.build(\"LuaCall\")` and try again.")
    end
end

export luacall, @lua_str

const LUA_STATE = Ref{Ptr{Cvoid}}(C_NULL)

function __init__()
    state = ccall((:luaL_newstate, liblua), Ptr{Cvoid}, ())
    state == C_NULL && error("Failed to initialize Lua")
    ccall((:luaL_openlibs, liblua), Cvoid, (Ptr{Cvoid},), state)
    global LUA_STATE[] = state
    atexit(()->ccall((:lua_close, liblua), Cvoid, (Ptr{Cvoid},), LUA_STATE[]))
    nothing
end

struct Table
    name::Symbol
end

struct LuaError <: Exception
    msg::String

    LuaError(msg) = new(msg)
    function LuaError()
        msg = unsafe_getstack(String, -1)
        ccall((:lua_settop, liblua), Cvoid, (Ptr{Cvoid}, Cint), LUA_STATE[], -2)
        new(msg)
    end
end

Base.showerror(io::IO, ex::LuaError) = print(io, "LuaError: ", ex.msg)

#define LUA_TNONE		(-1)
#define LUA_TNIL		0
#define LUA_TBOOLEAN		1
#define LUA_TLIGHTUSERDATA	2
#define LUA_TNUMBER		3
#define LUA_TSTRING		4
#define LUA_TTABLE		5
#define LUA_TFUNCTION		6
#define LUA_TUSERDATA		7
#define LUA_TTHREAD		8

function checkstack(size::Int=1)
    ok = ccall((:lua_checkstack, liblua), Cint, (Ptr{Cvoid}, Cint), LUA_STATE[], size)
    ok == 1 || throw(LuaError("insufficient space on the Lua stack for $size items"))
    nothing
end

function stacktype(pos::Int=-1)
    t = ccall((:lua_type, liblua), Cint, (Ptr{Cvoid}, Cint), LUA_STATE[], pos)
    if t <= 0
        Nothing  # TODO: Differentiate nil and none?
    elseif t == 1
        Bool
    elseif t == 3
        int = ccall((:lua_isinteger, liblua), Cint, (Ptr{Cvoid}, Cint), LUA_STATE[], pos)
        int == 0 ? LuaFloat : LuaInt
    elseif t == 4
        String
    else
        name = ccall((:lua_typename, liblua), Cstring, (Ptr{Cvoid}, Cint), LUA_STATE[], t)
        error("Lua type ", unsafe_string(name), " is not currently supported")
    end
end

pushstack(value::Integer) =
    ccall((:lua_pushinteger, liblua), Cvoid, (Ptr{Cvoid}, LuaInt), LUA_STATE[], value)

pushstack(value::Bool) =
    ccall((:lua_pushboolean, liblua), Cvoid, (Ptr{Cvoid}, Cint), LUA_STATE[], value)

pushstack(value::Real) =
    ccall((:lua_pushnumber, liblua), Cvoid, (Ptr{Cvoid}, LuaFloat), LUA_STATE[], value)

pushstack(::Nothing) =
    ccall((:lua_pushnil, liblua), Cvoid, (Ptr{Cvoid},), LUA_STATE[])

pushstack(value::AbstractString) =
    ccall((:lua_pushlstring, liblua), Cvoid,
          (Ptr{Cvoid}, Ptr{UInt8}, Csize_t),
          LUA_STATE[], value, length(value))

function getstack(::Type{T}, pos::Int=-1) where T
    checkstack(-pos)
    unsafe_getstack(T, pos)
end

getstack() = getstack(stacktype(-1), -1)

function unsafe_getstack(::Type{T}, pos::Int) where T<:Integer
    isnum = Ref{Cint}(-1)
    x = ccall((:lua_tointegerx, liblua), LuaInt,
              (Ptr{Cvoid}, Cint, Ref{Cint}),
              LUA_STATE[], pos, isnum)
    @assert isnum[] == 1
    x
end

unsafe_getstack(::Type{Bool}, pos::Int) =
    ccall((:lua_toboolean, liblua), Cint, (Ptr{Cvoid}, Cint), LUA_STATE[], pos) != 0

function unsafe_getstack(::Type{T}, pos::Int) where T<:Real
    isnum = Ref{Cint}(-1)
    x = ccall((:lua_tonumberx, liblua), LuaFloat,
              (Ptr{Cvoid}, Cint, Ref{Cint}),
              LUA_STATE[], pos, isnum)
    @assert isnum[] == 1
    x
end

unsafe_getstack(::Type{Nothing}, pos::Int) = nothing

function unsafe_getstack(::Type{String}, pos::Int)
    len = Ref{Csize_t}(0)
    ptr = ccall((:lua_tolstring, liblua), Ptr{UInt8},
                (Ptr{Cvoid}, Cint, Ref{Csize_t}),
                LUA_STATE[], pos, len)
    unsafe_string(ptr, len[])
end

function pcallk(f::Symbol, rt::NTuple{N,DataType}, args...) where N
    checkstack(length(args) + N + 1)
    #stackdump()
    ccall((:lua_getglobal, liblua), Cvoid, (Ptr{Cvoid}, Cstring), LUA_STATE[], f)
    #stackdump()
    for arg in args
        pushstack(arg)
    end
    #stackdump()
    rc = ccall((:lua_pcallk, liblua), Cint,
               (Ptr{Cvoid}, Cint, Cint, Cint, Ptr{Cvoid}, Ptr{Cvoid}),
               LUA_STATE[], length(args), N, 0, C_NULL, C_NULL)
    rc == 0 || throw(LuaError())
    #stackdump()
    rc
end

function luacall(f::Symbol, rt::DataType, args...)
    rc = pcallk(f, (rt,), args...)
    @assert rc == 0
    result = getstack(rt)
    ccall((:lua_settop, liblua), Cvoid, (Ptr{Cvoid}, Cint), LUA_STATE[], -2)
    #stackdump()
    result
end

function luacall(f::Symbol, rt::NTuple{N,DataType}, args...) where N
    rc = pcallk(f, rt, args...)
    @assert rc == 0
    results = Vector{Any}(undef, N)
    @inbounds for i = N:-1:1
        results[i] = getstack(rt[N-i+1], -i)
    end
    ccall((:lua_settop, liblua), Cvoid, (Ptr{Cvoid}, Cint), LUA_STATE[], -N - 1)
    #stackdump()
    results
end

macro lua_str(code::String)
    rc = ccall((:luaL_loadstring, liblua), Cint, (Ptr{Cvoid}, Cstring), LUA_STATE[], code)
    rc == 0 || throw(LuaError())
    # Do an initial "priming" call, which ensures that Lua tells C everything it needs to
    # know about what has been defined
    rc = ccall((:lua_pcallk, liblua), Cint,
               (Ptr{Cvoid}, Cint, Cint, Cint, Ptr{Cvoid}, Ptr{Cvoid}),
               LUA_STATE[], 0, 0, 0, C_NULL, C_NULL)
    rc == 0 || throw(LuaError())
end

function stackdump()
    top = ccall((:lua_gettop, liblua), Cint, (Ptr{Cvoid},), LUA_STATE[])
    println("Lua stack (", top, " items):")
    for i = 1:top
        t = ccall((:lua_type, liblua), Cint, (Ptr{Cvoid}, Cint), LUA_STATE[], i)
        n = unsafe_string(ccall((:lua_typename, liblua), Ptr{UInt8},
                                (Ptr{Cvoid}, Cint), LUA_STATE[], t))
        print("  [", i, "]: ", n, " ")
        if t == 4
            len = Ref{Csize_t}(0)
            ptr = ccall((:lua_tolstring, liblua), Ptr{UInt8},
                        (Ptr{Cvoid}, Cint, Ref{Csize_t}),
                        LUA_STATE[], i, len)
            s = unsafe_string(ptr, len[])
            println(repr(s))
        elseif t == 1
            b = ccall((:lua_toboolean, liblua), Cint, (Ptr{Cvoid}, Cint), LUA_STATE[], i)
            println(b != 0)
        elseif t == 3
            isnum = Ref{Cint}(-1)
            x = ccall((:lua_tonumberx, liblua), Cdouble,
                      (Ptr{Cvoid}, Cint, Ref{Cint}),
                      LUA_STATE[], i, isnum)
            @assert isnum[] == 1
            println(x)
        else
            println()
        end
    end
    println()
    nothing
end

end # module
