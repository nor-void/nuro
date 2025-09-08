# bootstrap/nuro.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Always dispatch to Python module under ~/.nuro/venv when available
try {
  $NURO_HOME = Join-Path ($env:USERPROFILE ?? $HOME) '.nuro'
  $VENV_PY   = Join-Path $NURO_HOME 'venv/Scripts/python.exe'
  if (Test-Path $VENV_PY) {
    & $VENV_PY '-m' 'nuro' @args
    exit $LASTEXITCODE
  } else {
    Write-Host "[nuro] venv python not found: $VENV_PY"
    Write-Host "[nuro] run 'pwsh bootstrap/get.nuro.ps1' to initialize."
    exit 1
  }
} catch {
  Write-Host "[nuro] dispatch failed: $($_.Exception.Message)"
  exit 1
}

$Ver = "0.0.22"

if ($env:NURO_DEBUG -eq '1') {
  echo "debug nuro v$Ver"
}

#================================================================================
# ref / base
#================================================================================
$Ref  = $env:NURO_REF
function Normalize-Ref([string]$r) {
  if (-not $r) { return 'main' }
  if ($r -like 'refs/heads/*') { return $r.Substring(11) }
  if ($r -like 'refs/tags/*')  { return $r.Substring(10) }
  return $r
}
$NormRef = Normalize-Ref $Ref
$Base = "https://raw.githubusercontent.com/mr-certain-a/nuro/$NormRef"
$Owner = "mr-certain-a"
$Repo  = "nuro"

#================================================================================
# === Bucket registry (local JSON) ===
#================================================================================
$NURO_HOME   = Join-Path ($env:USERPROFILE ?? $HOME) ".nuro"
$NURO_CONFIG = Join-Path $NURO_HOME "config"
$BUCKET_FILE = Join-Path $NURO_CONFIG "buckets.json"

function Get-NuroDefaultRegistry {
  $norm = Normalize-Ref $env:NURO_REF
  [pscustomobject]@{
    buckets = @(
      [pscustomobject]@{
        name     = 'official'
        uri      = "github::mr-certain-a/nuro@$norm"
        priority = 100
        trusted  = $true
      }
    )
    pins = [pscustomobject]@{}
  }
}

function Initialize-NuroRegistry {
  if (-not (Test-Path $NURO_HOME))   { New-Item -ItemType Directory -Path $NURO_HOME   | Out-Null }
  if (-not (Test-Path $NURO_CONFIG)) { New-Item -ItemType Directory -Path $NURO_CONFIG | Out-Null }
  if (-not (Test-Path $BUCKET_FILE)) {
    $def = Get-NuroDefaultRegistry
    ($def | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 $BUCKET_FILE
  }
}

# pins/buckets の型ブレを正規化
function Normalize-NuroRegistry([object]$reg) {
  if ($null -eq $reg) { return Get-NuroDefaultRegistry }

  # buckets
  if ($null -eq $reg.buckets) {
    $reg | Add-Member -NotePropertyName buckets -NotePropertyValue @() -Force
  } elseif ($reg.buckets -is [System.Array] -and $reg.buckets.Count -gt 0 -and $reg.buckets[0] -is [string]) {
    # 旧形式: 文字列配列 → オブジェクト配列へ変換
    $reg.buckets = @(
      foreach ($s in $reg.buckets) {
        [pscustomobject]@{ name = ($s -replace '[:/\\]','_'); uri = $s; priority = 50; trusted = $false }
      }
    )
  }

  # pins
  if ($null -eq $reg.pins) {
    $reg | Add-Member -NotePropertyName pins -NotePropertyValue ([pscustomobject]@{}) -Force
  } elseif ($reg.pins -is [hashtable]) {
    # Hashtable → PSCustomObject に寄せる
    $o = [pscustomobject]@{}
    foreach ($k in $reg.pins.Keys) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $reg.pins[$k] -Force }
    $reg.pins = $o
  } elseif ($reg.pins -isnot [pscustomobject]) {
    # 想定外型（string/array等）は空オブジェクトに
    $reg.pins = [pscustomobject]@{}
  }

  return $reg
}

