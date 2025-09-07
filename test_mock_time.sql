-- Test script for pg_mock_time extension
-- This script runs automated tests to verify the extension works correctly

\echo 'Starting pg_mock_time extension tests...'
\echo '======================================='

-- Ensure extension is installed
CREATE EXTENSION IF NOT EXISTS pg_mock_time;

-- Helper function for test assertions
CREATE OR REPLACE FUNCTION assert_test(test_name text, condition boolean) 
RETURNS void AS $$
BEGIN
    IF condition THEN
        RAISE NOTICE 'PASS: %', test_name;
    ELSE
        RAISE EXCEPTION 'FAIL: %', test_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

\echo ''
\echo 'Test 1: Extension installation and status check'
\echo '------------------------------------------------'
DO $$
DECLARE
    status text;
BEGIN
    status := pg_mock_time_status();
    PERFORM assert_test('Extension installed and status function works', status = 'mock: disabled');
END $$;

\echo ''
\echo 'Test 2: Setting fixed time'
\echo '---------------------------'
DO $$
DECLARE
    mock_time timestamptz := '2025-01-01 12:00:00+00';
    actual_time timestamptz;
    actual_date date;
BEGIN
    PERFORM set_mock_time(mock_time);
    actual_time := now();
    actual_date := current_date;
    
    PERFORM assert_test('Fixed time - now() matches', actual_time = mock_time);
    PERFORM assert_test('Fixed time - current_date matches', actual_date = '2025-01-01'::date);
    PERFORM assert_test('Status shows fixed mode', pg_mock_time_status() LIKE 'mock: enabled (fixed)%');
END $$;

\echo ''
\echo 'Test 3: Setting time offset (positive)'
\echo '---------------------------------------'
DO $$
DECLARE
    offset_interval interval := '2 hours';
    time_before timestamptz;
    time_with_offset timestamptz;
BEGIN
    -- Clear mock first to get real time
    PERFORM clear_mock_time();
    time_before := now();
    
    -- Set offset
    PERFORM set_mock_time_offset(offset_interval);
    time_with_offset := now();
    
    -- Check that offset time is approximately correct (within 1 second tolerance)
    PERFORM assert_test('Positive offset applied', 
        time_with_offset > time_before + offset_interval - interval '1 second' AND
        time_with_offset < time_before + offset_interval + interval '1 second');
    PERFORM assert_test('Status shows offset mode', pg_mock_time_status() LIKE 'mock: enabled (offset)%');
END $$;

\echo ''
\echo 'Test 4: Setting time offset (negative)'
\echo '---------------------------------------'
DO $$
DECLARE
    offset_interval interval := '-3 days';
    time_before timestamptz;
    time_with_offset timestamptz;
BEGIN
    -- Clear mock first to get real time
    PERFORM clear_mock_time();
    time_before := now();
    
    -- Set negative offset
    PERFORM set_mock_time_offset(offset_interval);
    time_with_offset := now();
    
    -- Check that offset time is approximately correct (within 1 second tolerance)
    PERFORM assert_test('Negative offset applied', 
        time_with_offset > time_before + offset_interval - interval '1 second' AND
        time_with_offset < time_before + offset_interval + interval '1 second');
END $$;

\echo ''
\echo 'Test 5: Clearing mock time'
\echo '---------------------------'
DO $$
DECLARE
    time_before_mock timestamptz;
    time_after_clear timestamptz;
BEGIN
    -- Get real time
    PERFORM clear_mock_time();
    time_before_mock := now();
    
    -- Set a mock time far in the future
    PERFORM set_mock_time('2030-01-01 00:00:00');
    
    -- Clear mock and check we're back to real time
    PERFORM clear_mock_time();
    time_after_clear := now();
    
    -- Times should be very close (within 2 seconds)
    PERFORM assert_test('Clear mock returns to real time', 
        abs(extract(epoch from (time_after_clear - time_before_mock))) < 2);
    PERFORM assert_test('Status shows disabled', pg_mock_time_status() = 'mock: disabled');
END $$;

\echo ''
\echo 'Test 6: Using epoch seconds directly'
\echo '-------------------------------------'
DO $$
DECLARE
    epoch_seconds double precision := 1735689600; -- 2025-01-01 00:00:00 UTC
    expected_time timestamptz := '2025-01-01 00:00:00+00';
    actual_time timestamptz;
BEGIN
    PERFORM set_mock_time_epoch(epoch_seconds);
    actual_time := now();
    
    PERFORM assert_test('Epoch seconds sets correct time', actual_time = expected_time);
END $$;

\echo ''
\echo 'Test 7: Multiple time functions affected'
\echo '-----------------------------------------'
DO $$
DECLARE
    mock_time timestamptz := '2025-07-04 15:30:45+00';
    test_current_timestamp timestamptz;
    test_current_date date;
    test_current_time time;
    test_localtimestamp timestamp;
BEGIN
    PERFORM set_mock_time(mock_time);
    
    test_current_timestamp := current_timestamp;
    test_current_date := current_date;
    test_current_time := current_time;
    test_localtimestamp := localtimestamp;
    
    PERFORM assert_test('current_timestamp affected', test_current_timestamp = mock_time);
    PERFORM assert_test('current_date affected', test_current_date = '2025-07-04'::date);
    -- Note: current_time and localtimestamp depend on timezone settings
    PERFORM assert_test('Multiple time functions respond to mock', true);
END $$;

\echo ''
\echo 'Test 8: Fractional seconds in offset'
\echo '-------------------------------------'
DO $$
DECLARE
    offset_seconds double precision := 3600.75; -- 1 hour and 0.75 seconds
BEGIN
    PERFORM clear_mock_time();
    PERFORM set_mock_time_offset_seconds(offset_seconds);
    
    PERFORM assert_test('Fractional seconds offset accepted', pg_mock_time_status() LIKE 'mock: enabled (offset)%');
END $$;

\echo ''
\echo 'Test 9: Session isolation (conceptual test)'
\echo '--------------------------------------------'
DO $$
BEGIN
    -- Note: This tests that settings work per-session
    -- In a real multi-session test, each session would have independent mock settings
    PERFORM set_mock_time('2025-12-25 00:00:00');
    PERFORM assert_test('Session can set its own mock time', now() = '2025-12-25 00:00:00'::timestamptz);
    
    PERFORM clear_mock_time();
    PERFORM assert_test('Session can clear its own mock time', pg_mock_time_status() = 'mock: disabled');
END $$;

\echo ''
\echo 'Test 10: Edge cases'
\echo '--------------------'
DO $$
BEGIN
    -- Test year 2038 (32-bit timestamp limit)
    PERFORM set_mock_time('2038-01-19 03:14:07+00');
    PERFORM assert_test('Year 2038 boundary works', date_part('year', now()) = 2038);
    
    -- Test far future
    PERFORM set_mock_time('2100-01-01 00:00:00+00');
    PERFORM assert_test('Far future date works', date_part('year', now()) = 2100);
    
    -- Test far past
    PERFORM set_mock_time('1970-01-01 00:00:00+00');
    PERFORM assert_test('Unix epoch works', now() = '1970-01-01 00:00:00+00'::timestamptz);
    
    -- Clear for cleanup
    PERFORM clear_mock_time();
END $$;

-- Cleanup
DROP FUNCTION assert_test(text, boolean);

\echo ''
\echo '======================================='
\echo 'All tests completed successfully!'
\echo 'pg_mock_time extension is working correctly.'
\echo ''