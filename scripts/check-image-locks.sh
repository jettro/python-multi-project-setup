#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sales_repo="${root_dir}/sales-application"
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/pmps-lock-check.XXXXXX")"
trap 'rm -rf "${staging_root}"' EXIT

python3 "${root_dir}/scripts/validate-image-locks.py"

for mode in release git local; do
    staging_sales="${staging_root}/${mode}/sales-application"
    mkdir -p "${staging_sales}"
    cp "${sales_repo}/docker/modes/${mode}/pyproject.toml" "${staging_sales}/pyproject.toml"
    cp "${sales_repo}/docker/modes/${mode}/uv.lock" "${staging_sales}/uv.lock"
    cp -R "${sales_repo}/packages" "${staging_sales}/packages"
    if [[ "${mode}" == "local" ]]; then
        mkdir -p "${staging_root}/${mode}/platform-core" "${staging_root}/${mode}/platform-framework"
        cp -R "${root_dir}/platform-core/packages" "${staging_root}/${mode}/platform-core/packages"
        cp -R "${root_dir}/platform-framework/packages" "${staging_root}/${mode}/platform-framework/packages"
    fi
    UV_OFFLINE=1 uv lock --project "${staging_sales}" --check
done

echo "All image locks match their manifests."
