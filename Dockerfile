# Stage 1: Build environment with dependencies (cached)
FROM postgres:17-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    make \
    gcc \
    postgresql-server-dev-17 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create build directory
WORKDIR /build

# Stage 2: Build the extension
FROM builder AS extension-builder

# Copy source files
COPY pg_mock_time_simple.c pg_mock_time_sql.c pg_mock_time.control pg_mock_time--1.0.sql Makefile ./

# Build the extension
RUN make && make install-all

# Stage 3: Final image
FROM postgres:17-bookworm

# Copy built extension from builder stage
COPY --from=extension-builder /usr/lib/postgresql/17/lib/pg_mock_time* /usr/lib/postgresql/17/lib/
COPY --from=extension-builder /usr/share/postgresql/17/extension/pg_mock_time* /usr/share/postgresql/17/extension/

# Copy installation script
COPY install_extension.sh /docker-entrypoint-initdb.d/

# Set LD_PRELOAD to the interception library
ENV LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so

WORKDIR /