[CmdletBinding()]
param([string]$Root = '')

$ErrorActionPreference = 'Stop'
if([string]::IsNullOrWhiteSpace($Root)){$Root=Split-Path -Parent $PSScriptRoot}
$failures = [Collections.Generic.List[string]]::new()

$desktopShortcutInstaller = Join-Path $Root 'scripts\Install-BeeForgeDesktopShortcut.ps1'
if (-not (Test-Path -LiteralPath $desktopShortcutInstaller -PathType Leaf)) {
    $failures.Add('Не найден Install-BeeForgeDesktopShortcut.ps1')
} else {
    $shortcutText = Get-Content -LiteralPath $desktopShortcutInstaller -Raw
    if ($shortcutText -notmatch 'BeeForge\.Next\.App\.exe' -or $shortcutText -notmatch 'beeforge-ai\.ico') {
        $failures.Add('Desktop shortcut должен напрямую указывать на BeeForge.Next.App.exe и фирменную иконку')
    }
}
if (Test-Path -LiteralPath (Join-Path $Root 'BEEFORGE-AI.cmd')) { $failures.Add('Устаревший BEEFORGE-AI.cmd не должен распространяться') }
if (Test-Path -LiteralPath (Join-Path $Root 'BEEFORGE-LEGACY.cmd')) { $failures.Add('Устаревший BEEFORGE-LEGACY.cmd не должен распространяться') }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'scripts\Publish-BeeForgeNext.ps1') -PathType Leaf)) {
    $failures.Add('Не найден Publish-BeeForgeNext.ps1')
}

# Some maintenance scripts still run under Windows PowerShell 5.1. Preserve
# their UTF-8 BOM so Russian diagnostics remain parseable there.
$windowsPowerShellUtf8Files = @(
    'scripts\BeeForgeRemote.Core.psm1',
    'scripts\Start-OpenCode.ps1',
    'scripts\Test-BeeGameQaPolicy.ps1',
    'scripts\Test-BeeTeamCoordinationPolicy.ps1',
    'scripts\Test-Distribution.ps1'
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
    (Join-Path $Root 'opencode\plugin\beeforge-team-guard.js.template')
    (Join-Path $Root 'tools\team-guard\v1.0.0\plugin.mjs')
    (Join-Path $Root 'tools\team-guard\v1.0.0\self-test.mjs')
)
$personalMarkers = @('C:\Users\snkashkin','C:\release_web','telegram-token.dpapi')
foreach ($file in $portableFiles) {
    $text = Get-Content -LiteralPath $file -Raw
    foreach ($marker in $personalMarkers) {
        if ($text.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $failures.Add("Персональная строка '$marker' обнаружена в $file") }
    }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'Distribution checks: PASS' -ForegroundColor Green
