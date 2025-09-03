# bootstrap/nuro.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===== ref / base =====
$Ref  = $env:NURO_REF
$Base = if ($Ref -and $Ref -match '^[vV]\d') {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/tags/$Ref"
} else {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/heads/main"
}
$Owner = "mr-certain-a"
$Repo  = "nuro"

function Invoke-RemoteCmd {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [string[]]$Args
  )

  # コマンド名の安全化（英数/_- のみ）
  $safe = $Name -replace '[^a-zA-Z0-9_-]', ''
  if ($safe -ne $Name -or [string]::IsNullOrWhiteSpace($safe)) {
    throw "nuro: invalid command name '$Name'"
  }

  # リモート取得（キャッシュ回避ヘッダ）
  $url = "$Base/cmds/$safe.ps1?cb=$([Guid]::NewGuid())"
  $H = @{
    'Cache-Control' = 'no-cache'
    'Pragma'        = 'no-cache'
    'User-Agent'    = 'nuro'
  }

  try {
    $code = Invoke-RestMethod -Uri $url -Headers $H -UseBasicParsing
  } catch {
    throw "nuro: failed to fetch '$safe' from $url`n$($_.Exception.Message)"
  }

  # 同一スコープへ定義をロード（Usage/Cmd 関数を公開）
  try {
    $sb = [scriptblock]::Create($code)
    . $sb
  } catch {
    throw "nuro: failed to load '$safe' script.`n$($_.Exception.Message)"
  }

  $main  = "NuroCmd_$safe"
  $usage = "NuroUsage_$safe"

  # ヘルプ要求の判定
  $isHelp = $false
  foreach ($h in @('-h','--help','/?')) {
    if ($Args -contains $h) { $isHelp = $true; break }
  }

  if ($isHelp) {
    if (Get-Command $usage -ErrorAction SilentlyContinue) {
      $line = & $usage
      if ($line) { Write-Host $line } else { Write-Host "nuro $safe - no usage available" }
    } else {
      Write-Host "nuro $safe - no usage available"
    }
    return
  }

  # 本体実行（必須）
  if (Get-Command $main -ErrorAction SilentlyContinue) {
    $res = & $main @Args
    if ($null -ne $res) { Write-Output $res }
  } else {
    throw "nuro: command '$safe' does not expose function '$main'"
  }
}

function Get-AllCommandsUsage {
  $apiUrl = "https://api.github.com/repos/$Owner/$Repo/contents/cmds"
  try { $files = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing } catch { return @() }
  $lines = @()

  foreach ($f in $files) {
    if ($f.name -like '*.ps1') {
      $name = [IO.Path]::GetFileNameWithoutExtension($f.name)
      $url  = "$Base/cmds/$($f.name)"
      try {
        $code = Invoke-RestMethod -Uri $url -UseBasicParsing
        $sb   = [scriptblock]::Create($code)

        # 同一スコープに読み込む（ドットソース）
        . $sb

        $usageFn = "NuroUsage_$name"
        if (Get-Command $usageFn -ErrorAction SilentlyContinue) {
          $line = & $usageFn
          if ($line) { $lines += "  $line" }
        } else {
          $lines += "  nuro $name - no usage available"
        }

        # 掃除（次のループに影響しないよう関数を消す）
        Remove-Item "function:$usageFn" -ErrorAction SilentlyContinue
        Remove-Item "function:NuroCmd_$name" -ErrorAction SilentlyContinue
      }
      catch {
        $lines += "  nuro $name - (usage unavailable)"
      }
    }
  }

  return $lines
}


function nuro {
  if ($args.Count -eq 0) {
    Write-Host "nuro — minimal runner v0.0.7`n"
    Write-Host "USAGE:"
    Write-Host "  nuro <command> [args...]"
    Write-Host "  nuro <command> -h|--help|/?`n"
    Write-Host "COMMANDS:"
    $us = Get-AllCommandsUsage
    if($us.Count -gt 0){ $us | ForEach-Object { Write-Host $_ } }
    else { Write-Host "  (no commands listed / offline)" }
    return
  }
  $cmd  = $args[0]
  $rest = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }
  Invoke-RemoteCmd -Name $cmd -Args $rest
}

if (-not $env:NURO_SILENT -or $env:NURO_SILENT -eq '0') {
  try { nuro } catch { Write-Host "nuro loaded (usage display failed)" }
}
