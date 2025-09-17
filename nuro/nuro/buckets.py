from __future__ import annotations

import os
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple
from urllib.parse import urlparse, urlunparse
from uuid import uuid4

from .debuglog import debug


@dataclass
class BucketSpec:
    type: str  # 'github' | 'raw' | 'local'
    base: str  # base path or URL (for github/raw this is a URL base to which /cmds/<name>.ps1 is appended)
    owner: Optional[str] = None
    repo: Optional[str] = None
    ref: Optional[str] = None  # branch/tag/ref default (ignored if an explicit commit is provided)


def parse_bucket_uri(uri: str) -> BucketSpec:
    if uri.startswith("github::"):
        spec = uri[8:]
        if "@" in spec:
            repo, ref = spec.split("@", 1)
        else:
            repo, ref = spec, "main"
        # base points to repo/ref root (without trailing /cmds)
        owner_repo = repo
        base = f"https://raw.githubusercontent.com/{owner_repo}/{ref}"
        return BucketSpec("github", base, owner=owner_repo.split("/")[0], repo=owner_repo.split("/")[1], ref=ref)
    if uri.startswith("raw::"):
        base = uri[5:].rstrip("/")
        return BucketSpec("raw", base)
    if uri.startswith("local::"):
        return BucketSpec("local", uri[7:])
    # treat everything else as local path
    return BucketSpec("local", uri)


def _normalize_raw_base(base: str) -> str:
    """Ensure raw.githubusercontent.com bases include a ref segment."""

    trimmed = base.rstrip("/")
    try:
        parsed = urlparse(trimmed)
    except Exception:
        return trimmed

    if parsed.netloc.lower() != "raw.githubusercontent.com":
        return trimmed

    parts = [p for p in parsed.path.split("/") if p]
    if len(parts) == 2:
        debug(f"raw base missing ref; injecting 'main' into {trimmed}")
        parts.append("main")
        new_path = "/" + "/".join(parts)
        parsed = parsed._replace(path=new_path)
        trimmed = urlunparse(parsed).rstrip("/")
    return trimmed


def resolve_cmd_source(bucket_uri: str, cmd: str) -> Dict[str, str]:
    """Resolve a command source from a bucket URI without extra metadata.

    For github/raw, returns a remote URL; for local, a filesystem path.
    This function does not consider commit pinning; see resolve_cmd_source_with_meta.
    """
    p = parse_bucket_uri(bucket_uri)
    if p.type in ("github", "raw"):
        base = p.base.rstrip("/")
        if p.type == "raw":
            base = _normalize_raw_base(base)
        # For github, p.base points to repo/ref root; commands live under cmds/
        if p.type == "github":
            url = f"{base}/cmds/{cmd}.ps1?cb={uuid4()}"
        else:
            url = f"{base}/cmds/{cmd}.ps1?cb={uuid4()}"
        debug(f"Resolved remote source: base={base} cmd={cmd} ext=ps1 uri={bucket_uri} -> {url}")
        return {"kind": "remote", "url": url}
    else:
        path = str((Path(p.base) / "cmds" / f"{cmd}.ps1").resolve())
        debug(f"Resolved local source: base={p.base} cmd={cmd} ext=ps1 path={path}")
        return {"kind": "local", "path": path}


def resolve_cmd_source_with_meta(bucket: Dict[str, object], cmd: str, ext: str = "ps1") -> Dict[str, str]:
    """Resolve command source considering optional metadata such as 'sha1-hash'.

    - If bucket['uri'] is github::owner/repo@ref and 'sha1-hash' is present,
      build the URL against that commit SHA.
    - For raw:: and local:: behave like resolve_cmd_source.
    """
    uri = str(bucket.get("uri", ""))
    p = parse_bucket_uri(uri)
    if p.type == "github":
        sha = str(bucket.get("sha1-hash") or "").strip()
        ref_or_sha = sha if sha else (p.ref or "main")
        base = f"https://raw.githubusercontent.com/{p.owner}/{p.repo}/{ref_or_sha}".rstrip("/")
        url = f"{base}/cmds/{cmd}.{ext}?cb={uuid4()}"
        debug(f"Resolved github source: bucket={bucket.get('name')} cmd={cmd} ext={ext} ref={ref_or_sha} -> {url}")
        return {"kind": "remote", "url": url}
    if p.type == "raw":
        base = _normalize_raw_base(p.base)
        url = f"{base}/cmds/{cmd}.{ext}?cb={uuid4()}"
        debug(f"Resolved raw source: bucket={bucket.get('name')} cmd={cmd} ext={ext} base={base} -> {url}")
        return {"kind": "remote", "url": url}
    # local
    path = str((Path(p.base) / "cmds" / f"{cmd}.{ext}").resolve())
    debug(f"Resolved local source: bucket={bucket.get('name')} cmd={cmd} ext={ext} -> {path}")
    return {"kind": "local", "path": path}


def fetch_to(path: Path, url: str, timeout: int = 60) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    debug(f"Fetching from URL: {url}")
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache", "Pragma": "no-cache", "User-Agent": "nuro"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
    path.write_bytes(data)
