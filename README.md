# Python Multi-Project Setup with uv

A working example of three independent uv workspaces:

```text
platform-framework -> platform-core -> sales-application
```

Each repository retains its own release cycle, virtual environment, and lock. Released
wheels are the host-development default; source checkouts are selected explicitly.
The coordination repository adds reproducible Docker inputs without combining the
repositories into one uv workspace.

## Checkout and host development

```bash
make checkout-sales       # sales only
make checkout-core        # sales + platform-core
make checkout-framework   # sales + platform-framework
make checkout-all         # all source repositories
```

Start the authenticated index, then select the sales dependency sources:

```bash
make pypi-init-auth
make pypi-start

make dev-release          # released core + released framework (default)
make dev-core             # editable core + released framework
make dev-framework        # released core + editable framework
make dev-all              # editable core + editable framework
make dev-status
```

The commands update only the managed `[tool.uv.sources]` block in the root manifest, refresh
the root lock, and synchronize the stable `sales-application/.venv`. PyCharm therefore sees
one project, one lock, and one interpreter. Switching back to the canonical committed state
is always `make dev-release`; the presence of a sibling checkout never changes resolution.

Source switching intentionally makes `pyproject.toml` and `uv.lock` local changes. Return to
`release` before committing, pulling, or building a release image. The switch is
transactional: a failed lock or sync restores the previous manifest and lock.

Workspace-only source declarations live at each repository root. This keeps individual
package metadata portable when a package is built, published, or installed from a Git
subdirectory.

When working in `platform-core` itself, its equivalent choices are:

```bash
make -C platform-core dev-release    # released framework
make -C platform-core dev-framework  # editable framework
```

## Git status across repositories

Run the aggregate status from the coordination repository:

```bash
make git-status
```

It refreshes remote references and shows each checked-out repository's branch, upstream
ahead/behind counts, up to ten incoming commits, local changes, and active source mode.
Each child repository also exposes its own `make git-status`. To use cached remote
references without network access:

```bash
GIT_STATUS_FETCH=0 make git-status
```

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

### PyCharm and IntelliJ

The IDE and `uv` use separate credentials. To browse and install packages through the IDE,
open the **Python Packages** tool window, add a **Basic HTTP** repository, and use:

- URL: `http://localhost:8080/simple/`
- Username and password: the `UV_INDEX_LOCAL_USERNAME` and `UV_INDEX_LOCAL_PASSWORD`
  values from the ignored `local-pypi/.env` file

Let the IDE store these credentials in the operating system keychain. Do not put them in
`pyproject.toml`, `uv.lock`, the repository URL, or committed IDE configuration.

PyCharm does not necessarily pass its saved repository credentials to `uv`. For dependency
syncs started by the IDE, add the same local credentials to `~/.netrc`:

```text
machine localhost
  login YOUR_USERNAME
  password YOUR_PASSWORD
```

Then restrict access to the file:

```bash
chmod 600 ~/.netrc
```

`uv` always reads `~/.netrc`, including when the IDE launches it. Be aware that `.netrc`
stores the password as plain text and shares these credentials with other clients connecting
to `localhost`; this is suitable only for the local demo. For a real HTTPS package registry,
prefer the registry's credential integration or `uv auth login` with secure credential storage.

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

The sales release manifest and lock are also its root host defaults. Git and local image
builds retain independent deployment inputs:

```text
sales-application/
├── pyproject.toml + uv.lock                 # release
└── docker/modes/
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
the selected lock only after `uv lock` succeeds. Release refresh updates the canonical sales
root lock and requires the authenticated local index to contain the four upstream wheels.

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
