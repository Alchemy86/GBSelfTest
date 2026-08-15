#!/usr/bin/env python3
"""Copy the scoreboard table from the generated page into the README.

Called by `tools/scoreboard.sh --write`. It exists so that the table in the
README is never typed by a person: `tools/check-readme.py` insists the two
agree, and a table anybody can edit by hand is a table that will eventually be
wrong.

    tools/splice-scoreboard.py docs/scoreboard.md README.md
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    source, target = Path(argv[0]), Path(argv[1])

    m = re.search(r"<!-- table -->\n(.*?)\n<!-- /table -->", source.read_text(), re.S)
    if not m:
        print(f"{source} has no table block", file=sys.stderr)
        return 1
    table = m.group(1)

    text = target.read_text()
    new, n = re.subn(
        r"(<!-- scoreboard -->\n).*?(\n<!-- /scoreboard -->)",
        lambda hit: hit.group(1) + table + hit.group(2),
        text,
        flags=re.S,
    )
    if not n:
        print(f"{target} has no scoreboard markers to splice into", file=sys.stderr)
        return 1
    if new == text:
        print(f"{target}: the scoreboard was already in step")
        return 0
    target.write_text(new)
    print(f"{target}: scoreboard updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
