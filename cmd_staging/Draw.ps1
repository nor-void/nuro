# Auto-generated wrapper for nuro (do not edit manually)
# Source: S:\repos\nuro\limbo\Show-AdminTools.ps1

function NuroUsage_Draw {
@"
Usage:
  Draw 

Notes:
  - 引数はそのまま透過されます（@args）。
"@
}

function NuroCmd_Draw {
    param([string[]]`$args)
    try {
        # function passthrough: dot-source original then invoke the function
        . "S:\repos\nuro\limbo\Show-AdminTools.ps1"
        & Draw @args
    } catch {
        Write-Error "`$($cmdFn): $($file.Name): $($_.Exception.Message)"
        throw
    }
}