function Save-NuroRegistry([object]$obj) {
  $obj = Normalize-NuroRegistry $obj
  ($obj | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 $BUCKET_FILE
}

function Load-NuroRegistry {
  Initialize-NuroRegistry
  try {
    $raw = Get-Content $BUCKET_FILE -Raw -Encoding UTF8

    if ($env:NURO_DEBUG -eq '1') {
      Write-Host "[nuro:Load] file=$BUCKET_FILE"
      Write-Host "[nuro:Load] raw.length=$($raw.Length)"
    }

    if ([string]::IsNullOrWhiteSpace($raw)) { throw "empty json" }

    $reg = $raw | ConvertFrom-Json
    if ($null -eq $reg) { throw "ConvertFrom-Json returned null" }

    $reg = Normalize-NuroRegistry $reg

    if ($env:NURO_DEBUG -eq '1') {
      Write-Host "[nuro:Load] buckets.count=$($reg.buckets.Count)"
      Write-Host "[nuro:Load] pins.type=$($reg.pins.GetType().FullName)"
      $__pinNames = Get-PinNames $reg.pins
      Write-Host "[nuro:Load] pins.keys=" ($__pinNames -join ', ')
    }

    return $reg
  }
  catch {
    if ($env:NURO_DEBUG -eq '1') {
      Write-Warning "[nuro:Load] fallback: $($_.Exception.Message)"
    }
    $def = Get-NuroDefaultRegistry
    Save-NuroRegistry $def
    return $def
  }
}


#================================================================================
# uri 形式:
#  - github::owner/repo@<ref>   （ref=refs/heads/.. / refs/tags/.. / <sha>）
#  - raw::https://host/base     （<base>/<cmd>.ps1 を取りに行く）
#  - local::<absolute_path>     （<path>\<cmd>.ps1 を読む）
#  - それ以外（絶対/相対パス）は local 扱いに自動補正
#================================================================================
function Parse-BucketUri([string]$uri) {
  if ($uri -like 'github::*') {
    $spec = $uri.Substring(8) # owner/repo@ref
    $parts = $spec -split '@', 2
    $repo  = $parts[0]
    $ref   = if ($parts.Count -gt 1 -and $parts[1]) { $parts[1] } else { 'main' }
    if ($ref -like 'refs/heads/*') { $ref = $ref.Substring(11) }
    elseif ($ref -like 'refs/tags/*') { $ref = $ref.Substring(10) }
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

#================================================================================
# --- Args配列を名前付き引数ハッシュに変換 ---
#================================================================================
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
  # 位置引数マッピング: 関数の ParameterMetadata から Position>=0 を昇順で採用
  $posOrder = @()
  if ($meta.ContainsKey('Sub')) { $posOrder += 'Sub' }
  foreach ($n in @('Url','OutFile','Sha256','TimeoutSec')) { if ($meta.ContainsKey($n)) { $posOrder += $n } }
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

#================================================================================
# Debug-ShowPins
#================================================================================
function Get-PinNames($pins) {
  if ($null -eq $pins) { return @() }
  if ($pins -is [hashtable]) { return @($pins.Keys) }
  try {
    $members = $pins | Get-Member -MemberType NoteProperty -ErrorAction Stop
    return @($members | Select-Object -ExpandProperty Name)
  } catch {
    return @()
  }
}

function Debug-ShowPins {
    param($reg)

    if ($env:NURO_DEBUG -ne '1') { return }

    if (-not $reg) { Write-Host "[pins] reg is null"; return }
    if (-not $reg.pins) { Write-Host "[pins] reg.pins is null"; return }

    $pinNames = Get-PinNames $reg.pins
    Write-Host "[pins] keys:" ($pinNames -join ', ')

    if ($reg.pins -is [hashtable]) {
      foreach ($k in $pinNames) { Write-Host ("  {0} = {1}" -f $k, $reg.pins[$k]) }
    } else {
      foreach ($p in ($reg.pins.PSObject.Properties | Where-Object { $_ -is [System.Management.Automation.PSNoteProperty] })) {
        Write-Host ("  {0} = {1}" -f $p.Name, $p.Value)
      }
    }

    # JSONで俯瞰したいとき
    Write-Host "[pins json]"
    $reg.pins | ConvertTo-Json -Depth 3
}

#================================================================================
# Invoke-RemoteCmd
#================================================================================
function Invoke-RemoteCmd {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [string[]]$Args
  )

  if ($null -eq $Args) { $Args = @() } else { $Args = @($Args) }

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

  Debug-ShowPins $reg

  $pinNames = Get-PinNames $reg.pins

  # pin 優先
  if (-not $bucketHint -and ($pinNames -contains $cmd)) {
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
  $msg = "nuro: command '$cmd' not found in any bucket."
  if ($errors.Count -gt 0 -and $env:NURO_DEBUG -eq '1') {
    Write-Host ($msg + "`n" + ($errors -join "`n"))
  } else {
    Write-Host $msg
  }
  return
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
