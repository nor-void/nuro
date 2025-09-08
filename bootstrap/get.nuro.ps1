# bootstrap/get.nuro.ps1
param(
  [string]$Ref = $env:NURO_REF,
  [string]$Owner = 'mr-certain-a',
  [string]$Repo  = 'nuro',
  [switch]$Force,
  [int]$TimeoutSec = 60,
  [string]$Sha256,
  [string]$UvUri,
  [string]$VenvSpec = '3.12'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-Ref([string]$r) {
  if (-not $r) { return 'main' }
  if ($r -like 'refs/heads/*') { return $r.Substring(11) }
  if ($r -like 'refs/tags/*')  { return $r.Substring(10) }
  return $r
}

# Root under ~/.nuro only (avoid PowerShell 7 '??' for PS5.1 compatibility)
$HOME_DIR = $env:USERPROFILE
if (-not $HOME_DIR) { $HOME_DIR = $HOME }
if (-not $HOME_DIR) { $HOME_DIR = [Environment]::GetFolderPath('UserProfile') }
$NURO_HOME  = Join-Path $HOME_DIR '.nuro'
$BOOT_DIR   = Join-Path $NURO_HOME 'bootstrap'
$TMP_DIR    = Join-Path $NURO_HOME 'tmp'
$CONF_DIR   = Join-Path $NURO_HOME 'config'
$BIN_DIR    = Join-Path $NURO_HOME 'bin'
$VENV_DIR   = Join-Path $NURO_HOME 'venv'
$LOGS_DIR   = Join-Path $NURO_HOME 'logs'

# Ensure directories
foreach ($d in @($NURO_HOME, $BOOT_DIR, $TMP_DIR, $CONF_DIR, $BIN_DIR, $LOGS_DIR)) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

# Per-run log file under ~/.nuro/logs
$__logFile = Join-Path $LOGS_DIR ("get.nuro." + (Get-Date -Format 'yyyyMMdd') + ".log")
try { Start-Transcript -Path $__logFile -Append -ErrorAction SilentlyContinue | Out-Null } catch { }

$ref = Normalize-Ref $Ref
$base = "https://raw.githubusercontent.com/$Owner/$Repo/$ref"
$src  = "$base/bootstrap/nuro.ps1"
$dst  = Join-Path $BOOT_DIR 'nuro.ps1'

Write-Host "[get.nuro] target: $dst"
$__resultPath = $dst

if ((Test-Path $dst) -and -not $Force) {
  Write-Host "[get.nuro] exists (use -Force to overwrite)"
} else {

# Use ~/.nuro/tmp for temp file (avoid system temp)
$tmp = Join-Path $TMP_DIR ([IO.Path]::GetRandomFileName())
try {
  Write-Host "[get.nuro] downloading: $src"
  Invoke-WebRequest -Uri $src -OutFile $tmp -TimeoutSec $TimeoutSec -UseBasicParsing | Out-Null

  if ($Sha256) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
      Remove-Item -Force $tmp -ErrorAction SilentlyContinue
      throw "SHA256 mismatch. expected=$Sha256 actual=$actual"
    }
  }

  Move-Item -Force $tmp $dst
  Write-Host "[get.nuro] saved: $dst"
  Write-Host "[get.nuro] usage: . $dst ; nuro"
}
catch {
  Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  throw
}

}

# =============================
# Python detection (>= 3.10)
# =============================

function Get-PythonCandidates {
  $cands = New-Object System.Collections.Generic.HashSet[string]
  foreach ($name in @('python','python3')) {
    $cmds = Get-Command $name -ErrorAction SilentlyContinue
    foreach ($c in @($cmds)) { if ($c.Source) { [void]$cands.Add($c.Source) } }
  }
  $py = Get-Command 'py' -ErrorAction SilentlyContinue
  if ($py) {
    try {
      $lines = & $py.Source '-0p' 2>$null
      foreach ($ln in @($lines)) {
        $p = $ln.Trim()
        if ($p -and (Test-Path $p)) { [void]$cands.Add($p) }
      }
      try {
        $p310 = & $py.Source '-3.10' '-c' 'import sys;print(sys.executable)' 2>$null
        if ($p310 -and (Test-Path $p310)) { [void]$cands.Add($p310) }
      } catch { }
    } catch { }
  }
  return @($cands)
}

