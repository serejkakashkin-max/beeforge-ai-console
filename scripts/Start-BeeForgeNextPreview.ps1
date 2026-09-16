[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root 'src\BeeForge.Next.App\BeeForge.Next.App.csproj'
$profileStore = Join-Path $root 'config\profiles.json'
$previous = $env:BEEFORGE_PROFILE_STORE
$previousRoot = $env:BEEFORGE_ROOT
try {
    $env:BEEFORGE_PROFILE_STORE = $profileStore
    $env:BEEFORGE_ROOT = $root
    & dotnet run --project $project --configuration Release
    if ($LASTEXITCODE -ne 0) { throw "BeeForge Next preview exited with code $LASTEXITCODE" }
} finally {
    $env:BEEFORGE_PROFILE_STORE = $previous
    $env:BEEFORGE_ROOT = $previousRoot
}
