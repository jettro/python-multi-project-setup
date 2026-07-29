#!/usr/bin/env bash
# checkout.sh — Bootstrap the full python-multi-project-setup workspace
#
# Clones all four repositories into the expected directory structure:
#
#   <parent>/
#   └── python-multi-project-setup/   ← coordination repo (this script lives here)
#       ├── platform-framework/        ← cloned by this script
#       ├── platform-core/             ← cloned by this script
#       └── sales-application/         ← cloned by this script
#
# Usage (run from the parent directory of python-multi-project-setup):
#   git clone git@github.com:jettro/python-multi-project-setup.git
#   cd python-multi-project-setup
#   bash checkout.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

echo "=== Checking out project repos into $(pwd) ==="
echo ""

clone_or_skip "git@github.com:jettro/pmps-platform-framework.git" "platform-framework"
clone_or_skip "git@github.com:jettro/pmps-platform-core.git"       "platform-core"
clone_or_skip "git@github.com:jettro/pmps-sales-application.git"   "sales-application"

echo ""
echo "=== Done. Next steps: ==="
echo ""
echo "  # Install all dependencies (development mode — editable path sources):"
echo "  make sync-all"
echo ""
echo "  # Run all tests:"
echo "  make test-all"
echo ""
echo "  # Start the app:"
echo "  make run"
