[CmdletBinding()]
param([string]$ProfileName = '')

$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1') -Force
$paths = Get-BeeLogPaths
$run = $null
if (Test-Path -LiteralPath $paths.Run) {
    try { $run = Get-Content -Raw -LiteralPath $paths.Run | ConvertFrom-Json } catch {}
}
$serverId = if ($run) { [int]$run.pid } else { 0 }
$context = if ($run) { $run.context } else { '?' }
$model = if ($run) { [IO.Path]::GetFileName($run.modelPath) } else { '?' }
if ([string]::IsNullOrWhiteSpace($ProfileName) -and $run) { $ProfileName = $run.profileName }
$host.UI.RawUI.WindowTitle = "BeeForge live metrics | $ProfileName | ctx $context | PID $serverId"
Write-Host "BeeForge AI Console - live metrics" -ForegroundColor Cyan
Write-Host "Profile: $ProfileName"
Write-Host "Model:   $model"
Write-Host "Context: $context    PID: $serverId"
Write-Host "Log:     $($paths.Stderr)"
Write-Host ('-' * 78)

$pattern = 'prompt processing|prompt eval time|n_decoded|tg_|cache reuse|cache_reuse|CUDA|OOM|out of memory|error|release:|stop processing|draft generated|accepted|acceptance'
$seen = 0
while ($true) {
    if (Test-Path -LiteralPath $paths.Stderr) {
        $lines = @(Get-Content -LiteralPath $paths.Stderr -ErrorAction SilentlyContinue)
        if ($lines.Count -lt $seen) { $seen = 0 }
        for ($i = $seen; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $pattern) {
                $color = if ($lines[$i] -match 'CUDA|OOM|out of memory|error') { 'Red' } elseif ($lines[$i] -match 'prompt|n_decoded|tg_') { 'Green' } else { 'Gray' }
                Write-Host $lines[$i] -ForegroundColor $color
            }
        }
        $seen = $lines.Count
    }
    $process = if ($serverId -gt 0) { Get-Process -Id $serverId -ErrorAction SilentlyContinue } else { $null }
    if (-not $process) {
        Write-Host "`nSERVER STOPPED" -ForegroundColor Yellow
        break
    }
    Start-Sleep -Milliseconds 750
}
