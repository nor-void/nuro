# cmds/get.ps1
param(
  [Parameter(Mandatory = $true)]
  [string]$Url,
  [string]$OutFile,
  [string]$Sha256,
  [switch]$Force,
  [int]$TimeoutSec = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Nuro([string]$Msg) { Write-Host "[nuro:get] $Msg" }

# 既定の保存先: ~/.nuro/pkgs/<filename>
if (-not $OutFile) {
  $home = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
  $pkgs = Join-Path $home '.nuro\pkgs'
  if (-not (Test-Path $pkgs)) { New-Item -ItemType Directory -Path $pkgs | Out-Null }

  $fname = [System.IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
  if ([string]::IsNullOrWhiteSpace($fname)) { $fname = 'download.bin' }
  $OutFile = Join-Path $pkgs $fname
} else {
  $dir = Split-Path $OutFile -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}

# 既存ファイルの扱い
if ((Test-Path $OutFile) -and -not $Force) {
  Write-Nuro "exists (use -Force to overwrite): $OutFile"
  $OutFile
  return
}

# ダウンロード → 一時ファイルでハッシュ検証 → 配置
$tmp = [System.IO.Path]::GetTempFileName()
try {
  Write-Nuro "downloading: $Url"
  Invoke-WebRequest -Uri $Url -OutFile $tmp -TimeoutSec $TimeoutSec | Out-Null

  if ($Sha256) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
      Remove-Item -Force $tmp -ErrorAction SilentlyContinue
      throw "SHA256 mismatch. expected=$Sha256 actual=$actual"
    }
  }

  Move-Item -Force $tmp $OutFile
  Write-Nuro "saved: $OutFile"
  $OutFile
}
catch {
  Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  throw
}
