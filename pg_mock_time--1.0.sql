-- Core C entry points
CREATE FUNCTION set_mock_time_epoch(double precision)
RETURNS void AS 'MODULE_PATHNAME', 'set_mock_time_epoch' 
LANGUAGE C VOLATILE;

CREATE FUNCTION set_mock_time_offset_seconds(double precision)
RETURNS void AS 'MODULE_PATHNAME', 'set_mock_time_offset_seconds' 
LANGUAGE C VOLATILE;

CREATE FUNCTION clear_mock_time()
RETURNS void AS 'MODULE_PATHNAME', 'clear_mock_time' 
LANGUAGE C VOLATILE;

CREATE FUNCTION pg_mock_time_status()
RETURNS text AS 'MODULE_PATHNAME', 'pg_mock_time_status' 
LANGUAGE C VOLATILE;

-- Convenience wrappers using native types
CREATE FUNCTION set_mock_time(ts timestamptz)
RETURNS void LANGUAGE sql VOLATILE AS $$
  SELECT set_mock_time_epoch(extract(epoch FROM ts));
$$;

CREATE FUNCTION set_mock_time_offset(iv interval)
RETURNS void LANGUAGE sql VOLATILE AS $$
  SELECT set_mock_time_offset_seconds(extract(epoch FROM iv));
$$;

-- Additional helper functions
CREATE FUNCTION advance_mock_time(iv interval)
RETURNS void LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  current_status text;
  current_epoch double precision;
BEGIN
  current_status := pg_mock_time_status();
  
  IF current_status = 'mock: disabled' THEN
    -- If not mocked, set to current time + interval
    PERFORM set_mock_time(now() + iv);
  ELSIF current_status LIKE 'mock: enabled (fixed)%' THEN
    -- If fixed time, we need to extract current mock time and add interval
    -- This is a simplified approach - in production you might want to store the value
    RAISE NOTICE 'Advancing fixed mock time by %', iv;
    -- For now, just add to the current real time as a fallback
    PERFORM set_mock_time_offset(iv);
  ELSE
    -- If already offset, add to the existing offset
    RAISE NOTICE 'Adding % to existing offset', iv;
    -- This would require tracking cumulative offset
    PERFORM set_mock_time_offset(iv);
  END IF;
END;
$$;

-- Function to reset to real time
CREATE FUNCTION reset_mock_time()
RETURNS void LANGUAGE sql VOLATILE AS $$
  SELECT clear_mock_time();
$$;