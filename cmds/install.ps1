# Auto-generated nuro command (inline original content)

function NuroUsage_Install {
  @"
Usage:
  nuro install <Package> [<Version>]

Notes:
  PRIVATE_PYPI_REPO 環境変数にホイールを保管したディレクトリを設定してください。
"@
}

function NuroCmd_Install {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Package,
    [string]$Version
  )

  Set-StrictMode -Version 2
  $ErrorActionPreference = 'Stop'

  # 1. レポジトリ確認
  if ([string]::IsNullOrWhiteSpace($env:PRIVATE_PYPI_REPO)) {
    $repo = $null
  } else {
    $repo = $env:PRIVATE_PYPI_REPO
  }
  if (-not $repo) {
    Write-Host "PRIVATE_PYPI_REPO が設定されていません。以下の例を参考に設定してください:" -ForegroundColor Yellow
    Write-Host '  $env:PRIVATE_PYPI_REPO="\\nas\pypi-tools"   # NAS の例'
    Write-Host '  $env:PRIVATE_PYPI_REPO="C:\\pypi-repo"       # ローカルパスの例'
    Write-Host '  $env:PRIVATE_PYPI_REPO="https://pypi.org/simple"  # 公式PyPI の例'
    exit 1
  }

  if (-not (Test-Path -Path $repo)) {
    Write-Host "指定された PRIVATE_PYPI_REPO が見つかりません: $repo" -ForegroundColor Red
    exit 1
  }

  Write-Host "Using repo: $repo"

  # 2. パッケージ候補取得
  $pattern = "$Package-*.whl"
  try {
    $files = Get-ChildItem -Path $repo -Filter $pattern | Sort-Object -Property Name
  } catch {
    Write-Host "パッケージ一覧の取得に失敗しました: $_" -ForegroundColor Red
    exit 1
  }

  if (-not $files -or $files.Count -eq 0) {
    Write-Host "パッケージ $Package が見つかりませんでした。" -ForegroundColor Yellow
    exit 1
  }

  # 3. バージョン選択
  if ($Version) {
    $matchPattern = "$Package-$Version"
    $packageFile = $files | Where-Object { $_.Name -like "$matchPattern*" } | Select-Object -First 1
    if (-not $packageFile) {
      $latest = ($files | Select-Object -Last 1).Name
      Write-Host "パッケージ $Package は見つかりましたが、バージョン $Version がありません。最新は $latest です。" -ForegroundColor Yellow
      exit 1
    }
  } else {
    $packageFile = $files | Select-Object -Last 1
  }

  Write-Host "Installing package: $($packageFile.Name)"

  # 4. pip 実行
  $fullPath = $packageFile.FullName
  $commandsToTry = @(
    @{ Label = 'py -m pip'; Args = @('py', '-m', 'pip', 'install', $fullPath) },
    @{ Label = 'python -m pip'; Args = @('python', '-m', 'pip', 'install', $fullPath) },
    @{ Label = 'pip'; Args = @('pip', 'install', $fullPath) }
  )

  foreach ($entry in $commandsToTry) {
    $exe = $entry.Args[0]
    $cmdInfo = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $cmdInfo) { continue }

    $arguments = $entry.Args[1..($entry.Args.Length - 1)]
    Write-Host "  -> $exe $($arguments -join ' ')"
    try {
      & $exe @arguments
    } catch {
      Write-Host "  $exe の実行に失敗しました: $_" -ForegroundColor Yellow
      continue
    }
    if ($LASTEXITCODE -eq 0) {
      Write-Host "インストールが完了しました。" -ForegroundColor Green
      exit 0
    }
    Write-Host "  $exe の終了コード: $LASTEXITCODE" -ForegroundColor Yellow
  }

  Write-Host "pip / python コマンドが見つからないか、インストールに失敗しました。" -ForegroundColor Red
  exit 1
}
