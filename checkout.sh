#!/usr/bin/env bash
# checkout.sh — Bootstrap only the repositories needed for a developer profile
#
# The sales repository is the default. Add platform sources only when needed:
#
#   <parent>/
#   └── python-multi-project-setup/   ← coordination repo (this script lives here)
#       ├── platform-framework/        ← framework or all profile
#       ├── platform-core/             ← core or all profile
#       └── sales-application/         ← every profile
#
# Usage (run from the parent directory of python-multi-project-setup):
#   git clone git@github.com:jettro/python-multi-project-setup.git
#   cd python-multi-project-setup
#   bash checkout.sh                 # sales only
#   bash checkout.sh core            # sales + platform-core
#   bash checkout.sh framework       # sales + platform-framework
#   bash checkout.sh all             # all repositories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
profile="${1:-sales}"

if [[ $# -gt 1 ]] || [[ ! "${profile}" =~ ^(sales|core|framework|all)$ ]]; then
    echo "Usage: $0 [sales|core|framework|all]" >&2
    exit 2
fi

clone_or_skip() {
    local repo_url="$1"
    local target_dir="$2"

    if [ -d "$target_dir/.git" ]; then
        echo "✔  $target_dir already exists — skipping clone"
    else
        echo "→  Cloning $repo_url into $target_dir"
        git clone "$repo_url" "$target_dir"
    fi
}

echo "=== Checking out '${profile}' developer profile into $(pwd) ==="
echo ""

clone_or_skip "git@github.com:jettro/pmps-sales-application.git"   "sales-application"

if [[ "${profile}" == "core" || "${profile}" == "all" ]]; then
    clone_or_skip "git@github.com:jettro/pmps-platform-core.git" "platform-core"
fi

if [[ "${profile}" == "framework" || "${profile}" == "all" ]]; then
    clone_or_skip "git@github.com:jettro/pmps-platform-framework.git" "platform-framework"
fi

echo ""
echo "=== Done. Next steps: ==="
echo ""
echo "  make pypi-init-auth"
echo "  make pypi-start"
echo "  make dev-${profile}"
