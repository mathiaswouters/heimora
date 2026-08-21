#!/usr/bin/env python3
"""Rewrite GRUB_CMDLINE_LINUX: drop tokens, append extras.

Exit 0 if the file changed, 2 if it was already correct, 1 on error.
Preserves every other kernel argument Anaconda wrote (root, rd.luks, resume, …).
"""
from __future__ import annotations

import pathlib
import re
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "usage: rewrite_grub_cmdline.py <grub-default> [drop,drop] [add,add]",
            file=sys.stderr,
        )
        return 1

    path = pathlib.Path(sys.argv[1])
    drop = {t for t in sys.argv[2].split(",") if t} if len(sys.argv) > 2 else set()
    extra = [t for t in sys.argv[3].split(",") if t] if len(sys.argv) > 3 else []

    text = path.read_text()
    pattern = re.compile(r'^(GRUB_CMDLINE_LINUX=)"(.*)"\s*$', re.M)

    def repl(match: re.Match[str]) -> str:
        args = [a for a in match.group(2).split() if a not in drop]
        for token in extra:
            if token not in args:
                args.append(token)
        return f'{match.group(1)}"{" ".join(args)}"'

    new, count = pattern.subn(repl, text, count=1)
    if count != 1:
        print("GRUB_CMDLINE_LINUX not found in", path, file=sys.stderr)
        return 1
    if new == text:
        return 2
    path.write_text(new)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
