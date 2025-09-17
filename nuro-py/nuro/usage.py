from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path
from typing import List, Dict, Any, Tuple

from .paths import ps1_dir, cache_dir
from .debuglog import debug
from . import __version__
from .registry import load_registry
from .config import official_bucket_base, load_app_config
from .pshost import run_usage_for_ps1_capture
from .buckets import resolve_cmd_source_with_meta, fetch_to
from .paths import logs_dir, ensure_tree
from urllib.parse import urlparse
import shutil
import unicodedata


def _list_local_commands() -> List[str]:
    base = ps1_dir()
    names = set()
    # flat
    for p in base.glob("*.ps1"):
        names.add(p.stem)
    # namespaced
    for d in base.iterdir():
        if d.is_dir():
            for p in d.glob("*.ps1"):
                names.add(p.stem)
    return sorted(names)


def _parse_owner_repo_ref_from_base(base: str) -> Tuple[str, str, str] | None:
    u = urlparse(base)
    parts = [p for p in u.path.split("/") if p]
    if u.netloc != "raw.githubusercontent.com" or len(parts) < 2:
        return None
    owner, repo = parts[0], parts[1]
    ref = parts[2] if len(parts) >= 3 and parts[2] else "main"
    return owner, repo, ref


def _list_remote_commands() -> List[str]:
    """List commands from the official bucket via GitHub API if possible.

    We parse owner/repo from the configured raw base URL and query
    the GitHub contents API for the "cmds" folder. If parsing fails,
    we return an empty list.
    """
    try:
        cfg = load_app_config()
        base = official_bucket_base(cfg)
        parsed = _parse_owner_repo_ref_from_base(base)
        if not parsed:
            return []
        owner, repo, ref = parsed
        # If registry has an 'official' bucket with sha1-hash, use it as ref for listing
        reg = load_registry()
        for b in reg.get("buckets", []):
            if b.get("name") == "official":
                sha = str(b.get("sha1-hash") or "").strip()
                if sha:
                    ref = sha
                break
        api_url = f"https://api.github.com/repos/{owner}/{repo}/contents/cmds?ref={ref}"
        debug(f"GitHub API URL (list commands): {api_url}")
        req = urllib.request.Request(api_url, headers={"User-Agent": "nuro"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        names: List[str] = []
        for item in data:
            name = item.get("name", "")
            if name.lower().endswith(".ps1"):
                names.append(Path(name).stem)
        return sorted(names)
    except Exception:
        return []


 # Python-implemented commands are no longer enumerated or displayed here.


def print_root_usage(refresh: bool = False) -> None:
    print(f"nuro v{__version__} — minimal runner(Py-CLI)\n")
    print("USAGE:")
    print("  nuro <command> [args...]")
    print("  nuro <command> -h|--help|/?\n")
    print("GLOBAL OPTIONS:")
    print("  --refresh          Refresh command list from GitHub when no args\n")
    # Optional full refresh: clear ps1 and usage caches first
    if refresh:
        try:
            cache_root = cache_dir()
            if cache_root.exists():
                shutil.rmtree(cache_root)
        except Exception:
            pass

        # Legacy ps1 cache location (pre-migration); remove if present
        legacy_ps1 = Path(os.path.expanduser("~")) / ".nuro" / "ps1"
        shutil.rmtree(legacy_ps1, ignore_errors=True)

        # Recreate directory structure required for subsequent operations
        ensure_tree()

    # Build commands list depending on refresh policy
    lines: List[str] = []
    if refresh:
        remote = _list_remote_commands()
        if remote:
            lines = remote
    if not lines:
        local_only = _list_local_commands()
        if local_only:
            lines = local_only
        else:
            # Cache empty -> allow remote listing once
            remote = _list_remote_commands()
            if remote:
                lines = remote
    # Prepare rows for output (from ps1 buckets and python commands)
    rows: List[List[str]] = []
    if lines:
        # Helper to compute display width considering full-width characters
        def _disp_len(s: str) -> int:
            w = 0
            for ch in s:
                e = unicodedata.east_asian_width(ch)
                w += 2 if e in ("F", "W") else 1
            return w

        def _pad(s: str, width: int) -> str:
            cur = _disp_len(s)
            if cur >= width:
                return s
            return s + (" " * (width - cur))

        headers = ["コマンド", "種別", "使用例"]
        # Try to enrich with one-line help by invoking NuroUsage_* using cache under ~/.nuro/ps1/official
        bucket_name = "official"
        ensure_tree()
        ps1_cache_dir = ps1_dir() / bucket_name
        ps1_cache_dir.mkdir(parents=True, exist_ok=True)
        # Determine official bucket from registry or synthesize default
        reg = load_registry()
        official_bucket = None
        for b in reg.get("buckets", []):
            if b.get("name") == bucket_name:
                official_bucket = b
                break
        if official_bucket is None:
            cfg = load_app_config()
            base = official_bucket_base(cfg)
            official_bucket = {"name": bucket_name, "uri": f"raw::{base}", "priority": 100, "trusted": True}
        # usage text cache directory
        ucache_dir = cache_dir() / "usage" / bucket_name
        ucache_dir.mkdir(parents=True, exist_ok=True)

        for n in lines:
            help_line = ""
            try:
                ufile = ucache_dir / f"{n}.txt"
                cached_text: str | None = None
                # Use cache when not refreshing
                if not refresh and ufile.exists():
                    cached_text = ufile.read_text(encoding="utf-8", errors="replace")
                if cached_text is None:
                    # Ensure ps1 cached, then capture usage and update cache
                    # Note: ps1 cache lives under ~/.nuro/ps1/official
                    t = (ps1_cache_dir / f"{n}.ps1")
                    if not t.exists():
                        src = resolve_cmd_source_with_meta(official_bucket, n)
                        if src.get("kind") == "remote":
                            fetch_to(t, src["url"], timeout=10)
                    out = ""
                    if t.exists():
                        out = run_usage_for_ps1_capture(t, n) or ""
                    # update cache file (even if empty, to avoid repeated fetches)
                    try:
                        ufile.write_text(out, encoding="utf-8")
                    except Exception:
                        pass
                    cached_text = out
                # compute first line for table
                if cached_text:
                    help_line = cached_text.splitlines()[0].strip()
                else:
                    help_line = ""
            except Exception:
                help_line = ""
            rows.append([n, bucket_name, help_line])

    if rows:
        # Compute column widths and print table
        def _disp_len(s: str) -> int:
            w = 0
            for ch in s:
                e = unicodedata.east_asian_width(ch)
                w += 2 if e in ("F", "W") else 1
            return w

        def _pad(s: str, width: int) -> str:
            cur = _disp_len(s)
            if cur >= width:
                return s
            return s + (" " * (width - cur))

        headers = ["コマンド", "種別", "使用例"]
        widths = [0, 0, 0]
        for i, h in enumerate(headers):
            widths[i] = max(widths[i], _disp_len(h))
        for r in rows:
            for i in range(3):
                widths[i] = max(widths[i], _disp_len(r[i]))

        print("COMMANDS (known):")
        print("")
        print("  " + "  ".join(_pad(headers[i], widths[i]) for i in range(3)))
        print("  " + "  ".join("-" * widths[i] for i in range(3)))
        for r in rows:
            print("  " + "  ".join(_pad(r[i], widths[i]) for i in range(3)))
    else:
        print("(no commands listed / offline)")
