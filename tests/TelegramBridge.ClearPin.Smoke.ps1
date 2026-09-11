Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bridgePath = Join-Path $root 'tools\telegram-bridge\v1.0.0\bridge.mjs'
$bridge = [IO.File]::ReadAllText($bridgePath, [Text.UTF8Encoding]::new($true))

$clearStart = $bridge.IndexOf('async function clearRecentTelegramChat(anchorMessageId)')
$clearEnd = $bridge.IndexOf('async function telegramUpload(', $clearStart)
if ($clearStart -lt 0 -or $clearEnd -le $clearStart) { throw 'Unable to locate chat-clear source block' }
$clearBlock = $bridge.Substring($clearStart, $clearEnd - $clearStart)
if ($clearBlock.Contains('pinnedMessageId = null')) { throw 'Chat clear must preserve the tracked pinned status' }
foreach ($needle in @(
    'deleteTelegramMessagesResilient',
    '.filter((messageId) => messageId !== protectedPinnedId)',
    'await updatePinnedStatus()'
)) {
    if (-not $bridge.Contains($needle)) { throw "Telegram clear/pin regression: missing $needle" }
}
if ($clearBlock.Contains('pinChatMessage') -or $clearBlock.Contains('unpinAllChatMessages')) { throw 'Clear must not repin messages' }
if (-not $bridge.Contains('if (pinnedUpdateInFlight) {')) { throw 'Concurrent pin refreshes must be retried' }
if (-not $bridge.Contains('schedulePinnedStatus(2000)')) { throw 'Transient pinned-message edit failures must be retried' }
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    & $node.Source (Join-Path $root 'tools\telegram-bridge\v1.0.0\clear-chat-self-test.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Behavioral clear test failed' }
    & $node.Source --check $bridgePath
    if ($LASTEXITCODE -ne 0) { throw "node --check failed with exit code $LASTEXITCODE" }
}
Write-Host 'Telegram clear/pin smoke test passed.'
