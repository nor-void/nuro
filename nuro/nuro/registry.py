from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

from .paths import buckets_path, ensure_tree
from .config import load_app_config, official_bucket_base


def _normalize_ref(ref: Optional[str]) -> str:
    if not ref:
        return "main"
    if ref.startswith("refs/heads/"):
        return ref[len("refs/heads/") :]
    if ref.startswith("refs/tags/"):
        return ref[len("refs/tags/") :]
    return ref


def _default_registry() -> Dict[str, Any]:
    # Load base URL from unified config
    cfg = load_app_config()
    base = official_bucket_base(cfg)
    return {
        "buckets": [
            {
                "name": "official",
                # Commands are expected under "cmds/" beneath this base
                "uri": f"raw::{base}",
                "priority": 100,
                "trusted": True,
            }
        ],
        "pins": {},
    }


def _normalize_registry(obj: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if obj is None:
        return _default_registry()

    buckets = obj.get("buckets")
    pins = obj.get("pins")

    # Normalize buckets
    if buckets is None:
        buckets = []
    elif buckets and isinstance(buckets, list) and isinstance(buckets[0], str):
        buckets = [
            {
                "name": (s.replace(":", "_").replace("/", "_").replace("\\", "_")),
                "uri": s,
                "priority": 50,
                "trusted": False,
            }
            for s in buckets
        ]

    # Normalize pins to dict[str,str]
    if pins is None:
        pins = {}
    elif not isinstance(pins, dict):
        try:
            pins = dict(pins)
        except Exception:
            pins = {}

    obj["buckets"] = buckets
    obj["pins"] = pins
    return obj


def load_registry() -> Dict[str, Any]:
    ensure_tree()
    p = buckets_path()
    if not p.exists():
        obj = _default_registry()
        p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        return obj
    try:
        raw = p.read_text(encoding="utf-8")
        data = json.loads(raw) if raw.strip() else None
        return _normalize_registry(data)
    except Exception:
        # fallback to default and overwrite broken file
        obj = _default_registry()
        p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
        return obj


def save_registry(obj: Dict[str, Any]) -> None:
    ensure_tree()
    p = buckets_path()
    normalized = _normalize_registry(obj)
    p.write_text(json.dumps(normalized, indent=2, ensure_ascii=False), encoding="utf-8")
