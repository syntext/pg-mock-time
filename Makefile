EXTENSION = pg_mock_time
MODULE_big = pg_mock_time_sql
OBJS = pg_mock_time_sql.o
DATA = pg_mock_time--1.0.sql
PG_CONFIG = pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Build the interception library (after PGXS include)
pg_mock_time_simple.so: pg_mock_time_simple.c
	gcc -Wall -fPIC -shared -o $@ $< -ldl

# Additional all target that includes our library
all: pg_mock_time_simple.so

# Custom install target
install-all: install pg_mock_time_simple.so
	$(INSTALL_SHLIB) pg_mock_time_simple.so '$(DESTDIR)$(pkglibdir)/pg_mock_time_simple.so'

# Test targets
.PHONY: all install-all test test-local test-docker docker-build docker-up docker-down docker-restart pg_mock_time_simple.so

# Run tests (chooses docker or local based on environment)
test: test-docker

# Test in local PostgreSQL instance
test-local: install-all
	@echo "Testing in local PostgreSQL instance..."
	psql -U postgres -c "DROP EXTENSION IF EXISTS pg_mock_time CASCADE;"
	psql -U postgres -c "CREATE EXTENSION pg_mock_time;"
	psql -U postgres -f test_mock_time.sql

# Test in Docker container
test-docker: docker-up
	@echo "Testing in Docker container..."
	@./test_extension.sh

# Docker management targets
docker-build:
	docker-compose build

docker-up: docker-build
	docker-compose up -d
	@echo "Waiting for PostgreSQL to be ready..."
	@for i in $$(seq 1 30); do \
		docker exec pg-mock-time pg_isready -U postgres >/dev/null 2>&1 && break || sleep 1; \
	done

docker-down:
	docker-compose down -v

docker-restart: docker-down docker-up

# Clean targets
clean-docker:
	docker-compose down -v
	docker rmi pg-mock-time-postgres || true

clean-all: clean clean-docker
	rm -f pg_mock_time_simple.so pg_mock_time_sql.so *.o *.bc

# Development helpers
shell:
	docker exec -it pg-mock-time psql -U postgres

bash:
	docker exec -it pg-mock-time bash

logs:
	docker logs pg-mock-time

# Installation test
install-test: install-all
	@echo "Testing installation..."
	@$(PG_CONFIG) --version
	@ls -la $(shell $(PG_CONFIG) --pkglibdir)/pg_mock_time* || echo "Files not found"
	@ls -la $(shell $(PG_CONFIG) --sharedir)/extension/pg_mock_time* || echo "Files not found"