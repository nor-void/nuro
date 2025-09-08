param(
  [ValidateSet('prod','test','dev')][string]$Channel = 'prod',
  [string]$Version,
  [string]$Repo = 'https://github.com/OWNER/REPO.git',
  [string]$Branch = 'codex'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------
# Helpers / Environment
# ------------------------
function Get-Home {
  $h = $env:USERPROFILE
  if (-not $h) { $h = $HOME }
  if (-not $h) { $h = [Environment]::GetFolderPath('UserProfile') }
  return $h
}

function Join-PathSafe([string]$a, [string]$b) { return (Join-Path $a $b) }

$HOME_DIR = Get-Home
$NURO_HOME = Join-PathSafe $HOME_DIR '.nuro'
$BIN_DIR  = Join-PathSafe $NURO_HOME 'bin'
$LOGS_DIR = Join-PathSafe $NURO_HOME 'logs'
$SRC_DIR  = Join-PathSafe $NURO_HOME 'src'
$VENV_DIR = Join-PathSafe $NURO_HOME 'venv'
$VENV_PY  = Join-PathSafe (Join-PathSafe $VENV_DIR 'Scripts') 'python.exe'
$LOG_FILE = Join-PathSafe $LOGS_DIR 'get.nuro.log'

function Ensure-Dir([string]$p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }

Ensure-Dir $NURO_HOME
Ensure-Dir $BIN_DIR
Ensure-Dir $LOGS_DIR
Ensure-Dir $SRC_DIR

try { Start-Transcript -Path $LOG_FILE -Append -ErrorAction SilentlyContinue | Out-Null } catch { }

function Log([string]$m) { Write-Host "[get.nuro] $m" }

# ------------------------
# Python detection (>=3.10 with venv/ensurepip)
# ------------------------
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
      foreach ($ln in @($lines)) { $p = $ln.Trim(); if ($p -and (Test-Path $p)) { [void]$cands.Add($p) } }
      try { $p310 = & $py.Source '-3.10' '-c' 'import sys;print(sys.executable)' 2>$null; if ($p310 -and (Test-Path $p310)) { [void]$cands.Add($p310) } } catch { }
    } catch { }
  }
  return @($cands)
}

function Probe-PythonVersion([string]$exe) {
  try { $out = & $exe '--version' 2>&1 } catch { return $null }
  if ($out -match 'Python\s+([0-9]+)\.([0-9]+)\.?(\d+)?') {
    $maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
    return [pscustomobject]@{ Path=$exe; Major=$maj; Minor=$min; Patch=$pat; Version = "${maj}.${min}.${pat}" }
  }
  return $null
}

function Test-PythonFeatures([string]$exe) {
  $venv_ok = $false; $ensurepip_ok = $false
  try { $null = & $exe '-c' 'import venv' 2>$null; if ($LASTEXITCODE -eq 0) { $venv_ok = $true } } catch { }
  try { $null = & $exe '-m' 'ensurepip' '--version' 2>$null; if ($LASTEXITCODE -eq 0) { $ensurepip_ok = $true } } catch { }
  return [pscustomobject]@{ venv_ok=$venv_ok; ensurepip_ok=$ensurepip_ok }
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
  $eligible = $infos | Where-Object { ($_.Major -gt 3 -or ($_.Major -eq 3 -and $_.Minor -ge 10)) -and $_.venv_ok -and $_.ensurepip_ok }
  if (-not $eligible) { return $null }
  return ($eligible | Sort-Object -Property @{Expression='Major';Descending=$true}, @{Expression='Minor';Descending=$true}, @{Expression='Patch';Descending=$true})[0]
}

# ------------------------
# uv.exe handling
# ------------------------
function Get-UvUri {
  $arch = ([string]$env:PROCESSOR_ARCHITECTURE).ToLowerInvariant()
  $triple = switch ($arch) { 'arm64' { 'aarch64-pc-windows-msvc' } default { 'x86_64-pc-windows-msvc' } }
  return "https://github.com/astral-sh/uv/releases/latest/download/uv-$triple.zip"
}

function Ensure-Uv {
  $uvExe = Join-PathSafe $BIN_DIR 'uv.exe'
  if (Test-Path $uvExe) { return $uvExe }
  $uri = Get-UvUri
  $tmpZip = Join-PathSafe $NURO_HOME ("uv-" + [IO.Path]::GetRandomFileName() + '.zip')
  $tmpDir = Join-PathSafe $NURO_HOME ("uv-" + [IO.Path]::GetRandomFileName())
  Log "downloading uv: $uri"
  Invoke-WebRequest -Uri $uri -OutFile $tmpZip -UseBasicParsing -TimeoutSec 120 | Out-Null
  try {
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
    $uv = Get-ChildItem -Path $tmpDir -Recurse -Filter 'uv.exe' | Select-Object -First 1
    if (-not $uv) { throw 'uv.exe not found in archive' }
    Move-Item -Force $uv.FullName $uvExe
  } finally {
    Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
  }
  Log "uv ready: $uvExe"
  return $uvExe
}

