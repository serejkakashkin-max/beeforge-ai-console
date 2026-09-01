Set-StrictMode -Version 2.0
$script:BeeRoot = Split-Path $PSScriptRoot -Parent
$script:ConfigPath = Join-Path $script:BeeRoot 'config\profiles.json'
$script:LogDir = Join-Path $script:BeeRoot 'logs'
$script:PidPath = Join-Path $script:LogDir 'qwen38-server.pid'
$script:RunPath = Join-Path $script:LogDir 'current-run.json'
$script:StdoutPath = Join-Path $script:LogDir 'current.stdout.log'
$script:StderrPath = Join-Path $script:LogDir 'current.stderr.log'
$script:BenchmarkPidPath = Join-Path $script:LogDir 'benchmark-test.pid'
$script:BenchmarkStatusPath = Join-Path $script:LogDir 'benchmark-test.status.json'
$script:BenchmarkResultPath = Join-Path $script:LogDir 'benchmark-test.result.json'
$script:BackupRetentionCount = 10
$script:BackupRetentionDays = 30
$script:BenchmarkRetentionCount = 20
$script:BenchmarkRetentionDays = 30
$script:ManagedFlags = @(
    '-m','--model','-mm','--mmproj','--mmproj-offload','--no-mmproj-offload','--image-min-tokens','--alias','-ngl','--gpu-layers','-c','--ctx-size','-b','--batch-size',
    '-ub','--ubatch-size','-t','--threads','-tb','--threads-batch','-ctk','--cache-type-k',
    '-ctv','--cache-type-v','--kv-tail-tokens','--kv-tail-type','-fa','--flash-attn',
    '--fit','-np','--parallel','--cache-reuse','--reasoning','--reasoning-budget',
    '--reasoning-loop-guard','--reasoning-preserve','--spec-type','--spec-draft-n-max',
    '--temp','--top-p','--top-k','--min-p','--repeat-penalty','--host','--port',
    '--log-colors'
)

function Initialize-BeeFolders {
    foreach ($path in @((Join-Path $script:BeeRoot 'config'), $script:LogDir, (Join-Path $script:BeeRoot 'backups'), (Join-Path $script:BeeRoot 'benchmarks'))) {
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }
}

function Invoke-BeeRetention {
    Initialize-BeeFolders
    $now = Get-Date
    $backupDir = [IO.Path]::GetFullPath((Join-Path $script:BeeRoot 'backups'))
    $benchmarkDir = [IO.Path]::GetFullPath((Join-Path $script:BeeRoot 'benchmarks'))
    $expectedRoot = [IO.Path]::GetFullPath($script:BeeRoot)
    foreach ($directory in @($backupDir,$benchmarkDir)) {
        if (-not $directory.StartsWith($expectedRoot,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe retention directory: $directory"
        }
    }

    $automaticBackups = @(Get-ChildItem -LiteralPath $backupDir -File -Filter 'opencode.*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    for ($index=0; $index -lt $automaticBackups.Count; $index++) {
        if ($index -ge $script:BackupRetentionCount -or $automaticBackups[$index].LastWriteTime -lt $now.AddDays(-$script:BackupRetentionDays)) {
            Remove-Item -LiteralPath $automaticBackups[$index].FullName -Force -ErrorAction Stop
        }
    }

    $benchmarkArtifacts = @(Get-ChildItem -LiteralPath $benchmarkDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'results.csv' -and $_.Name -ne 'README.md' } |
        Sort-Object LastWriteTime -Descending)
    for ($index=0; $index -lt $benchmarkArtifacts.Count; $index++) {
        if ($index -ge $script:BenchmarkRetentionCount -or $benchmarkArtifacts[$index].LastWriteTime -lt $now.AddDays(-$script:BenchmarkRetentionDays)) {
            Remove-Item -LiteralPath $benchmarkArtifacts[$index].FullName -Force -ErrorAction Stop
        }
    }
}

function Get-BeeRoot { return $script:BeeRoot }
function Get-BeeLogPaths {
    [pscustomobject]@{ Directory=$script:LogDir; Pid=$script:PidPath; Run=$script:RunPath; Stdout=$script:StdoutPath; Stderr=$script:StderrPath; BenchmarkPid=$script:BenchmarkPidPath; BenchmarkStatus=$script:BenchmarkStatusPath; BenchmarkResult=$script:BenchmarkResultPath }
}

function Initialize-BeeProfileSchema($Profile) {
    # Profiles created by older manager builds do not contain the vision fields.
    # Add new fields instead of assigning to missing PSCustomObject properties,
    # which is an error under Set-StrictMode in Windows PowerShell 5.1.
    $defaults = [ordered]@{
        visionEnabled = $false
        visionOffload = $false
        mmprojPath = ''
    }
    foreach ($entry in $defaults.GetEnumerator()) {
        if (-not $Profile.PSObject.Properties[$entry.Key]) {
            $Profile | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value
        }
    }
    # Profiles are user-defined; no profile has a privileged or undeletable role.
    if ($Profile.PSObject.Properties['protected']) { $Profile.protected = $false }
    else { $Profile | Add-Member -NotePropertyName 'protected' -NotePropertyValue $false }
    return $Profile
}

