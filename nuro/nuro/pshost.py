from __future__ import annotations

import os
import platform
import shutil
import subprocess
from pathlib import Path
from typing import Iterable, List, Optional


class PowerShellNotFound(RuntimeError):
    pass


def find_powershell() -> List[str]:
    # Prefer pwsh (PowerShell Core). Fallback to Windows PowerShell if on Windows.
    exe = shutil.which("pwsh")
    if exe:
        return [exe]
    if platform.system() == "Windows":
        exe = shutil.which("powershell") or shutil.which("powershell.exe")
        if exe:
            return [exe]
    raise PowerShellNotFound("PowerShell not found. Please install PowerShell (pwsh) or enable Windows PowerShell.")


def _ps_quote(s: str) -> str:
    # PowerShell single-quote escaping: ' -> ''
    return "'" + s.replace("'", "''") + "'"


def run_ps_file(file: Path, args: Iterable[str]) -> int:
    shell = find_powershell()
    qpath = _ps_quote(str(file))
    qargs = " ".join(_ps_quote(str(a)) for a in args)
    # Use -Command to execute script and merge all streams into stdout.
    # *>&1 merges Error/Warning/Verbose/Debug/Information into Success output.
    ps_cmd = f"& {{ & {qpath} {qargs}; exit $LASTEXITCODE }} *>&1"
    cmd = shell + ["-NoProfile", "-Command", ps_cmd]
    proc = subprocess.run(cmd)
    return proc.returncode


def run_usage_for_ps1(target: Path, cmd_name: str) -> int:
    # Create a temp wrapper that dot-sources the target and calls NuroUsage_<name>
    # Still executed with -File as requested.
    wrapper = target.parent / (f"._nuro_usage_{cmd_name}.ps1")
    try:
        usage_fn = f"NuroUsage_{cmd_name}"
        content = (
            f". '{target}'\n"
            f"if (Get-Command {usage_fn} -ErrorAction SilentlyContinue) {{ & {usage_fn} }} else {{ Write-Output 'usage unavailable' }}\n"
        )
        wrapper.write_text(content, encoding="utf-8")
        return run_ps_file(wrapper, [])
    finally:
        try:
            if wrapper.exists():
                wrapper.unlink()
        except Exception:
            pass
