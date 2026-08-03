# Coordinates the three independent repositories in dependency order:
# platform-framework -> platform-core -> sales-application.

SHELL := /bin/bash

.PHONY: \
	pypi-init-auth pypi-start pypi-stop pypi-status pypi-reset-packages \
	checkout-sales checkout-core checkout-framework checkout-all \
	git-status \
	sync-all dev-release dev-core dev-framework dev-all dev-status \
	test-all build-all publish-all run \
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

git-status:
	@./scripts/git-status.sh . python-multi-project-setup
	@if test -d platform-framework/.git; then ./scripts/git-status.sh platform-framework platform-framework; else echo "platform-framework: not checked out"; fi
	@if test -d platform-core/.git; then ./scripts/git-status.sh platform-core platform-core; else echo "platform-core: not checked out"; fi
	@if test -d sales-application/.git; then ./scripts/git-status.sh sales-application sales-application; else echo "sales-application: not checked out"; fi

checkout-sales:
	./checkout.sh sales

checkout-core:
	./checkout.sh core

checkout-framework:
	./checkout.sh framework

checkout-all:
	./checkout.sh all

sync-all:
	@test ! -d platform-framework || $(MAKE) -C platform-framework sync
	@test ! -d platform-core || $(MAKE) -C platform-core dev-release
	$(MAKE) -C sales-application dev-release

dev-release:
	$(MAKE) -C sales-application dev-release

dev-core:
	@test -d platform-core || (echo "platform-core is not checked out. Run 'make checkout-core'." >&2; exit 1)
	$(MAKE) -C sales-application dev-core

dev-framework:
	@test -d platform-framework || (echo "platform-framework is not checked out. Run 'make checkout-framework'." >&2; exit 1)
	$(MAKE) -C sales-application dev-framework

dev-all:
	@test -d platform-core && test -d platform-framework || (echo "Both platform repositories are required. Run 'make checkout-all'." >&2; exit 1)
	$(MAKE) -C sales-application dev-all

dev-status:
	$(MAKE) -C sales-application dev-status
	@test ! -d platform-core || $(MAKE) -C platform-core dev-status

test-all:
	@echo "── platform-framework ──"
	@test ! -d platform-framework || $(MAKE) -C platform-framework test
	@echo "── platform-core ──"
	@test ! -d platform-core || $(MAKE) -C platform-core test
	@echo "── sales-application ──"
	$(MAKE) -C sales-application test

build-all:
	$(MAKE) -C platform-framework build
	$(MAKE) -C platform-core build
	$(MAKE) -C sales-application build

publish-all: build-all
	$(MAKE) -C platform-framework publish
	$(MAKE) -C platform-core publish

run:
	$(MAKE) -C sales-application run

# ── Locks and source-policy validation ───────────────────────────────────────

check-locks:
	python3 scripts/validate-dev-profiles.py
	cd platform-framework && uv lock --check
	cd platform-core && uv lock --check
	$(MAKE) -C platform-core check-dev-locks
	cd sales-application && uv lock --check
	$(MAKE) -C sales-application check-dev-locks

check-image-locks:
	./scripts/check-image-locks.sh

refresh-image-locks:
	./scripts/refresh-image-locks.sh all

# ── Immutable Docker images ──────────────────────────────────────────────────

docker-release:
	@test -s $(PYPI_ENV) || (echo "Run 'make pypi-init-auth' first." >&2; exit 1)
	@set -a; . $(PYPI_ENV); set +a; \
		APP_REVISION=$(SALES_REVISION) \
		RELEASE_LOCK_CHECKSUM=$$(shasum -a 256 sales-application/uv.lock | awk '{print $$1}') \
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
