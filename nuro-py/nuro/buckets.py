from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse, urlunparse
from uuid import uuid4

from .debuglog import debug


@dataclass
class BucketSpec:
    type: str  # 'github' | 'raw' | 'local'
    base: str  # base path or URL (for github/raw this is a URL base to which /cmds/<name>.<ext> is appended)
    owner: Optional[str] = None
    repo: Optional[str] = None
    ref: Optional[str] = None  # branch/tag/ref default (ignored if an explicit commit is provided)


_GITHUB_CONTENTS_CACHE: Dict[Tuple[str, str, str], List[Dict[str, Any]]] = {}


def _parse_raw_github_components(base: str) -> Optional[Tuple[str, str, str]]:
    try:
        parsed = urlparse(base)
    except Exception:
        return None
    if parsed.netloc.lower() != "raw.githubusercontent.com":
        return None
    parts = [p for p in parsed.path.split("/") if p]
    if len(parts) < 2:
        return None
    owner, repo = parts[0], parts[1]
    ref = parts[2] if len(parts) >= 3 and parts[2] else "main"
    return owner, repo, ref


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
        owner, repo_name = owner_repo.split("/", 1)
        return BucketSpec("github", base, owner=owner, repo=repo_name, ref=ref)
    if uri.startswith("raw::"):
        base = uri[5:].rstrip("/")
        owner = repo_name = ref = None
        parsed = _parse_raw_github_components(base)
        if parsed:
            owner, repo_name, ref = parsed
        return BucketSpec("raw", base, owner=owner, repo=repo_name, ref=ref)
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


def _raw_base_with_ref(base: str, ref: str) -> str:
    try:
        parsed = urlparse(base)
    except Exception:
        return base.rstrip("/")
    if parsed.netloc.lower() != "raw.githubusercontent.com":
        return base.rstrip("/")
    parts = [p for p in parsed.path.split("/") if p]
    if len(parts) < 2:
        return base.rstrip("/")
    if len(parts) >= 3:
        parts[2] = ref
    else:
        parts.append(ref)
    new_path = "/" + "/".join(parts)
    return urlunparse(parsed._replace(path=new_path)).rstrip("/")


