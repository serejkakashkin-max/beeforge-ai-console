[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()

# BEEFORGE-AI.cmd starts the desktop UI with Windows PowerShell 5.1. Unlike
# PowerShell 7, it does not reliably decode UTF-8 scripts without a BOM. The
# remote-access module contains Russian UI messages and is imported before the
# window is shown, so losing its BOM makes the application exit at parse time.
$windowsPowerShellUtf8Files = @(
    'scripts\BeeForgeRemote.Core.psm1'
)
foreach ($relativePath in $windowsPowerShellUtf8Files) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $Root $relativePath))
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $hasUtf8Bom) { $failures.Add("Windows PowerShell 5.1 требует UTF-8 BOM: $relativePath") }
}

foreach ($path in 'config\templates\profiles.example.json','config\templates\telegram.example.json','config\templates\remote-access.example.json','opencode\opencode.template.json') {
    try { Get-Content -LiteralPath (Join-Path $Root $path) -Raw | ConvertFrom-Json | Out-Null }
    catch { $failures.Add("Некорректный JSON: $path — $($_.Exception.Message)") }
}

$tracked = @()
if (Test-Path -LiteralPath (Join-Path $Root '.git')) { $tracked = @(git -C $Root ls-files) }
foreach ($forbidden in 'secrets/','runtime/','logs/','backups/','config/profiles.json','config/telegram.json','config/remote-access.json') {
    if ($tracked | Where-Object { $_ -eq $forbidden.TrimEnd('/') -or $_.StartsWith($forbidden, [StringComparison]::OrdinalIgnoreCase) }) {
        $failures.Add("В Git попал локальный путь: $forbidden")
    }
}

$portableFiles = @(
    (Join-Path $Root 'config\templates\profiles.example.json'),
    (Join-Path $Root 'config\templates\telegram.example.json'),
    (Join-Path $Root 'config\templates\remote-access.example.json'),
    (Join-Path $Root 'opencode\opencode.template.json'),
    (Join-Path $Root 'opencode\plugin\beeforge-telegram.js.template')
)
$personalMarkers = @('C:\Users\snkashkin','C:\release_web','telegram-token.dpapi')
foreach ($file in $portableFiles) {
    $text = Get-Content -LiteralPath $file -Raw
    foreach ($marker in $personalMarkers) {
        if ($text.Contains($marker, [StringComparison]::OrdinalIgnoreCase)) { $failures.Add("Персональная строка '$marker' обнаружена в $file") }
    }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'Distribution checks: PASS' -ForegroundColor Green
