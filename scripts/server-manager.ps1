[CmdletBinding()]
param(
    [ValidateSet('Start','Stop','Status','Validate','Preview')]
    [string]$Action = 'Status',
    [string]$ProfileId
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BeeLlamaManager.Core.psm1') -Force

try {
    switch ($Action) {
        'Start' {
            $status = Start-BeeServer -ProfileId $ProfileId
            Write-Host ("READY http://127.0.0.1:{0}/v1 | profile={1} | context={2} | PID={3}" -f (Get-BeeProfile $ProfileId).port,$status.Profile,$status.Context,$status.Pid) -ForegroundColor Green
            $status | ConvertTo-Json -Depth 5
        }
        'Stop' {
            $result = Stop-BeeServer
            Write-Host $result.Message -ForegroundColor $(if ($result.Stopped) { 'Green' } else { 'Yellow' })
            $result | ConvertTo-Json
        }
        'Status' { Get-BeeServerStatus | ConvertTo-Json -Depth 5 }
        'Validate' {
            $profile = Get-BeeProfile $ProfileId
            $result = Test-BeeProfile $profile
            $result | ConvertTo-Json -Depth 5
            if (-not $result.Valid) { exit 2 }
        }
        'Preview' { Get-BeeCommandPreview (Get-BeeProfile $ProfileId) }
    }
} catch {
    $errorFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\manager-error.log'
    try { $_.Exception.Message | Set-Content -LiteralPath $errorFile -Encoding UTF8 } catch {}
    Write-Error $_.Exception.Message
    exit 1
}
