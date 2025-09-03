# bootstrap/nuro.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 参照先（デフォルト main）。タグ固定したい時だけ $env:NURO_REF="v0.0.1" を設定
$Ref  = $env:NURO_REF
$Base = if ($Ref -and $Ref -match '^[vV]\d') {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/tags/$Ref"
} else {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/heads/main"
}

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
    'get' {
      $url  = "$Base/cmds/get.ps1"
      # 直接文字列としてコード取得→ScriptBlockにしてパラメータ付きで実行（ローカル保存しない）
      $code = Invoke-RestMethod -Uri $url -UseBasicParsing
      $sb   = [scriptblock]::Create($code)
      & $sb @Rest
    }
    default {
@"
nuro — minimal runner

USAGE:
  nuro get -Url <https://...> [-Out <path>] [-Sha256 <hex>] [-Force] [-TimeoutSec <int>]

TIPS:
  # タグ固定で再現性を上げる場合
  `$env:NURO_REF = 'v0.0.1'

"@ | Write-Host
    }
  }
}
