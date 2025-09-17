param(
    [Parameter(Mandatory = $false)]
    [string]$Commit = 'f95143825801905b16baa3335d553b07d41f39c6'
)

if ([string]::IsNullOrWhiteSpace($Commit)) {
    Write-Error 'Commit hash is required.'
    exit 1
}

$home = $env:USERPROFILE
if (-not $home) {
    Write-Error 'USERPROFILE env var is not set. Cannot resolve Windows user home.'
    exit 1
}

$configDir = Join-Path $home '.nuro'
$configDir = Join-Path $configDir 'config'
$configPath = Join-Path $configDir 'buckets.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Error "buckets.json not found: $configPath"
    exit 1
}

try {
    $jsonText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $data = $jsonText | ConvertFrom-Json
} catch {
    Write-Error "Failed to read or parse buckets.json: $($_.Exception.Message)"
    exit 1
}

if (-not $data.buckets) {
    Write-Error 'buckets array missing in buckets.json.'
    exit 1
}

$official = $data.buckets | Where-Object { $_.name -eq 'official' } | Select-Object -First 1
if (-not $official) {
    Write-Error 'Official bucket entry not found in buckets.json.'
    exit 1
}

$official.'sha1-hash' = $Commit

try {
    $data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-Host "Updated official.sha1-hash to $Commit in $configPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to write buckets.json: $($_.Exception.Message)"
    exit 1
}
