#!/usr/bin/env bash
set -euo pipefail

images=(release git local)
containers=()

cleanup() {
    for container in "${containers[@]:-}"; do
        docker rm -f "${container}" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

for index in "${!images[@]}"; do
    mode="${images[$index]}"
    image="pmps-sales-application:${mode}"
    container="pmps-${mode}-test"
    port="$((18001 + index))"
    containers+=("${container}")

    docker run --rm --entrypoint python "${image}" -c \
        "import sales_api, sales_backend, core_domain, core_services, framework_core, framework_infra"
    uid="$(docker run --rm --entrypoint id "${image}" -u)"
    if [[ "${uid}" == "0" ]]; then
        echo "error: ${image} runs as root." >&2
        exit 1
    fi

    docker run -d --name "${container}" -p "${port}:8000" "${image}" >/dev/null
    for attempt in $(seq 1 30); do
        if curl --fail --silent "http://localhost:${port}/" >/dev/null; then
            break
        fi
        if [[ "${attempt}" == "30" ]]; then
            docker logs "${container}" >&2
            echo "error: ${image} did not become ready." >&2
            exit 1
        fi
        sleep 1
    done
    docker rm -f "${container}" >/dev/null
done

echo "All three images import, run as non-root, and serve HTTP."
