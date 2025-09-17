# Auto-generated nuro command (inline original content)

function NuroUsage_PortOpen {
  @"
Usage:
  port-open <PortNo>

Notes:
  - 引数はそのまま透過されます（@args）。
  "@
}

function NuroCmd_PortOpen {
  [CmdletBinding()]
  param(
      [Parameter(Mandatory=$true)]$PortNo
  )

  if (-not(Get-NetFirewallRule | where Name -eq PowerShellRemoting-In))
  {
      New-NetFirewallRule `
          -Name PowerShellRemoting-In `
          -DisplayName PowerShellRemoting-In `
          -Description "Windows PowerShell Remoting required to open for public connection. not for private network." `
          -Group "Windows Remote Management" `
          -Enabled True `
          -Profile Any `
          -Direction Inbound `
          -Action Allow `
          -EdgeTraversalPolicy Block `
          -LooseSourceMapping $False `
          -LocalOnlyMapping $False `
          -OverrideBlockRules $False `
          -Program Any `
          -LocalAddress Any `
          -RemoteAddress Any `
          -Protocol TCP `
          -LocalPort $PortNo `
          -RemotePort Any `
          -LocalUser Any `
          -RemoteUser Any 
  }
  else
  {
          Write-Verbose "Windows PowerShell Remoting port TCP $PortNo was alredy opend. Show Rule"
          Get-NetFirewallPortFilter -Protocol TCP | where Localport -eq $PortNo
  }
}

