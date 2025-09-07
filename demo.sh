#!/bin/bash
# Interactive demo of pg_mock_time extension
# Demonstrates examples from README documentation

echo "==================================="
echo "pg_mock_time Extension Demo"
echo "==================================="
echo ""

# Ensure container is running
docker exec pg-mock-time pg_isready -U postgres > /dev/null 2>&1 || {
    echo "Starting PostgreSQL container..."
    docker-compose up -d
    sleep 5
}

# Create extension
echo "Setting up extension..."
docker exec pg-mock-time psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /dev/null 2>&1

echo ""
echo "=== BASIC COMMANDS (from README) ==="
echo ""

echo "1. Check initial status:"
docker exec pg-mock-time psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "2. Current real time (without LD_PRELOAD):"
docker exec pg-mock-time psql -U postgres -t -c "SELECT now();"

echo ""
echo "3. Set a fixed time (2025-01-01 12:00:00+00):"
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time('2025-01-01 12:00:00+00');"
docker exec pg-mock-time psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "4. Time with LD_PRELOAD (should show fixed time):"
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'

echo ""
echo "5. Set time offset (3 hours in the future):"
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time_offset('3 hours'::interval);"
docker exec pg-mock-time psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "6. Time with LD_PRELOAD (should show +3 hours offset):"
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'

echo ""
echo "7. Set negative offset (2 days in the past):"
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time_offset('-2 days'::interval);"
docker exec pg-mock-time psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "8. Time with LD_PRELOAD (should show -2 days offset):"
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'

echo ""
echo "=== ADVANCED USAGE ==="
echo ""

echo "9. Using epoch time directly (2024-01-01 00:00:00 UTC):"
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time_epoch(1704067200);"
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'

echo ""
echo "10. Using fractional seconds (1 hour and 0.5 seconds offset):"
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time_offset_seconds(3600.5);"
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'

echo ""
echo "11. Advance time from current mock state (30 minutes):"
docker exec pg-mock-time psql -U postgres -c "SELECT advance_mock_time('30 minutes'::interval);"
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'

echo ""
echo "=== PRACTICAL EXAMPLE: SUBSCRIPTION EXPIRY ==="
echo ""

echo "12. Setting up subscription test data:"
docker exec pg-mock-time psql -U postgres -c "DROP TABLE IF EXISTS subscriptions;"
docker exec pg-mock-time bash -c 'LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -c "
CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INT,
    expires_at TIMESTAMPTZ
);

INSERT INTO subscriptions (user_id, expires_at) VALUES
    (1, NOW() + INTERVAL '\''30 days'\''),
    (2, NOW() + INTERVAL '\''7 days'\'');

SELECT user_id, expires_at FROM subscriptions ORDER BY user_id;"'

echo ""
echo "13. Test expiry after 10 days offset:"
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time_offset(interval '10 days');"
docker exec pg-mock-time bash -c 'echo "SELECT user_id, expires_at, expires_at < NOW() as expired FROM subscriptions ORDER BY user_id;" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres'

echo ""
echo "14. Test year-end scenario (2025-12-31 23:59:59+00):"
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time('2025-12-31 23:59:59+00');"
docker exec pg-mock-time bash -c 'echo "SELECT NOW() as year_end_time;" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres'

echo ""
echo "15. Reset using alias function:"
docker exec pg-mock-time psql -U postgres -c "SELECT reset_mock_time();"  # Same as clear_mock_time()
docker exec pg-mock-time psql -U postgres -c "SELECT pg_mock_time_status();"

echo ""
echo "16. Final verification - back to real time:"
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'

# Cleanup
docker exec pg-mock-time psql -U postgres -c "DROP TABLE IF EXISTS subscriptions;" > /dev/null 2>&1

echo ""
echo "==================================="
echo "Demo Complete!"
echo "==================================="
echo ""
echo "This demo showed all examples from the README:"
echo "✓ Basic Commands - fixed time, offsets, status checking"
echo "✓ Advanced Usage - epoch time, fractional seconds, advance time"
echo "✓ Practical Example - subscription expiry testing"
echo "✓ LD_PRELOAD behavior - mocking only affects processes with LD_PRELOAD"
echo ""
echo "Perfect for testing time-dependent database operations!"