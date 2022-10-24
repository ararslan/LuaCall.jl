# LuaCall.jl

A Julia package for interoperability with [Lua](https://www.lua.org/).

[![Concept](https://www.repostatus.org/badges/latest/concept.svg)](https://www.repostatus.org/#concept)
[![CI](https://github.com/ararslan/LuaCall.jl/workflows/CI/badge.svg)](https://github.com/ararslan/LuaCall.jl/actions?query=workflow%3ACI+branch%3Amain)
[![Codecov](http://codecov.io/github/ararslan/LuaCall.jl/coverage.svg?branch=main)](http://codecov.io/github/ararslan/LuaCall.jl?branch=main)

Functionality:

- [x] `luacall` function that mimics `ccall`
- [x] `lua""` string macro for evaluating Lua code for access from Julia
- [ ] Support for tables
- [ ] Support for Lua threads
