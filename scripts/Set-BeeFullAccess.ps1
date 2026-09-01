param(
    [ValidateSet('Status','Enable','Disable')][string]$Action = 'Status',
    [string]$Source = 'CLI'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BeeForgeTeam.Core.psm1') -Force

try {
    $result = switch ($Action) {
        'Enable' { Set-BeeFullAccess -Enabled $true -Source $Source }
        'Disable' { Set-BeeFullAccess -Enabled $false -Source $Source }
        default { Get-BeeFullAccessStatus }
    }
    $result | ConvertTo-Json -Depth 8 -Compress
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
