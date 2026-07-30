# Coordinates the three independent repositories in dependency order:
# platform-framework -> platform-core -> sales-application.

SHELL := /bin/bash

.PHONY: \
	pypi-init-auth pypi-start pypi-stop pypi-status pypi-reset-packages \
	sync-all test-all build-all publish-all run \
	check-locks check-image-locks refresh-image-locks \
	docker-release docker-git docker-local docker-test-all clean

PYPI_ENV := local-pypi/.env
PYPI_PASSWORD_FILE := local-pypi/auth/htpasswd
SALES_REVISION := $(shell git -C sales-application rev-parse HEAD 2>/dev/null || printf unknown)

# ── Authenticated local package index ────────────────────────────────────────

pypi-init-auth:
	./scripts/init-pypi-auth.sh

pypi-start:
	@test -s $(PYPI_PASSWORD_FILE) && test -s $(PYPI_ENV) || \
		(echo "Local index credentials are missing. Run 'make pypi-init-auth' first." >&2; exit 1)
	docker compose -f local-pypi/docker-compose.yml up -d
	@echo "Waiting for the local package index..."
	@for attempt in $$(seq 1 30); do \
		curl --fail --silent http://localhost:8080/health >/dev/null && \
			echo "Local index is healthy at http://localhost:8080" && exit 0; \
		sleep 1; \
	done; \
	echo "Local index did not become healthy; run 'docker compose -f local-pypi/docker-compose.yml logs'." >&2; \
	exit 1

pypi-stop:
	docker compose -f local-pypi/docker-compose.yml down

pypi-status:
	docker compose -f local-pypi/docker-compose.yml ps
	@curl --fail --silent http://localhost:8080/health >/dev/null && \
		echo "Health endpoint: OK" || \
		(echo "Health endpoint: unavailable" >&2; exit 1)

pypi-reset-packages:
	@find local-pypi/packages -mindepth 1 -maxdepth 1 -type f \
		\( -name '*.whl' -o -name '*.tar.gz' -o -name '*.zip' \) -print -delete

# ── Host development ─────────────────────────────────────────────────────────

sync-all:
	cd platform-framework && uv sync --all-groups
	cd platform-core && uv sync --all-groups
	cd sales-application && uv sync --all-groups

test-all:
	@echo "── platform-framework ──"
	cd platform-framework && uv run pytest -v
	@echo "── platform-core ──"
	cd platform-core && uv run pytest -v
	@echo "── sales-application ──"
	cd sales-application && uv run pytest -v

build-all:
	$(MAKE) -C platform-framework build
	$(MAKE) -C platform-core build
	$(MAKE) -C sales-application build

publish-all: build-all
	$(MAKE) -C platform-framework publish
	$(MAKE) -C platform-core publish

run:
	cd sales-application && uv run uvicorn sales_api.main:app --reload --port 8000

# ── Locks and source-policy validation ───────────────────────────────────────

check-locks:
	cd platform-framework && uv lock --check
	cd platform-core && uv lock --check
	cd sales-application && uv lock --check

check-image-locks:
	./scripts/check-image-locks.sh

refresh-image-locks:
	./scripts/refresh-image-locks.sh all

# ── Immutable Docker images ──────────────────────────────────────────────────

docker-release:
	@test -s $(PYPI_ENV) || (echo "Run 'make pypi-init-auth' first." >&2; exit 1)
	@set -a; . $(PYPI_ENV); set +a; \
		APP_REVISION=$(SALES_REVISION) \
		RELEASE_LOCK_CHECKSUM=$$(shasum -a 256 sales-application/docker/modes/release/uv.lock | awk '{print $$1}') \
		docker buildx bake release

docker-git:
	@APP_REVISION=$(SALES_REVISION) \
		GIT_LOCK_CHECKSUM=$$(shasum -a 256 sales-application/docker/modes/git/uv.lock | awk '{print $$1}') \
		docker buildx bake git

docker-local:
	@APP_REVISION=$(SALES_REVISION) \
		LOCAL_LOCK_CHECKSUM=$$(shasum -a 256 sales-application/docker/modes/local/uv.lock | awk '{print $$1}') \
		docker buildx bake local

docker-test-all: docker-release docker-git docker-local
	./scripts/test-images.sh

# ── Generated local artifacts only ──────────────────────────────────────────

clean:
	@for repository in platform-framework platform-core sales-application; do \
		find "$$repository" -mindepth 1 -maxdepth 1 -type d \
			\( -name '.venv' -o -name 'dist' \) -print; \
	done
	@echo "Clean is intentionally non-destructive; remove the listed generated directories explicitly."
