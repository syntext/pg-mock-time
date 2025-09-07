#!/bin/bash
# Wrapper script to start PostgreSQL with time mocking library preloaded

# First start PostgreSQL normally
echo "Starting PostgreSQL..."
exec postgres "$@" &
PG_PID=$!

# Wait for PostgreSQL to be ready
sleep 2

# Now we can safely set LD_PRELOAD for child processes
export LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_lib.so

# Keep the wrapper running
wait $PG_PID