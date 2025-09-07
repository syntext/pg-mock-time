# PostgreSQL Mock Time Extension

A PostgreSQL extension that allows you to mock system time for testing time-dependent database operations. This extension uses `LD_PRELOAD` to intercept system time calls and provides SQL functions to control the mocked time.

## Features

- **Fixed Time Mode**: Set a specific timestamp that all time functions will return
- **Offset Mode**: Add/subtract time offset from the real system time  
- **File-Based Configuration**: Simple and reliable time mock configuration via `/tmp/pg_mock_time.conf`
- **Safe Monotonic Clocks**: Preserves monotonic clocks for internal PostgreSQL operations
- **Simple SQL API**: Control time mocking with simple SQL function calls

## Quick Start

### Including in Your Docker Image

Add pg_mock_time to your existing PostgreSQL Docker image:

```dockerfile
FROM postgres:17-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-17 \
    git \
    && rm -rf /var/lib/apt/lists/*

# Clone and build the extension from GitHub
RUN git clone https://github.com/syntext/pg-mock-time.git /tmp/pg-mock-time \
    && cd /tmp/pg-mock-time \
    && make -f Makefile \
    && make -f Makefile install-all

# Your production stage
FROM postgres:17-bookworm

# Copy the extension files from builder
COPY --from=builder /usr/share/postgresql/17/extension/pg_mock_time* /usr/share/postgresql/17/extension/
COPY --from=builder /usr/lib/postgresql/17/lib/pg_mock_time* /usr/lib/postgresql/17/lib/

# Your customizations...
```

Then in your database initialization:

```sql
CREATE EXTENSION IF NOT EXISTS pg_mock_time;
```

### Using This Repository Directly

```bash
# Clone this repository
git clone https://github.com/syntext/pg-mock-time.git
cd pg-mock-time

# Show available commands
make help

# Build and start PostgreSQL with the extension
make up

# Run the test suite
make test

# Run the interactive demo
make demo

# Open a PostgreSQL shell
make shell
```

### Using Docker Compose

```bash
# Build and start the container
docker-compose up -d

# Connect to the database
docker exec -it pg-mock-time psql -U postgres
```

## Usage

### Basic Commands

```sql
-- Create the extension
CREATE EXTENSION IF NOT EXISTS pg_mock_time;

-- Set a fixed time (all time functions return this value)
SELECT set_mock_time('2025-01-01 12:00:00+00');

-- Set a time offset (3 hours in the future)
SELECT set_mock_time_offset('3 hours'::interval);

-- Set a negative offset (2 days in the past)  
SELECT set_mock_time_offset('-2 days'::interval);

-- Disable time mocking (return to real time)
SELECT clear_mock_time();

-- Check current mock status
SELECT pg_mock_time_status();
-- Returns: 'mock: disabled' or 'mock: enabled (fixed) ...' or 'mock: enabled (offset) ...'
```

### Important: Using LD_PRELOAD for Time Interception

The time mocking only affects processes that have the `LD_PRELOAD` environment variable set. For testing:

```bash
# Run psql with time mocking enabled
docker exec pg-mock-time bash -c 'LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres'

# Or set it for specific queries
docker exec pg-mock-time bash -c 'echo "SELECT now();" | LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t'
```

### Advanced Usage

```sql
-- Using epoch time directly (Unix timestamp in seconds)
SELECT set_mock_time_epoch(1704067200); -- 2024-01-01 00:00:00 UTC

-- Using fractional seconds for precise control
SELECT set_mock_time_offset_seconds(3600.5); -- 1 hour and 0.5 seconds

-- Advance time from current mock state
SELECT advance_mock_time('30 minutes'::interval);

-- Reset using alias function
SELECT reset_mock_time(); -- Same as clear_mock_time()
```

## Integration Patterns

### For Testing Frameworks

When using pg_mock_time in your test suite:

```dockerfile
# test.Dockerfile
FROM postgres:17-bookworm AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-17 \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/syntext/pg-mock-time.git /tmp/pg-mock-time \
    && cd /tmp/pg-mock-time \
    && make -f Makefile && make -f Makefile install-all

FROM postgres:17-bookworm

COPY --from=builder /usr/share/postgresql/17/extension/pg_mock_time* /usr/share/postgresql/17/extension/
COPY --from=builder /usr/lib/postgresql/17/lib/pg_mock_time* /usr/lib/postgresql/17/lib/

# Create extension on startup
RUN echo "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /docker-entrypoint-initdb.d/01-pg-mock-time.sql
```

Then in your test code:

```javascript
// Example: Node.js test
beforeEach(async () => {
  // Set LD_PRELOAD for time mocking
  process.env.LD_PRELOAD = '/usr/lib/postgresql/17/lib/pg_mock_time_simple.so';
  
  // Reset time before each test
  await db.query("SELECT clear_mock_time()");
});

test('subscription expires after 30 days', async () => {
  // Create subscription
  await db.query("INSERT INTO subscriptions (expires_at) VALUES (NOW() + INTERVAL '30 days')");
  
  // Fast-forward 31 days
  await db.query("SELECT set_mock_time_offset(INTERVAL '31 days')");
  
  // Check expiry
  const expired = await db.query("SELECT * FROM subscriptions WHERE expires_at < NOW()");
  expect(expired.rows).toHaveLength(1);
});
```

### For Development Environments

