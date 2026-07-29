# Root Makefile — coordinates all three repositories
#
# Dependency order:  platform-framework  →  platform-core  →  sales-application
#
# Quick start (development mode, editable path sources):
#   make sync-all
#   make test-all
#   make run
#
# Full released-packages workflow:
#   make pypi-start
#   make build-all
#   make publish-all
#   make docker-up

.PHONY: pypi-start pypi-stop sync-all test-all build-all publish-all run docker-up clean

# ── Local private PyPI server ─────────────────────────────────────────────────

pypi-start:
	docker compose -f local-pypi/docker-compose.yml up -d
	@echo "Waiting for PyPI server to be ready..."
	@until curl -sf http://localhost:8080/simple/ > /dev/null 2>&1; do sleep 1; done
	@echo "PyPI server running at http://localhost:8080"

pypi-stop:
	docker compose -f local-pypi/docker-compose.yml down

# ── Sync (development mode — editable path sources) ───────────────────────────

sync-all:
	cd platform-framework && uv sync --all-groups
	cd platform-core && uv sync --all-groups
	cd sales-application && uv sync --all-groups

# ── Tests ─────────────────────────────────────────────────────────────────────

test-all:
	@echo "\n── platform-framework ──"
	cd platform-framework && uv run pytest -v
	@echo "\n── platform-core ──"
	cd platform-core && uv run pytest -v
	@echo "\n── sales-application ──"
	cd sales-application && uv run pytest -v

# ── Build wheels (in dependency order) ───────────────────────────────────────

build-all:
	cd platform-framework && make build
	cd platform-core && make build
	cd sales-application && make build

# ── Publish wheels to local private index ─────────────────────────────────────
# Run `make pypi-start` first.

publish-all: build-all
	cd platform-framework && make publish
	cd platform-core && make publish

# ── Run the application (development mode) ────────────────────────────────────

run:
	cd sales-application && uv run uvicorn sales_api.main:app --reload --port 8000

# ── Docker (released-packages mode) ──────────────────────────────────────────
# Requires: make pypi-start && make publish-all first.

docker-up:
	cd sales-application && docker compose up --build

# ── Lock-file validation (CI) ─────────────────────────────────────────────────

check-locks:
	cd platform-framework && uv lock --check
	cd platform-core && uv lock --check
	cd sales-application && uv lock --check

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean:
	find . -type d -name ".venv" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "dist" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
