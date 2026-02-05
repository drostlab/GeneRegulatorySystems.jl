#!/bin/zsh

# Get the absolute directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
