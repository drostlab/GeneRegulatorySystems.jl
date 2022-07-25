#!/bin/sh
BIN=$(dirname $0)
exec julia --project="$BIN" "$BIN/sample.jl" "$@"