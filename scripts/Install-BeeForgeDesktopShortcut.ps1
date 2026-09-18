[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$ShortcutPath = ''
)

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
$exe = Join-Path $Root 'local\BeeForge.Next\BeeForge.Next.App.exe'
$icon = Join-Path $Root 'assets\beeforge-ai.ico'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Не найден BeeForge Next: $exe" }
if (-not (Test-Path -LiteralPath $icon -PathType Leaf)) { throw "Не найдена иконка BeeForge: $icon" }
if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $ShortcutPath = Join-Path $desktop 'BeeForge AI Console.lnk'
}
$ShortcutPath = [IO.Path]::GetFullPath($ShortcutPath)
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = $Root
$shortcut.IconLocation = "$icon,0"
$shortcut.Description = 'BeeForge AI Console'
$shortcut.Save()

[pscustomobject]@{
    Shortcut = $ShortcutPath
    Target = $exe
    WorkingDirectory = $Root
    Icon = $icon
} | ConvertTo-Json -Compress
