#!/bin/bash
set -euo pipefail

# Refresh collation versions and REINDEX to resolve collation mismatches
# Works for PG 14+; uses DB-level REFRESH on PG >= 16, and per-collation refresh on older.

CONTAINER_NAME=${PG_CONTAINER_NAME:-pg-mock-time}

echo "Detecting server version..."
sv=$(docker exec "$CONTAINER_NAME" psql -U postgres -t -A -c "SHOW server_version_num" 2>/dev/null || true)
if [[ -z "$sv" ]]; then
  echo "PostgreSQL container not reachable (container: $CONTAINER_NAME)." >&2
  exit 1
fi

echo "server_version_num=$sv"

if (( sv >= 160000 )); then
  echo "Refreshing database-level collation version (PG >= 16)..."
  docker exec "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;"
else
  echo "Refreshing individual collations (PG < 16)..."
  # Find mismatched collations and refresh them
  mapfile -t colls < <(docker exec "$CONTAINER_NAME" psql -U postgres -t -A -F, -c \
    "SELECT quote_ident(n.nspname)||'.'||quote_ident(c.collname) \
     FROM pg_collation c \
     JOIN pg_namespace n ON n.oid=c.collnamespace \
     WHERE c.collversion IS DISTINCT FROM pg_collation_actual_version(c.oid);")
  if (( ${#colls[@]} > 0 )); then
    for coll in "${colls[@]}"; do
      [[ -z "$coll" ]] && continue
      echo "ALTER COLLATION ${coll} REFRESH VERSION;"
      docker exec "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -c "ALTER COLLATION ${coll} REFRESH VERSION;"
    done
  else
    echo "No mismatched collations found."
  fi
fi

echo "Reindexing database to rebuild any text-dependent indexes..."
docker exec "$CONTAINER_NAME" psql -U postgres -v ON_ERROR_STOP=1 -c "REINDEX DATABASE postgres;"

echo "Done."

