from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict

from .paths import config_dir, ensure_tree


def _normalize_ref(ref: str | None) -> str:
    if not ref:
        return "main"
    if ref.startswith("refs/heads/"):
        return ref[len("refs/heads/") :]
    if ref.startswith("refs/tags/"):
        return ref[len("refs/tags/") :]
    return ref


def _default_github_config() -> Dict[str, Any]:
    # Environment override remains supported for backward compatibility
    ref = _normalize_ref(os.environ.get("NURO_REF"))
    return {
        "owner": "nor-void",
        "repo": "nuro",
        # Prefer ref unless an explicit sha is set in file
        "ref": ref,
        "sha": "",
    }


def _github_config_path() -> Path:
    return config_dir() / "github.json"


def load_github_config() -> Dict[str, Any]:
    """Load GitHub settings from ~/.nuro/config/github.json.

    If the file does not exist or is broken, create/overwrite it with defaults.
    """
    ensure_tree()
    p = _github_config_path()
    if not p.exists():
        obj = _default_github_config()
        p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        return obj
    try:
        raw = p.read_text(encoding="utf-8")
        data = json.loads(raw) if raw.strip() else {}
        if not isinstance(data, dict):
            raise ValueError("github.json must be a JSON object")
        # Fill defaults for missing keys
        defaults = _default_github_config()
        for k, v in defaults.items():
            data.setdefault(k, v)
        # Normalize ref
        data["ref"] = _normalize_ref(data.get("ref"))
        return data
    except Exception:
        obj = _default_github_config()
        p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        return obj


def repo_and_ref_from_config(cfg: Dict[str, Any]) -> tuple[str, str]:
    """Return (owner/repo, ref_or_sha) from loaded config.

    If cfg["sha"] is non-empty, it takes precedence over cfg["ref"].
    """
    owner = str(cfg.get("owner") or "nor-void").strip()
    repo = str(cfg.get("repo") or "nuro").strip()
    sha = str(cfg.get("sha") or "").strip()
    ref = _normalize_ref(cfg.get("ref"))
    use = sha if sha else ref
    return f"{owner}/{repo}", use

