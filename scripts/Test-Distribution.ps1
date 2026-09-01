[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()

foreach ($path in 'config\templates\profiles.example.json','config\templates\telegram.example.json','opencode\opencode.template.json') {
    try { Get-Content -LiteralPath (Join-Path $Root $path) -Raw | ConvertFrom-Json | Out-Null }
    catch { $failures.Add("Некорректный JSON: $path — $($_.Exception.Message)") }
}

$tracked = @()
if (Test-Path -LiteralPath (Join-Path $Root '.git')) { $tracked = @(git -C $Root ls-files) }
foreach ($forbidden in 'secrets/','runtime/','logs/','backups/','config/profiles.json','config/telegram.json') {
    if ($tracked | Where-Object { $_ -eq $forbidden.TrimEnd('/') -or $_.StartsWith($forbidden, [StringComparison]::OrdinalIgnoreCase) }) {
        $failures.Add("В Git попал локальный путь: $forbidden")
    }
}

$portableFiles = @(
    (Join-Path $Root 'config\templates\profiles.example.json'),
    (Join-Path $Root 'config\templates\telegram.example.json'),
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
