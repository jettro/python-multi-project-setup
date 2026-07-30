# Authenticated local package index

This directory configures `pypiserver/pypiserver:v2.4.1` as a development-only package
index. It is not production registry infrastructure.

From the coordination repository:

```bash
make pypi-init-auth
make pypi-start
make pypi-status
make pypi-stop
```

`pypi-init-auth` creates:

- `auth/htpasswd`, mounted read-only into the container;
- `.env`, containing the matching uv download and publication variables.

Both files are ignored and mode `0600`. `.env.example` documents the interface without a
working secret. Noninteractive initialization reads `PYPI_USERNAME` and `PYPI_PASSWORD`
from the environment.

The server protects `update,download`. `/simple/` listings and `/health` remain public for
easy diagnostics. Use:

```text
UV_INDEX_LOCAL_USERNAME
UV_INDEX_LOCAL_PASSWORD
```

for downloads and:

```text
UV_PUBLISH_USERNAME
UV_PUBLISH_PASSWORD
```

for `uv publish`.

This localhost example deliberately permits overwriting an existing artifact version.
Production registries should reject overwrites, use HTTPS, and use managed credentials.
Basic authentication over plain HTTP must not be used across an untrusted network.
