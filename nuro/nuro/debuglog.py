from __future__ import annotations

import datetime as _dt
import os
from pathlib import Path
from typing import Optional

from .paths import logs_dir, ensure_tree


_enabled: Optional[bool] = None  # None means uninitialized; default False when first checked


def _log_path() -> Path:
    return logs_dir() / "nuro-debug.log"


def set_debug_enabled(flag: bool) -> None:
    global _enabled
    _enabled = bool(flag)


def is_debug_enabled() -> bool:
    global _enabled
    if _enabled is None:
        # default OFF; allow env to turn on without CLI
        env = os.environ.get("NURO_DEBUG", "").strip()
        _enabled = env not in ("", "0", "false", "False", "no", "NO")
    return bool(_enabled)


def debug(message: str) -> None:
    """Write a debug line to console and to ~/.nuro/logs/nuro-debug.log if enabled.

    When disabled, this function is a no-op.
    """
    if not is_debug_enabled():
        return
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
