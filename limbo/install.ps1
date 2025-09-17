# install.ps1
param(
    [Parameter(Mandatory=$true)]
    [string]$Package,
    [string]$Version
)

# 1. レポジトリの場所を決定
$repo = $env:PRIVATE_PYPI_REPO
if (-not $repo -or $repo -eq "") {
    Write-Host "PRIVATE_PYPI_REPO が設定されていません。以下のように設定してください:"
    Write-Host '  $env:PRIVATE_PYPI_REPO="\\nas\pypi-tools"   # NASの例'
    Write-Host '  $env:PRIVATE_PYPI_REPO="c:/pypi-repo"       # ローカルパスの例'
    Write-Host '  $env:PRIVATE_PYPI_REPO="https://pypi.org/simple"  # 公式PyPIの例'
    exit 1
}

Write-Host "Using repo: $repo"

# 2. パッケージ候補の取得
$pattern = "$Package-*.whl"
$files = Get-ChildItem -Path $repo -Filter $pattern | Sort-Object Name

if (-not $files) {
    Write-Host "パッケージ $Package が見つかりませんでした。"
    exit 1
}

# 3. バージョン選択
if ($Version) {
    $packageFile = $files | Where-Object { $_.Name -match "$Package-$Version" }
    if (-not $packageFile) {
        $latest = ($files | Select-Object -Last 1).Name
        Write-Host "パッケージ $Package は見つかりましたが、バージョン $Version がありません。最新のバージョンは $latest です。"
        exit 1
    }
} else {
    $packageFile = $files | Select-Object -Last 1
}

Write-Host "Installing package: $($packageFile.Name)"

# 4. インストール実行（仮想環境を前提）
pip install "$($packageFile.FullName)"
