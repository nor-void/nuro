# bootstrap/nuro.ps1 
param(
  [string]$Ref = $env:NURO_REF 
)

if (-not $Ref) { $Ref = "main" }

function Get-BaseUrl {
  param([string]$Ref)
  if ($Ref -match '^[vV]\d') {
    # タグ想定
    return "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/tags/$Ref"
  } else {
    # ブランチ想定
    return "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/heads/$Ref"
  }
}

$Base = Get-BaseUrl -Ref $Ref

function Import-Remote {
  param(
    [Parameter(Mandatory=$true)][string]$RelativePath
  )
  $url = "$Base/$RelativePath"
  $tmp = Join-Path $env:TEMP ("nuro_" + ($RelativePath -replace '[\\/]', '_'))
  Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing | Out-Null
  . $tmp
}

# ここで GitHub 上のファイルを取り込む
Import-Remote 'lib/core.ps1'
Import-Remote 'cmds/get.ps1'

# エントリポイント
function nuro {
  [CmdletBinding()]
  param(
    [Parameter(Position=0)][ValidateSet('get','help')][string]$Cmd = 'help',
    [Parameter(ValueFromRemainingArguments)][string[]]$Rest
  )
  switch ($Cmd) {
    'get'  { Invoke-NuroGet @Rest }
    default {
      Write-Host @"
nuro — minimal scoop-like runner

USAGE:
  nuro get -Url <https://...> [-Out <path>] [-Sha256 <hex>] [-Force] [-TimeoutSec <int>]

EXAMPLE:
  nuro get -Url https://example.com/tool.ps1 -Out `$HOME\.nuro\pkgs\tool.ps1
"@
    }
  }
}
