#!/bin/bash
# Test script for pg_mock_time extension

set -e

echo "==================================="
echo "pg_mock_time Extension Test Suite"
echo "==================================="
echo ""

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec pg-mock-time pg_isready -U postgres > /dev/null 2>&1; then
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
docker exec pg-mock-time psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /dev/null 2>&1
echo "✓"

# Test 2: Check initial status
echo -n "2. Initial status (disabled)... "
status=$(docker exec pg-mock-time psql -U postgres -t -c "SELECT pg_mock_time_status();" | tr -d ' \n')
if [ "$status" = "mock:disabled" ]; then
    echo "✓"
else
    echo "✗ (got: $status)"
fi

# Test 3: Set fixed time
echo -n "3. Set fixed time... "
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time('2025-01-01 12:00:00+00');" > /dev/null 2>&1
status=$(docker exec pg-mock-time psql -U postgres -t -c "SELECT pg_mock_time_status();" | grep -o "fixed")
if [ "$status" = "fixed" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 4: Set offset time
echo -n "4. Set offset time... "
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time_offset(interval '1 hour');" > /dev/null 2>&1
status=$(docker exec pg-mock-time psql -U postgres -t -c "SELECT pg_mock_time_status();" | grep -o "offset")
if [ "$status" = "offset" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 5: Clear mock time
echo -n "5. Clear mock time... "
docker exec pg-mock-time psql -U postgres -c "SELECT clear_mock_time();" > /dev/null 2>&1
status=$(docker exec pg-mock-time psql -U postgres -t -c "SELECT pg_mock_time_status();" | tr -d ' \n')
if [ "$status" = "mock:disabled" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 6: Test convenience functions
echo -n "6. Convenience functions... "
funcs=$(docker exec pg-mock-time psql -U postgres -t -c "SELECT count(*) FROM pg_proc WHERE proname IN ('set_mock_time', 'set_mock_time_offset', 'advance_mock_time', 'reset_mock_time');" | tr -d ' \n')
if [ "$funcs" = "4" ]; then
    echo "✓"
else
    echo "✗ (found $funcs functions)"
fi

# Test 7: Test negative offset
echo -n "7. Negative offset... "
docker exec pg-mock-time psql -U postgres -c "SELECT set_mock_time_offset(interval '-2 hours');" > /dev/null 2>&1
status=$(docker exec pg-mock-time psql -U postgres -t -c "SELECT pg_mock_time_status();" | grep -o "\-7200")
if [ "$status" = "-7200" ]; then
    echo "✓"
else
    echo "✗"
fi

# Test 8: Reset via alias
echo -n "8. Reset via alias... "
docker exec pg-mock-time psql -U postgres -c "SELECT reset_mock_time();" > /dev/null 2>&1
status=$(docker exec pg-mock-time psql -U postgres -t -c "SELECT pg_mock_time_status();" | tr -d ' \n')
if [ "$status" = "mock:disabled" ]; then
    echo "✓"
else
    echo "✗"
fi

echo ""
echo "==================================="
echo "All tests completed!"
echo "===================================="