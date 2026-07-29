# Python Multi-Project Setup with uv

A working implementation of the blog post
[**How I'm Structuring Larger Python Projects with uv**](https://coenradie.com/posts/structuring-python-projects-with-uv/).

## The three repositories

```
platform-framework  ←  reusable technical building blocks (no domain knowledge)
       ↑
platform-core       ←  shared domain primitives (Product, Money, Address)
       ↑
sales-application   ←  concrete sales problem (Cart, Order, pricing, web UI)
```

Each repo is an independent git repository with its own lock file, virtual
environment, and release cycle. They are connected through `uv`'s
`[tool.uv.sources]` — not through a permanent shared workspace.

## Repository contents

### [`platform-framework`](https://github.com/jettro/pmps-platform-framework) (uv workspace, 3 packages)

| Package | Module | What it provides |
|---|---|---|
| `framework-core` | `framework_core` | `Entity`, `Repository[T]`, `Result[T,E]`, `Settings`, `EventBus` |
| `framework-infra` | `framework_infra` | `InMemoryRepository[T]`, `JsonFileRepository[T]` |
| `framework-evaluation` | `framework_evaluation` | `RepositoryContractSuite`, `EntityFactory` |

### [`platform-core`](https://github.com/jettro/pmps-platform-core) (uv workspace, 2 packages)

| Package | Module | What it provides |
|---|---|---|
| `core-domain` | `core_domain` | `Money`, `Address`, `Product` |
| `core-services` | `core_services` | `ProductService`, `CatalogQuery` |

### [`sales-application`](https://github.com/jettro/pmps-sales-application) (uv workspace, 2 packages)

| Package | Module | What it provides |
|---|---|---|
| `sales-backend` | `sales_backend` | `Order`, `Cart`, `PricingEngine`, `OrderService` |
| `sales-api` | `sales_api` | FastAPI app + single-page HTML/JS UI |

---

## The three dependency-source modes (core blog concept)

`uv` separates *what* you depend on (`[project.dependencies]`) from *where*
you get it (`[tool.uv.sources]`). This lets you switch sources without
changing the dependency contract.

### 1. Private index (normal day)

```toml
# platform-core/pyproject.toml — normal workflow
[tool.uv.sources]
framework-core  = { index = "local" }
framework-infra = { index = "local" }
```

Released wheels from `http://localhost:8080`. CI uses exactly the same
artifact as local development.

### 2. Editable local path (cross-repo feature)

```toml
# platform-core/pyproject.toml — when editing framework simultaneously
[tool.uv.sources]
framework-core  = { path = "../platform-framework/packages/framework-core", editable = true }
framework-infra = { path = "../platform-framework/packages/framework-infra", editable = true }
```

Changes in `platform-framework` are immediately visible in `platform-core`
without rebuilding a wheel.

### 3. Exact Git commit (share unreleased change)

```toml
[tool.uv.sources]
framework-core = {
    git = "ssh://git@github.com/yourorg/platform-framework.git",
    rev = "a1b2c3..."
}
```

Pins a specific commit — reproducible without publishing to the index.

---

## Workspaces: inside repos only

Each repo uses a uv workspace internally so that its packages share one
lock file and one virtual environment during development. The repos
themselves are *never* combined into one workspace — that would merge their
independent lifecycles.

```
platform-framework/
├── pyproject.toml      ← workspace root (virtual — no [project])
└── packages/
    ├── framework-core/pyproject.toml
    ├── framework-infra/pyproject.toml   # workspace = true source for framework-core
    └── framework-evaluation/pyproject.toml
```

---

## Quick start

### Development mode (editable paths — works immediately)

```bash
# From this directory:
make sync-all    # uv sync each repo in dependency order
make test-all    # 143 tests across all three repos
make run         # starts http://localhost:8000
```

### Released-packages mode (private index)

```bash
# 1. Start the local private PyPI server
make pypi-start           # docker compose up → http://localhost:8080

# 2. Build and publish upstream wheels
make build-all
make publish-all          # framework + core wheels → local pypi

# 3. Switch platform-core and sales-application to index sources
#    In each repo's root pyproject.toml:
#    comment out the path sources, uncomment the index sources

# 4. Re-sync
make sync-all

# 5. Or run via Docker (uses released packages + local pypi)
make docker-up            # builds image, starts sales-api on :8000
```

### Switching a single repo back to released packages

Edit the workspace root `pyproject.toml` in the relevant repo. The
comment blocks mark exactly what to swap:

```toml
# DEVELOPMENT MODE (active):
framework-core = { path = "../platform-framework/packages/framework-core", editable = true }

# RELEASED MODE (uncomment to activate):
# framework-core = { index = "local" }
```

Then `uv sync` — no other change needed.

---

## CI pattern (from the blog)

```bash
uv lock --check   # fail if lock file is out of date
uv sync --locked  # install exactly what is locked
uv run pytest
```

The lock file is the contract between development and CI. Committing it
ensures both environments install identical packages.

## Verifying released-package metadata

```bash
uv lock --no-sources
```

Resolves using only `[project.dependencies]` (ignores `[tool.uv.sources]`).
Reveals whether the portable dependency metadata is self-consistent
without any local overrides.
