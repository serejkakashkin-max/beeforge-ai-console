[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Model', 'Console', 'OpenCode', 'All')]
    [string]$Action,

    [switch]$ValidateOnly,

    [switch]$Simulate
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$script:ConsoleScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\ui\BeeLlama-Manager.ps1'))
$script:OpenCodeExe = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\@opencode-aidesktop\OpenCode.exe'))
$script:CoreModule = Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1'
Import-Module $script:CoreModule -Force

function New-Result {
    param(
        [string]$Target,
        [bool]$Succeeded,
        [string]$Message,
        [int]$Matched = 0,
        [int]$Forced = 0
    )
    [pscustomobject]@{
        Target    = $Target
        Succeeded = $Succeeded
        Message   = $Message
        Matched   = $Matched
        Forced    = $Forced
    }
}

function Get-ExactConsoleProcesses {
    $needle = $script:ConsoleScript.ToLowerInvariant()
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('powershell.exe', 'pwsh.exe') -and
        -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
        $_.CommandLine.ToLowerInvariant().Contains($needle)
    })
}

function Get-ExactOpenCodeProcesses {
    $needle = $script:OpenCodeExe.ToLowerInvariant()
    @(Get-CimInstance Win32_Process -Filter "Name='OpenCode.exe'" -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
        ([System.IO.Path]::GetFullPath($_.ExecutablePath)).ToLowerInvariant() -eq $needle
    })
}

function Close-ExactProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Resolver,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $true)]
        [string]$SuccessMessage,
        [int]$TimeoutSeconds = 12
    )

    $initial = @(& $Resolver)
    if ($initial.Count -eq 0) {
        return New-Result -Target $Target -Succeeded $true -Message "$Target уже закрыт."
    }

    foreach ($item in $initial) {
        try {
            $process = Get-Process -Id ([int]$item.ProcessId) -ErrorAction Stop
            if ($process.MainWindowHandle -ne 0) { [void]$process.CloseMainWindow() }
        } catch {}
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        $remaining = @(& $Resolver)
    } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

    $forced = 0
    foreach ($item in $remaining) {
        try {
            Stop-Process -Id ([int]$item.ProcessId) -Force -ErrorAction Stop
            $forced++
        } catch {}
    }

    Start-Sleep -Milliseconds 300
    $left = @(& $Resolver)
    if ($left.Count -gt 0) {
        return New-Result -Target $Target -Succeeded $false -Message "Не удалось полностью закрыть $Target." -Matched $initial.Count -Forced $forced
    }
    return New-Result -Target $Target -Succeeded $true -Message $SuccessMessage -Matched $initial.Count -Forced $forced
}

function Stop-Model {
    if ($Simulate) { return New-Result -Target 'Модель' -Succeeded $true -Message 'Simulation: model stop' -Matched 1 }
    $result = Stop-BeeServer
    New-Result -Target 'Модель' -Succeeded $true -Message ([string]$result.Message) -Matched $(if ($result.Stopped) { 1 } else { 0 })
}

function Close-Console {
    if ($Simulate) { return New-Result -Target 'BeeForge Console' -Succeeded $true -Message 'Simulation: console close' -Matched 1 }
    Close-ExactProcesses -Resolver { Get-ExactConsoleProcesses } -Target 'BeeForge Console' -SuccessMessage 'BeeForge Console закрыта.' -TimeoutSeconds 8
}

try {
    if ($ValidateOnly) {
        [pscustomobject]@{
            Valid         = $true
            Action        = $Action
            ConsoleScript = $script:ConsoleScript
            OpenCodeExe   = $script:OpenCodeExe
            CoreModule    = $script:CoreModule
            Commands      = @{
                StopModel     = [bool](Get-Command Stop-Model -CommandType Function -ErrorAction SilentlyContinue)
                CloseConsole  = [bool](Get-Command Close-Console -CommandType Function -ErrorAction SilentlyContinue)
                CloseOpenCode = [bool](Get-Command Get-ExactOpenCodeProcesses -CommandType Function -ErrorAction SilentlyContinue)
            }
        } | ConvertTo-Json -Depth 5 -Compress
        exit 0
    }

    $results = @()
    switch ($Action) {
        'Model'    { $results = @(Stop-Model) }
        'Console'  { $results = @(Close-Console) }
        'OpenCode' {
            $results = @(
                if ($Simulate) { New-Result -Target 'OpenCode' -Succeeded $true -Message 'Simulation: OpenCode close' -Matched 1 } else { Close-ExactProcesses -Resolver { Get-ExactOpenCodeProcesses } -Target 'OpenCode' -SuccessMessage 'OpenCode закрыт.' -TimeoutSeconds 15 }
            )
        }
        'All' {
            $results = @(
                Stop-Model
                if ($Simulate) { New-Result -Target 'OpenCode' -Succeeded $true -Message 'Simulation: OpenCode close' -Matched 1 } else { Close-ExactProcesses -Resolver { Get-ExactOpenCodeProcesses } -Target 'OpenCode' -SuccessMessage 'OpenCode закрыт.' -TimeoutSeconds 15 }
                Close-Console
            )
        }
    }

    [pscustomobject]@{
        Succeeded = -not ($results.Succeeded -contains $false)
        Action    = $Action
        Results   = $results
    } | ConvertTo-Json -Depth 6 -Compress
} catch {
    [pscustomobject]@{
        Succeeded = $false
        Action    = $Action
        Error     = $_.Exception.Message
        Results   = @()
    } | ConvertTo-Json -Depth 6 -Compress
    exit 1
}
