from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path
from typing import List

from .paths import ps1_dir
from .debuglog import debug
from . import __version__
from .registry import load_registry
from .config import official_bucket_base, load_app_config
from urllib.parse import urlparse


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


def _list_remote_commands() -> List[str]:
    """List commands from the official bucket via GitHub API if possible.

    We parse owner/repo from the configured raw base URL and query
    the GitHub contents API for the "cmds" folder. If parsing fails,
    we return an empty list.
    """
    try:
        cfg = load_app_config()
        base = official_bucket_base(cfg)
        # Expect: https://raw.githubusercontent.com/<owner>/<repo>[/*]
        u = urlparse(base)
        parts = [p for p in u.path.split("/") if p]
        if len(parts) < 2 or u.netloc != "raw.githubusercontent.com":
            return []
        owner, repo = parts[0], parts[1]
        # Try to detect ref if present in base, otherwise default to main
        ref = parts[2] if len(parts) >= 3 and parts[2] else "main"
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
        for n in lines:
            print(f"  {n}")
    else:
        print("(no commands listed / offline)")
