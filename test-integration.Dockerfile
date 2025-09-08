# Test Dockerfile to verify GitHub integration works
ARG PG_IMAGE=postgres:latest
FROM ${PG_IMAGE} AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-all \
    git \
    && rm -rf /var/lib/apt/lists/*

# Clone and build the extension from GitHub  
RUN git clone https://github.com/syntext/pg-mock-time.git /tmp/pg-mock-time \
    && cd /tmp/pg-mock-time \
    && make -f Makefile \
    && make -f Makefile install-all

# Final stage
FROM ${PG_IMAGE}

# Copy the extension files from builder (using wildcard for any PostgreSQL version)
COPY --from=builder /usr/share/postgresql/*/extension/pg_mock_time* /tmp/pg_ext/
COPY --from=builder /usr/lib/postgresql/*/lib/pg_mock_time* /tmp/pg_lib/

# Install to correct paths for this PostgreSQL version
RUN PG_LIB_DIR=$(pg_config --pkglibdir) && \
    PG_EXT_DIR=$(pg_config --sharedir)/extension && \
    mkdir -p "$PG_LIB_DIR" "$PG_EXT_DIR" && \
    cp /tmp/pg_lib/* "$PG_LIB_DIR/" && \
    cp /tmp/pg_ext/* "$PG_EXT_DIR/" && \
    rm -rf /tmp/pg_lib /tmp/pg_ext

# Create extension on startup
RUN echo "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /docker-entrypoint-initdb.d/01-pg-mock-time.sql

# Add a test script
RUN echo "#!/bin/bash\n\
echo 'Testing pg_mock_time extension...'\n\
sleep 5\n\
psql -U postgres -c \"SELECT pg_mock_time_status();\"\n\
psql -U postgres -c \"SELECT set_mock_time('2025-01-01 12:00:00+00');\"\n\
LD_PRELOAD=$(pg_config --pkglibdir)/pg_mock_time_simple.so psql -U postgres -t -c \"SELECT now();\"\n\
psql -U postgres -c \"SELECT clear_mock_time();\"\n\
echo 'Test complete!'" > /test-extension.sh && chmod +x /test-extension.sh

ENV POSTGRES_PASSWORD=testpass