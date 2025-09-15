<#
.SYNOPSIS
  limbo/*.ps1 を nuro規格（NuroUsage_*/NuroCmd_*）に自動整形して出力する。

.DESCRIPTION
  - ファイル先頭が script-level param の場合は「ファイル名」をコマンド名に採用。
    例: port-open.ps1 → NuroUsage_PortOpen / NuroCmd_PortOpen を生成。
    実行は原本 ps1 を "& <path> @args" で呼び出す（引数はそのまま透過）。
  - ps1 内に function 定義が1つ以上ある場合は、関数ごとに別ファイルを生成。
    各ラッパーは「元ps1を dot-source → その関数を @args で呼ぶ」。

  出力される各ファイルは、nuroの“bucket.ps1方式”と同様に
  NuroUsage_* / NuroCmd_* の2関数を含む。

.EXAMPLE
  .\tools\Create-NuroWrappers.ps1 -SourceDir .\limbo -OutDir .\nuro\bucket

.NOTES
  - UsageはASTから param 名等を拾って“最低限”の自動生成を行う（あとで手修正OK）。
  - コマンド名は PascalCase（英数字）化して Nuro規格の接頭辞を付与する。
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$SourceDir,                 # 例: .\limbo

  [Parameter(Mandatory)]
  [string]$OutDir                     # 例: .\nuro\bucket
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName 'System.Management.Automation'

function Resolve-Pascal {
  param([string]$Name)
  # 英数字以外でスプリット → 先頭大文字化 → 連結。先頭が数字なら Prefix を付ける
  $parts = ($Name -split '[^A-Za-z0-9]+') | Where-Object { $_ -ne '' }
  if (-not $parts) { return 'Cmd' }
  $joined = ($parts | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ''
  if ($joined -match '^[0-9]') { $joined = "Cmd$joined" }
  return $joined
}

function Get-Ast {
  param([string]$Text)
  $tokens = $null; $errors = $null
  return [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors), $errors
}

function Get-RootParamBlock {
  param($Ast)
  # スクリプト直下の ParamBlockAst を拾う（先頭param(...)の判定）
  return $Ast.ParamBlock
}

function Get-Functions {
  param($Ast)
  return $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
}

function Build-UsageText {
  param(
    [string]$DisplayName,     # human表示名（例: port-open or 関数名）
    [System.Collections.IEnumerable]$Params # ParameterAst列
  )
  $paramList =
    if ($Params -and $Params.Count -gt 0) {
      ($Params | ForEach-Object {
        $n = $_.Name.VariablePath.UserPath
        if ($_.Attributes | Where-Object { $_.TypeName.Name -eq 'switch' }) {
          "[-$n]"
        } else {
          "<$n>"
        }
      }) -join ' '
    } else { '' }

@"
Usage:
  $DisplayName $paramList

Notes:
  - 引数はそのまま透過されます（@args）。
"@
}

# 出力準備
$src = Resolve-Path $SourceDir
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = Get-ChildItem -LiteralPath $src -Filter '*.ps1' -File -Recurse
if (-not $files) { Write-Warning "No .ps1 under $src"; return }

foreach ($file in $files) {
  $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
  $parse = Get-Ast -Text $text
  $ast   = $parse[0]; $errs = $parse[1]

  if ($errs -and $errs.Count -gt 0) {
    Write-Warning "Parse warning(s) in $($file.Name): $($errs | ForEach-Object Message -join '; ')"
  }

  $rootParam = Get-RootParamBlock -Ast $ast
  $fnAsts    = Get-Functions -Ast $ast

  $relPathFromOutToSrc = Resolve-Path $file.DirectoryName
  # 生成ファイル名の一意化ヘルパ
  function Write-Wrapper {
    param(
      [string]$CmdName,                 # Pascal化後（例: PortOpen / ShowAdminTools など）
      [string]$DisplayName,             # Usageの1行目に出す呼び名（例: port-open / Show-AdminTools）
      [string]$WrapperFileName,         # 出力ps1のファイル名
      [string]$InvokeBlock,             # NuroCmd_* 内の実体呼び出し本文
      [System.Collections.IEnumerable]$ParamAsts  # Usage生成用
    )

    $usageFn = "NuroUsage_$CmdName"
    $cmdFn   = "NuroCmd_$CmdName"
    $usage   = Build-UsageText -DisplayName $DisplayName -Params $ParamAsts

    $content = @"
# Auto-generated wrapper for nuro (do not edit manually)
# Source: $($file.FullName)

function $usageFn {
@"
$usage
"@
}

function $cmdFn {
    param([string[]]`$args)
    try {
$InvokeBlock
    } catch {
        Write-Error "`$($cmdFn): $($file.Name): $($_.Exception.Message)"
        throw
    }
}
"@

    $outPath = Join-Path $OutDir $WrapperFileName
    $content | Set-Content -LiteralPath $outPath -Encoding UTF8 -NoNewline
    Write-Host "Generated: $outPath" -ForegroundColor Green
  }

  if ($rootParam) {
    # スクリプト型：ファイル名＝コマンド名
    $baseName   = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $cmdName    = Resolve-Pascal $baseName
    $wrapper    = "$cmdName.ps1"
    $display    = $baseName  # Usage表示は元のファイル名派
    $invoke     = @"
        # script passthrough: invoke the original ps1 with user args
        & "$($file.FullName)" @args
"@
    Write-Wrapper -CmdName $cmdName -DisplayName $display -WrapperFileName $wrapper -InvokeBlock $invoke -ParamAsts $rootParam.Parameters
  }

  if ($fnAsts.Count -gt 0) {
    foreach ($fn in $fnAsts) {
      $origFnName = $fn.Name
      $cmdName    = Resolve-Pascal $origFnName
      $wrapper    = "$cmdName.ps1"
      $display    = $origFnName   # Usage表示は元の関数名派
      $invoke     = @"
        # function passthrough: dot-source original then invoke the function
        . "$($file.FullName)"
        & $origFnName @args
"@
      Write-Wrapper -CmdName $cmdName -DisplayName $display -WrapperFileName $wrapper -InvokeBlock $invoke -ParamAsts $fn.Parameters
    }
  }

  # どちらにも該当しない（paramもfunctionも無い）ps1はスキップ（通知のみ）
  if (-not $rootParam -and $fnAsts.Count -eq 0) {
    Write-Warning "No root param or functions found in $($file.Name); skipped."
  }
}

Write-Host "Done. Put generated wrappers under: $OutDir" -ForegroundColor Cyan

