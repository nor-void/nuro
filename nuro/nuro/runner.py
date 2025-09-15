from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import subprocess
from .paths import ensure_tree, ps1_dir, py_dir, sh_dir, cmds_cache_base
from .registry import load_registry
from .buckets import resolve_cmd_source_with_meta, fetch_to
from .pshost import run_ps_file, run_usage_for_ps1, run_cmd_for_ps1


def ensure_nuro_tree() -> None:
    ensure_tree()


def _split_bucket_hint(name: str) -> Tuple[Optional[str], str]:
    if ":" in name:
        a, b = name.split(":", 1)
        if a and b:
            return a, b
    return None, name


def _local_paths_for_ext(cmd: str, bucket_hint: Optional[str], reg: Dict, ext: str) -> List[Path]:
    paths: List[Path] = []
    if ext == "ps1":
        base = ps1_dir()
    elif ext == "py":
        base = py_dir()
    else:
        base = sh_dir()
    # flat legacy path (not used for new cache structure but keep for completeness)
    paths.append(base / f"{cmd}.{ext}")
    # pinned bucket preferred
    pins = reg.get("pins", {}) or {}
    pinned = pins.get(cmd)
    if bucket_hint:
        paths.append(base / bucket_hint / f"{cmd}.{ext}")
    if pinned:
        paths.append(base / pinned / f"{cmd}.{ext}")
    # all buckets by priority
    buckets = sorted(reg.get("buckets", []), key=lambda x: int(x.get("priority", 0)), reverse=True)
    for b in buckets:
        paths.append(base / b.get("name", "") / f"{cmd}.{ext}")
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


def _bucket_resolution_order(cmd: str, reg: Dict, bucket_hint: Optional[str]) -> List[Dict]:
    # determine fetch order: bucket_hint -> pin -> priority
    order: List[Dict] = []  # bucket dicts in resolution order
    buckets_by_name = {b["name"]: b for b in reg.get("buckets", [])}
    if bucket_hint and bucket_hint in buckets_by_name:
        b = buckets_by_name[bucket_hint]
        order.append(b)
    pins = reg.get("pins", {}) or {}
    pinned = pins.get(cmd)
    if pinned and pinned in buckets_by_name and (not bucket_hint or pinned != bucket_hint):
        b = buckets_by_name[pinned]
        order.append(b)
    sorted_buckets = sorted(reg.get("buckets", []), key=lambda x: int(x.get("priority", 0)), reverse=True)
    for b in sorted_buckets:
        if (bucket_hint and b["name"] == bucket_hint) or (pinned and b["name"] == pinned):
            # already included
            pass
        order.append(b)
    return order

def _try_fetch_any(cmd: str, reg: Dict, bucket_hint: Optional[str]) -> Optional[Tuple[Path, str]]:
    exts = ["ps1", "py", "sh"]
    for b in _bucket_resolution_order(cmd, reg, bucket_hint):
        bname = str(b.get("name", ""))
        for ext in exts:
            if ext == "ps1":
                dest = ps1_dir() / bname / f"{cmd}.ps1"
            elif ext == "py":
                dest = py_dir() / bname / f"{cmd}.py"
            else:
                dest = sh_dir() / bname / f"{cmd}.sh"
            if dest.exists():
                return dest, ext
            src = resolve_cmd_source_with_meta(b, cmd, ext=ext)
            if src.get("kind") == "local":
                local_path = Path(src["path"])  # may be absolute
                if local_path.exists():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    try:
                        data = local_path.read_bytes()
                        dest.write_bytes(data)
                        return dest, ext
                    except Exception:
                        continue
            else:
                try:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    fetch_to(dest, src["url"])
                    return dest, ext
                except Exception:
                    continue
    return None


def run_command(name: str, args: List[str]) -> int:
    reg = load_registry()
    bucket_hint, cmd = _split_bucket_hint(name)

    # help path: nuro <cmd> -h / --help
    help_requested = any(a in ("-h", "--help", "/?") for a in args)

    # Search local caches in order: ext priority ps1 -> py -> sh
    for ext in ("ps1", "py", "sh"):
        paths = _local_paths_for_ext(cmd, bucket_hint, reg, ext)
        for p in paths:
            if p.exists():
                if help_requested:
                    if ext == "ps1":
                        return run_usage_for_ps1(p, cmd)
                    print(f"nuro {cmd} - no usage available")
                    return 0
                if ext == "ps1":
                    return run_cmd_for_ps1(p, cmd, args)
                if ext == "py":
                    code = (
                        "import runpy,sys; ns=runpy.run_path(%r); "
                        "f=ns.get('main'); sys.exit(int(f(sys.argv[1:]) or 0) if callable(f) else 0)"
                    ) % (str(p),)
                    return subprocess.call(["python3", "-c", code, *args])
                return subprocess.call(["bash", str(p), *args])

    # Attempt on-demand fetch for first available ext/bucket
    fetched = _try_fetch_any(cmd, reg, bucket_hint)
    if fetched:
        path, ext = fetched
        if help_requested:
            if ext == "ps1":
                return run_usage_for_ps1(path, cmd)
            print(f"nuro {cmd} - no usage available")
            return 0
        if ext == "ps1":
            return run_cmd_for_ps1(path, cmd, args)
        if ext == "py":
            code = (
                "import runpy,sys; ns=runpy.run_path(%r); "
                "f=ns.get('main'); sys.exit(int(f(sys.argv[1:]) or 0) if callable(f) else 0)"
            ) % (str(path),)
            return subprocess.call(["python3", "-c", code, *args])
        return subprocess.call(["bash", str(path), *args])

    raise RuntimeError(f"command '{cmd}' not found in any bucket")
