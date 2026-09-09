$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'BeeForgeTeam.Core.psm1'
Import-Module $modulePath -Force
try {
    $config = [pscustomobject]@{
        mcp = [pscustomobject]@{
            available = [pscustomobject]@{ type='local'; enabled=$true; command=@('powershell.exe','-NoProfile') }
            missing = [pscustomobject]@{ type='local'; enabled=$true; command=@('beeforge-missing-mcp.exe') }
        }
    }
    $module = Get-Module BeeForgeTeam.Core
    $catalog = @(& $module { param($candidate) Get-BeeMcpCatalog $candidate } $config)
    $available = $catalog | Where-Object Id -eq 'available'
    $missing = $catalog | Where-Object Id -eq 'missing'
    if($available.Status-ne'CONFIGURED'){throw "Executable-only MCP must be CONFIGURED, got $($available.Status)"}
    if($missing.Status-ne'MISSING'){throw "Missing MCP status regressed: $($missing.Status)"}
    'TEAM_MCP_CATALOG_TEST_OK'
} finally {
    Remove-Module BeeForgeTeam.Core -Force -ErrorAction SilentlyContinue
}
