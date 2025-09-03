# bootstrap/nuro.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ルート基準でロード
$ROOT = Resolve-Path (Join-Path $PSScriptRoot '..')
. (Join-Path $ROOT 'lib/core.ps1')
. (Join-Path $ROOT 'cmds/get.ps1')

function nuro {
  [CmdletBinding()]
  param(
    [Parameter(Position=0)]
    [ValidateSet('get','help')]
    [string]$Cmd = 'help',

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Rest
  )
  switch ($Cmd) {
    'get'  { Invoke-NuroGet @Rest }
    'help' {
@"
nuro — minimal scoop-like runner

USAGE:
  nuro get -Url <https://...> [-Out <path>] [-Sha256 <hex>] [-Force] [-TimeoutSec <int>]

EXAMPLE:
  nuro get -Url https://example.com/tool.ps1 -Out $HOME\.nuro\pkgs\tool.ps1
"@ | Write-Host
    }
  }
}
