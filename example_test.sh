#!/bin/bash
set -e
# Example: Testing time-dependent database operations with pg_mock_time

echo "==================================="
echo "Example: Testing Expiry Logic"
echo "==================================="
echo ""

# Container name (overridable)
CONTAINER="${PG_CONTAINER_NAME:-pg-mock-time}"
echo "Using container: ${CONTAINER}"
echo ""

# Setup
docker exec "$CONTAINER" psql -U postgres -c "DROP TABLE IF EXISTS subscriptions;" 2>/dev/null
docker exec "$CONTAINER" psql -U postgres -c "
CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);"

docker exec "$CONTAINER" psql -U postgres -c "
INSERT INTO subscriptions (user_id, expires_at) VALUES
    (1, NOW() + INTERVAL '30 days'),
    (2, NOW() + INTERVAL '7 days'),
    (3, NOW() - INTERVAL '1 day');"

docker exec "$CONTAINER" psql -U postgres -c "
CREATE OR REPLACE FUNCTION get_expired_subscriptions()
RETURNS TABLE(id INT, user_id INT, expires_at TIMESTAMPTZ) AS \$\$
BEGIN
    RETURN QUERY
    SELECT s.id, s.user_id, s.expires_at
    FROM subscriptions s
    WHERE s.expires_at < NOW();
END;
\$\$ LANGUAGE plpgsql;"

echo "Test setup complete. Created subscriptions table with 3 records:"
echo "- User 1: expires in 30 days"
echo "- User 2: expires in 7 days"
echo "- User 3: already expired"
echo ""

echo "1. Checking expired subscriptions at current time:"
docker exec "$CONTAINER" psql -U postgres -c "SELECT * FROM get_expired_subscriptions();"

echo ""
echo "2. Setting time to 10 days in the future..."
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset(interval '10 days');" > /dev/null

echo "   Checking expired subscriptions:"
docker exec "$CONTAINER" psql -U postgres -c "SELECT * FROM get_expired_subscriptions();"

echo ""
echo "3. Setting time to 35 days in the future..."
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time_offset(interval '35 days');" > /dev/null

echo "   Checking expired subscriptions:"
docker exec "$CONTAINER" psql -U postgres -c "SELECT * FROM get_expired_subscriptions();"

echo ""
echo "4. Testing specific date (2025-01-01)..."
docker exec "$CONTAINER" psql -U postgres -c "SELECT set_mock_time('2025-01-01 00:00:00+00');" > /dev/null

echo "   Subscriptions status on 2025-01-01:"
docker exec "$CONTAINER" psql -U postgres -c '
SELECT 
    user_id,
    expires_at,
    CASE 
        WHEN expires_at < NOW() THEN ''EXPIRED''
        ELSE ''ACTIVE''
    END as status,
    NOW() as current_time
FROM subscriptions
ORDER BY user_id;'

# Cleanup
docker exec "$CONTAINER" psql -U postgres -c "SELECT clear_mock_time();" > /dev/null

echo ""
echo "==================================="
echo "Test Complete!"
echo "==================================="
echo ""
echo "This example shows how pg_mock_time can be used to:"
echo "- Test expiry logic without waiting for real time to pass"
echo "- Verify behavior at specific dates"
echo "- Test time-dependent queries and functions"
