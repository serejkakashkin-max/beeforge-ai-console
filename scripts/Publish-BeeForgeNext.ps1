[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root)
$project = Join-Path $Root 'src\BeeForge.Next.App\BeeForge.Next.App.csproj'
$target = Join-Path $Root 'local\BeeForge.Next'
if (-not (Test-Path -LiteralPath $project -PathType Leaf)) { throw "Не найден проект BeeForge Next: $project" }
$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if (-not $dotnet) { throw 'Для сборки BeeForge Next требуется .NET 8 SDK.' }
if ($Clean -and (Test-Path -LiteralPath $target)) { Remove-Item -LiteralPath $target -Recurse -Force }
New-Item -ItemType Directory -Path $target -Force | Out-Null
& $dotnet.Source publish $project -c Release -r win-x64 --self-contained true -o $target --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet publish завершился с кодом $LASTEXITCODE" }
$exe = Join-Path $target 'BeeForge.Next.App.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "После публикации не найден $exe" }
[pscustomobject]@{ Published = $true; Path = $exe; SelfContained = $true } | ConvertTo-Json -Compress
