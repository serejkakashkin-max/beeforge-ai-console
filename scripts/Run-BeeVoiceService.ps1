[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][int]$Port,
    [string]$Model='small'
)

$ErrorActionPreference='Stop'
$runtime=Join-Path $Root 'runtime\telegram\voice'
$python=Join-Path $runtime '.venv\Scripts\python.exe'
$service=Join-Path $Root 'tools\telegram-bridge\v1.0.0\voice-service.py'
$key=Join-Path $Root 'secrets\telegram-bridge.key'
$models=Join-Path $runtime 'models'
$log=Join-Path $runtime 'voice-service.log'

if(-not(Test-Path -LiteralPath $python)){throw "Локальный Voice Service не установлен: $python"}
if(-not(Test-Path -LiteralPath $service)){throw "Не найден Voice Service: $service"}
if(-not(Test-Path -LiteralPath $key)){throw 'Не найден локальный ключ BeeForge Bridge'}
foreach($directory in @($runtime,$models)){if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force|Out-Null}}
$env:HF_HUB_DISABLE_SYMLINKS_WARNING='1'

try {
    & $python $service --host 127.0.0.1 --port $Port --key-file $key --model $Model --model-root $models *>> $log
    exit $LASTEXITCODE
} catch {
    [IO.File]::AppendAllText($log,"$([DateTime]::Now.ToString('o')) $($_.Exception.Message)`r`n",[Text.UTF8Encoding]::new($false))
    exit 1
}
