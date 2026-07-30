#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODES = ROOT / "sales-application" / "docker" / "modes"
INTERNAL = {"core-domain", "core-services", "framework-core", "framework-infra"}
SALES = {"sales-api", "sales-backend"}
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_LOCAL = {
    "core-domain": "../platform-core/packages/core-domain",
    "core-services": "../platform-core/packages/core-services",
    "framework-core": "../platform-framework/packages/framework-core",
    "framework-infra": "../platform-framework/packages/framework-infra",
}
PACKAGE_PROJECTS = {
    "core-domain": ROOT / "platform-core" / "packages" / "core-domain" / "pyproject.toml",
    "core-services": ROOT / "platform-core" / "packages" / "core-services" / "pyproject.toml",
    "framework-core": ROOT / "platform-framework" / "packages" / "framework-core" / "pyproject.toml",
    "framework-infra": ROOT / "platform-framework" / "packages" / "framework-infra" / "pyproject.toml",
}


def load(path: Path) -> dict:
    with path.open("rb") as stream:
        return tomllib.load(stream)


def fail(errors: list[str], path: Path, message: str) -> None:
    errors.append(f"{path.relative_to(ROOT)}: {message}")


def validate_mode(mode: str, errors: list[str]) -> None:
    directory = MODES / mode
    manifest_path = directory / "pyproject.toml"
    lock_path = directory / "uv.lock"
    if not manifest_path.is_file():
        fail(errors, manifest_path, "missing manifest")
        return
    if not lock_path.is_file():
        fail(errors, lock_path, "missing lock")
        return

    manifest = load(manifest_path)
    lock = load(lock_path)
    members = set(manifest.get("tool", {}).get("uv", {}).get("workspace", {}).get("members", []))
    if "packages/*" not in members:
        fail(errors, manifest_path, "sales workspace members are missing")

    sources = manifest.get("tool", {}).get("uv", {}).get("sources", {})
    if set(sources) & INTERNAL != INTERNAL:
        fail(errors, manifest_path, "all four upstream packages must have explicit sources")

    if mode == "release":
        indexes = {
            item.get("name"): item
            for item in manifest.get("tool", {}).get("uv", {}).get("index", [])
        }
        local_index = indexes.get("local")
        if not local_index or not local_index.get("explicit"):
            fail(errors, manifest_path, "named explicit index 'local' is required")
        for name in INTERNAL:
            if sources.get(name) != {"index": "local"}:
                fail(errors, manifest_path, f"{name} must resolve exclusively from index 'local'")
    elif mode == "git":
        revisions: dict[str, set[str]] = {}
        for name in INTERNAL:
            source = sources.get(name, {})
            revision = source.get("rev", "")
            repository = source.get("git", "")
            if not FULL_SHA.fullmatch(revision):
                fail(errors, manifest_path, f"{name} must use a full 40-character Git SHA")
            if "branch" in source or "tag" in source:
                fail(errors, manifest_path, f"{name} uses a moving Git reference")
            if not source.get("subdirectory"):
                fail(errors, manifest_path, f"{name} is missing its package subdirectory")
            revisions.setdefault(repository, set()).add(revision)
        if any(len(values) != 1 for values in revisions.values()):
            fail(errors, manifest_path, "packages from one repository must use the same SHA")
        metadata = {
            item.get("name"): item
            for item in manifest.get("tool", {}).get("uv", {}).get("dependency-metadata", [])
        }
        for name, project_path in PACKAGE_PROJECTS.items():
            project = load(project_path)["project"]
            expected = {
                "name": name,
                "version": project["version"],
                "requires-python": project["requires-python"],
                "requires-dist": project.get("dependencies", []),
            }
            actual = metadata.get(name)
            if actual != expected:
                fail(errors, manifest_path, f"static metadata for {name} is stale")
    elif mode == "local":
        for name, expected in EXPECTED_LOCAL.items():
            source = sources.get(name, {})
            if source.get("path") != expected:
                fail(errors, manifest_path, f"{name} must use {expected}")
            if source.get("editable"):
                fail(errors, manifest_path, f"{name} must not be editable in an image")

    locked_packages = {item["name"]: item for item in lock.get("package", [])}
    missing = (INTERNAL | SALES) - set(locked_packages)
    if missing:
        fail(errors, lock_path, f"missing packages: {', '.join(sorted(missing))}")

    for name in INTERNAL & set(locked_packages):
        source = locked_packages[name].get("source", {})
        serialized = repr(source)
        if re.search(r"://[^/@\s]+:[^/@\s]+@", serialized):
            fail(errors, lock_path, f"{name} contains credentials in its URL")
        if mode == "release":
            registry = source.get("registry", "")
            if registry.rstrip("/") != "http://localhost:8080/simple":
                fail(errors, lock_path, f"{name} is not locked to the local named index")
            if "git" in source or "directory" in source or "editable" in source:
                fail(errors, lock_path, f"{name} has a non-registry source")
        elif mode == "git":
            git = source.get("git", "")
            if not re.search(r"#[0-9a-f]{40}$", git):
                fail(errors, lock_path, f"{name} is not locked to an immutable Git commit")
            if "directory" in source or "editable" in source:
                fail(errors, lock_path, f"{name} has a path source")
        elif mode == "local":
            directory_source = source.get("directory", "")
            if directory_source != EXPECTED_LOCAL[name]:
                fail(errors, lock_path, f"{name} has unexpected path {directory_source!r}")
            if "editable" in source:
                fail(errors, lock_path, f"{name} is editable")


def validate_no_committed_credentials(errors: list[str]) -> None:
    candidates = [
        ROOT / "docker-bake.hcl",
        ROOT / "sales-application" / "Dockerfile",
        ROOT / "sales-application" / "Dockerfile.local",
        *(MODES.glob("*/pyproject.toml")),
        *(MODES.glob("*/uv.lock")),
    ]
    credential_url = re.compile(r"://[^/@\s]+:[^/@\s]+@")
    for path in candidates:
        if path.is_file() and credential_url.search(path.read_text()):
            fail(errors, path, "contains credentials in a URL")


def main() -> int:
    errors: list[str] = []
    for mode in ("release", "git", "local"):
        validate_mode(mode, errors)
    validate_no_committed_credentials(errors)
    if errors:
        print("Image lock validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("All image manifests and locks are structurally valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