# ------------------------
# Venv provisioning
# ------------------------
function Ensure-Venv {
  $py = Select-UsablePython
  if ($py) {
    Log ("python OK: {0} (v{1})" -f $py.Path, $py.Version)
    if (-not (Test-Path $VENV_PY)) {
      Log "creating venv via system python"
      & $py.Path '-m' 'venv' $VENV_DIR
      if ($LASTEXITCODE -ne 0) { throw "python -m venv failed ($LASTEXITCODE)" }
    }
  } else {
    Log "python not usable; using uv managed python"
    $uv = Ensure-Uv
    $spec = '3.12'
    & $uv 'python' 'install' $spec
    if ($LASTEXITCODE -ne 0) { throw "uv python install $spec failed ($LASTEXITCODE)" }
    if (-not (Test-Path $VENV_PY)) {
      & $uv 'venv' $VENV_DIR
      if ($LASTEXITCODE -ne 0) { throw "uv venv failed ($LASTEXITCODE)" }
    }
  }
  if (-not (Test-Path $VENV_PY)) { throw 'venv python not found' }
  & $VENV_PY '-m' 'pip' 'install' '--upgrade' 'pip' 'setuptools' 'wheel'
  if ($LASTEXITCODE -ne 0) { throw "pip bootstrap failed ($LASTEXITCODE)" }
  Log "venv ready: $VENV_PY"
}

# ------------------------
# Install nuro per channel
# ------------------------
function Get-GitHubZipUri([string]$repoUrl, [string]$branch) {
  $m = [regex]::Match($repoUrl, '^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?$')
  if (-not $m.Success) { throw "Repo is not a GitHub URL: $repoUrl" }
  $owner = $m.Groups[1].Value; $name = $m.Groups[2].Value
  return "https://github.com/$owner/$name/archive/refs/heads/$branch.zip"
}

function Get-GitHubZipUriByCommit([string]$repoUrl, [string]$commit) {
  $m = [regex]::Match($repoUrl, '^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?$')
  if (-not $m.Success) { throw "Repo is not a GitHub URL: $repoUrl" }
  if (-not ($commit -match '^[0-9a-fA-F]{7,40}$')) { throw "NURO_REF does not look like a commit hash: $commit" }
  $owner = $m.Groups[1].Value; $name = $m.Groups[2].Value
  return "https://github.com/$owner/$name/archive/$commit.zip"
}

function Install-Nuro {
  switch ($Channel) {
    'prod' {
      $pkg = 'nuro'
      if ($Version) { $pkg = "nuro==${Version}" }
      Log "pip install -U $pkg"
      & $VENV_PY '-m' 'pip' 'install' '-U' $pkg
      if ($LASTEXITCODE -ne 0) { throw "pip install failed ($LASTEXITCODE)" }
    }
    'test' {
      Log "pip install from TestPyPI"
      & $VENV_PY '-m' 'pip' 'install' '-U' '-i' 'https://test.pypi.org/simple/' 'nuro'
      if ($LASTEXITCODE -ne 0) { throw "pip install (test) failed ($LASTEXITCODE)" }
    }
    'dev' {
      $dst = Join-PathSafe $SRC_DIR 'nuro'
      $git = Get-Command 'git' -ErrorAction SilentlyContinue
      $ref = $env:NURO_REF
      if ($ref) {
        # When NURO_REF (commit hash) is provided, fetch exact commit archive from GitHub
        $zip = Join-PathSafe $NURO_HOME ("nuro-src-" + [IO.Path]::GetRandomFileName() + '.zip')
        $tmp = Join-PathSafe $NURO_HOME ("nuro-src-" + [IO.Path]::GetRandomFileName())
        $newTree = Join-PathSafe $NURO_HOME ("nuro-src-new-" + [IO.Path]::GetRandomFileName())
        $uri = Get-GitHubZipUriByCommit -repoUrl $Repo -commit $ref
        Log "NURO_REF detected: $ref"
        Log "downloading commit zip: $uri"
        Invoke-WebRequest -Uri $uri -OutFile $zip -UseBasicParsing -TimeoutSec 120 | Out-Null
        try {
          Expand-Archive -Path $zip -DestinationPath $tmp -Force
          $root = Get-ChildItem -Path $tmp | Select-Object -First 1
          Move-Item -Force $root.FullName $newTree
          if (Test-Path $dst) { Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue }
          Move-Item -Force $newTree $dst
        } finally {
          Remove-Item -Force $zip -ErrorAction SilentlyContinue
          Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
          if (Test-Path $newTree) { Remove-Item -Recurse -Force $newTree -ErrorAction SilentlyContinue }
        }
      }
      elseif ($git) {
        if (Test-Path $dst) {
          if (Test-Path (Join-PathSafe $dst '.git')) {
            Log "git fetch/checkout/reset to $Branch"
            & $git.Source '-C' $dst 'fetch' 'origin' $Branch '--depth' '1'
            & $git.Source '-C' $dst 'checkout' '-q' $Branch
            & $git.Source '-C' $dst 'reset' '--hard' "origin/$Branch"
          } else {
            Log 'existing non-git tree detected; removing before clone'
            Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
            Log "git clone --branch $Branch $Repo"
            & $git.Source 'clone' '--branch' $Branch '--depth' '1' $Repo $dst
          }
        } else {
          Log "git clone --branch $Branch $Repo"
          & $git.Source 'clone' '--branch' $Branch '--depth' '1' $Repo $dst
        }
      } else {
        $zip = Join-PathSafe $NURO_HOME ("nuro-src-" + [IO.Path]::GetRandomFileName() + '.zip')
        $tmp = Join-PathSafe $NURO_HOME ("nuro-src-" + [IO.Path]::GetRandomFileName())
        $newTree = Join-PathSafe $NURO_HOME ("nuro-src-new-" + [IO.Path]::GetRandomFileName())
        $uri = Get-GitHubZipUri -repoUrl $Repo -branch $Branch
        Log "downloading source zip: $uri"
        Invoke-WebRequest -Uri $uri -OutFile $zip -UseBasicParsing -TimeoutSec 120 | Out-Null
        try {
          Expand-Archive -Path $zip -DestinationPath $tmp -Force
          $root = Get-ChildItem -Path $tmp | Select-Object -First 1
          Move-Item -Force $root.FullName $newTree
          if (Test-Path $dst) { Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue }
          Move-Item -Force $newTree $dst
        } finally {
          Remove-Item -Force $zip -ErrorAction SilentlyContinue
          Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
          if (Test-Path $newTree) { Remove-Item -Recurse -Force $newTree -ErrorAction SilentlyContinue }
        }
      }
      Log "pip install -e $dst"
      & $VENV_PY '-m' 'pip' 'install' '-U' 'pip' 'setuptools' 'wheel'
      & $VENV_PY '-m' 'pip' 'install' '-e' $dst
      if ($LASTEXITCODE -ne 0) { throw "pip install -e failed ($LASTEXITCODE)" }
      # Log HEAD short SHA if git available
      if ($git -and (Test-Path (Join-PathSafe $dst '.git'))) {
        try {
          $sha = (& $git.Source '-C' $dst 'rev-parse' '--short' 'HEAD').Trim()
          if ($sha) { Log ('dev HEAD="{0}"' -f $sha) }
        } catch { }
      }
    }
  }
}

