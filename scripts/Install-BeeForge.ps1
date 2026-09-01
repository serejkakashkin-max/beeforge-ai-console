[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\AI\Projects',
    [string]$ModelRoot = (Join-Path $env:USERPROFILE '.lmstudio\models'),
    [string]$LlamaServerPath = '',
    [string]$TelegramUserId = '',
    [string]$TelegramChatId = '',
    [switch]$ConfigureOpenCode,
    [switch]$SkipDependencies,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:Root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:OpenCodeRoot = Join-Path $env:USERPROFILE '.config\opencode'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory = $script:Root) {
    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$FilePath завершился с кодом $LASTEXITCODE" }
    } finally { Pop-Location }
}

function Expand-PortableValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        return $Value.Replace('__BEEFORGE_ROOT__', $script:Root).Replace('__USERPROFILE__', $env:USERPROFILE).Replace('__PROJECT_ROOT__', $ProjectRoot)
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $result[$property.Name] = Expand-PortableValue $property.Value }
        return [pscustomobject]$result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $expanded = @($Value | ForEach-Object { Expand-PortableValue $_ })
        return ,$expanded
    }
    return $Value
}

function Write-JsonUtf8([string]$Path, $Value) {
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Install-NpmPackage([string]$Directory) {
    if (Test-Path -LiteralPath (Join-Path $Directory 'package-lock.json')) {
        Invoke-Checked 'npm.cmd' @('ci', '--no-audit', '--no-fund') $Directory
    }
}

function Install-VerifiedArchive([string]$Url, [string]$Sha256, [string]$TargetDirectory, [string]$ExecutableName) {
    if (Test-Path -LiteralPath (Join-Path $TargetDirectory $ExecutableName) -PathType Leaf) { return }
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('beeforge-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $archive = Join-Path $tempRoot 'package.zip'
        Invoke-WebRequest -Uri $Url -OutFile $archive -UseBasicParsing
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Sha256.ToLowerInvariant()) { throw "Неверная SHA256 для $Url" }
        $expanded = Join-Path $tempRoot 'expanded'
        Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
        $source = Get-ChildItem -LiteralPath $expanded -Recurse -File -Filter $ExecutableName | Select-Object -First 1
        if (-not $source) { throw "$ExecutableName не найден в загруженном архиве" }
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $TargetDirectory $ExecutableName) -Force
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'BeeForge AI Console поддерживает Windows.' }
foreach ($directory in 'config','logs','backups','runtime','secrets') {
    New-Item -ItemType Directory -Path (Join-Path $script:Root $directory) -Force | Out-Null
}
New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null

Write-Step 'Создание локальных конфигураций'
$profilesPath = Join-Path $script:Root 'config\profiles.json'
if ($Force -or -not (Test-Path -LiteralPath $profilesPath)) {
    $template = Get-Content -LiteralPath (Join-Path $script:Root 'config\templates\profiles.example.json') -Raw | ConvertFrom-Json
    $profiles = Expand-PortableValue $template
    $oldModelRoot = [string]$profiles.modelRoots[0]
    $profiles.modelRoots = @([IO.Path]::GetFullPath($ModelRoot))
    $profiles.openCodeConfigPath = Join-Path $script:OpenCodeRoot 'opencode.json'
    foreach ($profile in $profiles.profiles) {
        if ($oldModelRoot -and $profile.modelPath) { $profile.modelPath = ([string]$profile.modelPath).Replace($oldModelRoot, [IO.Path]::GetFullPath($ModelRoot)) }
        if ($LlamaServerPath) { $profile.serverPath = [IO.Path]::GetFullPath($LlamaServerPath) }
    }
    Write-JsonUtf8 $profilesPath $profiles
}

$telegramPath = Join-Path $script:Root 'config\telegram.json'
if ($Force -or -not (Test-Path -LiteralPath $telegramPath)) {
    $template = Get-Content -LiteralPath (Join-Path $script:Root 'config\templates\telegram.example.json') -Raw | ConvertFrom-Json
    $telegram = Expand-PortableValue $template
    $telegram.allowedUserId = $TelegramUserId
    $telegram.allowedChatId = $TelegramChatId
    Write-JsonUtf8 $telegramPath $telegram
}

