function NuroUsage_bucket {
  'nuro bucket <add|ls|rm|pin|unpin> [...]'
}

function NuroCmd_bucket {
  [CmdletBinding()]
  param(
    [Parameter(Position=0)][ValidateSet('add','ls','rm','pin','unpin')][string]$Sub = 'ls',
    [Parameter(Position=1, ValueFromRemainingArguments=$true)][string[]]$Rest
  )
  Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'

  # === 同じレジストリ/ヘルパ（本体側と一致させる） ===
  $NURO_HOME   = Join-Path ($env:USERPROFILE ?? $HOME) ".nuro"
  $NURO_CONFIG = Join-Path $NURO_HOME "config"
  $APP_CONFIG  = Join-Path $NURO_CONFIG "config.json"
  function Ensure-NuroDirs { if (-not (Test-Path $NURO_CONFIG)) { New-Item -ItemType Directory -Path $NURO_CONFIG | Out-Null } }
  function Get-DefaultAppConfig { [pscustomobject]@{ official_bucket_base = 'https://raw.githubusercontent.com/nor-void/nuro' } }
  function Load-NuroAppConfig {
    Ensure-NuroDirs
    if (-not (Test-Path $APP_CONFIG)) { $def = Get-DefaultAppConfig; ($def | ConvertTo-Json -Depth 4) | Set-Content -Encoding UTF8 $APP_CONFIG; return $def }
    try { $raw = Get-Content $APP_CONFIG -Raw -Encoding UTF8; $data = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }; if (-not $data.official_bucket_base) { $data | Add-Member -NotePropertyName official_bucket_base -NotePropertyValue (Get-DefaultAppConfig).official_bucket_base -Force }; return $data } catch { $def = Get-DefaultAppConfig; ($def | ConvertTo-Json -Depth 4) | Set-Content -Encoding UTF8 $APP_CONFIG; return $def }
  }
  $BUCKET_FILE = Join-Path $NURO_CONFIG "buckets.json"
  function Initialize-NuroRegistry {
    Ensure-NuroDirs
    if (-not (Test-Path $BUCKET_FILE)) {
      $cfg = Load-NuroAppConfig; $base = $cfg.official_bucket_base.TrimEnd('/')
      $obj = @{ buckets = @(@{ name='official'; uri=("raw::{0}" -f $base); priority=100; trusted=$true }); pins = @{} }
      $obj | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $BUCKET_FILE
    }
  }
  function Load-NuroRegistry { Initialize-NuroRegistry; Get-Content $BUCKET_FILE -Raw | ConvertFrom-Json }
  function Save-NuroRegistry($obj) { ($obj | ConvertTo-Json -Depth 5) | Set-Content -Encoding UTF8 $BUCKET_FILE }

  switch ($Sub) {
    'add' {
      if ($Rest.Count -lt 1) { throw "usage: nuro bucket add <path|github::owner/repo@ref|raw::https://base> [name] [priority]" }
      $spec = $Rest[0]
      $name = if ($Rest.Count -ge 2) { $Rest[1] } else {
        # デフォ名: ローカルならフォルダ名/URLならホスト名ベース
        if ($spec -match '^[A-Za-z]:\\|^/|^\\|^\.' ) { Split-Path $spec -Leaf }
        elseif ($spec -like 'local::*') { Split-Path ($spec.Substring(7)) -Leaf }
        elseif ($spec -like 'raw::*')   { ([Uri]($spec.Substring(5))).Host }
        elseif ($spec -like 'github::*'){ ($spec.Substring(8) -split '@',2)[0].Replace('/','_') }
        else { $spec.Replace('::','_').Replace(':','_') }
      }
      $prio = if ($Rest.Count -ge 3) { [int]$Rest[2] } else { 50 }

      # ローカルパスが素で来たら local:: を付ける
      if ($spec -notlike 'github::*' -and $spec -notlike 'raw::*' -and $spec -notlike 'local::*') {
        if ($spec -match '^[A-Za-z]:\\|^/|^\\|^\.' ) { $spec = "local::$spec" }
        elseif ($spec -like 'http*://*') { $spec = "raw::$spec" }
      }

      $reg = Load-NuroRegistry
      if ($reg.buckets | Where-Object { $_.name -eq $name }) { throw "bucket '$name' already exists" }
      $reg.buckets += @{ name=$name; uri=$spec; priority=$prio; trusted=$false }
      Save-NuroRegistry $reg
      "added bucket: $name -> $spec (priority=$prio)"
    }
    'ls' {
      $reg = Load-NuroRegistry
      $reg.buckets | Sort-Object -Property @{Expression='priority';Descending=$true} |
        ForEach-Object { "{0,-12} prio={1,3}  {2}" -f $_.name, $_.priority, $_.uri }
    }
    'rm' {
      if ($Rest.Count -lt 1) { throw "usage: nuro bucket rm <name>" }
      $name = $Rest[0]
      $reg = Load-NuroRegistry
      $before = $reg.buckets.Count
      $reg.buckets = @($reg.buckets | Where-Object { $_.name -ne $name })
      if ($before -eq $reg.buckets.Count) { throw "bucket '$name' not found" }
      foreach ($k in @($reg.pins.PSObject.Properties.Name)) { if ($reg.pins.$k -eq $name) { $reg.pins.PSObject.Properties.Remove($k) } }
      Save-NuroRegistry $reg
      "removed bucket: $name"
    }
    'pin' {
      if ($Rest.Count -lt 2) { throw "usage: nuro bucket pin <command> <bucketName>" }
      $cmd = $Rest[0]; $b = $Rest[1]
      $reg = Load-NuroRegistry
      if (-not ($reg.buckets | Where-Object { $_.name -eq $b })) { throw "bucket '$b' not found" }
      $reg.pins | Add-Member -NotePropertyName $cmd -NotePropertyValue $b -Force
      Save-NuroRegistry $reg
      "pinned: $cmd -> $b"
    }
    'unpin' {
      if ($Rest.Count -lt 1) { throw "usage: nuro bucket unpin <command>" }
      $cmd = $Rest[0]
      $reg = Load-NuroRegistry
      if ($reg.pins.PSObject.Properties.Name -contains $cmd) {
        $reg.pins.PSObject.Properties.Remove($cmd); Save-NuroRegistry $reg; "unpinned: $cmd"
      } else { "no pin for: $cmd" }
    }
  }
}

