#!/usr/bin/env julia
#=
Server startup script - run from tools/server directory:
    julia run.jl
or directly:
    ./run.jl
=#

using Pkg

# Activate the server project
Pkg.activate(@__DIR__)

# Ensure all dependencies are available
Pkg.instantiate()

using Revise

# Enable logging
using Logging

global_logger(ConsoleLogger(stderr, Logging.Info))

import JSON

JSON.lower(s::Symbol) = String(s)

using Oxygen
using server

# Parse command line args
host = "127.0.0.1"
port = 8000

if length(ARGS) >= 1
    host = ARGS[1]
end
if length(ARGS) >= 2
    port = parse(Int, ARGS[2])
end

# Start server
server.serve(revise=:lazy, middleware=[Cors()], host=host, port=port)
