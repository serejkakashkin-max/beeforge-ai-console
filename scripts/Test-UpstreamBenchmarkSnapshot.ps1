[CmdletBinding()]
param([string]$Root = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$snapshotRoot = Join-Path ([IO.Path]::GetFullPath($Root)) 'third_party\LlamaServerLauncher'
$expectedCount = 46
$expectedAggregate = '568f9a78e439369da69f1d1e12bd377e3508c482134b7c096e43d4b749b40dff'

$files = @()
$files += Get-ChildItem (Join-Path $snapshotRoot 'Benchmarking') -Recurse -File
$files += Get-ChildItem (Join-Path $snapshotRoot 'OptimizationModels') -File
$files += Get-ChildItem (Join-Path $snapshotRoot 'OptimizationServices') -File
$files += Get-ChildItem (Join-Path $snapshotRoot 'ViewModels') -File
$files += Get-ChildItem (Join-Path $snapshotRoot 'Views') -File

if ($files.Count -ne $expectedCount) { throw "Upstream benchmark snapshot file count changed: $($files.Count), expected $expectedCount." }
$lines = @($files | ForEach-Object {
    $relative = $_.FullName.Substring($snapshotRoot.Length + 1).Replace('\','/')
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$relative`n$hash"
} | Sort-Object)
$payload = ($lines -join "`n") + "`n"
$digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))).ToLowerInvariant()
if ($digest -ne $expectedAggregate) { throw "Upstream benchmark snapshot hash changed: $digest" }
Write-Host 'UPSTREAM_BENCHMARK_SNAPSHOT_OK' -ForegroundColor Green
