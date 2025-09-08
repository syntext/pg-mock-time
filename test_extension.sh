#!/bin/bash
# Test script for pg_mock_time extension

set -e

echo "==================================="
echo "pg_mock_time Extension Test Suite"
echo "==================================="
echo ""

# Container name (overridable)
CONTAINER="${PG_CONTAINER_NAME:-pg-mock-time}"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec "$CONTAINER" pg_isready -U postgres > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "PostgreSQL failed to start in time"
        exit 1
    fi
    sleep 1
done

echo ""
echo "Running tests..."
echo "----------------"

# Test 1: Extension creation
echo -n "1. Extension creation... "
docker exec "$CONTAINER" psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /dev/null 2>&1
echo "✓"

# Test 2: Check initial status
echo -n "2. Initial status (disabled)... "
status=$(docker exec "$CONTAINER" psql -U postgres -t -c "SELECT pg_mock_time_status();" | tr -d ' \n')
if [ "$status" = "mock:disabled" ]; then
    echo "✓"
else
    echo "✗ (got: $status)"
fi

# Test 3: Set fixed time
echo -n "3. Set fixed time... "
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time('2025-01-01 12:00:00+00');" > /dev/null 2>&1
status=$(docker exec "$CONTAINER" psql -U postgres -t -c "SELECT pg_mock_time_status();" | grep -o "fixed")
if [ "$status" = "fixed" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 4: Set offset time
echo -n "4. Set offset time... "
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset(interval '1 hour');" > /dev/null 2>&1
status=$(docker exec "$CONTAINER" psql -U postgres -t -c "SELECT pg_mock_time_status();" | grep -o "offset")
if [ "$status" = "offset" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 5: Clear mock time
echo -n "5. Clear mock time... "
docker exec "$CONTAINER" psql -U postgres -c "SELECT clear_mock_time();" > /dev/null 2>&1
status=$(docker exec "$CONTAINER" psql -U postgres -t -c "SELECT pg_mock_time_status();" | tr -d ' \n')
if [ "$status" = "mock:disabled" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 6: Test convenience functions
echo -n "6. Convenience functions... "
funcs=$(docker exec "$CONTAINER" psql -U postgres -t -c "SELECT count(*) FROM pg_proc WHERE proname IN ('set_mock_time', 'set_mock_time_offset', 'advance_mock_time', 'reset_mock_time');" | tr -d ' \n')
if [ "$funcs" = "4" ]; then
    echo "✓"
else
    echo "✗ (found $funcs functions)"
fi

# Test 7: Test negative offset
echo -n "7. Negative offset... "
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset(interval '-2 hours');" > /dev/null 2>&1
status=$(docker exec "$CONTAINER" psql -U postgres -t -c "SELECT pg_mock_time_status();" | grep -o "\-7200")
if [ "$status" = "-7200" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 8: Reset via alias
echo -n "8. Reset via alias... "
docker exec "$CONTAINER" psql -U postgres -c "SELECT reset_mock_time();" > /dev/null 2>&1
status=$(docker exec "$CONTAINER" psql -U postgres -t -c "SELECT pg_mock_time_status();" | tr -d ' \n')
if [ "$status" = "mock:disabled" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 9: now() and current_date reflect fixed time
echo -n "9. now() and current_date reflect fixed time... "
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time('2025-01-01 12:00:00+00');" > /dev/null 2>&1
n_ok=$(docker exec "$CONTAINER" psql -U postgres -At -c "SELECT (now() = timestamptz '2025-01-01 12:00:00+00')::int")
d_ok=$(docker exec "$CONTAINER" psql -U postgres -At -c "SELECT (current_date = date '2025-01-01')::int")
docker exec "$CONTAINER" psql -U postgres -c "SELECT clear_mock_time();" > /dev/null 2>&1
if [ "$n_ok" = "1" ] && [ "$d_ok" = "1" ]; then
    echo "✓"
else
    echo "✗ (now_ok=$n_ok, date_ok=$d_ok)"
fi

# Test 10: now() reflects positive offset (~2 hours)
echo -n "10. now() reflects +2h offset... "
base=$(docker exec "$CONTAINER" psql -U postgres -At -c "SELECT extract(epoch FROM now())")
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset(interval '2 hours');" > /dev/null 2>&1
ok=$(docker exec "$CONTAINER" psql -U postgres -At -c "SELECT (abs(extract(epoch FROM now()) - $base - 7200) < 2)::int")
docker exec "$CONTAINER" psql -U postgres -c "SELECT clear_mock_time();" > /dev/null 2>&1
if [ "$ok" = "1" ]; then
    echo "✓"
else
    echo "✗"
fi

echo ""
echo "==================================="
echo "All tests completed!"
echo "===================================="
