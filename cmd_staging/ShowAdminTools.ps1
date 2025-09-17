# Auto-generated wrapper for nuro (do not edit manually)
# Source: S:\repos\nuro\limbo\Show-AdminTools.ps1

function NuroUsage_ShowAdminTools {
@"
Usage:
  Show-AdminTools 

Notes:
  - 引数はそのまま透過されます（@args）。
"@
}

function NuroCmd_ShowAdminTools {
    param([string[]]`$args)
    try {
        # function passthrough: dot-source original then invoke the function
        . "S:\repos\nuro\limbo\Show-AdminTools.ps1"
        & Show-AdminTools @args
    } catch {
        Write-Error "`$($cmdFn): $($file.Name): $($_.Exception.Message)"
        throw
    }
}