function Get-BeeProfileStore {
    Initialize-BeeFolders
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { throw "Profile store not found: $script:ConfigPath" }
    # Windows PowerShell 5.1 treats UTF-8 without BOM as an ANSI file. Reading
    # explicitly as UTF-8 keeps Russian profile names stable across PS 5/7.
    $json = [IO.File]::ReadAllText($script:ConfigPath, [Text.UTF8Encoding]::new($false))
    $store = $json | ConvertFrom-Json
    foreach ($profile in @($store.profiles)) { Initialize-BeeProfileSchema $profile | Out-Null }
    return $store
}

function Save-BeeProfileStore([Parameter(Mandatory=$true)]$Store) {
    Initialize-BeeFolders
    $temp = "$script:ConfigPath.tmp"
    foreach ($profile in @($Store.profiles)) { Initialize-BeeProfileSchema $profile | Out-Null }
    $json = $Store | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $temp -Destination $script:ConfigPath -Force
}

function Get-BeeNewProfileTemplate {
    [pscustomobject]@{
        id='qwen38-daily-162k'; name='Qwen38 Daily 162K'; protected=$false
        modelPath=(Join-Path $env:USERPROFILE '.lmstudio\models\zerodigest\Qwen3.8-27B-Uncensored-YMQ-MTP-GGUF\Qwen3.8-27B-Uncensored-YMQ-S-Pro.gguf')
        serverPath=(Join-Path $script:BeeRoot 'runtime\beellama-v0.4.3-cuda13.1\llama-server.exe')
        alias='qwen38-ymq-s-pro'; context=162000; gpuLayers='all'; batch=2048; ubatch=512
        threads=16; threadsBatch=16; flashAttention=$true; kvK='kvarn4'; kvV='kvarn4'
        kvTailTokens=1024; kvTailType='f16'; cacheReuse=256; parallel=1
        reasoningEnabled=$true; reasoningBudget=32768; reasoningPreserve=$true
        mtpEnabled=$false; mtpNMax=4; temperature=1.0; topP=0.95; topK=20
        minP=0.0; repeatPenalty=1.0; host='127.0.0.1'; port=8080
        openCodeSync=$true; openCodeOutput=32764; visionEnabled=$false; visionOffload=$false; mmprojPath=''; advancedArgs=@()
    }
}

function Get-BeeProfile([string]$ProfileId) {
    $store = Get-BeeProfileStore
    if ([string]::IsNullOrWhiteSpace($ProfileId)) { $ProfileId = [string]$store.activeProfileId }
    $profile = @($store.profiles | Where-Object { $_.id -eq $ProfileId }) | Select-Object -First 1
    if (-not $profile) { throw "Profile not found: $ProfileId" }
    return $profile
}

function Get-BeeModelFiles {
    $store = Get-BeeProfileStore
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($store.modelRoots)) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Filter '*.gguf' -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike 'mmproj*' } |
                ForEach-Object { if (-not $items.Contains($_.FullName)) { $items.Add($_.FullName) } }
        }
    }
    return @($items | Sort-Object)
}

function Get-BeeVisionProjectorFiles([string]$ModelPath) {
    $store = Get-BeeProfileStore
    $items = New-Object System.Collections.Generic.List[string]
    $modelDirectory = if (-not [string]::IsNullOrWhiteSpace($ModelPath)) { Split-Path -Parent $ModelPath } else { $null }
    foreach ($root in @($modelDirectory) + @($store.modelRoots)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $searchRoot = if ($root -eq $modelDirectory) { $root } else { $root }
        Get-ChildItem -LiteralPath $searchRoot -Filter '*.gguf' -Recurse:($root -ne $modelDirectory) -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)^(mmproj|.*(?:vision|projector|clip).*)' } |
            ForEach-Object { if (-not $items.Contains($_.FullName)) { $items.Add($_.FullName) } }
    }
    return @($items | Sort-Object @{Expression={ if ($modelDirectory -and (Split-Path -Parent $_) -eq $modelDirectory) { 0 } else { 1 } }}, @{Expression={ $_ }})
}

function Test-BeeVisionProfile([Parameter(Mandatory=$true)]$Profile, [string]$HelpText) {
    $enabledProperty = $Profile.PSObject.Properties['visionEnabled']
    $enabled = ($enabledProperty -and [bool]$Profile.visionEnabled)
    if (-not $enabled) { return [pscustomobject]@{ Enabled=$false; Valid=$true; Errors=@(); Warnings=@() } }
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $pathProperty = $Profile.PSObject.Properties['mmprojPath']
    $mmprojPath = if ($pathProperty) { [string]$Profile.mmprojPath } else { '' }
    if ([string]::IsNullOrWhiteSpace($mmprojPath)) { $errors.Add('Vision is enabled but no mmproj projector is selected') }
    elseif (-not (Test-Path -LiteralPath $mmprojPath -PathType Leaf)) { $errors.Add("Vision projector not found: $mmprojPath") }
    elseif ([IO.Path]::GetExtension($mmprojPath) -ne '.gguf') { $errors.Add('Vision projector must be a .gguf file') }
    if ($HelpText -and $HelpText -notmatch [regex]::Escape('-mm')) { $errors.Add('Runtime does not support the -mm / --mmproj vision flag') }
    if ($HelpText -and $HelpText -notmatch [regex]::Escape('--no-mmproj-offload')) { $errors.Add('Runtime does not support projector offload control') }
    if ($HelpText -and $HelpText -notmatch [regex]::Escape('--image-min-tokens')) { $errors.Add('Runtime does not support image token limits') }
    if ($mmprojPath -and $mmprojPath -ne $Profile.modelPath -and (Split-Path -Parent $mmprojPath) -ne (Split-Path -Parent $Profile.modelPath)) {
        $warnings.Add('Projector is outside the model folder; verify that it matches this model family before launch')
    }
    return [pscustomobject]@{ Enabled=$true; Valid=($errors.Count -eq 0); Errors=@($errors); Warnings=@($warnings) }
}

