-- pg_mock_time Extension Demo
-- This demonstrates how the extension works

\echo '==================================='
\echo 'pg_mock_time Extension Demo'
\echo '==================================='
\echo ''

-- Create the extension
CREATE EXTENSION IF NOT EXISTS pg_mock_time;

\echo '1. Initial status - time mocking is disabled:'
SELECT pg_mock_time_status();
SELECT now() AS current_real_time;

\echo ''
\echo '2. Set fixed time to 2025-01-01 12:00:00:'
SELECT set_mock_time('2025-01-01 12:00:00+00');
SELECT pg_mock_time_status();

\echo ''
\echo 'Note: Time interception requires LD_PRELOAD to be set for the client process.'
\echo 'The configuration has been saved to /tmp/pg_mock_time.conf'
\echo ''

-- Show that the configuration is active
\echo '3. Set time offset to +1 day:'
SELECT set_mock_time_offset(interval '1 day');
SELECT pg_mock_time_status();

\echo ''
\echo '4. Set negative offset (-2 hours):'
SELECT set_mock_time_offset(interval '-2 hours');
SELECT pg_mock_time_status();

\echo ''
\echo '5. Use convenience function to advance time by 30 minutes:'
SELECT advance_mock_time(interval '30 minutes');
SELECT pg_mock_time_status();

\echo ''
\echo '6. Reset to real time:'
SELECT reset_mock_time();
SELECT pg_mock_time_status();
SELECT now() AS back_to_real_time;

\echo ''
\echo '==================================='
\echo 'Demo Complete!'
\echo '==================================='
\echo ''
\echo 'To see time mocking in action, run a client with LD_PRELOAD set:'
\echo '  docker exec -e LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so pg-mock-time psql -U postgres'
\echo ''
\echo 'Or test with a simple time-checking query after setting mock time:'
\echo '  SELECT set_mock_time(''2025-01-01 00:00:00+00'');'
\echo '  -- Then in a new connection with LD_PRELOAD:'
\echo '  SELECT now();  -- Would show 2025-01-01 if LD_PRELOAD is active'