function Probe-PythonVersion([string]$exe) {
  try {
    $out = & $exe '--version' 2>&1
    if ($out -match 'Python\s+([0-9]+)\.([0-9]+)\.?(\d+)?') {
      $maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
      return [pscustomobject]@{ Path = $exe; Major=$maj; Minor=$min; Patch=$pat; Version = "${maj}.${min}.${pat}" }
    }
  } catch { }
  return $null
}

function Test-PythonFeatures([string]$exe) {
  $venv_ok = $false; $ensurepip_ok = $false
  try { $null = & $exe '-c' 'import venv' 2>$null; if ($LASTEXITCODE -eq 0) { $venv_ok = $true } } catch { $venv_ok = $false }
  try { $null = & $exe '-m' 'ensurepip' '--version' 2>$null; if ($LASTEXITCODE -eq 0) { $ensurepip_ok = $true } } catch { $ensurepip_ok = $false }
  return [pscustomobject]@{ venv_ok = $venv_ok; ensurepip_ok = $ensurepip_ok }
}

function Select-UsablePython {
  $infos = @()
  foreach ($p in (Get-PythonCandidates)) {
    $info = Probe-PythonVersion $p
    if ($info) {
      $feat = Test-PythonFeatures $p
      $info | Add-Member -NotePropertyName venv_ok -NotePropertyValue $feat.venv_ok -Force
      $info | Add-Member -NotePropertyName ensurepip_ok -NotePropertyValue $feat.ensurepip_ok -Force
      $infos += $info
    }
  }
  if (-not $infos) { return $null }
  # Prefer highest version meeting >= 3.10
  $minMajor = 3; $minMinor = 10
  $eligible = $infos | Where-Object { ($_.Major -gt $minMajor -or ($_.Major -eq $minMajor -and $_.Minor -ge $minMinor)) -and $_.venv_ok -and $_.ensurepip_ok }
  if (-not $eligible) { return $null }
  return ($eligible | Sort-Object -Property @{Expression='Major';Descending=$true}, @{Expression='Minor';Descending=$true}, @{Expression='Patch';Descending=$true})[0]
}

try {
  $py = Select-UsablePython
  $state = if ($py) {
    Write-Host ("[get.nuro] python OK: {0} (v{1})" -f $py.Path, $py.Version)
    [pscustomobject]@{ path = $py.Path; version = $py.Version; source = 'system'; min_ok = $true; venv_ok = $py.venv_ok; ensurepip_ok = $py.ensurepip_ok }
  } else {
    Write-Host "[get.nuro] python not found or < 3.10 or missing venv/ensurepip"
    [pscustomobject]@{ path = $null; version = $null; source = 'absent'; min_ok = $false; venv_ok = $false; ensurepip_ok = $false }
  }
  $state | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $CONF_DIR 'python.json') -Encoding UTF8
} catch {
  Write-Host "[get.nuro] python detection failed: $($_.Exception.Message)"
}

# ======================================================
# If Python is not usable, fetch uv.exe under ~/.nuro/bin
# ======================================================

function Get-UvDefaultUri {
  if ($UvUri) { return $UvUri }
  $arch = ([string]$env:PROCESSOR_ARCHITECTURE).ToLowerInvariant()
  $triple = switch ($arch) {
    'arm64' { 'aarch64-pc-windows-msvc' }
    default { 'x86_64-pc-windows-msvc' }
  }
  return "https://github.com/astral-sh/uv/releases/latest/download/uv-$triple.zip"
}