function Get-BeeSupportedHelp([string]$ServerPath) {
    if (-not (Test-Path -LiteralPath $ServerPath -PathType Leaf)) { throw "Server executable not found: $ServerPath" }
    return ((& $ServerPath --help 2>&1) | Out-String)
}

function Test-BeeProfile([Parameter(Mandatory=$true)]$Profile, [switch]$SkipHelp) {
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Profile.modelPath -PathType Leaf)) { $errors.Add("GGUF model not found: $($Profile.modelPath)") }
    elseif ([IO.Path]::GetExtension([string]$Profile.modelPath) -ne '.gguf') { $errors.Add('Model must be a .gguf file') }
    if (-not (Test-Path -LiteralPath $Profile.serverPath -PathType Leaf)) { $errors.Add("llama-server.exe not found: $($Profile.serverPath)") }
    elseif ([IO.Path]::GetFileName([string]$Profile.serverPath) -ne 'llama-server.exe') { $errors.Add('Runtime path must point to llama-server.exe') }
    if ([int]$Profile.context -lt 1) { $errors.Add('Context must be a positive integer') }
    if ([int]$Profile.context -ge 180000) { $warnings.Add('180K context has very small VRAM headroom on this GPU') }
    if ([int]$Profile.port -lt 1 -or [int]$Profile.port -gt 65535) { $errors.Add('Port must be between 1 and 65535') }
    if ([int]$Profile.batch -lt 1 -or [int]$Profile.ubatch -lt 1) { $errors.Add('Batch and ubatch must be positive') }
    if ([int]$Profile.ubatch -gt [int]$Profile.batch) { $errors.Add('Ubatch cannot exceed batch') }
    if ([int]$Profile.threads -lt 1 -or [int]$Profile.threadsBatch -lt 1) { $errors.Add('Thread counts must be positive') }
    if ([int]$Profile.parallel -lt 1) { $errors.Add('Parallel must be at least 1') }
    if ([int]$Profile.reasoningBudget -lt 0) { $errors.Add('Reasoning budget cannot be negative') }
    if ([int]$Profile.mtpNMax -lt 2 -or [int]$Profile.mtpNMax -gt 4) { $errors.Add('MTP n-max must be 2, 3, or 4') }
    if ([string]$Profile.alias -notmatch '^[A-Za-z0-9._-]+$') { $errors.Add('Alias may contain only letters, digits, dot, underscore, and dash') }
    if ([string]$Profile.host -notin @('127.0.0.1','localhost')) { $warnings.Add('Non-local host exposes the API beyond localhost') }

    $helpText = $null
    if (-not $SkipHelp -and (Test-Path -LiteralPath $Profile.serverPath -PathType Leaf)) {
        try { $helpText = Get-BeeSupportedHelp $Profile.serverPath } catch { $errors.Add($_.Exception.Message) }
    }
    if ($helpText) {
        $requiredFlags = @(
            '-m','--alias','-ngl','-c','-b','-ub','-t','-tb','-ctk','-ctv',
            '--kv-tail-tokens','--kv-tail-type','-fa','--fit','-np','--cache-reuse',
            '--reasoning','--reasoning-budget','--reasoning-loop-guard','--temp',
            '--top-p','--top-k','--min-p','--repeat-penalty','--host','--port','--log-colors'
        )
        if ([bool]$Profile.reasoningPreserve) { $requiredFlags += '--reasoning-preserve' }
        if ([bool]$Profile.mtpEnabled) { $requiredFlags += @('--spec-type','--spec-draft-n-max') }
        foreach ($requiredFlag in $requiredFlags) {
            if ($helpText -notmatch [regex]::Escape($requiredFlag)) { $errors.Add("Runtime does not support required flag: $requiredFlag") }
        }
    }
    $vision = Test-BeeVisionProfile $Profile $helpText
    foreach ($error in @($vision.Errors)) { $errors.Add($error) }
    foreach ($warning in @($vision.Warnings)) { $warnings.Add($warning) }
    foreach ($entry in @($Profile.advancedArgs)) {
        $flag = [string]$entry.flag
        $value = [string]$entry.value
        if ($flag -notmatch '^--?[A-Za-z0-9][A-Za-z0-9-]*$') { $errors.Add("Invalid advanced flag: $flag"); continue }
        if ($script:ManagedFlags -contains $flag) { $errors.Add("Advanced flag duplicates a managed field: $flag") }
        if ($value -match "[`r`n`0]") { $errors.Add("Invalid newline or NUL in value for $flag") }
        if ($helpText -and $helpText -notmatch [regex]::Escape($flag)) { $errors.Add("Flag is not supported by this runtime: $flag") }
    }
    [pscustomobject]@{ Valid=($errors.Count -eq 0); Errors=@($errors); Warnings=@($warnings) }
}

