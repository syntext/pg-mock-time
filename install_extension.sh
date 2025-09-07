#!/bin/bash
set -e

# Wait for PostgreSQL to be ready
until pg_isready -U postgres; do
  echo "Waiting for PostgreSQL to start..."
  sleep 1
done

# Create the extension in the postgres database
psql -U postgres -d postgres <<EOF
CREATE EXTENSION IF NOT EXISTS pg_mock_time;
EOF

echo "pg_mock_time extension installed successfully"