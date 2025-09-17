from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from .paths import config_dir, ensure_tree
from . import DEFAULT_OFFICIAL_BUCKET_BASE


# Config file path: ~/.nuro/config/config.json
def _config_path() -> Path:
    return config_dir() / "config.json"


def _default_app_config() -> Dict[str, Any]:
    return {
        # Official bucket base URL (commands live under "cmds/")
        "official_bucket_base": DEFAULT_OFFICIAL_BUCKET_BASE,
    }


def load_app_config() -> Dict[str, Any]:
    """Load main app config from ~/.nuro/config/config.json.

    If the file does not exist or is broken, create/overwrite it with defaults.
    """
    ensure_tree()
    p = _config_path()
    if not p.exists():
        obj = _default_app_config()
        p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        return obj
    try:
        raw = p.read_text(encoding="utf-8")
        data = json.loads(raw) if raw.strip() else {}
        if not isinstance(data, dict):
            raise ValueError("config.json must be a JSON object")
        # Fill defaults for missing keys
        defaults = _default_app_config()
        for k, v in defaults.items():
            data.setdefault(k, v)
        return data
    except Exception:
        obj = _default_app_config()
        p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        return obj


def official_bucket_base(cfg: Dict[str, Any] | None = None) -> str:
    if cfg is None:
        cfg = load_app_config()
    base = str(cfg.get("official_bucket_base") or DEFAULT_OFFICIAL_BUCKET_BASE).strip()
    # Normalize: trim trailing slashes
    while base.endswith("/"):
        base = base[:-1]
    return base