function Get-BeeArguments([Parameter(Mandatory=$true)]$Profile) {
    $args = New-Object System.Collections.Generic.List[string]
    foreach ($value in @(
        '-m',[string]$Profile.modelPath,'--alias',[string]$Profile.alias,
        '-ngl',[string]$Profile.gpuLayers,'-c',[string]$Profile.context,
        '-b',[string]$Profile.batch,'-ub',[string]$Profile.ubatch,
        '-t',[string]$Profile.threads,'-tb',[string]$Profile.threadsBatch,
        '-ctk',[string]$Profile.kvK,'-ctv',[string]$Profile.kvV,
        '--kv-tail-tokens',[string]$Profile.kvTailTokens,'--kv-tail-type',[string]$Profile.kvTailType,
        '-fa',$(if ([bool]$Profile.flashAttention) {'on'} else {'off'}),'--fit','off',
        '-np',[string]$Profile.parallel,'--cache-reuse',[string]$Profile.cacheReuse,
        '--reasoning',$(if ([bool]$Profile.reasoningEnabled) {'on'} else {'off'}),
        '--reasoning-budget',[string]$Profile.reasoningBudget,'--reasoning-loop-guard','force-close',
        '--temp',[string]$Profile.temperature,'--top-p',[string]$Profile.topP,
        '--top-k',[string]$Profile.topK,'--min-p',[string]$Profile.minP,
        '--repeat-penalty',[string]$Profile.repeatPenalty,'--host',[string]$Profile.host,
        '--port',[string]$Profile.port,'--log-colors','off'
    )) { $args.Add([string]$value) }
    $visionEnabled = ($Profile.PSObject.Properties['visionEnabled'] -and [bool]$Profile.visionEnabled)
    if ($visionEnabled) {
        foreach ($value in @('-mm',[string]$Profile.mmprojPath)) { $args.Add($value) }
        $visionOffload = ($Profile.PSObject.Properties['visionOffload'] -and [bool]$Profile.visionOffload)
        $args.Add($(if ($visionOffload) { '--mmproj-offload' } else { '--no-mmproj-offload' }))
        foreach ($value in @('--image-min-tokens','1024')) { $args.Add($value) }
    }
    if ([bool]$Profile.reasoningPreserve) { $args.Add('--reasoning-preserve') }
    if ([bool]$Profile.mtpEnabled) {
        foreach ($value in @('--spec-type','draft-mtp','--spec-draft-n-max',[string]$Profile.mtpNMax)) { $args.Add($value) }
    }
    foreach ($entry in @($Profile.advancedArgs)) {
        $args.Add([string]$entry.flag)
        if (-not [string]::IsNullOrEmpty([string]$entry.value)) { $args.Add([string]$entry.value) }
    }
    return @($args)
}

function Get-BeeCommandPreview([Parameter(Mandatory=$true)]$Profile) {
    $parts = @('"' + ([string]$Profile.serverPath).Replace('"','\"') + '"')
    foreach ($arg in @(Get-BeeArguments $Profile)) {
        if ($arg -match '[\s"]') { $parts += '"' + $arg.Replace('"','\"') + '"' } else { $parts += $arg }
    }
    return ($parts -join ' ')
}

function ConvertTo-BeeProcessArgument([AllowEmptyString()][string]$Value) {
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    # Start-Process flattens ArgumentList into one Windows command line. Quote using
    # the CommandLineToArgvW rules so paths with spaces and Cyrillic remain intact.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function ConvertTo-BeeArgumentLine([string[]]$Arguments) {
    return ((@($Arguments) | ForEach-Object { ConvertTo-BeeProcessArgument ([string]$_) }) -join ' ')
}

function Get-BeeAllowedServerPaths {
    $store = Get-BeeProfileStore
    return @($store.profiles | ForEach-Object { try { [IO.Path]::GetFullPath([string]$_.serverPath) } catch {} } | Select-Object -Unique)
}

function Stop-BeeServer {
    Initialize-BeeFolders
    Stop-BeeBenchmark | Out-Null
    $result = [pscustomobject]@{ Stopped=$false; Message='No managed server is running' }
    if (-not (Test-Path -LiteralPath $script:PidPath)) { return $result }
    $serverId = 0
    if (-not [int]::TryParse((Get-Content -Raw -LiteralPath $script:PidPath).Trim(), [ref]$serverId)) {
        Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Stopped=$false; Message='Removed invalid PID file' }
    }
    $process = Get-Process -Id $serverId -ErrorAction SilentlyContinue
    if (-not $process) {
        Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Stopped=$false; Message='Removed stale PID file' }
    }
    $actual = $null
    try { $actual = [IO.Path]::GetFullPath($process.Path) } catch {}
    if (-not $actual -or (Get-BeeAllowedServerPaths) -notcontains $actual) {
        throw "PID $serverId does not belong to a configured llama-server.exe; refusing to stop it"
    }
    Stop-Process -Id $serverId -Force
    try { Wait-Process -Id $serverId -Timeout 10 -ErrorAction SilentlyContinue } catch {}
    Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Stopped=$true; Message="Stopped BeeLlama server PID $serverId" }
}

