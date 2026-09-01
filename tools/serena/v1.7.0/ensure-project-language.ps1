<#
.SYNOPSIS
Prepares a project-local Serena configuration before the MCP server starts.

.DESCRIPTION
The script never edits application source. It detects supported language
servers from source files and common project manifests, creates or updates
.serena\project.yml, and preserves manually maintained Serena settings.

Configurations created by this script are marked as BeeForge-managed so their
language server list can be reconciled when a project changes technology.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$script:ProjectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
$script:ProjectFiles = @()

function Initialize-ProjectInventory {
    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if ($rg) {
        $script:ProjectFiles = @(& $rg.Source --files `
            --glob '!node_modules/**' --glob '!vendor/**' `
            --glob '!dist/**' --glob '!build/**' --glob '!coverage/**' `
            --glob '!target/**' --glob '!bin/**' --glob '!obj/**' `
            --glob '!.git/**' --glob '!.serena/**' --glob '!.venv/**' `
            --glob '!venv/**' --glob '!__pycache__/**' `
            $script:ProjectRoot 2>$null)
        return
    }

    $script:ProjectFiles = @(Get-ChildItem -LiteralPath $script:ProjectRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](node_modules|vendor|dist|build|coverage|target|bin|obj|\.git|\.serena|\.venv|venv|__pycache__)[\\/]' } |
        ForEach-Object { $_.FullName })
}

