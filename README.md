# PostgreSQL Mock Time Extension

A PostgreSQL extension that allows you to mock system time for testing time-dependent database operations. This extension uses `LD_PRELOAD` to intercept system time calls and provides SQL functions to control the mocked time.

## Supported PostgreSQL Versions

Requires PostgreSQL 14 or later.

## Features

- **Fixed Time Mode**: Set a specific timestamp that all time functions will return
- **Offset Mode**: Add/subtract time offset from the real system time  
- **File-Based Configuration**: Simple and reliable time mock configuration via `/tmp/pg_mock_time.conf`
- **Safe Monotonic Clocks**: Preserves monotonic clocks for internal PostgreSQL operations
- **Simple SQL API**: Control time mocking with simple SQL function calls

## Quick Start

### Choosing PostgreSQL Image

You can specify any PostgreSQL Docker image using the `PG_IMAGE` environment variable:

```bash
# Use default (latest PostgreSQL)
export PG_IMAGE=postgres:latest

# Use PostgreSQL 16 
export PG_IMAGE=postgres:16

# Use PostgreSQL 15 with bookworm
export PG_IMAGE=postgres:15-bookworm

# Use specific patch version
export PG_IMAGE=postgres:17.6

# Tested OS bases: Debian 12 (bookworm), Debian 13 (trixie)
```

### Building for Different PostgreSQL Images

```bash
# Build with default image (postgres:latest)
make docker-build

# Build with PostgreSQL 16
PG_IMAGE=postgres:16 make docker-build

# Build with PostgreSQL 15 bookworm
PG_IMAGE=postgres:15-bookworm make docker-build

# Build with specific version
PG_IMAGE=postgres:17.6 make docker-build

# Test with different images
PG_IMAGE=postgres:16 make test
PG_IMAGE=postgres:17 make test
```

### Including in Your Docker Image

Add pg_mock_time to your existing PostgreSQL Docker image:

```dockerfile
# Use ARG to specify PostgreSQL image
ARG PG_IMAGE=postgres:17.6
FROM ${PG_IMAGE} AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-all \
    git \
    && rm -rf /var/lib/apt/lists/*

# Clone and build the extension
RUN git clone https://github.com/syntext/pg-mock-time.git /tmp/pg-mock-time \
    && cd /tmp/pg-mock-time \
    && make -f Makefile \
    && make -f Makefile install-all

# Final stage
FROM ${PG_IMAGE}

# Stage built artifacts and install to runtime paths without relying on pg_config
RUN mkdir -p /tmp/pg_lib /tmp/pg_ext

COPY --from=builder /usr/lib/postgresql/*/lib/pg_mock_time* /tmp/pg_lib/
COPY --from=builder /usr/share/postgresql/*/extension/pg_mock_time* /tmp/pg_ext/

# Create init SQL to install the extension during initdb
RUN echo "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /docker-entrypoint-initdb.d/01-pg-mock-time.sql

# Locate target directories dynamically and install
RUN set -eux; \
    libdir=$(find /usr/lib/postgresql -maxdepth 2 -type d -name lib | head -n1); \
    extdir=$(find /usr/share/postgresql -maxdepth 2 -type d -name extension | head -n1); \
    test -n "$libdir" && test -n "$extdir"; \
    cp /tmp/pg_lib/* "$libdir/"; \
    cp /tmp/pg_ext/* "$extdir/"; \
    # Provide a stable path for LD_PRELOAD
    cp "$libdir/pg_mock_time_simple.so" /usr/local/lib/pg_mock_time_simple.so; \
    rm -rf /tmp/pg_lib /tmp/pg_ext; \
    ls -la "$libdir"/pg_mock_time*; \
    ls -la "$extdir"/pg_mock_time*

# Set LD_PRELOAD for the postgres process by default
ENV LD_PRELOAD=/usr/local/lib/pg_mock_time_simple.so

WORKDIR /
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
docker exec -it ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres
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

Validate `now()` and `current_date` after a change (new transaction):

```bash
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -c "SELECT set_mock_time('2025-01-01 12:00:00+00');"
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -At -c "SELECT now() = '2025-01-01 12:00:00+00'::timestamptz, current_date = date '2025-01-01'"
```

### Server Preload Required (LD_PRELOAD)

Time mocking only affects processes that load the interposer via `LD_PRELOAD`. For PostgreSQL queries like `now()` and `current_date`, the process that must be preloaded is the PostgreSQL backend (the server), not the client (`psql`, app, etc.).

This repository’s Dockerfile already sets `LD_PRELOAD` for the server via an entrypoint script, so you don’t need to set it for `psql`.

Verify the preload is active:

```bash
# Get a backend PID from inside the container
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -At -c 'SELECT pg_backend_pid()'

