# lib/core.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NuroHome { Join-Path $HOME '.nuro' }
function Get-NuroPkgs { Join-Path (Get-NuroHome) 'pkgs' }

function Ensure-NuroDirs {
  foreach ($d in @((Get-NuroHome),(Get-NuroPkgs))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
  }
}

function Write-Nuro {
  param([string]$Msg)
  Write-Host "[nuro] $Msg"
}

function Save-WithHashCheck {
  param(
    [Parameter(Mandatory=$true)][string]$SrcPath,
    [Parameter(Mandatory=$true)][string]$DstPath,
    [string]$Sha256 # 省略可
  )
  if ($Sha256) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $SrcPath).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256.ToLowerInvariant()) {
      Remove-Item -Force $SrcPath -ErrorAction SilentlyContinue
      throw "SHA256 mismatch. expected=$Sha256 actual=$actual"
    }
  }
  $dir = Split-Path $DstPath -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Move-Item -Force -Path $SrcPath -Destination $DstPath
  Write-Nuro "saved: $DstPath"
}

function Default-OutputPath {
  param([string]$Url)
  $fname = [System.IO.Path]::GetFileName((New-Object System.Uri $Url).AbsolutePath)
  if (-not $fname) { $fname = 'download.bin' }
  Join-Path (Get-NuroPkgs) $fname
}

