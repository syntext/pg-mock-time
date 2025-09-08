# Set PostgreSQL image (can be overridden with --build-arg)
ARG PG_IMAGE=postgres:latest

# Stage 1: Build environment with dependencies (cached)
FROM ${PG_IMAGE} AS builder

# Install build dependencies matching the container's PostgreSQL major version
# Use PG_MAJOR provided by the official postgres image to select the right dev package
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    make \
    gcc \
    postgresql-server-dev-$PG_MAJOR \
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
FROM ${PG_IMAGE}

# Copy built extension from builder stage using runtime paths
# Since the builder might be using different paths, we copy dynamically
RUN mkdir -p /tmp/pg_lib /tmp/pg_ext

COPY --from=extension-builder /usr/lib/postgresql/*/lib/pg_mock_time* /tmp/pg_lib/
COPY --from=extension-builder /usr/share/postgresql/*/extension/pg_mock_time* /tmp/pg_ext/

# Install the extension files to the correct runtime paths
RUN PG_LIB_DIR=$(pg_config --pkglibdir) && \
    PG_EXT_DIR=$(pg_config --sharedir)/extension && \
    echo "Installing to PostgreSQL lib directory: $PG_LIB_DIR" && \
    echo "Installing to PostgreSQL extension directory: $PG_EXT_DIR" && \
    mkdir -p "$PG_LIB_DIR" && \
    mkdir -p "$PG_EXT_DIR" && \
    cp /tmp/pg_lib/* "$PG_LIB_DIR/" && \
    cp /tmp/pg_ext/* "$PG_EXT_DIR/" && \
    rm -rf /tmp/pg_lib /tmp/pg_ext && \
    ls -la "$PG_LIB_DIR"/pg_mock_time* && \
    ls -la "$PG_EXT_DIR"/pg_mock_time*

# Copy installation script
COPY install_extension.sh /docker-entrypoint-initdb.d/

# Create an entrypoint script that sets LD_PRELOAD dynamically
RUN echo '#!/bin/bash' > /usr/local/bin/pg-mock-time-entrypoint.sh && \
    echo 'export LD_PRELOAD=$(pg_config --pkglibdir)/pg_mock_time_simple.so' >> /usr/local/bin/pg-mock-time-entrypoint.sh && \
    echo 'echo "Setting LD_PRELOAD to: $LD_PRELOAD"' >> /usr/local/bin/pg-mock-time-entrypoint.sh && \
    echo 'exec "$@"' >> /usr/local/bin/pg-mock-time-entrypoint.sh && \
    chmod +x /usr/local/bin/pg-mock-time-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/pg-mock-time-entrypoint.sh"]
CMD ["docker-entrypoint.sh", "postgres"]

WORKDIR /
