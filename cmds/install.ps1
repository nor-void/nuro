# Auto-generated nuro command (inline original content)

function NuroUsage_Install {
  'nuro install <Package> [<Version>] # PRIVATE_PYPI_REPO 環境変数にホイールを保管したディレクトリを設定してください。'
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
    @{ Label = 'py -m pip';      Args = @('py',      '-m', 'pip', 'install', $fullPath) },
    @{ Label = 'python -m pip';  Args = @('python',  '-m', 'pip', 'install', $fullPath) },
    @{ Label = 'pip';            Args = @('pip',            'install', $fullPath) }
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
      # ===== 成功時: ~/.nuro/venv を前提に汎用 shim を作成 =====
      $NURO_HOME = Join-Path ($env:USERPROFILE ?? $HOME) ".nuro"
      $VENV_PY   = Join-Path $NURO_HOME "venv\Scripts\python.exe"
      $BIN_DIR   = Join-Path $NURO_HOME "bin"
      if (-not (Test-Path $VENV_PY)) {
        Write-Host "WARNING: venv python not found: $VENV_PY (shim not created)" -ForegroundColor Yellow
        Write-Host "インストールが完了しました。" -ForegroundColor Green
        exit 0
      }

      try {
        New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null

        # --- Python helper: console_scripts と top_level package を取得 ---
        $pyHelper = @'
import sys, json
try:
    import importlib.metadata as m
except Exception:
    import importlib_metadata as m  # backport
name = sys.argv[1]
out = {"top": [], "eps": []}
try:
    dist = m.distribution(name)
    try:
        txt = dist.read_text("top_level.txt") or ""
        out["top"] = [ln.strip() for ln in txt.splitlines() if ln.strip()]
    except Exception:
        pass
    try:
        for ep in getattr(dist, "entry_points", []):
            if getattr(ep, "group", "") == "console_scripts":
                out["eps"].append({"name": ep.name, "value": ep.value})
    except Exception:
        pass
except Exception:
    pass
print(json.dumps(out))
'@

        $tmpPy = [IO.Path]::Combine([IO.Path]::GetTempPath(), "nu_meta_{0}.py" -f ([Guid]::NewGuid().ToString("N")))
        Set-Content -Path $tmpPy -Value $pyHelper -Encoding Ascii
        $json = & $VENV_PY $tmpPy $Package
        Remove-Item $tmpPy -ErrorAction SilentlyContinue

        $module = $null
        $shimBase = $Package
        try {
          $meta = $json | ConvertFrom-Json
          if ($meta.eps -and $meta.eps.Count -gt 0) {
            $ep = $meta.eps | Select-Object -First 1
            $shimBase = $ep.name
            $module = ($ep.value -split ":",2)[0]
          }
          if (-not $module -and $meta.top -and $meta.top.Count -gt 0) {
            $module = $meta.top[0]
          }
        } catch { }

        if (-not $module) { $module = $Package }  # 最終フォールバック

        $SHIM = Join-Path $BIN_DIR ("{0}.shim" -f $shimBase)
        $shimContent = "@echo off`r`n""$VENV_PY"" -m $module %*"
        Set-Content -Path $SHIM -Value $shimContent -Encoding Ascii

        # PATH 追加（User スコープ）
        $uPath = [Environment]::GetEnvironmentVariable('Path','User')
        if ($uPath -notmatch [Regex]::Escape($BIN_DIR)) {
          [Environment]::SetEnvironmentVariable('Path', ($uPath.TrimEnd(';') + ';' + $BIN_DIR), 'User')
        }
        $env:Path = ($env:Path.TrimEnd(';') + ';' + $BIN_DIR)

        Write-Host ("Shim created: {0}" -f $SHIM)
        Write-Host ("Run: {0}.shim --help" -f $shimBase)
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
