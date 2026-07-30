#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
auth_dir="${root_dir}/local-pypi/auth"
password_file="${auth_dir}/htpasswd"
env_file="${root_dir}/local-pypi/.env"
username="${PYPI_USERNAME:-local}"
password="${PYPI_PASSWORD:-}"

if ! command -v htpasswd >/dev/null 2>&1; then
    echo "error: htpasswd is required (install apache2-utils on Linux or httpd on macOS)." >&2
    exit 1
fi

if [[ -z "${password}" ]]; then
    if [[ ! -t 0 ]]; then
        echo "error: no interactive terminal; provide PYPI_PASSWORD through the environment." >&2
        exit 1
    fi
    read -r -s -p "Password for local index user '${username}': " password
    printf '\n'
    read -r -s -p "Repeat password: " password_confirmation
    printf '\n'
    if [[ "${password}" != "${password_confirmation}" ]]; then
        echo "error: passwords do not match." >&2
        exit 1
    fi
fi

if [[ -z "${password}" ]]; then
    echo "error: password must not be empty." >&2
    exit 1
fi

mkdir -p "${auth_dir}"
umask 077
temporary_password_file="$(mktemp "${auth_dir}/.htpasswd.XXXXXX")"
temporary_env_file="$(mktemp "${root_dir}/local-pypi/.env.XXXXXX")"
trap 'rm -f "${temporary_password_file}" "${temporary_env_file}"' EXIT

# pypiserver's pinned passlib extra validates Apache's APR1-MD5 format without
# requiring the optional native bcrypt backend.
printf '%s\n' "${password}" | htpasswd -m -i -c "${temporary_password_file}" "${username}" >/dev/null
{
    printf 'UV_INDEX_LOCAL_USERNAME=%q\n' "${username}"
    printf 'UV_INDEX_LOCAL_PASSWORD=%q\n' "${password}"
    printf 'UV_PUBLISH_USERNAME=%q\n' "${username}"
    printf 'UV_PUBLISH_PASSWORD=%q\n' "${password}"
} > "${temporary_env_file}"

chmod 600 "${temporary_password_file}" "${temporary_env_file}"
mv -f "${temporary_password_file}" "${password_file}"
mv -f "${temporary_env_file}" "${env_file}"
trap - EXIT

echo "Created local-pypi/auth/htpasswd and local-pypi/.env with mode 0600."
