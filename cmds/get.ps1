# cmds/get.ps1
echo "debug get v0.2"
function NuroUsage_get {
  'nuro get -Url <https://...> [-OutFile <path>] [-Sha256 <hex>] [-Force] [-TimeoutSec <int>]'
}

function NuroCmd_get {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$OutFile,
    [string]$Sha256,
    [switch]$Force,
    [int]$TimeoutSec = 60
  )

if ($env:NURO_DEBUG -eq '1') {
  Write-Host "[nuro:get][DBG] PSBoundParameters:"
  $PSBoundParameters.GetEnumerator() | ForEach-Object {
    Write-Host ("  {0} = {1}" -f $_.Key, $_.Value)
  }
}

  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  function Write-Nuro([string]$Msg) { Write-Host "[nuro:get] $Msg" }

  if (-not $OutFile) {
    $home = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $pkgs = Join-Path $home '.nuro\pkgs'
    if (-not (Test-Path $pkgs)) { New-Item -ItemType Directory -Path $pkgs | Out-Null }
    $fname = [IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($fname)) { $fname = 'download.bin' }
    $OutFile = Join-Path $pkgs $fname
  } else {
    $dir = Split-Path $OutFile -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  }

  if ((Test-Path $OutFile) -and -not $Force) {
    Write-Nuro "exists (use -Force to overwrite): $OutFile"; return $OutFile
  }

  $tmp = [IO.Path]::GetTempFileName()
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
}