if (-not $SkipDependencies) {
    Write-Step 'Установка Node.js MCP-зависимостей'
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'Не найден Node.js/npm. Установите Node.js LTS и повторите запуск.' }
    Install-NpmPackage (Join-Path $script:Root 'tools\playwright-mcp')
    Install-NpmPackage (Join-Path $script:Root 'tools\chrome-devtools-mcp')
    Install-NpmPackage (Join-Path $script:Root 'tools\context7-mcp\v4.0.3')

    Write-Step 'Установка Serena 1.7.0'
    if (-not (Get-Command uv.exe -ErrorAction SilentlyContinue)) { throw 'Не найден uv. Установите uv (winget install astral-sh.uv) и повторите запуск.' }
    $serenaRoot = Join-Path $script:Root 'tools\serena\v1.7.0'
    New-Item -ItemType Directory -Path $serenaRoot -Force | Out-Null
    $serenaPython = Join-Path $serenaRoot '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $serenaPython)) {
        Invoke-Checked 'uv.exe' @('venv', (Join-Path $serenaRoot '.venv'), '--python', '3.13')
        Invoke-Checked 'uv.exe' @('pip', 'install', '--python', $serenaPython, 'serena-agent @ git+https://github.com/oraios/serena.git@v1.7.0')
    }

    Write-Step 'Установка локального распознавания голоса'
    if (-not (Get-Command py.exe -ErrorAction SilentlyContinue)) { throw 'Не найден Python Launcher (py.exe). Установите Python 3.11–3.13.' }
    $voiceRoot = Join-Path $script:Root 'runtime\telegram\voice'
    $voicePython = Join-Path $voiceRoot '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $voicePython)) {
        New-Item -ItemType Directory -Path $voiceRoot -Force | Out-Null
        Invoke-Checked 'py.exe' @('-3', '-m', 'venv', (Join-Path $voiceRoot '.venv'))
        Invoke-Checked $voicePython @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', (Join-Path $script:Root 'tools\telegram-bridge\v1.0.0\voice-requirements.txt'))
    }

    Write-Step 'Загрузка проверенных Windows MCP и GitHub MCP'
    Install-VerifiedArchive 'https://github.com/sbroenne/mcp-windows/releases/download/v1.3.21/windows-mcp-server-1.3.21-win-x64.zip' 'cd2e454bdbe96f66b4947f9848dccf387e49a2a6d98ea463f4a9de8d74968c01' (Join-Path $script:Root 'tools\windows-mcp\v1.3.21') 'Sbroenne.WindowsMcp.exe'
    Install-VerifiedArchive 'https://github.com/github/github-mcp-server/releases/download/v1.11.0/github-mcp-server_Windows_x86_64.zip' 'd16a3b2bbf775365541aa18729c0c3ff5e1b26dfb5dc190928895ba482211268' (Join-Path $script:Root 'tools\github-mcp\v1.11.0') 'github-mcp-server.exe'
}

if ($ConfigureOpenCode) {
    Write-Step 'Установка конфигурации OpenCode'
    New-Item -ItemType Directory -Path $script:OpenCodeRoot,(Join-Path $script:OpenCodeRoot 'plugin') -Force | Out-Null
    $openCodePath = Join-Path $script:OpenCodeRoot 'opencode.json'
    if (Test-Path -LiteralPath $openCodePath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $openCodePath -Destination "$openCodePath.before-beeforge-$stamp" -Force
    }
    $openCodeTemplate = Get-Content -LiteralPath (Join-Path $script:Root 'opencode\opencode.template.json') -Raw | ConvertFrom-Json
    Write-JsonUtf8 $openCodePath (Expand-PortableValue $openCodeTemplate)
    Copy-Item -LiteralPath (Join-Path $script:Root 'opencode\AGENTS.md') -Destination (Join-Path $script:OpenCodeRoot 'AGENTS.md') -Force
    $skillTarget = Join-Path $env:USERPROFILE '.agents\skills'
    New-Item -ItemType Directory -Path $skillTarget -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $script:Root 'opencode\skills') -Directory | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $skillTarget $_.Name) -Recurse -Force }
    $pluginSource = Join-Path $script:Root 'tools\telegram-bridge\v1.0.0\plugin.mjs'
    $pluginUri = ([uri]$pluginSource).AbsoluteUri
    $pluginText = (Get-Content -LiteralPath (Join-Path $script:Root 'opencode\plugin\beeforge-telegram.js.template') -Raw).Replace('__BEEFORGE_PLUGIN_URI__', $pluginUri)
    [IO.File]::WriteAllText((Join-Path $script:OpenCodeRoot 'plugin\beeforge-telegram.js'), $pluginText, [Text.UTF8Encoding]::new($false))
}

Write-Step 'Проверка установки'
$required = @(
    (Join-Path $script:Root 'BEEFORGE-AI.cmd'),
    (Join-Path $script:Root 'tools\telegram-bridge\v1.0.0\bridge.mjs'),
    $profilesPath,
    $telegramPath
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing) { throw "Не созданы обязательные файлы: $($missing -join ', ')" }
Get-Content -LiteralPath $profilesPath -Raw | ConvertFrom-Json | Out-Null
Get-Content -LiteralPath $telegramPath -Raw | ConvertFrom-Json | Out-Null

Write-Host "`nBeeForge подготовлен: $script:Root" -ForegroundColor Green
Write-Host 'Откройте BEEFORGE-AI.cmd, выберите llama-server и GGUF, затем сохраните Telegram-токен в интерфейсе.'
if (-not $ConfigureOpenCode) { Write-Host 'Для установки командной конфигурации OpenCode повторите скрипт с -ConfigureOpenCode.' }