function Test-SourceFile {
    param([string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($script:ProjectFiles | Where-Object { $_ -like $pattern } | Select-Object -First 1) { return $true }
    }
    return $false
}

function Test-ProjectMarker {
    param([string[]]$Names)
    foreach ($name in $Names) {
        if (Test-Path -LiteralPath (Join-Path $script:ProjectRoot $name)) { return $true }
    }
    return $false
}

function Get-PackageFramework {
    $packagePath = Join-Path $script:ProjectRoot 'package.json'
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return $null }
    try {
        $package = [IO.File]::ReadAllText($packagePath, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
        $names = @()
        foreach ($section in @('dependencies','devDependencies','peerDependencies')) {
            $property = $package.PSObject.Properties[$section]
            if ($property -and $property.Value) { $names += @($property.Value.PSObject.Properties.Name) }
        }
        if ('@angular/core' -in $names) { return 'angular' }
        if ('vue' -in $names) { return 'vue' }
        if ('svelte' -in $names -or '@sveltejs/kit' -in $names) { return 'svelte' }
    } catch {
        # Invalid package.json must not prevent Serena from starting. Source-file
        # detection remains available and OpenCode will report the JSON issue.
    }
    return $null
}

function Get-DetectedLanguageServers {
    $servers = [System.Collections.Generic.List[string]]::new()
    $framework = Get-PackageFramework
    $hasDeno = Test-ProjectMarker @('deno.json','deno.jsonc')

    if ((Test-ProjectMarker @('angular.json')) -or $framework -eq 'angular') { $servers.Add('angular') }
    elseif ((Test-SourceFile @('*.vue')) -or $framework -eq 'vue') { $servers.Add('vue') }
    elseif ((Test-SourceFile @('*.svelte')) -or $framework -eq 'svelte') { $servers.Add('svelte') }
    elseif ($hasDeno) { $servers.Add('deno') }
    elseif ((Test-SourceFile @('*.ts','*.tsx','*.js','*.jsx','*.mts','*.cts','*.mjs','*.cjs')) -or
            (Test-ProjectMarker @('package.json','tsconfig.json','jsconfig.json'))) { $servers.Add('typescript') }

    if ((Test-SourceFile @('*.py','*.pyi')) -or (Test-ProjectMarker @('pyproject.toml','setup.py','setup.cfg','requirements.txt','Pipfile'))) { $servers.Add('python') }
    if ((Test-SourceFile @('*.go')) -or (Test-ProjectMarker @('go.mod'))) { $servers.Add('go') }
    if ((Test-SourceFile @('*.rs')) -or (Test-ProjectMarker @('Cargo.toml'))) { $servers.Add('rust') }
    if ((Test-SourceFile @('*.java')) -or (Test-ProjectMarker @('pom.xml','build.gradle'))) { $servers.Add('java') }
    if (Test-SourceFile @('*.cs','*.csproj','*.sln')) { $servers.Add('csharp') }
    if ((Test-SourceFile @('*.php')) -or (Test-ProjectMarker @('composer.json'))) { $servers.Add('php') }
    if ((Test-SourceFile @('*.rb')) -or (Test-ProjectMarker @('Gemfile'))) { $servers.Add('ruby') }
    if (Test-SourceFile @('*.kt','*.kts')) { $servers.Add('kotlin') }
    if (Test-SourceFile @('*.swift')) { $servers.Add('swift') }
    if ((Test-SourceFile @('*.cpp','*.cc','*.cxx','*.c','*.h','*.hpp')) -or (Test-ProjectMarker @('CMakeLists.txt'))) { $servers.Add('cpp') }
    if (Test-SourceFile @('*.lua')) { $servers.Add('lua') }
    if (Test-SourceFile @('*.scala')) { $servers.Add('scala') }
    if (Test-SourceFile @('*.ex','*.exs')) { $servers.Add('elixir') }

    return @($servers | Select-Object -Unique)
}

function Get-DetectedLineEnding {
    $candidates = @($script:ProjectFiles | Where-Object { $_ -match '\.(?:ts|tsx|js|jsx|mts|cts|mjs|cjs|py|pyi|go|rs|java|cs|php|rb|kt|kts|swift|cpp|cc|cxx|c|h|hpp|lua|scala|ex|exs|vue|svelte)$' } | Select-Object -First 20)
    $crlf = 0
    $lf = 0
    foreach ($candidate in $candidates) {
        $path = if ([IO.Path]::IsPathRooted($candidate)) { $candidate } else { Join-Path $script:ProjectRoot $candidate }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $bytes = [IO.File]::ReadAllBytes($path)
        $limit = [Math]::Min($bytes.Length, 65536)
        for ($i = 0; $i -lt $limit; $i++) {
            if ($bytes[$i] -eq 10) {
                if ($i -gt 0 -and $bytes[$i - 1] -eq 13) { $crlf++ } else { $lf++ }
            }
        }
    }
    if (($crlf + $lf) -gt 0) { return $(if ($crlf -gt $lf) { 'crlf' } else { 'lf' }) }
    if (Test-ProjectMarker @('package.json','deno.json','deno.jsonc','pyproject.toml','go.mod','Cargo.toml')) { return 'lf' }
    return $null
}

function Set-UnsetScalar {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Name,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^$([regex]::Escape($Name)):\s*$") {
            $Lines[$i] = "$Name`: `"$Value`""
            return $true
        }
        if ($Lines[$i] -match "^$([regex]::Escape($Name)):\s*\S+") { return $false }
    }
    $insertAfter = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^encoding:\s*') { $insertAfter = $i; break }
    }
    if ($insertAfter -ge 0) { $Lines.Insert($insertAfter + 1, "$Name`: `"$Value`"") }
    else { $Lines.Add("$Name`: `"$Value`"") }
    return $true
}

function Set-ScalarValue {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Name,
        [string]$Value
    )
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^$([regex]::Escape($Name)):") {
            $changed = $Lines[$i] -ne "$Name`: $Value"
            $Lines[$i] = "$Name`: $Value"
            return $changed
        }
    }
    $Lines.Add("$Name`: $Value")
    return $true
}