# Check the process has LD_PRELOAD set
PID=...                       # paste the PID from above
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} bash -lc "tr '\0' '\n' </proc/$PID/environ | grep LD_PRELOAD"

# (optional) Confirm the shared object is mapped
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} bash -lc "grep pg_mock_time_simple /proc/$PID/maps"
```

If you are integrating into your own image without this repo’s Dockerfile, ensure the server process is started with:

```bash
export LD_PRELOAD=$(pg_config --pkglibdir)/pg_mock_time_simple.so
exec docker-entrypoint.sh postgres
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


## Testcontainers

- Use `Dockerfile.example` as a base to produce an image that works with Testcontainers out of the box.
- The image:
  - Installs the extension files for the current Postgres version at build time.
  - Sets `LD_PRELOAD=/usr/local/lib/pg_mock_time_simple.so` via `ENV` (safe if no config file is present).
  - Keeps the official `docker-entrypoint.sh` and `CMD` (no custom entrypoint).
  - Honors `POSTGRES_USER`, `POSTGRES_DB`, and `POSTGRES_PASSWORD` in initialization to `CREATE EXTENSION`.

Example (Java):

```java
PostgreSQLContainer<?> pg = new PostgreSQLContainer<>(
    DockerImageName.parse("your-registry/pg-mock-time:testcontainers")
);
pg.start();

try (Connection c = DriverManager.getConnection(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword())) {
    try (Statement s = c.createStatement()) {
        s.execute("SELECT pg_mock_time_status()");
        s.execute("SELECT set_mock_time('2025-01-01 12:00:00+00')");
    }
}
```

To disable mocking in a specific test, override env: `withEnv("LD_PRELOAD", "")`.

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
- **Dockerfile**: Multi-stage build for any PostgreSQL version
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

- **PostgreSQL**: Versions 14 and later
- **Operating System**: Debian 12/13 tested; other OS/platforms not tested
- **Compiler/Toolchain**: Built with GCC provided by Debian 12/13 base images; other toolchains not tested

## Troubleshooting

### Collation version mismatch warnings

Symptoms:
- WARNING: database "postgres" has a collation version mismatch
- DETAIL: The database was created using collation version 2.36, but the operating system provides version 2.41.

Why this happens:
- PostgreSQL stores the OS collation library version (glibc/ICU) at initdb time. If you later start the same data directory on an image with a newer/different collation library, PostgreSQL warns because text sort order may differ.

Solid solutions:
- Avoid reusing data volumes across OS variants or major versions. This repo now derives a unique Compose project per `PG_IMAGE` tag, isolating volumes for each tag (e.g., `postgres:15-bookworm`, `postgres:17.4`, etc.).
- If you intentionally keep the data and just want to align collations:
  - PostgreSQL 16+: `make refresh-collations` (runs `ALTER DATABASE ... REFRESH COLLATION VERSION;` then `REINDEX DATABASE`).
  - PostgreSQL 14–15: `make refresh-collations` (refreshes each mismatched collation and reindexes the database).

If you don’t care about the data (dev/test):
- `make clean` to recreate the data volume under the current image’s collation library.

Prevention tips:
- Pin image tags (e.g., `postgres:15-bookworm`, `postgres:17.4-bookworm`) when you want consistent OS/glibc.
- Switch tags with separate volumes (already handled by the per-tag Compose project in Makefiles).

### Time mocking not working

Ensure the PostgreSQL server (not the client) is started with `LD_PRELOAD`:

```bash
# Check environment on a backend process
PID=$(docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -At -c 'SELECT pg_backend_pid()')
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} bash -lc "tr '\0' '\n' </proc/$PID/environ | grep LD_PRELOAD"

# Verify the shared object exists at runtime
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} bash -lc 'ls -l $(pg_config --pkglibdir)/pg_mock_time_simple.so'

# If not set, add an entrypoint that exports LD_PRELOAD before starting postgres
```

Also remember the semantics of `now()`:
- `now()` is fixed at the start of the current transaction.
- Use a new statement/transaction after changing the mock to observe the effect, or use `clock_timestamp()` to see immediate changes within the same transaction.

Example checks:

```bash
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -c "SELECT set_mock_time('2025-01-01 12:00:00+00');"
# New transaction
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -At -c "SELECT now() = '2025-01-01 12:00:00+00'::timestamptz"  # t
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -At -c "SELECT current_date = date '2025-01-01'"          # t
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -c "SELECT clear_mock_time();"
```

For offsets:

```bash
base=$(docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -At -c "SELECT extract(epoch FROM now())")
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -c "SELECT set_mock_time_offset(interval '2 hours');"
delta=$(docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -At -c "SELECT extract(epoch FROM now()) - $base")
echo $delta  # ~7200
docker exec ${PG_CONTAINER_NAME:-pg-mock-time} psql -U postgres -c "SELECT clear_mock_time();"
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
