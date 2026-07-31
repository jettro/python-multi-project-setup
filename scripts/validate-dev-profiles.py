#!/usr/bin/env python3
from __future__ import annotations

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = {"core-domain", "core-services", "framework-core", "framework-infra"}

EXPECTED = {
    ROOT / "sales-application" / "dev" / "profiles" / "core": {
        "core-domain": "editable",
        "core-services": "editable",
        "framework-core": "registry",
        "framework-infra": "registry",
    },
    ROOT / "sales-application" / "dev" / "profiles" / "framework": {
        "core-domain": "registry",
        "core-services": "registry",
        "framework-core": "editable",
        "framework-infra": "editable",
    },
    ROOT / "sales-application" / "dev" / "profiles" / "all": {
        name: "editable" for name in UPSTREAM
    },
    ROOT / "platform-core" / "dev" / "profiles" / "framework": {
        name: "editable" for name in UPSTREAM
    },
}


def load(path: Path) -> dict:
    with path.open("rb") as stream:
        return tomllib.load(stream)


def source_kind(source: dict) -> str:
    if "editable" in source:
        return "editable"
    if "registry" in source:
        return "registry"
    return "other"


def main() -> int:
    errors: list[str] = []
    for directory, expected in EXPECTED.items():
        manifest_path = directory / "pyproject.toml"
        lock_path = directory / "uv.lock"
        if not manifest_path.is_file() or not lock_path.is_file():
            errors.append(f"{directory.relative_to(ROOT)}: missing manifest or lock")
            continue

        manifest = load(manifest_path)
        direct = set(manifest.get("project", {}).get("dependencies", []))
        missing_direct = UPSTREAM - direct
        if missing_direct:
            errors.append(
                f"{manifest_path.relative_to(ROOT)}: source-overridden packages must be "
                f"direct dependencies: {', '.join(sorted(missing_direct))}"
            )

        packages = {item["name"]: item for item in load(lock_path).get("package", [])}
        for name, kind in expected.items():
            actual = source_kind(packages.get(name, {}).get("source", {}))
            if actual != kind:
                errors.append(
                    f"{lock_path.relative_to(ROOT)}: {name} must be {kind}, found {actual}"
                )

    if errors:
        print("Developer profile validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("All developer profiles select the intended released or editable sources.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