function Register-SerenaProject {
    $configPath = Join-Path $env:USERPROFILE '.serena\serena_config.yml'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return }
    $configLines = [System.Collections.Generic.List[string]]::new()
    $configLines.AddRange([IO.File]::ReadAllLines($configPath, [Text.UTF8Encoding]::new($false)))
    $canonical = $script:ProjectRoot.TrimEnd('\')
    if ($configLines | Where-Object { $_ -match '^\s*-\s*(.+?)\s*$' -and $matches[1].Trim('"','''').TrimEnd('\') -eq $canonical } | Select-Object -First 1) { return }
    $projectsIndex = -1
    for ($i = 0; $i -lt $configLines.Count; $i++) { if ($configLines[$i] -match '^projects:\s*$') { $projectsIndex = $i; break } }
    if ($projectsIndex -lt 0) { $configLines.Add(''); $configLines.Add('projects:'); $configLines.Add("- $canonical") }
    else {
        $insert = $projectsIndex + 1
        while ($insert -lt $configLines.Count -and $configLines[$insert] -match '^\s*-\s*') { $insert++ }
        $configLines.Insert($insert, "- $canonical")
    }
    [IO.File]::WriteAllLines($configPath, $configLines, [Text.UTF8Encoding]::new($false))
}

Initialize-ProjectInventory
$servers = @(Get-DetectedLanguageServers)
$lineEnding = Get-DetectedLineEnding
$serenaDir = Join-Path $script:ProjectRoot '.serena'
$projectYml = Join-Path $serenaDir 'project.yml'

if ($servers.Count -eq 0) {
    [pscustomobject]@{ status = 'no-supported-source'; project = $script:ProjectRoot; language_servers = @(); line_ending = $lineEnding } | ConvertTo-Json -Compress
    exit 0
}

if (-not (Test-Path -LiteralPath $projectYml)) {
    New-Item -ItemType Directory -Path $serenaDir -Force | Out-Null
    $newConfig = @(
        '# beeforge_managed_language_servers: true'
        "project_name: `"$([IO.Path]::GetFileName($script:ProjectRoot))`""
        'language_servers:'
        ($servers | ForEach-Object { "- $_" })
        'encoding: "utf-8"'
        $(if ($lineEnding) { "line_ending: `"$lineEnding`"" } else { 'line_ending:' })
        'ignore_all_files_in_gitignore: true'
        'read_only: false'
        'initial_prompt: "BeeForge project: use durable Serena memories for every activated project; read memory_maintenance first; never store secrets or transient task logs."'
        'ls_workspace_folders:'
        '- "."'
    )
    [IO.File]::WriteAllLines($projectYml, $newConfig, [Text.UTF8Encoding]::new($true))
    Register-SerenaProject
    [pscustomobject]@{ status = 'created'; project = $script:ProjectRoot; language_servers = $servers; line_ending = $lineEnding } | ConvertTo-Json -Compress
    exit 0
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.AddRange([IO.File]::ReadAllLines($projectYml, [Text.UTF8Encoding]::new($false)))
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^language_servers:\s*(?:\[\])?\s*$') { $start = $i; break }
}
if ($start -lt 0) { throw "Serena configuration has no language_servers field: $projectYml" }

$end = $start + 1
while ($end -lt $lines.Count -and ($lines[$end] -match '^\s*-\s*\S+')) { $end++ }
$existingLines = @()
if ($end -gt ($start + 1)) { $existingLines = @($lines.GetRange($start + 1, $end - $start - 1)) }
$existing = @($existingLines | ForEach-Object { if ($_ -match '^\s*-\s*(\S+)') { $matches[1] } })
$managed = @($lines | Where-Object { $_ -eq '# beeforge_managed_language_servers: true' }).Count -gt 0
$target = if ($managed) { @($servers) } else { @($existing + ($servers | Where-Object { $_ -notin $existing })) }
$languagesChanged = (@($existing) -join "`n") -ne (@($target) -join "`n")

if ($languagesChanged) {
    $replacement = [System.Collections.Generic.List[string]]::new()
    $replacement.Add('language_servers:')
    foreach ($server in $target) { $replacement.Add("- $server") }
    $lines.RemoveRange($start, $end - $start)
    $lines.InsertRange($start, $replacement)
}
$lineEndingChanged = Set-UnsetScalar -Lines $lines -Name 'line_ending' -Value $lineEnding
$memoryReadOnlyChanged = Set-ScalarValue -Lines $lines -Name 'read_only' -Value 'false'
$memoryPromptChanged = Set-ScalarValue -Lines $lines -Name 'initial_prompt' -Value '"BeeForge project: use durable Serena memories for every activated project; read memory_maintenance first; never store secrets or transient task logs."'

if ($languagesChanged -or $lineEndingChanged -or $memoryReadOnlyChanged -or $memoryPromptChanged) {
    [IO.File]::WriteAllLines($projectYml, $lines, [Text.UTF8Encoding]::new($true))
}
Register-SerenaProject

$added = @($target | Where-Object { $_ -notin $existing })
$removed = @($existing | Where-Object { $_ -notin $target })
$status = if ($languagesChanged -and $managed) { 'reconciled' } elseif ($languagesChanged) { 'extended' } elseif ($lineEndingChanged) { 'line-ending-set' } elseif ($memoryReadOnlyChanged -or $memoryPromptChanged) { 'memory-enabled' } else { 'already-configured' }
[pscustomobject]@{
    status = $status
    project = $script:ProjectRoot
    language_servers = $target
    added = $added
    removed = $removed
    line_ending = $lineEnding
    managed = $managed
} | ConvertTo-Json -Compress
