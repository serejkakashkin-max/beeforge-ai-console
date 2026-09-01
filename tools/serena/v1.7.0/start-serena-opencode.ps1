$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Location).Path
$ensureScript = Join-Path $toolRoot 'ensure-project-language.ps1'
$serenaExe = Join-Path $toolRoot '.venv\Scripts\serena.exe'

# OpenCode starts this wrapper in the selected project directory. Prepare an
# empty/stale project configuration before Serena reads it; writing project.yml
# after Serena starts is too late and Serena can overwrite that change on exit.
try {
    if (Test-Path -LiteralPath $ensureScript -PathType Leaf) {
        & $ensureScript -ProjectPath $projectRoot *> $null
    }
} catch {
    # Keep stdout clean because it carries the MCP stdio protocol. Serena can
    # still start; stderr is safe for a concise diagnostic message.
    [Console]::Error.WriteLine("BeeForge Serena preflight warning: $($_.Exception.Message)")
}

& $serenaExe start-mcp-server `
    --context codex `
    --project-from-cwd `
    --transport stdio `
    --enable-web-dashboard false `
    --enable-gui-log-window false `
    --open-web-dashboard false `
    --tool-timeout 240 `
    --log-level WARNING
exit $LASTEXITCODE
