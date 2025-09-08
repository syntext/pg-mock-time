#!/bin/bash
# Interactive demo of pg_mock_time extension
# Demonstrates examples from README documentation

# Container name (overridable)
CONTAINER="${PG_CONTAINER_NAME:-pg-mock-time}"

echo "==================================="
echo "pg_mock_time Extension Demo"
echo "==================================="
echo ""

# Detect docker compose (v1 or v2)
detect_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

echo "Using container: ${CONTAINER}"
echo ""

# Ensure container is running
docker exec "$CONTAINER" pg_isready -U postgres > /dev/null 2>&1 || {
    echo "Starting PostgreSQL container..."
    DC=$(detect_compose)
    $DC up -d
    sleep 5
}

# Create extension
echo "Setting up extension..."
docker exec "$CONTAINER" psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /dev/null 2>&1

echo ""
echo "=== BASIC COMMANDS (from README) ==="
echo ""

echo "1. Check initial status:"
docker exec "$CONTAINER" psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "2. Current real time:"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

echo ""
echo "3. Set a fixed time (2025-01-01 12:00:00+00):"
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time('2025-01-01 12:00:00+00');"
docker exec "$CONTAINER" psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "4. Time should show fixed time (new transaction):"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

echo ""
echo "5. Set time offset (3 hours in the future):"
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset('3 hours'::interval);"
docker exec "$CONTAINER" psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "6. Time should show +3 hours offset (new transaction):"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

echo ""
echo "7. Set negative offset (2 days in the past):"
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset('-2 days'::interval);"
docker exec "$CONTAINER" psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "8. Time should show -2 days offset (new transaction):"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

echo ""
echo "=== ADVANCED USAGE ==="
echo ""

echo "9. Using epoch time directly (2024-01-01 00:00:00 UTC):"
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_epoch(1704067200);"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

echo ""
echo "10. Using fractional seconds (1 hour and 0.5 seconds offset):"
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset_seconds(3600.5);"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

echo ""
echo "11. Advance time from current mock state (30 minutes):"
docker exec "$CONTAINER" psql -U postgres -c "SELECT advance_mock_time('30 minutes'::interval);"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

echo ""
echo "=== PRACTICAL EXAMPLE: SUBSCRIPTION EXPIRY ==="
echo ""

echo "12. Setting up subscription test data:"
docker exec "$CONTAINER" psql -U postgres -c "DROP TABLE IF EXISTS subscriptions;"
docker exec "$CONTAINER" psql -U postgres -c 'CREATE TABLE subscriptions (id SERIAL PRIMARY KEY, user_id INT, expires_at TIMESTAMPTZ);'
docker exec "$CONTAINER" psql -U postgres -c "INSERT INTO subscriptions (user_id, expires_at) VALUES (1, NOW() + INTERVAL '30 days'), (2, NOW() + INTERVAL '7 days');"
docker exec "$CONTAINER" psql -U postgres -c 'SELECT user_id, expires_at FROM subscriptions ORDER BY user_id;'

echo ""
echo "13. Test expiry after 10 days offset:"
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset(interval '10 days');"
docker exec "$CONTAINER" psql -U postgres -c "SELECT user_id, expires_at, expires_at < NOW() as expired FROM subscriptions ORDER BY user_id;"

echo ""
echo "14. Test year-end scenario (2025-12-31 23:59:59+00):"
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time('2025-12-31 23:59:59+00');"
docker exec "$CONTAINER" psql -U postgres -c "SELECT NOW() as year_end_time;"

echo ""
echo "15. Reset using alias function:"
docker exec "$CONTAINER" psql -U postgres -c "SELECT reset_mock_time();"  # Same as clear_mock_time()
docker exec "$CONTAINER" psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "16. Final verification - back to real time:"
docker exec "$CONTAINER" psql -U postgres -t -c "SELECT now();"

# Cleanup
docker exec "$CONTAINER" psql -U postgres -c "DROP TABLE IF EXISTS subscriptions;" > /dev/null 2>&1

echo ""
echo "==================================="
echo "Demo Complete!"
echo "==================================="
echo ""
echo "This demo showed all examples from the README:"
echo "✓ Basic Commands - fixed time, offsets, status checking"
echo "✓ Advanced Usage - epoch time, fractional seconds, advance time"
echo "✓ Practical Example - subscription expiry testing"
echo "✓ Server preload behavior - mocking requires LD_PRELOAD on the PostgreSQL server"
echo ""
echo "Perfect for testing time-dependent database operations!"
