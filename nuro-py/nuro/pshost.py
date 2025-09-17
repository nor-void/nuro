from __future__ import annotations

import os
import platform
import shutil
import subprocess
from pathlib import Path
from typing import Iterable, List, Optional
from uuid import uuid4

from .debuglog import debug
from .paths import logs_dir, ensure_tree

class PowerShellNotFound(RuntimeError):
    pass


def find_powershell() -> List[str]:
    # Prefer pwsh (PowerShell Core). Fallback to Windows PowerShell if on Windows.
    exe = shutil.which("pwsh")
    if exe:
        debug(f"PowerShell resolved: pwsh -> {exe}")
        return [exe]
    if platform.system() == "Windows":
        exe = shutil.which("powershell") or shutil.which("powershell.exe")
        if exe:
            debug(f"PowerShell resolved: powershell -> {exe}")
            return [exe]
    raise PowerShellNotFound("PowerShell not found. Please install PowerShell (pwsh) or enable Windows PowerShell.")


def _ps_quote(s: str) -> str:
    # PowerShell single-quote escaping: ' -> ''
    return "'" + s.replace("'", "''") + "'"


def run_ps_file(file: Path, args: Iterable[str]) -> int:
    shell = find_powershell()
    qpath = _ps_quote(str(file))
    qargs = " ".join(_ps_quote(str(a)) for a in args)
    # Prepare transcript to capture host (Write-Host) output reliably
    ensure_tree()
    ts_path = logs_dir() / f"ps-transcript-{uuid4().hex}.log"
    qts = _ps_quote(str(ts_path))
    # Use -Command and Start-Transcript to capture host output; also set exit code
    ps_cmd = (
        f"$ts={qts}; try {{ Start-Transcript -Path $ts -Force | Out-Null }} catch {{}}; "
        f"$LASTEXITCODE=0; $code=0; "
        f"try {{ & {qpath} {qargs}; $code=$LASTEXITCODE }} catch {{ $code=1; Write-Error $_ }} finally {{ try {{ Stop-Transcript | Out-Null }} catch {{}} }}; "
        f"exit $code"
    )
    cmd = shell + ["-NoProfile", "-Command", ps_cmd]
    debug(f"Invoking PowerShell: {' '.join(cmd)}")
    debug(f"Working dir: {os.getcwd()} | Script: {file} | Exists: {file.exists()} | Transcript: {ts_path}")
    # Stream output live and merge stderr into stdout for reliability
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except Exception as e:
        debug(f"Failed to start PowerShell: {e}")
        raise

    captured_any = False
    if proc.stdout is not None:
        for line in proc.stdout:
            captured_any = True
            # pass-through to console
            print(line, end="")
    rc = proc.wait()
    if not captured_any:
        debug("No output captured from PowerShell process; attempting transcript fallback.")
        try:
            if ts_path.exists():
                text = ts_path.read_text(encoding="utf-8", errors="replace")
                if text.strip():
                    print(text, end="" if text.endswith("\n") else "\n")
                else:
                    debug("Transcript file is empty.")
            else:
                debug("Transcript file was not created.")
        except Exception as e:
            debug(f"Failed to read transcript: {e}")
    debug(f"PowerShell exited with code: {rc}")
    return rc


