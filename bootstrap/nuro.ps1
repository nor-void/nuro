# nuro bootstrap
# GitHub 直読みで lib/core.ps1 と cmds/get.ps1 をロードして nuro コマンドを定義する
# ローカルにクローン不要、irm + iex だけで即利用可

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# 設定：参照するリビジョン
# ============================================================
# デフォルトは main ブランチ。タグ指定したい場合は環境変数 NURO_REF をセットしておく。
$Ref = $env:NURO_REF
if (-not $Ref) { $Ref = "main" }

function Get-BaseUrl {
  param([string]$Ref)
  if ($Ref -match '^[vV]\d') {
    # タグ指定
    return "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/tags/$Ref"
  } else {
    # ブランチ指定
    return "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/heads/$Ref"
  }
}

$Base = Get-BaseUrl -Ref $Ref

# ============================================================
# リモート import ヘルパ
# ============================================================
function Import-Remote {
  param([Parameter(Mandatory=$true)][string]$RelativePath)
  $url = "$Base/$RelativePath"
  try {
    $code = Invoke-RestMethod -Uri $url -UseBasicParsing
    Invoke-Expression $code
  } catch {
    throw "[nuro] failed to load: $url`n$($_.Exception.Message)"
  }
}

# ============================================================
# サブモジュールをロード
# ============================================================
Import-Remote 'lib/core.ps1'
Import-Remote 'cmds/get.ps1'

# ============================================================
# エントリポイント
# ============================================================
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
    default {
      Write-Host @"
nuro — minimal scoop-like runner (PowerShell)

USAGE:
  nuro get -Url <https://...> [-Out <path>] [-Sha256 <hex>] [-Force] [-TimeoutSec <int>]

EXAMPLE:
  nuro get -Url https://example.com/tool.ps1 -Out `$HOME\.nuro\pkgs\tool.ps1
"@
    }
  }
}
