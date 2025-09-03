# cmds/install_python3_if_needed.ps1

function NuroUsage_install_python3_if_needed {
  'nuro install_python3_if_needed [-Version <x.y.z>]'
}

function NuroCmd_install_python3_if_needed {
  [CmdletBinding()]
  param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '3.13.7'
  )

  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  # Windows以外は案内だけ（元スクリプトがWindows向けのため）
  if (-not $IsWindows) {
    Write-Host "[nuro:py] Non-Windows detected. Please install Python $Version from https://www.python.org/downloads/ ." -ForegroundColor Yellow
    return $false
  }

  function Get-InstalledPython3Path {
    $roots = @(
      'HKCU:\Software\Python\PythonCore',
      'HKLM:\Software\Python\PythonCore',
      'HKLM:\Software\WOW6432Node\Python\PythonCore'
    )
    foreach ($r in $roots) {
      if (-not (Test-Path $r)) { continue }
      Get-ChildItem $r -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match '^3(\.\d+)?$'
      } | ForEach-Object {
        $ip = Join-Path $_.PsPath 'InstallPath'
        if (Test-Path $ip) {
          $p = (Get-ItemProperty $ip).'(default)'; if (-not $p) { $p = (Get-ItemProperty $ip).InstallPath }
          if ($p) {
            $exe  = Join-Path $p 'python.exe'; if (Test-Path $exe)  { return $exe }
            $exe2 = (Get-ItemProperty $ip -ErrorAction SilentlyContinue).ExecutablePath
            if ($exe2 -and (Test-Path $exe2)) { return $exe2 }
          }
        }
      } | Select-Object -First 1 | ForEach-Object { return $_ }
    }
    return $null
  }

  try {
    $found = Get-InstalledPython3Path
    if ($found) {
      Write-Host "[nuro:py] Python3 found: $found"
      return $true
    }

    # --- Download installer ---
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe"
    $installer = Join-Path $env:TEMP ("python-$Version-amd64.exe")

    Write-Host "[nuro:py] Downloading: $url"
    Invoke-WebRequest -Uri $url -OutFile $installer
    if (-not (Test-Path $installer)) { throw "Failed to download installer: $installer" }

    # --- Silent install (per-user, no PATH modify; close to original flags) ---
    Write-Host "[nuro:py] Silent install (per-user, PATH unchanged)"
    $args = @(
      '/quiet',
      'InstallAllUsers=0',
      'PrependPath=0',
      'Include_test=0',
      'Include_launcher=0',
      'Include_pip=1',
      'AssociateFiles=0',
      'Shortcuts=0',
      'SimpleInstall=1'
    )
    $p = Start-Process -FilePath $installer -ArgumentList $args -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "Installer exit code: $($p.ExitCode)" }

    $found = Get-InstalledPython3Path
    if (-not $found) { throw "Installed but python.exe not found in registry paths." }

    Write-Host "[nuro:py] Installed: $found"
    return $true
  }
  catch {
    Write-Error $_.Exception.Message
    return $false
  }
}
