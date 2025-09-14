from __future__ import annotations

import os
from pathlib import Path


def home_dir() -> Path:
    h = os.path.expanduser("~")
    return Path(h)


def nuro_home() -> Path:
    return home_dir() / ".nuro"


def ps1_dir() -> Path:
    return nuro_home() / "ps1"


def locale_dir() -> Path:
    return nuro_home() / "locale"


def logs_dir() -> Path:
    return nuro_home() / "logs"


def config_dir() -> Path:
    return nuro_home() / "config"


def buckets_path() -> Path:
    return config_dir() / "buckets.json"


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def ensure_tree() -> None:
    ensure_dir(nuro_home())
    ensure_dir(ps1_dir())
    ensure_dir(locale_dir())
    ensure_dir(logs_dir())
    ensure_dir(config_dir())