```yaml
# docker-compose.yml for development
version: '3.8'

services:
  postgres:
    build:
      context: .
      dockerfile: |
        FROM postgres:17-bookworm AS builder
        RUN apt-get update && apt-get install -y build-essential postgresql-server-dev-17 git
        RUN git clone https://github.com/syntext/pg-mock-time.git /tmp/pg-mock-time \
            && cd /tmp/pg-mock-time && make -f Makefile && make -f Makefile install-all
        FROM postgres:17-bookworm
        COPY --from=builder /usr/share/postgresql/17/extension/pg_mock_time* /usr/share/postgresql/17/extension/
        COPY --from=builder /usr/lib/postgresql/17/lib/pg_mock_time* /usr/lib/postgresql/17/lib/
    environment:
      POSTGRES_DB: myapp_dev
      POSTGRES_USER: developer
      POSTGRES_PASSWORD: devpass
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
```

## Practical Example: Testing Time-Dependent Logic

```sql
-- Create a subscription system
CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INT,
    expires_at TIMESTAMPTZ
);

-- Insert test data
INSERT INTO subscriptions (user_id, expires_at) VALUES
    (1, NOW() + INTERVAL '30 days'),
    (2, NOW() + INTERVAL '7 days');

-- Test expiry at different times
SELECT set_mock_time_offset(interval '10 days');
-- Now queries will see time 10 days in the future

SELECT * FROM subscriptions WHERE expires_at < NOW();
-- Will show user 2's subscription as expired

-- Test specific date scenarios
SELECT set_mock_time('2025-12-31 23:59:59+00');
-- Test year-end logic

SELECT clear_mock_time();
-- Back to real time
```

## How It Works

The extension uses a two-component architecture:

1. **SQL Extension (`pg_mock_time_sql.so`)**: Provides PostgreSQL functions to control time mocking
2. **Interception Library (`pg_mock_time_simple.so`)**: Intercepts system time calls via `LD_PRELOAD`

The components communicate through a configuration file at `/tmp/pg_mock_time.conf`, making the system simple and reliable.

### Architecture Components

- **pg_mock_time_sql.c**: PostgreSQL extension providing SQL functions
- **pg_mock_time_simple.c**: Time interception library using LD_PRELOAD
- **pg_mock_time.control**: PostgreSQL extension control file
- **pg_mock_time--1.0.sql**: SQL function definitions and helpers
- **Dockerfile**: Multi-stage build for PostgreSQL 17
- **docker-compose.yml**: Container orchestration configuration

## Testing

### Run Full Test Suite

```bash
make test
```

This runs 8 comprehensive tests:
1. Extension creation
2. Initial status (disabled)
3. Fixed time mode
4. Offset time mode
5. Clear mock time
6. Convenience functions
7. Negative offset
8. Reset via alias

### Run Interactive Demo

```bash
make demo
```

This shows:
- Real time vs mocked time comparison
- Fixed time mode in action
- Offset mode demonstration
- How LD_PRELOAD affects time reading

### Run Practical Example

```bash
./example_test.sh
```

Demonstrates testing subscription expiry logic at different time points.

## Available Make Targets

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make build` | Build the Docker image with the extension |
| `make test` | Run the full test suite |
| `make demo` | Run interactive demonstration |
| `make up` | Start the PostgreSQL container |
| `make down` | Stop and remove the container |
| `make restart` | Restart the container |
| `make shell` | Open psql shell in container |
| `make bash` | Open bash shell in container |
| `make logs` | Show container logs |
| `make status` | Check extension status |
| `make clean` | Clean up containers and volumes |

## Limitations

- Requires `LD_PRELOAD` to be set for the client process to see mocked time
- Configuration is stored in `/tmp/pg_mock_time.conf` (cleared on system restart)
- Does not affect `CLOCK_MONOTONIC` to preserve internal PostgreSQL timing
- Each process reads the configuration independently

## Security Considerations

- This extension modifies fundamental system behavior and should **only be used in development/testing environments**
- **Never use in production databases**
- Requires superuser privileges to install
- The configuration file is world-readable at `/tmp/pg_mock_time.conf`

## Compatibility

- **PostgreSQL**: Version 17 tested
- **Operating System**: Linux Debian/Ubuntu tested
- **Architecture**: Supports both ARM64 (Apple Silicon) and x86_64 (tested)

## Troubleshooting

### Time mocking not working

Ensure `LD_PRELOAD` is set for your client process:

```bash
# Check if set in container environment
docker exec pg-mock-time printenv | grep LD_PRELOAD

# For time mocking to work, run clients with LD_PRELOAD
docker exec pg-mock-time bash -c 'LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres'
```

### Extension not found

```sql
-- Check if extension files are installed
SELECT * FROM pg_available_extensions WHERE name = 'pg_mock_time';

-- If not found, rebuild the image
make clean
make build
make up
```

### Build failures

```bash
# Clean everything and rebuild
make clean
docker system prune
make build
```

### Connection issues

```bash
# Check PostgreSQL status
make status
make logs

# Restart if needed
make restart
```

## Project Structure

```
pg-mock-time/
├── pg_mock_time_sql.c         # PostgreSQL extension functions
├── pg_mock_time_simple.c      # LD_PRELOAD interception library
├── pg_mock_time.control       # Extension control file
├── pg_mock_time--1.0.sql      # SQL function definitions
├── Dockerfile                 # Multi-stage Docker build
├── docker-compose.yml         # Container configuration
├── Makefile                   # Build system for extension
├── GNUmakefile                # Main makefile (delegates to Makefile.docker)
├── Makefile.docker            # Docker-based build commands
├── install_extension.sh       # Container initialization script
├── test_extension.sh          # Test suite script
├── demo.sh                    # Interactive demonstration
├── example_test.sh            # Practical usage example
└── README.md                  # This file
```

## Contributing

Contributions are welcome! Please ensure:
- Code follows PostgreSQL extension conventions
- All tests pass (`make test`)
- Documentation is updated for new features
- Examples demonstrate the feature clearly

## License

This project is provided as-is for testing and development purposes.

## Support

For issues, questions, or contributions, please open an issue on the project repository.