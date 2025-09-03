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

  # --- 安全化 ---
  $safe = $Name -replace '[^a-zA-Z0-9_-]', ''
  if ($safe -ne $Name -or [string]::IsNullOrWhiteSpace($safe)) {
    throw "nuro: invalid command name '$Name'"
  }

  # --- 取得（キャッシュ回避つき）---
  $url = "$Base/cmds/$safe.ps1?cb=$([Guid]::NewGuid())"
  $H = @{ 'Cache-Control'='no-cache'; 'Pragma'='no-cache'; 'User-Agent'='nuro' }
  $code = Invoke-RestMethod -Uri $url -Headers $H -UseBasicParsing
  $sb   = [scriptblock]::Create($code)
  . $sb  # 同一スコープで NuroUsage_*, NuroCmd_* を定義

  $main  = "NuroCmd_$safe"
  $usage = "NuroUsage_$safe"
  if (-not (Get-Command $main -ErrorAction SilentlyContinue)) {
    throw "nuro: command '$safe' does not expose function '$main'"
  }

  # --- ヘルプ判定（トークンに -h/--help/? が含まれていたら）---
  if ($Args -contains '-h' -or $Args -contains '--help' -or $Args -contains '/?') {
    if (Get-Command $usage -ErrorAction SilentlyContinue) { (& $usage) | Write-Host }
    else { Write-Host "nuro $safe - no usage available" }
    return
  }

 & $main @Args
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
    Write-Host "nuro — minimal runner v0.0.9`n"
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