function Clear-BeeRuntimeLogs {
    Initialize-BeeFolders
    $resolved = [IO.Path]::GetFullPath($script:LogDir)
    $expected = [IO.Path]::GetFullPath((Join-Path $script:BeeRoot 'logs'))
    if ($resolved -ne $expected -or -not $resolved.StartsWith([IO.Path]::GetFullPath($script:BeeRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe log directory: $resolved"
    }
    Get-ChildItem -LiteralPath $resolved -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction Stop
}

function Test-BeePortAvailable([string]$HostName, [int]$Port) {
    $address = [Net.IPAddress]::Loopback
    if ($HostName -eq '0.0.0.0') { $address = [Net.IPAddress]::Any }
    elseif ($HostName -notin @('127.0.0.1','localhost')) {
        $parsed = $null
        if ([Net.IPAddress]::TryParse($HostName, [ref]$parsed)) { $address = $parsed }
    }
    $listener = New-Object Net.Sockets.TcpListener -ArgumentList $address, $Port
    try { $listener.Start(); return $true } catch { return $false } finally { try { $listener.Stop() } catch {} }
}

function Set-BeeJsonProperty($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Update-BeeOpenCode([Parameter(Mandatory=$true)]$Profile) {
    if (-not [bool]$Profile.openCodeSync) { return [pscustomobject]@{Updated=$false;Message='OpenCode sync is disabled for this profile';Backup=$null} }
    $store = Get-BeeProfileStore
    $path = [string]$store.openCodeConfigPath
    if (-not (Test-Path -LiteralPath $path)) { throw "OpenCode config not found: $path" }
    $backupDir = Join-Path $script:BeeRoot 'backups'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupDir "opencode.profile-manager-$stamp.json"
    Copy-Item -LiteralPath $path -Destination $backupPath
    Invoke-BeeRetention
    # Always decode OpenCode's config as UTF-8 explicitly. Windows PowerShell
    # 5.1 otherwise treats a valid UTF-8 file without BOM as ANSI and turns
    # Russian agent prompts into mojibake on the next profile sync.
    $config = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    $alias = [string]$Profile.alias
    Set-BeeJsonProperty $config 'model' "beellama/$alias"
    if (-not $config.provider -or -not $config.provider.beellama) { throw 'OpenCode provider.beellama is missing' }
    Set-BeeJsonProperty $config.provider.beellama.options 'baseURL' "http://$($Profile.host):$($Profile.port)/v1"
    if (-not $config.provider.beellama.options.extraBody) { Set-BeeJsonProperty $config.provider.beellama.options 'extraBody' ([pscustomobject]@{}) }
    if (-not $config.provider.beellama.options.extraBody.chat_template_kwargs) { Set-BeeJsonProperty $config.provider.beellama.options.extraBody 'chat_template_kwargs' ([pscustomobject]@{}) }
    $templateArgs = $config.provider.beellama.options.extraBody.chat_template_kwargs
    Set-BeeJsonProperty $templateArgs 'enable_thinking' ([bool]$Profile.reasoningEnabled)
    # OpenCode exposes Default/Low/Medium/High as model variants when the model
    # has reasoning=true. Do not pin reasoning_effort here: the selected variant
    # must be allowed to set it per request.
    if ($templateArgs.PSObject.Properties['reasoning_effort']) {
        $templateArgs.PSObject.Properties.Remove('reasoning_effort')
    }
    Set-BeeJsonProperty $templateArgs 'preserve_thinking' ([bool]$Profile.reasoningPreserve)
    $visionEnabled = ($Profile.PSObject.Properties['visionEnabled'] -and [bool]$Profile.visionEnabled)
    $modelConfig = [pscustomobject]@{
        name=$alias
        reasoning=[bool]$Profile.reasoningEnabled
        attachment=$visionEnabled
        modalities=[pscustomobject]@{ input=@('text') + $(if ($visionEnabled) { @('image') } else { @() }); output=@('text') }
        interleaved=[pscustomobject]@{ field='reasoning_content' }
        limit=[pscustomobject]@{ context=[int]$Profile.context; output=[int]$Profile.openCodeOutput }
    }
    $models = $config.provider.beellama.models
    $existing = $models.PSObject.Properties[$alias]
    if ($existing) { $existing.Value = $modelConfig } else { $models | Add-Member -NotePropertyName $alias -NotePropertyValue $modelConfig }
    if ($config.agent -and $config.agent.build) {
        Set-BeeJsonProperty $config.agent.build 'model' "beellama/$alias"
        Set-BeeJsonProperty $config.agent.build 'temperature' ([double]$Profile.temperature)
        Set-BeeJsonProperty $config.agent.build 'top_p' ([double]$Profile.topP)
        Set-BeeJsonProperty $config.agent.build 'top_k' ([int]$Profile.topK)
    }
    if ($config.agent) {
        foreach ($agentName in @('team-lead','operator','web-operator','browser-debug','github','research','docker')) {
            $agentProperty = $config.agent.PSObject.Properties[$agentName]
            if ($agentProperty -and $agentProperty.Value) { Set-BeeJsonProperty $agentProperty.Value 'model' "beellama/$alias" }
        }
    }
    if (-not $config.command) { Set-BeeJsonProperty $config 'command' ([pscustomobject]@{}) }
    $plan = [pscustomobject]@{
        template='Составь подробный пошаговый план для следующей задачи: $ARGUMENTS. Сначала исследуй проект и ограничения, затем опиши этапы, риски, проверки и критерии готовности. На этом этапе ничего не изменяй и не запускай команды, которые меняют файлы.'
        description='Исследовать задачу и составить план без внесения изменений'
        agent='plan'
    }
    Set-BeeJsonProperty $config.command 'plan' $plan
    $temp = "$path.tmp"
    # A BOM makes Windows editors consistently recognize Russian text as UTF-8.
    # Use .NET instead of Set-Content because its UTF-8 BOM behavior differs
    # between Windows PowerShell 5.1 and newer PowerShell versions.
    $json = $config | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $temp -Destination $path -Force
    return [pscustomobject]@{Updated=$true;Message="OpenCode updated: beellama/$alias";Backup=$backupPath}
}

function Test-BeeRunningProfileMatch([Parameter(Mandatory=$true)]$Profile) {
    $status = Get-BeeServerStatus
    if (-not $status.Ready -or -not (Test-Path -LiteralPath $script:RunPath)) { return $false }
    try {
        $run = Get-Content -Raw -LiteralPath $script:RunPath | ConvertFrom-Json
        return ($run.profileId -eq $Profile.id -and
            [IO.Path]::GetFullPath([string]$run.modelPath) -eq [IO.Path]::GetFullPath([string]$Profile.modelPath) -and
            [string]$run.alias -eq [string]$Profile.alias -and
            [int]$run.context -eq [int]$Profile.context -and
            [bool]$run.visionEnabled -eq [bool]($Profile.PSObject.Properties['visionEnabled'] -and $Profile.visionEnabled) -and
            [bool]$run.visionOffload -eq [bool]($Profile.PSObject.Properties['visionOffload'] -and $Profile.visionOffload) -and
            [string]$run.mmprojPath -eq [string]$(if ($Profile.PSObject.Properties['mmprojPath']) { $Profile.mmprojPath } else { '' }) -and
            [int]$run.port -eq [int]$Profile.port)
    } catch { return $false }
}

function Start-BeeServer([string]$ProfileId) {
    Initialize-BeeFolders
    $profile = Get-BeeProfile $ProfileId
    $validation = Test-BeeProfile $profile
    if (-not $validation.Valid) { throw ($validation.Errors -join [Environment]::NewLine) }
    Stop-BeeBenchmark | Out-Null
    Stop-BeeServer | Out-Null
    $portReady = $false
    for ($portAttempt = 0; $portAttempt -lt 20; $portAttempt++) {
        if (Test-BeePortAvailable ([string]$profile.host) ([int]$profile.port)) { $portReady = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $portReady) { throw "Port $($profile.port) is already in use" }
    Clear-BeeRuntimeLogs
    $arguments = @(Get-BeeArguments $profile)
    $argumentLine = ConvertTo-BeeArgumentLine $arguments
    $process = Start-Process -FilePath $profile.serverPath -ArgumentList $argumentLine -RedirectStandardOutput $script:StdoutPath -RedirectStandardError $script:StderrPath -PassThru -WindowStyle Hidden
    Set-Content -LiteralPath $script:PidPath -Value $process.Id -Encoding ASCII
    [pscustomobject]@{ profileId=$profile.id; profileName=$profile.name; alias=$profile.alias; modelPath=$profile.modelPath; serverPath=$profile.serverPath; context=$profile.context; visionEnabled=[bool]($profile.PSObject.Properties['visionEnabled'] -and $profile.visionEnabled); visionOffload=[bool]($profile.PSObject.Properties['visionOffload'] -and $profile.visionOffload); mmprojPath=[string]$(if ($profile.PSObject.Properties['mmprojPath']) { $profile.mmprojPath } else { '' }); host=$profile.host; port=$profile.port; pid=$process.Id; startedAt=(Get-Date).ToString('o') } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:RunPath -Encoding UTF8
    $ready = $false
    for ($attempt=0; $attempt -lt 60; $attempt++) {
        if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) { break }
        try { $health = Invoke-RestMethod "http://$($profile.host):$($profile.port)/health" -TimeoutSec 2; if ($health) { $ready=$true; break } } catch {}
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $process.Id -Force }
        Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue
        $tail = if (Test-Path -LiteralPath $script:StderrPath) { (Get-Content -LiteralPath $script:StderrPath -Tail 30) -join [Environment]::NewLine } else { 'No error log was produced' }
        throw "BeeLlama did not become ready within 120 seconds.`n$tail"
    }
    Update-BeeOpenCode $profile | Out-Null
    $store = Get-BeeProfileStore
    $store.activeProfileId = $profile.id
    $store.lastGoodProfileId = $profile.id
    Save-BeeProfileStore $store
    return Get-BeeServerStatus
}

function Stop-BeeBenchmark {
    Initialize-BeeFolders
    if (-not (Test-Path -LiteralPath $script:BenchmarkPidPath)) { return [pscustomobject]@{Stopped=$false;Message='No benchmark is running'} }
    $testPid = 0
    if (-not [int]::TryParse((Get-Content -Raw -LiteralPath $script:BenchmarkPidPath).Trim(),[ref]$testPid)) {
        Remove-Item -LiteralPath $script:BenchmarkPidPath -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{Stopped=$false;Message='Removed invalid benchmark PID file'}
    }
    $process = Get-Process -Id $testPid -ErrorAction SilentlyContinue
    if ($process) {
        $commandLine = ''
        try { $commandLine = [string](Get-CimInstance Win32_Process -Filter "ProcessId=$testPid").CommandLine } catch {}
        $workerPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'run-benchmark.ps1'))
        if ([IO.Path]::GetFileName([string]$process.Path) -ne 'powershell.exe' -or $commandLine -notlike "*$workerPath*") {
            throw "PID $testPid is not the managed BeeLlama benchmark; refusing to stop it"
        }
        Stop-Process -Id $testPid -Force
        try { Wait-Process -Id $testPid -Timeout 5 -ErrorAction SilentlyContinue } catch {}
    }
    Remove-Item -LiteralPath $script:BenchmarkPidPath -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{state='Stopped';message='Test stopped by user';finishedAt=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $script:BenchmarkStatusPath -Encoding UTF8
    return [pscustomobject]@{Stopped=$true;Message='Benchmark stopped'}
}

function Start-BeeBenchmark([string]$ProfileId,[int]$PromptTokens=4096,[int]$OutputTokens=256,[int]$TimeoutSec=900) {
    Initialize-BeeFolders
    $profile = Get-BeeProfile $ProfileId
    $server = Get-BeeServerStatus
    if (-not $server.Ready) { throw 'BeeLlama server is not ready. Start the selected profile first.' }
    if (Test-Path -LiteralPath $script:RunPath) {
        $activeRun = $null
        try { $activeRun = Get-Content -Raw -LiteralPath $script:RunPath | ConvertFrom-Json } catch {}
        if (-not $activeRun -or $activeRun.profileId -ne $profile.id) { throw 'The selected profile is not the running server profile. Enable apply/restart before the test.' }
    }
    if ($PromptTokens -lt 256) { throw 'Benchmark prompt must be at least 256 tokens' }
    if ($OutputTokens -lt 16 -or $OutputTokens -gt 4096) { throw 'Benchmark output must be between 16 and 4096 tokens' }
    $safeInput = [int]$profile.context - $OutputTokens - 256
    if (($PromptTokens + $OutputTokens + 256) -gt [int]$profile.context) { throw "Benchmark input $PromptTokens plus output $OutputTokens does not fit context $($profile.context). Maximum safe input is $safeInput." }
    if ($TimeoutSec -lt 30 -or $TimeoutSec -gt 3600) { throw 'Benchmark timeout must be between 30 and 3600 seconds' }
    Stop-BeeBenchmark | Out-Null
    Remove-Item -LiteralPath $script:BenchmarkStatusPath,$script:BenchmarkResultPath -Force -ErrorAction SilentlyContinue
    $worker = Join-Path $PSScriptRoot 'run-benchmark.ps1'
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$worker,'-ProfileId',[string]$profile.id,'-PromptTokens',[string]$PromptTokens,'-OutputTokens',[string]$OutputTokens,'-TimeoutSec',[string]$TimeoutSec)
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList (ConvertTo-BeeArgumentLine $arguments) -PassThru -WindowStyle Hidden
    Set-Content -LiteralPath $script:BenchmarkPidPath -Value $process.Id -Encoding ASCII
    return [pscustomobject]@{Started=$true;Pid=$process.Id;PromptTokens=$PromptTokens;OutputTokens=$OutputTokens;Message='Benchmark started'}
}

