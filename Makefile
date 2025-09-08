# PostgreSQL image support (any PostgreSQL Docker image)
PG_IMAGE ?= postgres:latest
PG_CONTAINER_NAME ?= pg-mock-time

# Extract major version (e.g., 17 from postgres:17.4)
PG_MAJOR := $(shell echo "$(PG_IMAGE)" | sed -nE 's/.*:([0-9]+).*/\1/p')
ifeq ($(PG_MAJOR),)
  PG_MAJOR := default
endif

# Extract full tag (portable, no awk ternary)
# If PG_IMAGE has a tag (contains ':'), use the part after ':'; else 'latest'
PG_TAG := $(shell sh -c 'img="$(PG_IMAGE)"; tag=$$(printf "%s" "$$img" | sed -n "s/^[^:]*://p"); if [ -n "$$tag" ]; then printf "%s\n" "$$tag"; else printf "%s\n" latest; fi')
PG_TAGSAFE := $(shell sh -c "echo '$(PG_TAG)' | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g'")

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

## Detect docker compose command (supports both v1 and v2)
DOCKER_COMPOSE := $(shell command -v docker-compose >/dev/null 2>&1 && echo docker-compose || echo docker compose)

# Use a per-tag compose project name to avoid cross-version/OS volume reuse
COMPOSE_PROJECT_NAME := $(PG_CONTAINER_NAME)

# Docker management targets
docker-build:
	PG_IMAGE=$(PG_IMAGE) PG_MAJOR=$(PG_MAJOR) PG_CONTAINER_NAME=$(PG_CONTAINER_NAME) PG_PORT=$(PG_PORT) COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) $(DOCKER_COMPOSE) build

docker-up: docker-build
	PG_IMAGE=$(PG_IMAGE) PG_MAJOR=$(PG_MAJOR) PG_CONTAINER_NAME=$(PG_CONTAINER_NAME) PG_PORT=$(PG_PORT) COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) $(DOCKER_COMPOSE) up -d
	@echo "Waiting for PostgreSQL ($(PG_IMAGE)) to be ready..."
	@for i in $$(seq 1 30); do \
		docker exec $(PG_CONTAINER_NAME) pg_isready -U postgres >/dev/null 2>&1 && break || sleep 1; \
	done

docker-down:
	PG_IMAGE=$(PG_IMAGE) PG_MAJOR=$(PG_MAJOR) PG_CONTAINER_NAME=$(PG_CONTAINER_NAME) PG_PORT=$(PG_PORT) COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) $(DOCKER_COMPOSE) down -v

docker-restart: docker-down docker-up

# Clean targets
clean-docker:
	$(DOCKER_COMPOSE) down -v
	docker rmi pg-mock-time-postgres || true

clean-all: clean clean-docker
	rm -f pg_mock_time_simple.so pg_mock_time_sql.so *.o *.bc

# Development helpers
shell:
	docker exec -it $(PG_CONTAINER_NAME) psql -U postgres

bash:
	docker exec -it $(PG_CONTAINER_NAME) bash

logs:
	docker logs $(PG_CONTAINER_NAME)

# Installation test
install-test: install-all
	@echo "Testing installation..."
	@$(PG_CONFIG) --version
	@ls -la $(shell $(PG_CONFIG) --pkglibdir)/pg_mock_time* || echo "Files not found"
	@ls -la $(shell $(PG_CONFIG) --sharedir)/extension/pg_mock_time* || echo "Files not found"