function Install-Uv {
  param([string]$Uri)

  $tmpZip  = Join-Path $TMP_DIR ("uv-" + [IO.Path]::GetRandomFileName() + '.zip')
  $tmpDir  = Join-Path $TMP_DIR ("uv-" + [IO.Path]::GetRandomFileName())
  $destExe = Join-Path $BIN_DIR 'uv.exe'

  try {
    Write-Host "[get.nuro] downloading uv: $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $tmpZip -TimeoutSec $TimeoutSec -UseBasicParsing | Out-Null

    try {
      Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
    } catch {
      # In case it's a direct exe, move it
      if ((Split-Path $tmpZip -Leaf) -like '*.exe') {
        Move-Item -Force $tmpZip $destExe
        return $destExe
      } else { throw }
    }

    $uv = Get-ChildItem -Path $tmpDir -Recurse -Filter 'uv.exe' | Select-Object -First 1
    if (-not $uv) { throw 'uv.exe not found in archive' }
    Move-Item -Force $uv.FullName $destExe
    Write-Host "[get.nuro] uv saved: $destExe"
    return $destExe
  }
  finally {
    Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
  }
}

try {
  $pyState = Get-Content -Path (Join-Path $CONF_DIR 'python.json') -Raw | ConvertFrom-Json
  # Ensure uv is present when python is not usable OR when we need to bootstrap a venv
  if (-not $pyState.min_ok -or -not (Test-Path (Join-Path $VENV_DIR 'Scripts/python.exe'))) {
    $uri = Get-UvDefaultUri
    $exe = Install-Uv -Uri $uri
    $ver = $null
    try { $ver = (& $exe '--version' 2>$null) } catch { }
    $uvState = [pscustomobject]@{ path = $exe; version = $ver; source = 'download'; ok = $true }
    $uvState | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $CONF_DIR 'uv.json') -Encoding UTF8
  }
} catch {
  Write-Host "[get.nuro] uv download skipped/failed: $($_.Exception.Message)"
}

# ===============================================
# Create ~/.nuro/venv using uv when Python unusable
# ===============================================

function New-UvVenv {
  param(
    [Parameter(Mandatory)] [string]$UvExe,
    [Parameter(Mandatory)] [string]$TargetDir,
    [Parameter(Mandatory)] [string]$PythonSpec
  )
  if ((Test-Path (Join-Path $TargetDir 'Scripts/python.exe'))) {
    Write-Host "[get.nuro] venv already exists: $TargetDir"
    return (Join-Path $TargetDir 'Scripts/python.exe')
  }
  Write-Host "[get.nuro] creating venv via uv: python=$PythonSpec dir=$TargetDir"
  $args = @('venv','--python', $PythonSpec, $TargetDir)
  & $UvExe @args
  if ($LASTEXITCODE -ne 0) { throw "uv venv failed with exit code $LASTEXITCODE" }
  $venvPy = Join-Path $TargetDir 'Scripts/python.exe'
  if (-not (Test-Path $venvPy)) { throw 'venv python not found after uv venv' }
  return $venvPy
}

try {
  if (-not (Test-Path (Join-Path $VENV_DIR 'Scripts/python.exe'))) {
    $uv = $null
    try { $uv = (Get-Content -Path (Join-Path $CONF_DIR 'uv.json') -Raw | ConvertFrom-Json).path } catch { }
    if (-not $uv -or -not (Test-Path $uv)) { throw 'uv.exe not available' }
    $venvPy = New-UvVenv -UvExe $uv -TargetDir $VENV_DIR -PythonSpec $VenvSpec
    $verOut = & $venvPy '--version' 2>&1
    $venvOk = $false; $pipOk = $false
    try { $null = & $venvPy '-c' 'import venv' 2>$null; if ($LASTEXITCODE -eq 0) { $venvOk = $true } } catch { }
    try { $null = & $venvPy '-m' 'ensurepip' '--version' 2>$null; if ($LASTEXITCODE -eq 0) { $pipOk = $true } } catch { }
    $rec = [pscustomobject]@{ dir = $VENV_DIR; python = $venvPy; version = $verOut; provider = 'uv'; spec = $VenvSpec; venv_ok = $venvOk; ensurepip_ok = $pipOk; ok = ($venvOk -and $pipOk) }
    $rec | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $CONF_DIR 'venv.json') -Encoding UTF8
    if (-not $rec.ok) { throw 'created venv failed validation (venv/ensurepip)' }
    Write-Host "[get.nuro] venv ready: $($rec.python)"
  } else {
    $venvPy = Join-Path $VENV_DIR 'Scripts/python.exe'
    $verOut = & $venvPy '--version' 2>&1
    $rec = [pscustomobject]@{ dir = $VENV_DIR; python = $venvPy; version = $verOut; provider = 'existing'; spec = $VenvSpec; venv_ok = $true; ensurepip_ok = $true; ok = $true }
    $rec | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $CONF_DIR 'venv.json') -Encoding UTF8
    Write-Host "[get.nuro] venv present: $($rec.python)"
  }
} catch {
  Write-Host "[get.nuro] venv creation skipped/failed: $($_.Exception.Message)"
}

