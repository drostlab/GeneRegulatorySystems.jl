# Server Tool

## Running the Server

You will need to install `npm`.
To run both the backend and frontend simultaneously, use:

```bash
./tools/server/dev.sh
```

This will:
- Start the frontend (Vue.js dev server) in the background
- Display the frontend URL when ready
- Run the backend (Julia server) in the foreground, showing its logs

### Stopping the Server

Press `Ctrl+C` to cleanly shut down both the frontend and backend.

## Manual Setup

If you prefer to run them separately in different terminals:

**Terminal 1 (Backend):**
```bash
cd tools/server
julia --project=. run.jl
```

**Terminal 2 (Frontend):**
```bash
cd tools/server/grs-frontend
npm run dev
```
