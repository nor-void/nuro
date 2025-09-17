from __future__ import annotations

import os
import sys
from typing import List, Optional, Tuple

from .runner import run_command, ensure_nuro_tree
from .usage import print_root_usage
from . import __version__
from .debuglog import set_debug_enabled, is_debug_enabled


def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    # Parse global flags: --debug / --no-debug / --refresh (usage refresh)
    dbg = None
    refresh_usage = False
    filtered: List[str] = []
    it = iter(argv)
    for a in it:
        if a in ("--debug", "-d"):
            dbg = True
            continue
        if a in ("--no-debug",):
            dbg = False
            continue
        if a in ("--refresh",):
            refresh_usage = True
            continue
        filtered.append(a)
    argv = filtered

    if dbg is not None:
        set_debug_enabled(dbg)

    # Ensure ~/.nuro tree exists
    ensure_nuro_tree()

    if not argv:
        print_root_usage(refresh=refresh_usage)
        return 0

    name = argv[0]
    args = argv[1:]

    # help/version shortcut: nuro -h/--help, nuro --version/-V
    if name in ("-h", "--help", "/?"):
        print_root_usage(refresh=refresh_usage)
        return 0
    if name in ("--version", "-V"):
        print(__version__)
        return 0

    try:
        code = run_command(name, args)
        return int(code or 0)
    except KeyboardInterrupt:
        return 130
    except Exception as e:  # keep message concise
        sys.stderr.write(f"nuro: {e}\n")
        return 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
