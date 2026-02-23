#!/bin/bash

# Get the absolute directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"



# Ensure npm is installed
if ! command -v npm >/dev/null 2>&1; then
    echo "[dev.sh] npm not found. Please install Node.js and npm first."
    exit 1
fi

# Ensure Node.js version is >=20.19.0 or >=22.12.0
NODE_VERSION=$(node -v | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
NODE_MINOR=$(echo "$NODE_VERSION" | cut -d. -f2)
NODE_PATCH=$(echo "$NODE_VERSION" | cut -d. -f3)

version_gte() {
    # $1 = version string, $2 = required version string
    [ "$1" = "$2" ] && return 0
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 1
        fi
    done
    return 0
}

if ! version_gte "$NODE_VERSION" "20.19.0" && ! version_gte "$NODE_VERSION" "22.12.0"; then
    echo "[dev.sh] Node.js version $NODE_VERSION is too old. Please install Node.js >=20.19.0 or >=22.12.0."
    echo "You can use nvm (https://github.com/nvm-sh/nvm) to manage Node.js versions."
    exit 1
fi

# Ensure vite is installed in grs-frontend
if ! command -v vite >/dev/null 2>&1; then
    echo "[dev.sh] vite not found, running npm install in grs-frontend..."
    (cd "$SCRIPT_DIR/grs-frontend" && npm install)
fi

# Start frontend in background and capture output
(cd "$SCRIPT_DIR/grs-frontend" && npm run dev 2>&1 | tee /tmp/frontend.log) &
FRONTEND_PID=$!

# Wait a moment and extract the frontend URL
sleep 2
FRONTEND_URL=$(grep -oE 'http://[^ ]+' /tmp/frontend.log | head -1)
if [ -n "$FRONTEND_URL" ]; then
    echo "Frontend running at: $FRONTEND_URL"
fi

# Cleanup function
cleanup() {
    echo "Shutting down..."
    kill $FRONTEND_PID 2>/dev/null
    exit
}

# Trap Ctrl+C and call cleanup
trap cleanup SIGINT SIGTERM

# Run backend in foreground
cd "$SCRIPT_DIR"
julia --project=. run.jl
