# Auto-generated nuro command (inline original content)

function NuroUsage_Install {
  'nuro install <Package> [<Version>] [-ModuleTail cli] [-ShimName <name>] # PRIVATE_PYPI_REPO を設定しておく'
}

function NuroCmd_Install {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Package,
    [string]$Version,
    [string]$ModuleTail = 'cli',     # 例: aixTool.cli の "cli" 部分
    [string]$ShimName                # 省略時は $Package.cmd
  )

  Set-StrictMode -Version 2
  $ErrorActionPreference = 'Stop'

  # 1. レポジトリ確認
 if ([string]::IsNullOrWhiteSpace($env:PRIVATE_PYPI_REPO)) {
    $repo = $null
  } else {
    $repo = $env:PRIVATE_PYPI_REPO
  }if (-not $repo) {
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
  try { $files = Get-ChildItem -Path $repo -Filter $pattern | Sort-Object -Property Name }
  catch {
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

  # 4. 仮想環境を用意してインストール
  $fullPath = $packageFile.FullName

  $currentDir = (Get-Location).Path
  $venvRoot = Join-Path $currentDir $Package

  $isWindows = [Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
  $scriptsDirName = if ($isWindows) { 'Scripts' } else { 'bin' }
  $pythonExeName = if ($isWindows) { 'python.exe' } else { 'python' }
  $entryExeName = if ($isWindows) { "{0}.exe" -f $Package } else { $Package }
  $venvScriptsDir = Join-Path $venvRoot $scriptsDirName
  $venvPython = Join-Path $venvScriptsDir $pythonExeName
  $venvEntry = Join-Path $venvScriptsDir $entryExeName

  if (-not (Test-Path $venvPython)) {
    $pythonBootstrap = $null
    foreach ($candidate in @('py','python3','python')) {
      if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $pythonBootstrap = $candidate
        break
      }
    }

    if (-not $pythonBootstrap) {
      Write-Host "python / py コマンドが見つかりません。仮想環境を作成できませんでした。" -ForegroundColor Red
      exit 1
    }

    $venvArgs = @('-m','venv',$venvRoot)
    Write-Host "Creating virtual environment: $venvRoot"
    try {
      & $pythonBootstrap @venvArgs
    } catch {
      Write-Host "仮想環境の作成に失敗しました: $_" -ForegroundColor Red
      exit 1
    }

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPython)) {
      Write-Host "仮想環境の作成に失敗しました (exit code $LASTEXITCODE)。" -ForegroundColor Red
      exit 1
    }
  } else {
    Write-Host "Reusing existing virtual environment: $venvRoot"
  }

  $pipArgs = @('-m','pip','install',$fullPath)
  Write-Host "  -> $venvPython -m pip install $fullPath"
  try {
    & $venvPython @pipArgs
  } catch {
    Write-Host "パッケージのインストールに失敗しました: $_" -ForegroundColor Red
    exit 1
  }

  if ($LASTEXITCODE -ne 0) {
    Write-Host "pip install の終了コード: $LASTEXITCODE" -ForegroundColor Red
    exit 1
  }

  # ===== 成功: シム作成（~/.nuro/bin に配置） =====
  # ユーザーディレクトリを段階的に判定（PowerShell 5 互換対応）
  $userRoot = $env:USERPROFILE
  if ([string]::IsNullOrWhiteSpace($userRoot)) { $userRoot = $HOME }
  if ([string]::IsNullOrWhiteSpace($userRoot)) { $userRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) }
  if ([string]::IsNullOrWhiteSpace($userRoot)) {
    Write-Host "WARNING: ユーザーディレクトリを特定できません。shim をカレントディレクトリに作成します。" -ForegroundColor Yellow
    $userRoot = $currentDir
  }
  $NURO_HOME = Join-Path $userRoot ".nuro"
  $BIN_DIR   = Join-Path $NURO_HOME "bin"

  try {
    New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null
  } catch {
    Write-Host "WARNING: shim 用ディレクトリの作成に失敗しました: $_" -ForegroundColor Yellow
  }

  if (-not (Test-Path $BIN_DIR)) {
    Write-Host "WARNING: shim 用ディレクトリにアクセスできないため、シムを作成できませんでした。" -ForegroundColor Yellow
    Write-Host "インストールが完了しました。" -ForegroundColor Green
    exit 0
  }

  # モジュールは "<Package>.<ModuleTail>"（ModuleTailが空なら Package 単体）
  $Module = if ([string]::IsNullOrWhiteSpace($ModuleTail)) { $Package } else { "$Package.$ModuleTail" }

  # シム名（既定は <Package>.cmd）
  if ([string]::IsNullOrWhiteSpace($ShimName)) { $ShimName = $Package }
  $SHIM = Join-Path $BIN_DIR ("{0}.cmd" -f $ShimName)

  if (-not (Test-Path $venvEntry)) {
    Write-Host "WARNING: $Package のエントリーポイント ($venvEntry) が見つかりません。python -m $Module を使用します。" -ForegroundColor Yellow
    $shimCommand = '"{0}" -m {1} %*' -f $venvPython, $Module
  } else {
    $shimCommand = '"{0}" %*' -f $venvEntry
  }

  $shimContent = "@echo off`r`n$shimCommand"
  try {
    Set-Content -Path $SHIM -Value $shimContent -Encoding Ascii
    Write-Host "Shim created: $SHIM"
  } catch {
    Write-Host "WARNING: shim creation failed: $_" -ForegroundColor Yellow
  }

  Write-Host "インストールが完了しました。" -ForegroundColor Green
  Write-Host "Run: $ShimName.cmd --help"
  exit 0
}