function Get-BeeBenchmarkStatus {
    Initialize-BeeFolders
    $data = $null
    if (Test-Path -LiteralPath $script:BenchmarkStatusPath) { try { $data=Get-Content -Raw -LiteralPath $script:BenchmarkStatusPath|ConvertFrom-Json } catch {} }
    if (-not $data) { $data=[pscustomobject]@{state='Idle';message='No benchmark results yet'} }
    foreach ($field in @('startedAt','finishedAt','elapsedSec','targetPromptTokens','targetOutputTokens','promptTokens','outputTokens','promptTps','decodeTps','finishReason','contentPreview')) {
        if (-not $data.PSObject.Properties[$field]) { $data | Add-Member -NotePropertyName $field -NotePropertyValue $null }
    }
    $running = $false
    if (Test-Path -LiteralPath $script:BenchmarkPidPath) {
        $testPid=0
        if ([int]::TryParse((Get-Content -Raw -LiteralPath $script:BenchmarkPidPath).Trim(),[ref]$testPid)) { $running=[bool](Get-Process -Id $testPid -ErrorAction SilentlyContinue) }
    }
    $data | Add-Member -NotePropertyName Running -NotePropertyValue $running -Force
    if ($running -and $data.startedAt) { try { $data | Add-Member -NotePropertyName elapsedSec -NotePropertyValue ([math]::Round(((Get-Date)-[datetime]$data.startedAt).TotalSeconds,1)) -Force } catch {} }
    return $data
}

