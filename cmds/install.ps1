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
    [string]$ShimName                # 省略時は $Package.shim
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

  # 4. pip 実行
  $fullPath = $packageFile.FullName
  $commandsToTry = @(
    @{ Label='py -m pip';     Args=@('py','-m','pip','install',$fullPath) },
    @{ Label='python -m pip'; Args=@('python','-m','pip','install',$fullPath) },
    @{ Label='pip';           Args=@('pip','install',$fullPath) }
  )

  foreach ($entry in $commandsToTry) {
    $exe = $entry.Args[0]
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }

    $arguments = $entry.Args[1..($entry.Args.Length - 1)]
    Write-Host "  -> $exe $($arguments -join ' ')"
    try { & $exe @arguments } catch { Write-Host "  $exe の実行に失敗: $_" -ForegroundColor Yellow; continue }

    if ($LASTEXITCODE -eq 0) {
      # ===== 成功: 汎用 shim 作成（~/.nuro/venv 固定） =====
      # ユーザーディレクトリを段階的に判定（PowerShell 5 互換対応）
      $userRoot = $env:USERPROFILE
      if ([string]::IsNullOrWhiteSpace($userRoot)) { $userRoot = $HOME }
      if ([string]::IsNullOrWhiteSpace($userRoot)) { $userRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) }
      if ([string]::IsNullOrWhiteSpace($userRoot)) {
        Write-Host "WARNING: ユーザーディレクトリを特定できません。shim をカレントディレクトリに作成します。" -ForegroundColor Yellow
        $userRoot = (Get-Location).Path
      }
      $NURO_HOME = Join-Path $userRoot ".nuro"
      $VENV_PY   = Join-Path $NURO_HOME "venv\Scripts\$Package.exe"
      $BIN_DIR   = Join-Path $NURO_HOME "bin"
      if (-not (Test-Path $VENV_PY)) {
        Write-Host "WARNING: venv python not found: $VENV_PY (shim not created)" -ForegroundColor Yellow
        Write-Host "インストールが完了しました。" -ForegroundColor Green
        exit 0
      }

      try {
        New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null

        # モジュールは "<Package>.<ModuleTail>"（ModuleTailが空なら Package 単体）
        $Module = if ([string]::IsNullOrWhiteSpace($ModuleTail)) { $Package } else { "$Package.$ModuleTail" }

        # シム名（既定は <Package>.cmd）
        if ([string]::IsNullOrWhiteSpace($ShimName)) { $ShimName = $Package }
        $SHIM = Join-Path $BIN_DIR ("{0}.cmd" -f $ShimName)

        $shimContent = "@echo off`r`n""$VENV_PY"" %*"
        Set-Content -Path $SHIM -Value $shimContent -Encoding Ascii

        Write-Host "Shim created: $SHIM"
        Write-Host "Run: $ShimName.shim --help"
      } catch {
        Write-Host "WARNING: shim creation failed: $_" -ForegroundColor Yellow
      }

      Write-Host "インストールが完了しました。" -ForegroundColor Green
      exit 0
    }

    Write-Host "  $exe の終了コード: $LASTEXITCODE" -ForegroundColor Yellow
  }

  Write-Host "pip / python コマンドが見つからないか、インストールに失敗しました。" -ForegroundColor Red
  exit 1
}
