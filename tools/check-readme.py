#!/usr/bin/env python3
"""Fail if the README claims something the build does not produce.

A README that sells a test tool has to be held to the tool's own standard: if a
number is in it, that number should have come out of a run. So the three things
in there that could quietly go stale are pinned to the artefacts that generate
them, and CI checks all three:

  * the check-count badge, against `src/registry.asm` -- the same registry the
    ROM is built from;
  * the failure excerpt, against `docs/screenshots/failure-excerpt.txt`, which
    `tools/screenshots.sh` cuts straight out of a real run;
  * the scoreboard table, against `docs/scoreboard.md`, which
    `tools/scoreboard.sh` writes by running every row.

    tools/check-readme.py

Standard library only, like everything else here.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
REGISTRY = ROOT / "src" / "registry.asm"
EXCERPT = ROOT / "docs" / "screenshots" / "failure-excerpt.txt"
SCOREBOARD = ROOT / "docs" / "scoreboard.md"


def block(text: str, name: str) -> str | None:
    """The lines between <!-- name --> and <!-- /name -->."""
    m = re.search(rf"<!-- {name} -->\n(.*?)\n<!-- /{name} -->", text, re.S)
    return m.group(1) if m else None


def main() -> int:
    readme = README.read_text()
    bad: list[str] = []

    # 1. the badge count, from the registry the cartridge is built from
    checks = len(re.findall(r"^\s*check ", REGISTRY.read_text(), re.M))
    if checks == 0:
        return complain("no checks found in the registry; the format has moved")
    for claim in re.findall(r"checks-(\d+)-", readme):
        if int(claim) != checks:
            bad.append(f"the badge says {claim} checks, the registry has {checks}")
    for claim in re.findall(r"(\d+) checks\b", readme):
        if int(claim) != checks:
            bad.append(f'"{claim} checks" in the README, {checks} in the registry')

    # 2. the failure excerpt, verbatim from a run
    got = block(readme, "failure-excerpt")
    if got is None:
        bad.append("the failure-excerpt block is missing from the README")
    elif EXCERPT.exists():
        want = "```\n" + EXCERPT.read_text().rstrip("\n") + "\n```"
        if got.strip() != want.strip():
            bad.append(
                "the failure excerpt is not what the last run produced; "
                "run tools/screenshots.sh and paste "
                f"{EXCERPT.relative_to(ROOT)} back in"
            )
    else:
        bad.append(f"{EXCERPT.relative_to(ROOT)} is missing; run tools/screenshots.sh")

    # 3. the scoreboard table, from the runs
    got = block(readme, "scoreboard")
    if got is None:
        bad.append("the scoreboard block is missing from the README")
    elif SCOREBOARD.exists():
        want = block(SCOREBOARD.read_text(), "table")
        if want is None:
            bad.append("docs/scoreboard.md has no table block; run tools/scoreboard.sh")
        elif got.strip() != want.strip():
            bad.append(
                "the scoreboard in the README is not the one in "
                "docs/scoreboard.md; run tools/scoreboard.sh --write"
            )
    else:
        bad.append("docs/scoreboard.md is missing; run tools/scoreboard.sh --write")

    if bad:
        for line in bad:
            print(f"README: {line}", file=sys.stderr)
        return 1
    print(f"README matches the build ({checks} checks, excerpt and scoreboard in step)")
    return 0


def complain(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
