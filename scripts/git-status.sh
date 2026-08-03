#!/usr/bin/env bash
set -u

repository="${1:-.}"
label="${2:-$(basename "$(cd "${repository}" && pwd)")}"

if ! git -C "${repository}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "${label}: not a Git repository" >&2
    exit 1
fi

printf '\n== %s ==\n' "${label}"

if [[ "${GIT_STATUS_FETCH:-1}" != "0" ]]; then
    if git -C "${repository}" fetch --all --prune --quiet; then
        echo "Fetch: refreshed"
    else
        echo "Fetch: warning - failed; incoming status uses cached remote references" >&2
    fi
else
    echo "Fetch: skipped (GIT_STATUS_FETCH=0)"
fi

branch="$(git -C "${repository}" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -n "${branch}" ]]; then
    echo "Branch: ${branch}"
else
    echo "Branch: detached at $(git -C "${repository}" rev-parse --short HEAD)"
fi

upstream="$(git -C "${repository}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [[ -n "${upstream}" ]]; then
    read -r ahead behind < <(
        git -C "${repository}" rev-list --left-right --count "HEAD...${upstream}"
    )
    echo "Upstream: ${upstream} (ahead ${ahead}, behind ${behind})"
    if (( behind > 0 )); then
        echo "Incoming commits (up to 10):"
        git -C "${repository}" log --oneline --decorate --max-count=10 "HEAD..${upstream}"
        if (( behind > 10 )); then
            echo "... and $((behind - 10)) more"
        fi
    fi
else
    echo "Upstream: none"
fi

changes="$(git -C "${repository}" status --short)"
if [[ -n "${changes}" ]]; then
    echo "Local changes:"
    printf '%s\n' "${changes}"
else
    echo "Local changes: none"
fi
