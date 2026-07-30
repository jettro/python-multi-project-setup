#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sales_repo="${root_dir}/sales-application"

usage() {
    echo "Usage: $0 release|git|local|all" >&2
}

refresh_mode() {
    local mode="$1"
    local mode_dir="${sales_repo}/docker/modes/${mode}"
    local staging_root
    local staging_sales
    local staged_lock
    local temporary_lock

    if [[ ! -f "${mode_dir}/pyproject.toml" ]]; then
        echo "error: unknown image mode '${mode}'." >&2
        exit 2
    fi

    staging_root="$(mktemp -d "${TMPDIR:-/tmp}/pmps-lock-${mode}.XXXXXX")"
    trap 'rm -rf "${staging_root}"' EXIT
    staging_sales="${staging_root}/sales-application"
    mkdir -p "${staging_sales}"
    cp "${mode_dir}/pyproject.toml" "${staging_sales}/pyproject.toml"
    cp -R "${sales_repo}/packages" "${staging_sales}/packages"

    if [[ "${mode}" == "local" ]]; then
        mkdir -p "${staging_root}/platform-core" "${staging_root}/platform-framework"
        cp -R "${root_dir}/platform-core/packages" "${staging_root}/platform-core/packages"
        cp -R "${root_dir}/platform-framework/packages" "${staging_root}/platform-framework/packages"
    fi

    if [[ "${mode}" == "release" ]]; then
        if [[ ! -f "${root_dir}/local-pypi/.env" ]]; then
            echo "error: release lock needs local index credentials; run 'make pypi-init-auth'." >&2
            exit 1
        fi
        set -a
        # shellcheck disable=SC1091
        source "${root_dir}/local-pypi/.env"
        set +a
    fi

    echo "Refreshing ${mode} lock..."
    uv lock --project "${staging_sales}"
    staged_lock="${staging_sales}/uv.lock"
    temporary_lock="$(mktemp "${mode_dir}/.uv.lock.XXXXXX")"
    cp "${staged_lock}" "${temporary_lock}"
    chmod 644 "${temporary_lock}"
    mv -f "${temporary_lock}" "${mode_dir}/uv.lock"
    trap - EXIT
    rm -rf "${staging_root}"
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

case "$1" in
    release|git|local)
        refresh_mode "$1"
        ;;
    all)
        refresh_mode release
        refresh_mode git
        refresh_mode local
        ;;
    *)
        usage
        exit 2
        ;;
esac
