#!/usr/bin/env python3
"""Release notes for VERSION: CHANGELOG.md's section for it, then every
commit since the previous release tag grouped by its Conventional Commits
type (the same grouping as IronStack's releases).

    python3 tools/ci/release_notes.py 0.9.1 > notes.md

Run from the repo root, with the tags fetched (`fetch-depth: 0`).
"""

import re
import subprocess
import sys

TITLES = {
    "feat": "Features",
    "fix": "Fixes",
    "perf": "Performance",
    "refactor": "Refactor",
    "docs": "Documentation",
    "test": "Tests",
    "build": "Build",
    "ci": "CI",
    "chore": "Chore",
    "style": "Style",
    "revert": "Reverts",
}
TYPE_RE = re.compile(r"^(" + "|".join(TITLES) + r")(\([^)]*\))?!?:\s")


def changelog_section(text, version):
    """The body under `## [version]`, up to the next `## ` heading."""
    match = re.search(
        r"^## \[" + re.escape(version) + r"\][^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S
    )
    return match.group(1).strip() if match else ""


def grouped_commits(lines):
    """`sha<TAB>subject` lines as Markdown sections, most interesting first;
    a subject that isn't a Conventional Commit goes under Other."""
    groups = {kind: [] for kind in [*TITLES, "other"]}
    for line in lines:
        if not line.strip():
            continue
        sha, _, subject = line.partition("\t")
        match = TYPE_RE.match(subject)
        groups[match.group(1) if match else "other"].append(f"- {subject} ({sha})")
    return "\n\n".join(
        f"### {TITLES.get(kind, 'Other')}\n\n" + "\n".join(items)
        for kind, items in groups.items()
        if items
    )


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def main():
    version = sys.argv[1]
    try:
        previous = git("describe", "--tags", "--abbrev=0", "--match", "v*", "HEAD^").strip()
    except subprocess.CalledProcessError:
        previous = ""
    commits = git(
        "log", f"{previous}..HEAD" if previous else "HEAD", "--no-merges", "--pretty=format:%h%x09%s"
    ).splitlines()

    with open("CHANGELOG.md", encoding="utf-8") as f:
        section = changelog_section(f.read(), version)

    parts = []
    if section:
        parts.append(section)
    parts.append(
        "Install on the phone: `devel-su rpm -Uvh harbour-ironstack-"
        f"{version}-1.aarch64.rpm` (armv7hl for an older 32-bit phone, i486 for the emulator)."
    )
    since = f" since {previous}" if previous else ""
    parts.append(f"## Commits{since}\n\n" + (grouped_commits(commits) or "_None._"))
    print("\n\n".join(parts))


if __name__ == "__main__":
    main()
