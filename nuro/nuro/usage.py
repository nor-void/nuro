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


def _list_remote_commands_from_github() -> List[str]:
    reg = load_registry()
    # prefer official bucket
    official = None
    for b in reg.get("buckets", []):
        if b.get("name") == "official":
            official = b
            break
    if not official:
        return []
    uri = official.get("uri", "")
    if not uri.startswith("github::"):
        return []
    spec = uri[8:]
    repo, ref = (spec.split("@", 1) + ["main"])[:2]
    api_url = f"https://api.github.com/repos/{repo}/contents/cmds?ref={ref}"
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


def print_root_usage() -> None:
    print(f"nuro v{__version__} — minimal runner\n")
    print("USAGE:")
    print("  nuro <command> [args...]")
    print("  nuro <command> -h|--help|/?\n")
    print("GLOBAL OPTIONS:")
    print("  --debug | -d       Enable debug logging")
    print("  --no-debug         Disable debug logging\n")
    # Try online list, fallback to local/offline
    lines: List[str] = []
    try:
        remote = _list_remote_commands_from_github()
        if remote:
            lines = remote
    except Exception:
        pass
    if not lines:
        lines = _list_local_commands()
    if lines:
        print("COMMANDS (known):")
        for n in lines:
            print(f"  {n}")
    else:
        print("(no commands listed / offline)")
