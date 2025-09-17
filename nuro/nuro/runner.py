from __future__ import annotations

import os
from pathlib import Path
import sys
from typing import Dict, Iterable, List, Optional, Tuple

import subprocess
import ast
import re
from importlib import metadata as _im
import json
from .debuglog import debug
from .paths import ensure_tree, ps1_dir, py_dir, sh_dir, cmds_cache_base, cache_dir
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
        debug(f"Trying bucket '{bname}' for cmd={cmd}")
        for ext in exts:
            if ext == "ps1":
                dest = ps1_dir() / bname / f"{cmd}.ps1"
            elif ext == "py":
                dest = py_dir() / bname / f"{cmd}.py"
            else:
                dest = sh_dir() / bname / f"{cmd}.sh"
            if dest.exists():
                debug(f"Fetch fallback found cached file: {dest}")
                return dest, ext
            src = resolve_cmd_source_with_meta(b, cmd, ext=ext)
            debug(f"Attempting fetch: bucket={bname} cmd={cmd} ext={ext} dest={dest} src={src}")
            if src.get("kind") == "local":
                local_path = Path(src["path"])  # may be absolute
                if local_path.exists():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    try:
                        data = local_path.read_bytes()
                        dest.write_bytes(data)
                        debug(f"Copied local command from {local_path} -> {dest}")
                        return dest, ext
                    except Exception as copy_err:
                        debug(f"Failed to copy local command from {local_path}: {copy_err}")
                        continue
            else:
                try:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    fetch_to(dest, src["url"])
                    debug(f"Fetched remote command for cmd={cmd} ext={ext} bucket={bname} -> {dest}")
                    return dest, ext
                except Exception as fetch_err:
                    debug(f"Fetch error bucket={bname} cmd={cmd} ext={ext}: {fetch_err}")
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
                debug(f"Using cached script: cmd={cmd} ext={ext} path={p}")
                if help_requested:
                    if ext == "ps1":
                        return run_usage_for_ps1(p, cmd)
                    print(f"nuro {cmd} - no usage available")
                    return 0
                if ext == "ps1":
                    return run_cmd_for_ps1(p, cmd, args)
                if ext == "py":
                    if not _ensure_script_requirements(p):
                        return 1
                    code = (
                        "import runpy,sys,inspect; ns=runpy.run_path(%r); "
                        "f=ns.get('main'); "
                        "\nif callable(f):\n"
                        "    try:\n"
                        "        sig=inspect.signature(f)\n"
                        "        rc=f(sys.argv[1:]) if len(sig.parameters)>=1 else f()\n"
                        "    except TypeError:\n"
                        "        rc=f()\n"
                        "    sys.exit(int(rc or 0))\n"
                        "else:\n"
                        "    sys.exit(0)\n"
                    ) % (str(p),)
                    exe = _python_exe()
                    return subprocess.call([exe, "-c", code, *args])
                return subprocess.call(["bash", str(p), *args])

    # Attempt on-demand fetch for first available ext/bucket
    fetched = _try_fetch_any(cmd, reg, bucket_hint)
    if fetched:
        path, ext = fetched
        debug(f"Using freshly fetched script: cmd={cmd} ext={ext} path={path}")
        if help_requested:
            if ext == "ps1":
                return run_usage_for_ps1(path, cmd)
            print(f"nuro {cmd} - no usage available")
            return 0
        if ext == "ps1":
            return run_cmd_for_ps1(path, cmd, args)
        if ext == "py":
            if not _ensure_script_requirements(path):
                return 1
            code = (
                "import runpy,sys,inspect; ns=runpy.run_path(%r); "
                "f=ns.get('main'); "
                "\nif callable(f):\n"
                "    try:\n"
                "        sig=inspect.signature(f)\n"
                "        rc=f(sys.argv[1:]) if len(sig.parameters)>=1 else f()\n"
                "    except TypeError:\n"
                "        rc=f()\n"
                "    sys.exit(int(rc or 0))\n"
                "else:\n"
                "    sys.exit(0)\n"
            ) % (str(path),)
            exe = _python_exe()
            return subprocess.call([exe, "-c", code, *args])
        return subprocess.call(["bash", str(path), *args])

    debug(f"Command '{cmd}' not found after checking all buckets (bucket_hint={bucket_hint})")
    raise RuntimeError(f"command '{cmd}' not found in any bucket")


# ---------------- dependency handling for python scripts -----------------

_REQ_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+")


def _extract_requirements_from_file(path: Path) -> List[str]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
        node = ast.parse(src, filename=str(path))
        for stmt in node.body:
            if isinstance(stmt, ast.Assign):
                for t in stmt.targets:
                    if isinstance(t, ast.Name) and t.id == "__requires__":
                        if isinstance(stmt.value, (ast.List, ast.Tuple)):
                            reqs: List[str] = []
                            for e in stmt.value.elts:
                                if isinstance(e, ast.Constant) and isinstance(e.value, str):
                                    reqs.append(e.value.strip())
                            return reqs
        return []
    except Exception:
        return []


