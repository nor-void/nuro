from __future__ import annotations

import os
import sys
from typing import List, Optional, Tuple

from .runner import run_command, ensure_nuro_tree
from .usage import print_root_usage
from . import __version__


def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    # Ensure ~/.nuro tree exists
    ensure_nuro_tree()

    if not argv:
        print_root_usage()
        return 0

    name = argv[0]
    args = argv[1:]

    # help/version shortcut: nuro -h/--help, nuro --version/-V
    if name in ("-h", "--help", "/?"):
        print_root_usage()
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
