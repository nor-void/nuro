# cmds/get.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NuroGet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [string]$Out,
    [string]$Sha256,
    [switch]$Force,
    [int]$TimeoutSec = 60
  )

  Ensure-NuroDirs
  if (-not $Out) { $Out = Default-OutputPath -Url $Url }

  if ((Test-Path $Out) -and -not $Force) {
    Write-Nuro "exists (use -Force to overwrite): $Out"
    return $Out
  }

  $tmp = New-Item -ItemType File -Path ([System.IO.Path]::GetTempFileName()) -Force
  Remove-Item $tmp -Force
  $tmp = [System.IO.Path]::GetTempFileName()

  Write-Nuro "downloading: $Url"
  try {
    # いちばん確実：一旦ファイルに落とす
    Invoke-WebRequest -Uri $Url -OutFile $tmp -TimeoutSec $TimeoutSec | Out-Null
  } catch {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw
  }

  Save-WithHashCheck -SrcPath $tmp -DstPath $Out -Sha256 $Sha256
  return $Out
}

