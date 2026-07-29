# Local PyPI Server

A local private PyPI server used during development to host built wheels from the
`platform-framework` repo so that `platform-core` and `sales-application` can install
them without publishing to the public PyPI.

This directory is a coordination artifact — it does **not** have its own git repo.

## Starting the Server

```bash
docker compose up -d
```

The server listens on `http://localhost:8080`.

## Verifying the Server is Running

```bash
curl http://localhost:8080/simple/
```

You should see an HTML listing of available packages (empty at first).

## Building and Publishing a Wheel

From inside a repo (e.g. `platform-framework`):

```bash
# Build a specific package (output lands in the workspace root dist/)
uv build --package framework-core

# Publish all wheels to the local server (server accepts any credentials)
UV_PUBLISH_USERNAME=any UV_PUBLISH_PASSWORD=any \
  uv publish --publish-url http://localhost:8080 dist/*.whl
```

Or simply run `make build && make publish` from the repo root.

## Referencing This Index in Other Repos

All three repos (`platform-framework`, `platform-core`, `sales-application`) declare
this server as an explicit index in their workspace root `pyproject.toml`:

```toml
[[tool.uv.index]]
name     = "local"
url      = "http://localhost:8080/simple/"
explicit = true
```

Packages that come from this local index are pinned in `[tool.uv.sources]`:

```toml
[tool.uv.sources]
framework-core       = { index = "local" }
framework-infra      = { index = "local" }
framework-evaluation = { index = "local" }
```

## Workflow Summary

```
platform-framework  →  make build && make publish  →  local-pypi server
platform-core       →  uv sync  (resolves framework-* from local-pypi)
sales-application   →  uv sync  (resolves core-* from local-pypi)
```

## Package Storage

Wheels are stored in `./packages/` which is volume-mounted into the container.
The directory is tracked in git via `.gitkeep`; actual wheels should be excluded
from version control (add `packages/*.whl` to `.gitignore` if desired).
