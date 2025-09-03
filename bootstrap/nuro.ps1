# bootstrap/nuro.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Ver = "0.0.16"
if ($env:NURO_DEBUG -eq '1') {
  echo "debug nuro v$Ver"
}

# ===== ref / base =====
$Ref  = $env:NURO_REF
$Base = if ($Ref -and $Ref -match '^[vV]\d') {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/tags/$Ref"
} else {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/heads/main"
}
$Owner = "mr-certain-a"
$Repo  = "nuro"

# --- Args配列を名前付き引数ハッシュに変換 ---
function Convert-ArgsToHash {
  param(
    [string]  $TargetFn,   # 例: 'NuroCmd_get'
    [string[]]$Tokens = @()
  )
  if ($null -eq $Args) { $Args = @() }

  $meta = (Get-Command $TargetFn).Parameters   # IDictionary<string, ParameterMetadata>

  # 名前/エイリアスの正規化マップ（大文字小文字無視）
  $nameMap = @{}
  foreach ($p in $meta.Values) {
    $nameMap[$p.Name.ToLower()] = $p.Name
    foreach ($a in $p.Aliases) { $nameMap[$a.ToLower()] = $p.Name }
  }

  $map = [ordered]@{}
  $i = 0

  # 位置引数はこの優先順で埋める（存在するものだけ）
  $posOrder = @('Url','OutFile','Sha256','TimeoutSec') | Where-Object { $meta.ContainsKey($_) }
  $posIdx = 0

  while ($i -lt $Tokens.Count) {
    $t = $Tokens[$i]

    if ($t -eq '--') { break }    # ここから先は未解析(必要なら拡張)

    if ($t -like '-*') {
      # -Param / --param / -Alias
      $raw = $t.TrimStart('-')
      if ($raw -in @('h','help','?')) { return @{ __showHelp = $true } }

      $canon = $nameMap[$raw.ToLower()]
      if (-not $canon) { throw "nuro: unknown parameter '-$raw' for $TargetFn" }

      $p = $meta[$canon]
      # SwitchParameter かどうか
      if ($p.ParameterType -eq [switch] -or $p.ParameterType.Name -eq 'SwitchParameter') {
        $map[$canon] = $true; $i++; continue
      } else {
        if ($i + 1 -ge $Tokens.Count) { throw "nuro: parameter '-$raw' expects a value." }
        $map[$canon] = $Tokens[$i+1]; $i += 2; continue
      }
    }

    # 位置引数：未セットの次の候補に順番で割り当て
    while ($posIdx -lt $posOrder.Count -and $map.Contains($posOrder[$posIdx])) { $posIdx++ }
    if ($posIdx -lt $posOrder.Count) {
      $map[$posOrder[$posIdx]] = $t
      $posIdx++; $i++; continue
    } else {
      throw "nuro: unexpected positional argument '$t' for $TargetFn"
    }
  }

  return $map
}

function Invoke-RemoteCmd {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [string[]]$Args = @()
  )
  if ($null -eq $Args) { $Args = @() }

  if ($env:NURO_DEBUG -eq '1') {
      Write-Host "[nuro:Invoke-RemoteCmd] Name = $Name"
      Write-Host "[nuro:Invoke-RemoteCmd] Args.Count = $($Args.Count)"
      for ($i=0; $i -lt $Args.Count; $i++) {
        Write-Host ("  Args[{0}] = {1}" -f $i, $Args[$i])
      }
  }

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
  
  # help 判定
  $isHelp = ($Args -and ($Args -contains '-h' -or $Args -contains '--help' -or $Args -contains '/?'))
  if ($isHelp) {
    if (Get-Command $usage -ErrorAction SilentlyContinue) { (& $usage) | Write-Host }
    else { Write-Host "nuro $safe - no usage available" }
    return
  }
  
  if (-not (Get-Command $main -ErrorAction SilentlyContinue)) {
    throw "nuro: command '$safe' does not expose function '$main'"
  }
  
  # ここで Args を辞書化 → ハッシュスプラットで実行
  $paramHash = Convert-ArgsToHash -TargetFn $main -Tokens $Args
  if ($paramHash.Contains('__showHelp')) {
    if (Get-Command $usage -ErrorAction SilentlyContinue) { (& $usage) | Write-Host }
    else { Write-Host "nuro $safe - no usage available" }
    return
  }
  
  $res = & $main @paramHash
  if ($null -ne $res) { Write-Output $res }
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
    Write-Host "nuro — minimal runner v$Ver`n"
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
