# Auto-generated wrapper for nuro (do not edit manually)
# Source: S:\repos\nuro\limbo\pgres2d.ps1

function NuroUsage_Pgres2d {
@"
Usage:
  pgres2d <Arg1>

Notes:
  - 引数はそのまま透過されます（@args）。
"@
}

function NuroCmd_Pgres2d {
    param([string[]]`$args)
    try {
        # script passthrough: invoke the original ps1 with user args
        & "S:\repos\nuro\limbo\pgres2d.ps1" @args
    } catch {
        Write-Error "`$($cmdFn): $($file.Name): $($_.Exception.Message)"
        throw
    }
}