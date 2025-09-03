echo "nuro v0.1"
function nuro {
  if ($args.Count -eq 0) {
@"
nuro — minimal runner

USAGE:
  nuro get -Url <https://...> [-OutFile <path>] [-Sha256 <hex>] [-Force] [-TimeoutSec <int>]

EXAMPLE:
  nuro get -Url https://example.com/file.ps1 -OutFile `$HOME\.nuro\pkgs\file.ps1
"@ | Write-Host
    return
  }

  $cmd  = $args[0]
  $rest = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }

  switch ($cmd) {
    'get' {
      $url = "$Base/cmds/get.ps1"
      $code = Invoke-RestMethod -Uri $url -UseBasicParsing
      $sb   = [scriptblock]::Create($code)
      & $sb @rest    # ← 名前付き引数もそのまま子スクリプトへ渡る
    }
    default {
      Write-Host "nuro: unknown command '$cmd'"
    }
  }
}