def _list_github_cmds(owner: str, repo: str, ref: str) -> List[Dict[str, Any]]:
    key = (owner, repo, ref)
    if key in _GITHUB_CONTENTS_CACHE:
        return _GITHUB_CONTENTS_CACHE[key]
    api_url = f"https://api.github.com/repos/{owner}/{repo}/contents/cmds?ref={ref}"
    debug(f"GitHub contents API: owner={owner} repo={repo} ref={ref} url={api_url}")
    req = urllib.request.Request(api_url, headers={"User-Agent": "nuro"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        body = resp.read().decode("utf-8", errors="replace")
    data = json.loads(body)
    if not isinstance(data, list):
        debug(f"Unexpected contents payload type: {type(data)}")
        return []
    _GITHUB_CONTENTS_CACHE[key] = data
    return data


def _github_download_url(owner: str, repo: str, ref: str, filename: str) -> Optional[str]:
    try:
        listing = _list_github_cmds(owner, repo, ref)
    except Exception as exc:
        debug(f"GitHub contents fetch failed for {owner}/{repo}@{ref}: {exc}")
        return None
    for item in listing:
        if not isinstance(item, dict):
            continue
        if item.get("name") != filename:
            continue
        url = item.get("download_url")
        if url:
            debug(
                f"Resolved GitHub download_url: owner={owner} repo={repo} ref={ref} file={filename} url={url}"
            )
            return url
    debug(f"File {filename} not found in GitHub contents for {owner}/{repo}@{ref}")
    return None


def resolve_cmd_source(bucket_uri: str, cmd: str) -> Dict[str, str]:
    """Resolve a command source from a bucket URI without extra metadata.

    For github/raw, returns a remote URL; for local, a filesystem path.
    This function does not consider commit pinning; see resolve_cmd_source_with_meta.
    """
    p = parse_bucket_uri(bucket_uri)
    if p.type == "github" and p.owner and p.repo:
        url = _github_download_url(p.owner, p.repo, p.ref or "main", f"{cmd}.ps1")
        if url:
            return {"kind": "remote", "url": url}
        base = p.base.rstrip("/")
        url = f"{base}/cmds/{cmd}.ps1?cb={uuid4()}"
        debug(
            f"GitHub contents fallback (no download_url): base={base} cmd={cmd} ext=ps1 uri={bucket_uri}"
        )
        return {"kind": "remote", "url": url}
    if p.type == "raw":
        if p.owner and p.repo:
            url = _github_download_url(p.owner, p.repo, p.ref or "main", f"{cmd}.ps1")
            if url:
                return {"kind": "remote", "url": url}
        base = _normalize_raw_base(p.base.rstrip("/"))
        url = f"{base}/cmds/{cmd}.ps1?cb={uuid4()}"
        debug(f"Resolved raw source: base={base} cmd={cmd} ext=ps1 uri={bucket_uri} -> {url}")
        return {"kind": "remote", "url": url}
    if p.type == "local":
        path = str((Path(p.base) / "cmds" / f"{cmd}.ps1").resolve())
        debug(f"Resolved local source: base={p.base} cmd={cmd} ext=ps1 path={path}")
        return {"kind": "local", "path": path}
    # Default fallback uses base URL when metadata insufficient
    base = p.base.rstrip("/")
    url = f"{base}/cmds/{cmd}.ps1?cb={uuid4()}"
    debug(f"Resolved remote source (fallback): base={base} cmd={cmd} ext=ps1 uri={bucket_uri} -> {url}")
    return {"kind": "remote", "url": url}


def resolve_cmd_source_with_meta(bucket: Dict[str, object], cmd: str, ext: str = "ps1") -> Dict[str, str]:
    """Resolve command source considering optional metadata such as 'sha1-hash'.

    - If bucket['uri'] is github::owner/repo@ref and 'sha1-hash' is present,
      prefer the GitHub contents download_url scoped to that commit.
    - For raw:: and local:: behave like resolve_cmd_source.
    """
    uri = str(bucket.get("uri", ""))
    p = parse_bucket_uri(uri)
    filename = f"{cmd}.{ext}"
    if p.type == "github" and p.owner and p.repo:
        sha = str(bucket.get("sha1-hash") or "").strip()
        ref_or_sha = sha if sha else (p.ref or "main")
        url = _github_download_url(p.owner, p.repo, ref_or_sha, filename)
        if url:
            debug(
                f"Resolved GitHub source via contents: bucket={bucket.get('name')} cmd={cmd} ext={ext} ref={ref_or_sha} -> {url}"
            )
            return {"kind": "remote", "url": url}
        base = f"https://raw.githubusercontent.com/{p.owner}/{p.repo}/{ref_or_sha}".rstrip("/")
        url = f"{base}/cmds/{filename}?cb={uuid4()}"
        debug(
            f"GitHub contents fallback: bucket={bucket.get('name')} cmd={cmd} ext={ext} ref={ref_or_sha} -> {url}"
        )
        return {"kind": "remote", "url": url}
    if p.type == "raw":
        sha = str(bucket.get("sha1-hash") or "").strip()
        ref = sha if sha else (p.ref or "main")
        if p.owner and p.repo:
            url = _github_download_url(p.owner, p.repo, ref, filename)
            if url:
                debug(
                    f"Resolved raw GitHub source via contents: bucket={bucket.get('name')} cmd={cmd} ext={ext} ref={ref} -> {url}"
                )
                return {"kind": "remote", "url": url}
            base = _raw_base_with_ref(p.base, ref)
        else:
            base = _normalize_raw_base(p.base)
            if sha:
                # base does not point to GitHub raw; no way to inject commit, so keep normalized base
                debug(
                    f"raw bucket missing GitHub context; using normalized base for {bucket.get('name')} with ref hint {ref}"
                )
        base = base.rstrip("/")
        url = f"{base}/cmds/{filename}?cb={uuid4()}"
        debug(f"Resolved raw source: bucket={bucket.get('name')} cmd={cmd} ext={ext} base={base} -> {url}")
        return {"kind": "remote", "url": url}
    # local
    path = str((Path(p.base) / "cmds" / filename).resolve())
    debug(f"Resolved local source: bucket={bucket.get('name')} cmd={cmd} ext={ext} -> {path}")
    return {"kind": "local", "path": path}


def fetch_to(path: Path, url: str, timeout: int = 60) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    debug(f"Fetching from URL: {url}")
    req = urllib.request.Request(
        url,
        headers={"Cache-Control": "no-cache", "Pragma": "no-cache", "User-Agent": "nuro"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
    path.write_bytes(data)