def run_usage_for_ps1(target: Path, cmd_name: str) -> int:
    """Run NuroUsage_<name> by dot-sourcing the target without creating a wrapper file."""
    shell = find_powershell()
    qtarget = _ps_quote(str(target))
    ensure_tree()
    ts_path = logs_dir() / f"ps-transcript-{uuid4().hex}.log"
    qts = _ps_quote(str(ts_path))
    usage_fn = f"NuroUsage_{cmd_name}"
    inner = (
        f". {qtarget}; "
        f"if (Get-Command {usage_fn} -ErrorAction SilentlyContinue) {{ & {usage_fn} }} else {{ Write-Output 'usage unavailable' }}"
    )
    ps_cmd = (
        f"$ts={qts}; try {{ Start-Transcript -Path $ts -Force | Out-Null }} catch {{}}; "
        f"$LASTEXITCODE=0; $code=0; "
        f"try {{ {inner} }} catch {{ $code=1; Write-Error $_ }} finally {{ try {{ Stop-Transcript | Out-Null }} catch {{}} }}; "
        f"exit $code"
    )
    cmd = shell + ["-NoProfile", "-Command", ps_cmd]
    debug(f"Invoking PowerShell: {' '.join(cmd)}")
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except Exception as e:
        debug(f"Failed to start PowerShell: {e}")
        raise
    captured_any = False
    if proc.stdout is not None:
        for line in proc.stdout:
            captured_any = True
            print(line, end="")
    rc = proc.wait()
    if not captured_any:
        debug("No output captured from PowerShell process; attempting transcript fallback.")
        try:
            if ts_path.exists():
                text = ts_path.read_text(encoding="utf-8", errors="replace")
                if text.strip():
                    print(text, end="" if text.endswith("\n") else "\n")
        except Exception as e:
            debug(f"Failed to read transcript: {e}")
    debug(f"PowerShell exited with code: {rc}")
    return rc


def run_usage_for_ps1_capture(target: Path, cmd_name: str) -> str:
    """Invoke NuroUsage_<name> from a PS1 file and capture stdout as text.

    Returns the captured stdout (may be empty). Errors are swallowed and
    returned as empty string.
    """
    shell = find_powershell()
    usage_fn = f"NuroUsage_{cmd_name}"
    qtarget = _ps_quote(str(target))
    ps_cmd = f". {qtarget}; if (Get-Command {usage_fn} -ErrorAction SilentlyContinue) {{ & {usage_fn} }} else {{ Write-Output 'usage unavailable' }}"
    try:
        cmd = shell + ["-NoProfile", "-Command", ps_cmd]
        debug(f"Invoking PowerShell (capture): {' '.join(cmd)}")
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        out = proc.stdout or ""
        return out.strip()
    except Exception as e:
        debug(f"run_usage_for_ps1_capture failed: {e}")
        return ""

def run_cmd_for_ps1(target: Path, cmd_name: str, args: Iterable[str]) -> int:
    """Run NuroCmd_<name> by dot-sourcing the target without creating a wrapper file.

    CLI args are forwarded via PowerShell's automatic $args and splatted to the function.
    """
    shell = find_powershell()
    qtarget = _ps_quote(str(target))
    ensure_tree()
    ts_path = logs_dir() / f"ps-transcript-{uuid4().hex}.log"
    qts = _ps_quote(str(ts_path))
    invoke_fn = f"NuroCmd_{cmd_name}"
    arg_list = list(args)
    qitems = ", ".join(_ps_quote(str(a)) for a in arg_list)
    inner = (
        f"$NURO_ARGS=@({qitems}); "
        f". {qtarget}; "
        f"if (Get-Command {invoke_fn} -ErrorAction SilentlyContinue) {{ & {invoke_fn} @NURO_ARGS }} else {{ Write-Error 'command entry not found' -ErrorAction Continue }}"
    )
    ps_cmd = (
        f"$ts={qts}; try {{ Start-Transcript -Path $ts -Force | Out-Null }} catch {{}}; "
        f"$LASTEXITCODE=0; $code=0; "
        f"try {{ {inner} }} catch {{ $code=1; Write-Error $_ }} finally {{ try {{ Stop-Transcript | Out-Null }} catch {{}} }}; "
        f"exit $code"
    )
    cmd = shell + ["-NoProfile", "-Command", ps_cmd]
    debug(f"Invoking PowerShell: {' '.join(cmd)}")
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except Exception as e:
        debug(f"Failed to start PowerShell: {e}")
        raise
    captured_any = False
    if proc.stdout is not None:
        for line in proc.stdout:
            captured_any = True
            print(line, end="")
    rc = proc.wait()
    if not captured_any:
        try:
            if ts_path.exists():
                text = ts_path.read_text(encoding="utf-8", errors="replace")
                if text.strip():
                    print(text, end="" if text.endswith("\n") else "\n")
        except Exception as e:
            debug(f"Failed to read transcript: {e}")
    debug(f"PowerShell exited with code: {rc}")
    return rc
