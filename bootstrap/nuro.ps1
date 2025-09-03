# bootstrap/nuro.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Ver = "0.0.17"

if ($env:NURO_DEBUG -eq '1') {
  echo "debug nuro v$Ver"
}

#================================================================================
# ref / base
#================================================================================
$Ref  = $env:NURO_REF
$Base = if ($Ref -and $Ref -match '^[vV]\d') {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/tags/$Ref"
} else {
  "https://raw.githubusercontent.com/mr-certain-a/nuro/refs/heads/main"
}
$Owner = "mr-certain-a"
$Repo  = "nuro"

#================================================================================
# === Bucket registry (local JSON) ===
#================================================================================
$NURO_HOME   = Join-Path ($env:USERPROFILE ?? $HOME) ".nuro"
$NURO_CONFIG = Join-Path $NURO_HOME "config"
$BUCKET_FILE = Join-Path $NURO_CONFIG "buckets.json"

function Initialize-NuroRegistry {
  if (-not (Test-Path $NURO_CONFIG)) { New-Item -ItemType Directory -Path $NURO_CONFIG | Out-Null }
  if (-not (Test-Path $BUCKET_FILE)) {
    $ref = $env:NURO_REF
    $mainRef = if ($ref -and $ref -match '^[vV]\d') { "refs/tags/$ref" } else { "refs/heads/main" }
    $obj = @{
      buckets = @(
        @{ name='official'; uri=("github::mr-certain-a/nuro@{0}" -f $mainRef); priority=100; trusted=$true }
      )
      pins = @{}
    }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $BUCKET_FILE
  }
}
function Load-NuroRegistry { Initialize-NuroRegistry; Get-Content $BUCKET_FILE -Raw | ConvertFrom-Json }
function Save-NuroRegistry($obj) { ($obj | ConvertTo-Json -Depth 5) | Set-Content -Encoding UTF8 $BUCKET_FILE }

# uri 形式:
#  - github::owner/repo@<ref>   （ref=refs/heads/.. / refs/tags/.. / <sha>）
#  - raw::https://host/base     （<base>/<cmd>.ps1 を取りに行く）
#  - local::<absolute_path>     （<path>\<cmd>.ps1 を読む）
#  - それ以外（絶対/相対パス）は local 扱いに自動補正
function Parse-BucketUri([string]$uri) {
  if ($uri -like 'github::*') {
    $spec = $uri.Substring(8) # owner/repo@ref
    $parts = $spec -split '@', 2
    $repo  = $parts[0]
    $ref   = if ($parts.Count -gt 1 -and $parts[1]) { $parts[1] } else { 'refs/heads/main' }
    return @{ type='github'; base=("https://raw.githubusercontent.com/{0}/{1}" -f $repo, $ref) }
  }
  elseif ($uri -like 'raw::*') {
    return @{ type='raw'; base=($uri.Substring(5).TrimEnd('/')) }
  }
  elseif ($uri -like 'local::*') {
    return @{ type='local'; base=($uri.Substring(7)) }
  }
  else {
    # パスっぽいものは local 扱い
    return @{ type='local'; base=$uri }
  }
}

# コマンドスクリプトの取得
function Resolve-CmdSource([string]$bucketUri,[string]$cmdName) {
  $p = Parse-BucketUri $bucketUri
  switch ($p.type) {
    'github' { return @{ kind='remote'; url=("{0}/{1}.ps1?cb={2}" -f $p.base, $cmdName, [Guid]::NewGuid()) } }
    'raw'    { return @{ kind='remote'; url=("{0}/{1}.ps1?cb={2}" -f $p.base, $cmdName, [Guid]::NewGuid()) } }
    'local'  {
      $path = Join-Path $p.base "$cmdName.ps1"
      return @{ kind='local'; path=$path }
    }
  }
}

# 実行（取って dot-source → NuroCmd_* 呼び出し）; Args は後述の Convert-ArgsToHash を使用
function Run-FromBucket([string]$bucketUri,[string]$cmd,[string[]]$tokens) {
  $src = Resolve-CmdSource $bucketUri $cmd
  $H = @{ 'Cache-Control'='no-cache'; 'Pragma'='no-cache'; 'User-Agent'='nuro' }

  $code = $null
  if ($src.kind -eq 'remote') {
    $code = Invoke-RestMethod -Uri $src.url -Headers $H -UseBasicParsing
  } else {
    if (-not (Test-Path $src.path)) { throw "local script not found: $($src.path)" }
    $code = Get-Content $src.path -Raw -Encoding UTF8
  }

  $sb = [scriptblock]::Create($code)
  . $sb

  $main  = "NuroCmd_$cmd"
  $usage = "NuroUsage_$cmd"

  # help?
  if ($tokens -and ($tokens -contains '-h' -or $tokens -contains '--help' -or $tokens -contains '/?')) {
    if (Get-Command $usage -ErrorAction SilentlyContinue) { (& $usage) | Write-Host } else { Write-Host "nuro $cmd - no usage available" }
    return
  }

  if (-not (Get-Command $main -ErrorAction SilentlyContinue)) {
    throw "nuro: command '$cmd' does not expose function '$main'"
  }

  $ph = Convert-ArgsToHash -TargetFn $main -Tokens $tokens
  if ($ph.Contains('__showHelp')) {
    if (Get-Command $usage -ErrorAction SilentlyContinue) { (& $usage) | Write-Host } else { Write-Host "nuro $cmd - no usage available" }
    return
  }

  $res = & $main @ph
  if ($null -ne $res) { Write-Output $res }
}

# --- Args配列を名前付き引数ハッシュに変換 ---
function Convert-ArgsToHash {
  param(
    [string]  $TargetFn,   # 例: 'NuroCmd_get'
    [string[]]$Tokens
  )
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
    [string[]]$Args
  )
  if ($env:NURO_DEBUG -eq '1') {
      Write-Host "[nuro:Invoke-RemoteCmd] Name = $Name"
      Write-Host "[nuro:Invoke-RemoteCmd] Args.Count = $($Args.Count)"
      for ($i=0; $i -lt $Args.Count; $i++) {
        Write-Host ("  Args[{0}] = {1}" -f $i, $Args[$i])
      }
  }

  # bucket 指定 (bucket:cmd) の分解
  $bucketHint = $null; $cmd = $Name
  if ($Name -match '^([^:]+):([^:]+)$') { $bucketHint = $Matches[1]; $cmd = $Matches[2] }

  $reg = Load-NuroRegistry

  # pin 優先
  if (-not $bucketHint -and $reg.pins.PSObject.Properties.Name -contains $cmd) {
    $bucketHint = $reg.pins.$cmd
  }

  if ($bucketHint) {
    $b = $reg.buckets | Where-Object { $_.name -eq $bucketHint }
    if (-not $b) { throw "bucket '$bucketHint' not found" }
    return (Run-FromBucket -bucketUri $b.uri -cmd $cmd -tokens $Args)
  }

  # 候補列: priority desc
  $cands = $reg.buckets | Sort-Object -Property @{Expression='priority';Descending=$true}
  $errors = @()
  foreach ($b in $cands) {
    try {
      return (Run-FromBucket -bucketUri $b.uri -cmd $cmd -tokens $Args)
    } catch {
      $errors += "  - $($b.name): $($_.Exception.Message.Split("`n")[0])"
    }
  }
  throw ("nuro: command '$cmd' not found in any bucket.`n" + ($errors -join "`n"))
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