def _pkg_name_from_spec(spec: str) -> str:
    # take leading token up to bracket or comparator
    s = spec.strip()
    s = s.split("[", 1)[0]
    m = _REQ_NAME_RE.match(s)
    return m.group(0) if m else s


def _is_req_satisfied(spec: str) -> bool:
    name = _pkg_name_from_spec(spec)
    try:
        ver = _im.version(name)
    except Exception:
        return False
    # if exact pin specified, verify equality; for other operators, force install
    if "==" in spec:
        want = spec.split("==", 1)[1].strip()
        return ver == want
    # no version constraint -> any installed version is fine
    ops = [">=", "<=", ">", "<", "!=", "~=", "==="]
    if any(op in spec for op in ops):
        return False
    return True


def _ensure_script_requirements(path: Path) -> bool:
    reqs = _extract_requirements_from_file(path)
    if not reqs:
        return True
    debug(f"Checking script requirements for {path}")
    cache = _load_reqs_cache()
    changed = False
    # Determine if a nuro-managed venv exists; if not, we do not modify system/user site-packages
    have_venv = _is_venv_python(_python_exe())
    # If any requirement is missing and no venv, inform and return without attempting installs
    missing_specs: List[str] = []
    for spec in reqs:
        if cache.get(spec) is True:
            continue
        if not _is_req_satisfied(spec):
            missing_specs.append(spec)
    if missing_specs and not have_venv:
        msg = (
            "nuro: Python dependency install requires ~/.nuro/venv. "
            "Please provision it (e.g., run bootstrap/get.nuro.ps1)."
        )
        try:
            sys.stderr.write(msg + "\n")
        except Exception:
            print(msg)
        debug("Dependency install skipped: ~/.nuro/venv not found")
        return False
    for spec in reqs:
        if cache.get(spec) is True:
            debug(f"Requirement cached as satisfied: {spec}")
            continue
        if _is_req_satisfied(spec):
            debug(f"Requirement already satisfied: {spec}")
            cache[spec] = True
            changed = True
            continue
        debug(f"Installing requirement: {spec}")
        try:
            # try python -m pip / pip3 / pip in order
            def _try(cmd: list[str]) -> int:
                # Suppress pip's stdout/stderr; rely on debug() for reporting
                return subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            exe = _python_exe()
            # Require installs to go into nuro-managed venv
            base = [exe, "-m", "pip", "install"]
            cmds = [
                base + [spec],
                ["pip3", "install", spec],
                ["pip", "install", spec],
            ]
            rc = 1
            for c in cmds:
                rc = _try(c)
                if rc == 0:
                    break
            if rc == 0:
                cache[spec] = True
                changed = True
                debug(f"Installed requirement: {spec}")
                _print_green(f"Installed dependency: {spec}")
            else:
                cache[spec] = False
                changed = True
                debug(f"Failed to install requirement (rc={rc}): {spec}")
        except Exception as e:
            cache[spec] = False
            changed = True
            debug(f"Exception during pip install for {spec}: {e}")
    if changed:
        _save_reqs_cache(cache)
    return True


def _python_exe() -> str:
    # Prefer nuro-managed venv if present; else fall back to python3 on PATH
    home = os.path.expanduser("~")
    # Windows-style path from bootstrap is ~/.nuro/venv/Scripts/python.exe
    win = Path(home) / ".nuro" / "venv" / "Scripts" / "python.exe"
    posix = Path(home) / ".nuro" / "venv" / "bin" / "python3"
    if win.exists():
        debug(f"Using venv python: {win}")
        return str(win)
    if posix.exists():
        debug(f"Using venv python: {posix}")
        return str(posix)
    return "python3"


def _is_venv_python(exe: str) -> bool:
    try:
        exe_path = Path(exe)
        return (
            (".nuro" in exe_path.as_posix() and "venv" in exe_path.as_posix())
            or bool(os.environ.get("VIRTUAL_ENV"))
        )
    except Exception:
        return False

def _reqs_cache_path() -> Path:
    return cache_dir() / "py-reqs.json"

def _load_reqs_cache() -> Dict[str, bool]:
    try:
        p = _reqs_cache_path()
        if not p.exists():
            return {}
        raw = p.read_text(encoding="utf-8")
        data = json.loads(raw) if raw.strip() else {}
        if isinstance(data, dict):
            return {str(k): bool(v) for k, v in data.items()}
        return {}
    except Exception:
        return {}

def _save_reqs_cache(d: Dict[str, bool]) -> None:
    try:
        p = _reqs_cache_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(d, indent=2, ensure_ascii=False), encoding="utf-8")
    except Exception:
        pass

def _print_green(msg: str) -> None:
    try:
        print("\x1b[32m" + msg + "\x1b[0m")
    except Exception:
        print(msg)
