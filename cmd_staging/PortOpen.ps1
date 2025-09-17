# Auto-generated wrapper for nuro (do not edit manually)
# Source: S:\repos\nuro\limbo\port-open.ps1

function NuroUsage_PortOpen {
@"
Usage:
  port-open <PortNo>

Notes:
  - 引数はそのまま透過されます（@args）。
"@
}

function NuroCmd_PortOpen {
    param([string[]]`$args)
    try {
        # script passthrough: invoke the original ps1 with user args
        & "S:\repos\nuro\limbo\port-open.ps1" @args
    } catch {
        Write-Error "`$($cmdFn): $($file.Name): $($_.Exception.Message)"
        throw
    }
}