# cmds/time.ps1
function NuroUsage_time {
  'nuro time [-Utc] [-Format <fmt>]'
}

function NuroCmd_time {
  [CmdletBinding()]
  param(
    [string]$Format = 'yyyy-MM-ddTHH:mm:ss.fffK',
    [switch]$Utc
  )
  $dt = if ($Utc) { [DateTime]::UtcNow } else { Get-Date }
  $dt.ToString($Format)
}