try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }

# =====================================
# Create shims under ~/.nuro/bin (nuro)
# =====================================

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$shimCmdLines = @(
  '@echo off',
  'setlocal',
  'set "_NURO_HOME=%USERPROFILE%\.nuro"',
  'set "_PY=%_NURO_HOME%\venv\Scripts\python.exe"',
  'if not exist "%_PY%" (',
  '  echo [nuro.cmd] venv python not found: %_PY% 1>&2',
  '  for %%P in (pwsh.exe powershell.exe) do (',
  '    if exist "%_NURO_HOME%\bootstrap\get.nuro.ps1" %%P -NoProfile -ExecutionPolicy Bypass -File "%_NURO_HOME%\bootstrap\get.nuro.ps1"',
  '  )',
  ')',
  'if not exist "%_PY%" (',
  '  echo [nuro.cmd] still missing venv; aborting. 1>&2',
  '  exit /b 1',
  ')',
  '"%_PY%" -m nuro %*',
  'exit /b %ERRORLEVEL%'
)
$shimCmd = ($shimCmdLines -join "`r`n")

$shimPs1Lines = @(
  'param([string[]]$args)',
  '$usr = $env:USERPROFILE; if (-not $usr) { $usr = $HOME }; if (-not $usr) { $usr = [Environment]::GetFolderPath(''UserProfile'') }',
  '$NURO_HOME = Join-Path $usr ''.nuro''',
  '$py = Join-Path $NURO_HOME ''venv/Scripts/python.exe''',
  'if (-not (Test-Path $py)) {',
  '  $get = Join-Path $NURO_HOME ''bootstrap/get.nuro.ps1''',
  '  if (Test-Path $get) {',
  '    try { pwsh -NoProfile -ExecutionPolicy Bypass -File $get } catch { }',
  '  }',
  '}',
  'if (-not (Test-Path $py)) { Write-Error "[nuro.ps1] venv python not found: $py"; exit 1 }',
  '& $py -m nuro @args',
  'exit $LASTEXITCODE'
)
$shimPs1 = ($shimPs1Lines -join "`r`n")

$cmdPath = Join-Path $BIN_DIR 'nuro.cmd'
$ps1Path = Join-Path $BIN_DIR 'nuro.ps1'
Write-FileUtf8NoBom -Path $cmdPath -Content $shimCmd
Write-FileUtf8NoBom -Path $ps1Path -Content $shimPs1
Write-Host "[get.nuro] shims created: $cmdPath, $ps1Path"

# =====================================
# Add ~/.nuro/bin to PATH (user + session)
# =====================================

function Path-Contains([string]$path, [string]$dir) {
  $tgt = $dir.TrimEnd('\\')
  $matches = @((($path -split ';') | Where-Object { $_.TrimEnd('\\') -ieq $tgt }))
  return $matches.Count -gt 0
}

function Add-ToUserPath([string]$dir) {
  $current = [Environment]::GetEnvironmentVariable('Path','User')
  if ([string]::IsNullOrEmpty($current)) {
    $new = $dir
  } elseif (-not (Path-Contains $current $dir)) {
    $new = "$dir;$current"
  } else {
    $new = $current
  }
  if ($new -ne $current) {
    [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    return $true
  }
  return $false
}

$added = Add-ToUserPath -dir $BIN_DIR
if (-not (Path-Contains $env:PATH $BIN_DIR)) { $env:PATH = "$BIN_DIR;" + $env:PATH }
if ($added) { Write-Host "[get.nuro] added to User PATH: $BIN_DIR" } else { Write-Host "[get.nuro] already in User PATH: $BIN_DIR" }