# ------------------------
# Create shim (cmd only)
# ------------------------
function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Ensure-Shim {
  $cmdPath = Join-PathSafe $BIN_DIR 'nuro.cmd'
  $lines = @(
    '@echo off',
    'setlocal',
    'set "_PY=%USERPROFILE%\\.nuro\\venv\\Scripts\\python.exe"',
    '"%_PY%" -m nuro %*',
    'exit /b %ERRORLEVEL%'
  )
  $content = ($lines -join "`r`n")
  Write-FileUtf8NoBom -Path $cmdPath -Content $content
  Log "shim created: $cmdPath"
}

# ------------------------
# PATH updates
# ------------------------
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
  } else { $new = $current }
  if ($new -ne $current) { [Environment]::SetEnvironmentVariable('Path', $new, 'User'); return $true }
  return $false
}

function Ensure-Path {
  $added = Add-ToUserPath -dir $BIN_DIR
  if (-not (Path-Contains $env:PATH $BIN_DIR)) { $env:PATH = "$BIN_DIR;" + $env:PATH }
  if ($added) { Log "added to User PATH: $BIN_DIR" } else { Log "already in User PATH: $BIN_DIR" }
}

# ------------------------
# Validation
# ------------------------
function Validate-Run {
  $ok1 = $false; $ok2 = $false
  try { $out1 = (& 'nuro' '--version') 2>&1; Log ("nuro --version => {0}" -f $out1); $ok1 = $true } catch { Log ("nuro --version failed: {0}" -f $_.Exception.Message) }
  try { $out2 = (& $VENV_PY '-m' 'nuro' '--version') 2>&1; Log ("python -m nuro --version => {0}" -f $out2); $ok2 = $true } catch { Log ("python -m nuro failed: {0}" -f $_.Exception.Message) }
  if ($ok1 -and $ok2) { Log 'SUCCESS'; return 0 } else { Log 'FAILURE'; return 1 }
}

# ------------------------
# Main
# ------------------------
try {
  Log ("channel=$Channel branch=$Branch repo=$Repo version=$Version")
  Ensure-Venv
  Install-Nuro
  Ensure-Shim
  Ensure-Path
  $code = Validate-Run
  # Summary
  if ($Channel -eq 'dev') { Log ("Summary: Channel=dev Branch=$Branch Repo=$Repo") }
  elseif ($Channel -eq 'prod') { if ($Version) { Log ("Summary: Channel=prod Version=$Version") } else { Log ("Summary: Channel=prod") } }
  else { Log ("Summary: Channel=test") }
  try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
  exit $code
} catch {
  Log ("ERROR: {0}" -f $_.Exception.Message)
  try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
  exit 1
}
