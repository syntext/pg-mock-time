# Repository Guidelines

## Project Structure & Module Organization
- Root contains the PostgreSQL extension sources and tooling.
  - `pg_mock_time_sql.c` – SQL-callable C functions (extension .so)
  - `pg_mock_time_simple.c` – LD_PRELOAD time interposer (.so)
  - `pg_mock_time.control`, `pg_mock_time--1.0.sql` – extension control and SQL wrappers
  - `Makefile`, `GNUmakefile`, `Makefile.docker` – build and Docker workflows
  - `docker-compose.yml`, `Dockerfile*` – containerized dev/test images
  - `test_extension.sh`, `test_mock_time.sql`, `example_test.sh`, `demo.sh` – tests and demos

## Build, Test, and Development Commands
- Primary workflow uses Docker (recommended):
  - `make build` – build Docker image with the extension
  - `make up` / `make down` / `make restart` – manage Postgres container
  - `make test` – run the integration test suite (8 checks)
  - `make demo` – interactive demonstration
  - `make shell` / `make bash` / `make logs` – connect and inspect
- Local (no Docker) targets are in `Makefile`:
  - `make -f Makefile install-all` – install extension and interposer locally
  - `make -f Makefile test-local` – run tests against a local Postgres

## Coding Style & Naming Conventions
- C (extension and interposer):
  - Indentation: 4 spaces; keep lines ≤ 100 chars
  - Names: functions `snake_case`, constants/macros `UPPER_SNAKE_CASE`
  - Place braces on the same line for functions/controls; prefer `static` for file‑local symbols
  - Keep dependencies minimal; include Postgres headers before others in the SQL module
- SQL: user-facing functions in `snake_case`; add SQL wrappers in `pg_mock_time--1.0.sql` that call the C entry points. If you introduce breaking changes, add a new `--X.Y.sql` and bump version in the control file.
- Shell: bash scripts should start with `#!/bin/bash` and `set -e` (match existing scripts).

## Testing Guidelines
- Run `make test` (Docker). For local instances, use `make -f Makefile test-local`.
- Extend `test_mock_time.sql` and `test_extension.sh` for new behavior. Cover:
  - fixed time, offset (positive/negative), advance/reset, status text
- No formal coverage gate; keep tests fast and deterministic.

## Commit & Pull Request Guidelines
- Commits: use clear, scoped messages; Conventional Commits style is encouraged (e.g., `feat: add advance_mock_time`).
- PRs: include a concise description, test plan (commands and expected output), related issues, and README/SQL updates when applicable. Include Docker and local repro steps if relevant.

## Security & Configuration Tips
- Intended for dev/test only. Time mocking relies on `LD_PRELOAD` and a world‑readable config at `/tmp/pg_mock_time.conf`. Do not deploy to production.
