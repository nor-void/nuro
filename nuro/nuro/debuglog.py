from __future__ import annotations

import datetime as _dt
from pathlib import Path

from .paths import logs_dir, ensure_tree


def _log_path() -> Path:
    return logs_dir() / "nuro-debug.log"


def debug(message: str) -> None:
    """Write a debug line to console and to ~/.nuro/logs/nuro-debug.log.

    Always prints to console to make attempted URLs visible as requested.
    """
    ensure_tree()
    ts = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {message}"
    try:
        p = _log_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        # Swallow logging errors silently
        pass
    print(f"[DEBUG] {message}")

