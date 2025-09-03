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
  param([Parameter(Mandatory=$true)][string]$Name,[string[]]$Args)
  $safe = $Name -replace '[^a-zA-Z0-9_-]', ''
  if ($safe -ne $Name -or [string]::IsNullOrWhiteSpace($safe)) { throw "nuro: invalid command name '$Name'" }
  $url = "$Base/cmds/$safe.ps1"
  $code = Invoke-RestMethod -Uri $url -UseBasicParsing
  $sb   = [scriptblock]::Create($code)
  & $sb   # NuroUsage_*, NuroCmd_* を定義してもらう
  $main  = "NuroCmd_$safe"
  $usage = "NuroUsage_$safe"

  $isHelp = $false; foreach($h in @('-h','--help','/?')){ if($Args -contains $h){ $isHelp=$true; break } }

  if($isHelp){
    if(Get-Command $usage -ErrorAction SilentlyContinue){ & $usage } else { "nuro $safe - no usage available" }
    return
  }
  if(Get-Command $main -ErrorAction SilentlyContinue){ & $main @Args } else { & $sb @Args }
}

function Get-AllCommandsUsage {
  $apiUrl = "https://api.github.com/repos/$Owner/$Repo/contents/cmds"
  try { $files = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing } catch { return @() }
  $lines = @()
  foreach($f in $files){
    if($f.name -like '*.ps1'){
      $name = [IO.Path]::GetFileNameWithoutExtension($f.name)
      try {
        $line = Invoke-RemoteCmd -Name $name -Args @('--help')
        if($line){ $lines += "  $line" }
      } catch {
        $lines += "  nuro $name  (usage unavailable)"
      }
    }
  }
  return $lines
}

function nuro {
  if ($args.Count -eq 0) {
    Write-Host "nuro — minimal runner v0.2`n"
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
