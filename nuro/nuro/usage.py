from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path
from typing import List, Dict, Any, Tuple

from .paths import ps1_dir
from .debuglog import debug
from . import __version__
from .registry import load_registry
from .config import official_bucket_base, load_app_config
from .pshost import run_usage_for_ps1_capture
from .paths import logs_dir, ensure_tree
from urllib.parse import urlparse
import tempfile


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
        # If registry has an 'official' bucket with sha1-hash, use it as ref
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


def print_root_usage() -> None:
    print(f"nuro v{__version__} — minimal runner\n")
    print("USAGE:")
    print("  nuro <command> [args...]")
    print("  nuro <command> -h|--help|/?\n")
    print("GLOBAL OPTIONS:")
    print("  --debug | -d       Enable debug logging")
    print("  --no-debug         Disable debug logging\n")
    # Try online list (from official bucket), fallback to local/offline
    lines: List[str] = []
    remote = _list_remote_commands()
    if remote:
        lines = remote
    if not lines:
        lines = _list_local_commands()
    if lines:
        print("COMMANDS (known):")
        # Try to enrich with one-line help by invoking NuroUsage_*
        cfg = load_app_config()
        base = official_bucket_base(cfg)
        parsed = _parse_owner_repo_ref_from_base(base)
        bucket_name = "official"
        if parsed:
            # Prepare temp dir for fetched scripts
            ensure_tree()
            tmpdir = Path(tempfile.gettempdir()) / "nuro-usage"
            tmpdir.mkdir(parents=True, exist_ok=True)
            for n in lines:
                help_line = ""
                try:
                    # fetch raw script to temp and run usage capture
                    owner, repo, ref = parsed
                    # Override ref with commit if configured
                    reg = load_registry()
                    for b in reg.get("buckets", []):
                        if b.get("name") == "official":
                            sha = str(b.get("sha1-hash") or "").strip()
                            if sha:
                                ref = sha
                            break
                    raw_base = f"https://raw.githubusercontent.com/{owner}/{repo}/{ref}"
                    raw_url = f"{raw_base}/cmds/{n}.ps1"
                    req = urllib.request.Request(raw_url, headers={"User-Agent": "nuro"})
                    with urllib.request.urlopen(req, timeout=10) as resp:
                        code = resp.read().decode("utf-8", errors="replace")
                    t = tmpdir / f"{n}.ps1"
                    t.write_text(code, encoding="utf-8")
                    out = run_usage_for_ps1_capture(t, n)
                    if out:
                        help_line = out.splitlines()[0].strip()
                except Exception:
                    pass
                if help_line:
                    print(f"  {n}：{bucket_name}：{help_line}")
                else:
                    print(f"  {n}：{bucket_name}")
        else:
            for n in lines:
                print(f"  {n}：official")
    else:
        print("(no commands listed / offline)")
