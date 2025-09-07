# Test Dockerfile to verify GitHub integration works
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

# Final stage
FROM postgres:17-bookworm

# Copy the extension files from builder
COPY --from=builder /usr/share/postgresql/17/extension/pg_mock_time* /usr/share/postgresql/17/extension/
COPY --from=builder /usr/lib/postgresql/17/lib/pg_mock_time* /usr/lib/postgresql/17/lib/

# Create extension on startup
RUN echo "CREATE EXTENSION IF NOT EXISTS pg_mock_time;" > /docker-entrypoint-initdb.d/01-pg-mock-time.sql

# Add a test script
RUN echo "#!/bin/bash\n\
echo 'Testing pg_mock_time extension...'\n\
sleep 5\n\
psql -U postgres -c \"SELECT pg_mock_time_status();\"\n\
psql -U postgres -c \"SELECT set_mock_time('2025-01-01 12:00:00+00');\"\n\
LD_PRELOAD=/usr/lib/postgresql/17/lib/pg_mock_time_simple.so psql -U postgres -t -c \"SELECT now();\"\n\
psql -U postgres -c \"SELECT clear_mock_time();\"\n\
echo 'Test complete!'" > /test-extension.sh && chmod +x /test-extension.sh

ENV POSTGRES_PASSWORD=testpass