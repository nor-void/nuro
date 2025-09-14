from __future__ import annotations

import os
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple
from uuid import uuid4
from .debuglog import debug


@dataclass
class BucketSpec:
    type: str  # 'github' | 'raw' | 'local'
    base: str  # base path or URL


def parse_bucket_uri(uri: str) -> BucketSpec:
    if uri.startswith("github::"):
        spec = uri[8:]
        if "@" in spec:
            repo, ref = spec.split("@", 1)
        else:
            repo, ref = spec, "main"
        # base points to cmds directory
        base = f"https://raw.githubusercontent.com/{repo}/{ref}/cmds"
        return BucketSpec("github", base)
    if uri.startswith("raw::"):
        base = uri[5:].rstrip("/")
        return BucketSpec("raw", base)
    if uri.startswith("local::"):
        return BucketSpec("local", uri[7:])
    # treat everything else as local path
    return BucketSpec("local", uri)


def resolve_cmd_source(bucket_uri: str, cmd: str) -> Dict[str, str]:
    p = parse_bucket_uri(bucket_uri)
    if p.type in ("github", "raw"):
        url = f"{p.base}/{cmd}.ps1?cb={uuid4()}"
        return {"kind": "remote", "url": url}
    else:
        path = str((Path(p.base) / f"{cmd}.ps1").resolve())
        return {"kind": "local", "path": path}


def fetch_to(path: Path, url: str, timeout: int = 60) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if "github" in url:
        debug(f"Fetching from URL: {url}")
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache", "Pragma": "no-cache", "User-Agent": "nuro"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
    path.write_bytes(data)