function Get-BeeLatestTiming {
    $result = [ordered]@{ PromptTPS=$null; DecodeTPS=$null; PromptTokens=$null; DecodedTokens=$null }
    if (-not (Test-Path -LiteralPath $script:StderrPath)) { return [pscustomobject]$result }
    $lines = @(Get-Content -LiteralPath $script:StderrPath -Tail 300 -ErrorAction SilentlyContinue)
    foreach ($line in $lines) {
        if ($line -match 'prompt (?:eval time|processing).*?([0-9]+(?:\.[0-9]+)?) tokens per second') { $result.PromptTPS=[double]::Parse($matches[1],[Globalization.CultureInfo]::InvariantCulture) }
        if ($line -match 'prompt processing, n_tokens\s*=\s*(\d+)') { $result.PromptTokens=[int]$matches[1] }
        if ($line -match 'n_decoded\s*=\s*(\d+),\s*tg\s*=\s*([0-9]+(?:\.[0-9]+)?) t/s') { $result.DecodedTokens=[int]$matches[1]; $result.DecodeTPS=[double]::Parse($matches[2],[Globalization.CultureInfo]::InvariantCulture) }
        if ($line -match 'eval time\s*=.*?([0-9]+(?:\.[0-9]+)?) tokens per second' -and $line -notmatch 'prompt eval') { $result.DecodeTPS=[double]::Parse($matches[1],[Globalization.CultureInfo]::InvariantCulture) }
    }
    return [pscustomobject]$result
}

