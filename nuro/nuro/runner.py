from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

from .paths import ensure_tree, ps1_dir
from .registry import load_registry
from .buckets import resolve_cmd_source, fetch_to
from .pshost import run_ps_file, run_usage_for_ps1, run_cmd_for_ps1


def ensure_nuro_tree() -> None:
    ensure_tree()


def _split_bucket_hint(name: str) -> Tuple[Optional[str], str]:
    if ":" in name:
        a, b = name.split(":", 1)
        if a and b:
            return a, b
    return None, name


def _local_ps1_paths(cmd: str, bucket_hint: Optional[str], reg: Dict) -> List[Path]:
    paths: List[Path] = []
    base = ps1_dir()
    # flat legacy path
    paths.append(base / f"{cmd}.ps1")
    # pinned bucket preferred
    pins = reg.get("pins", {}) or {}
    pinned = pins.get(cmd)
    if bucket_hint:
        paths.append(base / bucket_hint / f"{cmd}.ps1")
    if pinned:
        paths.append(base / pinned / f"{cmd}.ps1")
    # all buckets by priority
    buckets = sorted(reg.get("buckets", []), key=lambda x: int(x.get("priority", 0)), reverse=True)
    for b in buckets:
        paths.append(base / b.get("name", "") / f"{cmd}.ps1")
    # dedup while preserving order
    seen = set()
    uniq: List[Path] = []
    for p in paths:
        sp = str(p)
        if sp in seen:
            continue
        seen.add(sp)
        uniq.append(p)
    return uniq


def _try_fetch(cmd: str, reg: Dict, bucket_hint: Optional[str]) -> Optional[Path]:
    base = ps1_dir()
    # determine fetch order: bucket_hint -> pin -> priority
    order: List[Tuple[str, str]] = []  # (bucket_name, uri)
    buckets_by_name = {b["name"]: b for b in reg.get("buckets", [])}
    if bucket_hint and bucket_hint in buckets_by_name:
        b = buckets_by_name[bucket_hint]
        order.append((b["name"], b["uri"]))
    pins = reg.get("pins", {}) or {}
    pinned = pins.get(cmd)
    if pinned and pinned in buckets_by_name and (not bucket_hint or pinned != bucket_hint):
        b = buckets_by_name[pinned]
        order.append((b["name"], b["uri"]))
    sorted_buckets = sorted(reg.get("buckets", []), key=lambda x: int(x.get("priority", 0)), reverse=True)
    for b in sorted_buckets:
        if (bucket_hint and b["name"] == bucket_hint) or (pinned and b["name"] == pinned):
            # already included
            pass
        order.append((b["name"], b["uri"]))

    # Try fetching from each until success; do not overwrite existing (policy A)
    for name, uri in order:
        dest = base / name / f"{cmd}.ps1"
        if dest.exists():
            return dest
        src = resolve_cmd_source(uri, cmd)
        if src.get("kind") == "local":
            local_path = Path(src["path"])  # may be absolute
            if local_path.exists():
                dest.parent.mkdir(parents=True, exist_ok=True)
                try:
                    # copy
                    data = local_path.read_bytes()
                    dest.write_bytes(data)
                    return dest
                except Exception:
                    continue
        else:
            try:
                fetch_to(dest, src["url"])
                return dest
            except Exception:
                continue
    return None


def run_command(name: str, args: List[str]) -> int:
    reg = load_registry()
    bucket_hint, cmd = _split_bucket_hint(name)

    # help path: nuro <cmd> -h / --help
    help_requested = any(a in ("-h", "--help", "/?") for a in args)

    # Search local files
    for p in _local_ps1_paths(cmd, bucket_hint, reg):
        if p.exists():
            if help_requested:
                return run_usage_for_ps1(p, cmd)
            return run_cmd_for_ps1(p, cmd, args)

    # Attempt on-demand fetch (policy A: only when missing)
    fetched = _try_fetch(cmd, reg, bucket_hint)
    if fetched:
        if help_requested:
            return run_usage_for_ps1(fetched, cmd)
        return run_cmd_for_ps1(fetched, cmd, args)

    # Fallback to Python implementation (if any)
    try:
        mod_name = f"nuro.commands.{cmd}"
        mod = __import__(mod_name, fromlist=["main"])
        if hasattr(mod, "main"):
            return int(mod.main(args) or 0)
        raise ImportError
    except Exception:
        raise RuntimeError(f"command '{cmd}' not found in any bucket or python implementation")
