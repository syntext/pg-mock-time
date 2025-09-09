#!/bin/bash
set -e

# Honor Testcontainers/official image env vars
PGUSER="${POSTGRES_USER:-postgres}"
PGDB="${POSTGRES_DB:-$PGUSER}"

# If a password is set (Testcontainers does this), use it for psql/pg_isready
if [ -n "${POSTGRES_PASSWORD:-}" ]; then
  export PGPASSWORD="${POSTGRES_PASSWORD}"
fi

# Wait for PostgreSQL to be ready
until pg_isready -U "$PGUSER" -d "$PGDB"; do
  echo "Waiting for PostgreSQL to start..."
  sleep 1
done

# Create the extension in the target database
psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDB" <<EOF
CREATE EXTENSION IF NOT EXISTS pg_mock_time;
EOF

echo "pg_mock_time extension installed successfully in database: $PGDB"
