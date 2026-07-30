# Python Multi-Project Setup with uv

A working example of three independent uv workspaces:

```text
platform-framework -> platform-core -> sales-application
```

Each repository retains its own release cycle, virtual environment, and host-development
lock. The coordination repository adds reproducible Docker inputs without combining the
repositories into one uv workspace.

## Checkout and host development

```bash
bash checkout.sh
make sync-all
make test-all
make run
```

The normal repository manifests use editable sibling paths, so changes flow immediately
between the three checkouts. `make check-locks` verifies those development locks without
rewriting them.

Workspace-only source declarations live at each repository root. This keeps individual
package metadata portable when a package is built, published, or installed from a Git
subdirectory.

## Authenticated local package index

The local pypiserver is an intentionally small teaching registry. Initialize credentials
before starting it:

```bash
make pypi-init-auth
make pypi-start
make pypi-status
```

Initialization prompts without putting the password in shell history. For noninteractive
use, provide `PYPI_USERNAME` and `PYPI_PASSWORD` in the environment. It creates ignored
`local-pypi/.env` and `local-pypi/auth/htpasswd` files with restrictive permissions.

Package listing and `/health` are public for diagnostics. Uploads and package downloads
require Basic authentication. Plain HTTP Basic authentication is acceptable only for this
localhost demonstration; a real registry must use HTTPS and managed, rotated credentials.

The demo permits overwriting a version to keep the learning loop short. Production release
repositories should reject overwrites. Reset only generated packages with:

```bash
make pypi-reset-packages
```

Build and publish upstream wheels in dependency order:

```bash
make build-all
make publish-all
```

`publish-all` publishes framework and core wheels. The sales packages are built from the
current sales source inside every image and do not need to be published first.

## Three immutable image modes

The sales repository contains independent deployment manifests and locks:

```text
sales-application/docker/modes/
├── release/{pyproject.toml,uv.lock}
├── git/{pyproject.toml,uv.lock}
└── local/{pyproject.toml,uv.lock}
```

- `release` installs the four upstream packages from the authenticated `local` index.
- `git` installs them from full, exact commits in the two public GitHub repositories.
- `local` copies neighbouring checkouts through narrow named BuildKit contexts and installs
  non-editable snapshots.

All modes run `uv sync --locked --no-dev --no-editable` during the build, copy only the
completed virtual environment into the runtime image, run as UID 10001, and start through
the `sales-api` console entry point. Kubernetes receives only the completed image and never
resolves Python dependencies.

Build one mode:

```bash
make docker-release
make docker-git
make docker-local
```

Or call Bake directly (Bake outputs a local Docker image):

```bash
set -a; source local-pypi/.env; set +a
docker buildx bake release
docker buildx bake git
docker buildx bake local
```

Only the release target receives `UV_INDEX_LOCAL_USERNAME` and
`UV_INDEX_LOCAL_PASSWORD`, through required BuildKit secret mounts. They are never Docker
arguments, persistent environment variables, lock content, or image labels. The public
index endpoint is relocated from host-side `localhost` to `host.docker.internal` for the
build only; Bake also supplies Linux `host-gateway` support.

Run a built release image:

```bash
docker run --rm -p 8000:8000 pmps-sales-application:release
```

Use `make docker-test-all` to build and smoke-test all three images.

## Refreshing and validating deployment locks

```bash
./scripts/refresh-image-locks.sh release
./scripts/refresh-image-locks.sh git
./scripts/refresh-image-locks.sh local
# or:
make refresh-image-locks

make check-image-locks
```

The refresh script stages copies in a safely created temporary checkout layout and replaces
the selected lock only after `uv lock` succeeds. It never overwrites the developer manifest
or lock. Release refresh requires the authenticated local index to contain the four upstream
wheels.

Git mode currently pins:

- platform-core: `9fe1b235ff3204f30d426f2fce16f0aa8d476eb5`
- platform-framework: `cb59cd6204d01f93a01e032fcc583c659bcbefe4`

Update all entries for one repository to the same new full SHA, then refresh and validate
the Git lock. Static dependency metadata in that manifest mirrors the four packages’
published metadata and lets uv resolve the Git subdirectories without applying their
repository-root development overrides.

For private Git repositories, replace HTTPS sources with SSH URLs and add an SSH mount to
the Git builder. Do not copy a private key into an image.

The validator rejects wrong source kinds, editable external image sources, moving or short
Git revisions, inconsistent repository SHAs, missing sales workspace packages, stale locks,
and credentials embedded in URLs.

## Moving to a production registry

Replace the named `local` index URL, refresh the release lock, and supply
`UV_INDEX_LOCAL_USERNAME` and `UV_INDEX_LOCAL_PASSWORD` from CI secrets. The Dockerfile
does not contain registry credentials. Production CI should:

- reject path or Git sources in a release lock;
- reject paths or moving Git references in integration images;
- build with HTTPS certificate verification enabled;
- inspect image history and configuration for secret leakage;
- publish immutable versions.