function Get-BeeServerStatus {
    Initialize-BeeFolders
    $status = [ordered]@{ Running=$false; Ready=$false; Pid=$null; Profile=''; Model=''; Context=$null; Uptime=''; VramUsedMiB=$null; VramTotalMiB=$null; GpuUtil=$null; RamUsedGiB=$null; RamTotalGiB=$null; RamAvailableGiB=$null; SharedVram='n/a'; PromptTPS=$null; DecodeTPS=$null; PromptTokens=$null; DecodedTokens=$null; Message='Stopped' }
    $run = $null
    if (Test-Path -LiteralPath $script:RunPath) {
        try { $run = Get-Content -Raw -LiteralPath $script:RunPath | ConvertFrom-Json; $status.Profile=$run.profileName; $status.Model=[IO.Path]::GetFileName($run.modelPath); $status.Context=$run.context } catch {}
    }
    if (Test-Path -LiteralPath $script:PidPath) {
        $serverId=0
        if ([int]::TryParse((Get-Content -Raw -LiteralPath $script:PidPath).Trim(),[ref]$serverId)) {
            $process=Get-Process -Id $serverId -ErrorAction SilentlyContinue
            $actualPath = $null
            if ($process) { try { $actualPath = [IO.Path]::GetFullPath($process.Path) } catch {} }
            if ($process -and $actualPath -and (Get-BeeAllowedServerPaths) -contains $actualPath) {
                $status.Running=$true; $status.Pid=$serverId; $status.Uptime=((Get-Date)-$process.StartTime).ToString('hh\:mm\:ss'); $status.Message='Running'
                try { if ($run -and (Invoke-RestMethod "http://$($run.host):$($run.port)/health" -TimeoutSec 1)) { $status.Ready=$true; $status.Message='Ready' } } catch {}
            }
        }
    }
    try {
        $gpu = (& nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1) -split ','
        $status.VramUsedMiB=[int]$gpu[0].Trim(); $status.VramTotalMiB=[int]$gpu[1].Trim(); $status.GpuUtil=[int]$gpu[2].Trim()
    } catch {}
    try { $os=Get-CimInstance Win32_OperatingSystem; $status.RamUsedGiB=[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB),1); $status.RamTotalGiB=[math]::Round(($os.TotalVisibleMemorySize/1MB),1); $status.RamAvailableGiB=[math]::Round(($os.FreePhysicalMemory/1MB),1) } catch {}
    if ($status.Running) {
        $timing=Get-BeeLatestTiming
        $status.PromptTPS=$timing.PromptTPS; $status.DecodeTPS=$timing.DecodeTPS; $status.PromptTokens=$timing.PromptTokens; $status.DecodedTokens=$timing.DecodedTokens
    }
    return [pscustomobject]$status
}

function Open-BeeLiveLog {
    $watcher = Join-Path $PSScriptRoot 'watch-qwen38-performance.ps1'
    $profile = ''
    if (Test-Path -LiteralPath $script:RunPath) { try { $profile=(Get-Content -Raw -LiteralPath $script:RunPath | ConvertFrom-Json).profileName } catch {} }
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$watcher,'-ProfileName',$profile)
    Start-Process -FilePath 'powershell.exe' -ArgumentList (ConvertTo-BeeArgumentLine $arguments) -WindowStyle Normal | Out-Null
}

Export-ModuleMember -Function Initialize-BeeFolders,Invoke-BeeRetention,Get-BeeRoot,Get-BeeLogPaths,Get-BeeProfileStore,Save-BeeProfileStore,Get-BeeNewProfileTemplate,Get-BeeProfile,Get-BeeModelFiles,Get-BeeVisionProjectorFiles,Get-BeeSupportedHelp,Test-BeeProfile,Get-BeeArguments,Get-BeeCommandPreview,Start-BeeServer,Stop-BeeServer,Get-BeeServerStatus,Open-BeeLiveLog,Update-BeeOpenCode,Test-BeeRunningProfileMatch,Start-BeeBenchmark,Stop-BeeBenchmark,Get-BeeBenchmarkStatus
