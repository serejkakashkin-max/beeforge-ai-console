Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RequiredMemories = @('core','tech_stack','suggested_commands','conventions','task_completion')

function Get-BeeSerenaMemoryPaths {
    $root = Split-Path $PSScriptRoot -Parent
    [pscustomobject]@{
        Root = $root
        Policy = $(if($env:BEEFORGE_SERENA_MEMORY_POLICY_PATH){$env:BEEFORGE_SERENA_MEMORY_POLICY_PATH}else{Join-Path $root 'runtime\serena-memory.json'})
        SerenaConfig = $(if($env:BEEFORGE_SERENA_CONFIG_PATH){$env:BEEFORGE_SERENA_CONFIG_PATH}else{Join-Path $env:USERPROFILE '.serena\serena_config.yml'})
        TelegramConfig = $(if($env:BEEFORGE_TELEGRAM_CONFIG_PATH){$env:BEEFORGE_TELEGRAM_CONFIG_PATH}else{Join-Path $root 'config\telegram.json'})
        OpenCodeData = $(if($env:BEEFORGE_OPENCODE_GLOBAL_DATA){$env:BEEFORGE_OPENCODE_GLOBAL_DATA}else{Join-Path $env:APPDATA 'ai.opencode.desktop\opencode.global.dat'})
        SerenaExe = $(if($env:BEEFORGE_SERENA_EXE){$env:BEEFORGE_SERENA_EXE}else{Join-Path $root 'tools\serena\v1.7.0\.venv\Scripts\serena.exe'})
        EnsureScript = $(if($env:BEEFORGE_SERENA_ENSURE_SCRIPT){$env:BEEFORGE_SERENA_ENSURE_SCRIPT}else{Join-Path $root 'tools\serena\v1.7.0\ensure-project-language.ps1'})
    }
}

function Get-BeeCanonicalProjectPath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path)){return $null}
    try { return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\') } catch { return $null }
}

function Test-BeeSafeProjectPath([string]$Path) {
    $full=Get-BeeCanonicalProjectPath $Path
    if(-not$full -or -not(Test-Path -LiteralPath $full -PathType Container)){return $false}
    $root=[IO.Path]::GetPathRoot($full).TrimEnd('\')
    if($full.TrimEnd('\') -eq $root){return $false}
    $blocked=@($env:WINDIR,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData)|Where-Object{$_}|ForEach-Object{(Get-BeeCanonicalProjectPath $_).ToLowerInvariant()}
    return $full.ToLowerInvariant() -notin $blocked
}

function Get-BeeSerenaMemoryPolicy {
    $path=(Get-BeeSerenaMemoryPaths).Policy
    if(Test-Path -LiteralPath $path -PathType Leaf){
        try {$policy=[IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json} catch {throw "Некорректный файл политики памяти Serena: $($_.Exception.Message)"}
    } else {$policy=[pscustomobject]@{version=2;enabled=$true;autoEnableAllProjects=$true}}
    if($null-eq$policy.PSObject.Properties['enabled']){$policy|Add-Member NoteProperty enabled $true}
    if($null-eq$policy.PSObject.Properties['autoEnableAllProjects']){$policy|Add-Member NoteProperty autoEnableAllProjects $true}
    return $policy
}

function Save-BeeSerenaMemoryPolicy($Policy) {
    $path=(Get-BeeSerenaMemoryPaths).Policy
    $dir=Split-Path $path -Parent;if($dir){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($tmp,($Policy|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Invoke-BeeSerenaCli([string[]]$Arguments) {
    $exe=(Get-BeeSerenaMemoryPaths).SerenaExe
    $previous=$env:PYTHONIOENCODING
    try {
        $env:PYTHONIOENCODING='utf-8'
        $null=& $exe @Arguments
        return $LASTEXITCODE
    } finally {
        if($null-eq$previous){Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue}else{$env:PYTHONIOENCODING=$previous}
    }
}

function Get-BeeSerenaRegisteredProjects {
    $path=(Get-BeeSerenaMemoryPaths).SerenaConfig
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    $lines=[IO.File]::ReadAllLines($path,[Text.UTF8Encoding]::new($false));$in=$false;$result=@()
    foreach($line in $lines){
        if($line -match '^projects:\s*$'){$in=$true;continue}
        if($in -and $line -match '^\s*-\s*(.+?)\s*$'){$result+=($matches[1].Trim('"',''''))}
        elseif($in -and $line -match '^\S') {break}
    }
    return @($result)
}

function Register-BeeSerenaProject([string]$ProjectPath) {
    $config=(Get-BeeSerenaMemoryPaths).SerenaConfig
    if(-not(Test-Path -LiteralPath $config -PathType Leaf)){return}
    $full=Get-BeeCanonicalProjectPath $ProjectPath
    if($full -in @(Get-BeeSerenaRegisteredProjects|ForEach-Object{Get-BeeCanonicalProjectPath $_})){return}
    $lines=[Collections.Generic.List[string]]::new();$lines.AddRange([IO.File]::ReadAllLines($config,[Text.UTF8Encoding]::new($false)))
    $projects=-1;for($i=0;$i-lt$lines.Count;$i++){if($lines[$i]-match'^projects:\s*$'){$projects=$i;break}}
    if($projects-lt0){$lines.Add('');$lines.Add('projects:');$lines.Add("- $full")}
    else {$insert=$projects+1;while($insert-lt$lines.Count-and$lines[$insert]-match'^\s*-\s*'){$insert++};$lines.Insert($insert,"- $full")}
    [IO.File]::WriteAllLines($config,$lines,[Text.UTF8Encoding]::new($false))
}

function Get-BeeOpenCodeProjects {
    $path=(Get-BeeSerenaMemoryPaths).OpenCodeData
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    try {
        $data=[IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
        $server=$data.server;if($server -is [string]){$server=$server|ConvertFrom-Json}
        return @($server.projects.local|ForEach-Object{$_.worktree}|Where-Object{$_})
    } catch {return @()}
}

function Get-BeeTelegramProjects {
    $path=(Get-BeeSerenaMemoryPaths).TelegramConfig
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    try {$data=[IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;return @($data.allowedProjects|Where-Object{$_})}catch{return @()}
}

function Get-BeeSerenaMemoryStatus([string]$ProjectPath) {
    $full=Get-BeeCanonicalProjectPath $ProjectPath
    $memoryDir=Join-Path $full '.serena\memories'
    $existing=@();if(Test-Path -LiteralPath $memoryDir){$existing=@(Get-ChildItem -LiteralPath $memoryDir -File -Filter '*.md'|ForEach-Object{$_.BaseName})}
    $required=@($script:RequiredMemories);$present=@($required|Where-Object{$_ -in $existing});$missing=@($required|Where-Object{$_ -notin $existing})
    $verified=@();$needsReview=@()
    foreach($name in $present){
        $memoryFile=Join-Path $memoryDir "$name.md"
        $content=[IO.File]::ReadAllText($memoryFile,[Text.UTF8Encoding]::new($false))
        $hasDate=$content-match'(?im)^\s*-\s*Last verified:\s*\d{4}-\d{2}-\d{2}\s*$'
        $hasScope=$content-match'(?im)^\s*-\s*Scope:\s*\S.+'
        $hasEvidence=$content-match'(?im)^\s*-\s*Evidence:\s*\S.+'
        if($hasDate-and$hasScope-and$hasEvidence){$verified+=$name}else{$needsReview+=$name}
    }
    $config=Join-Path $full '.serena\project.yml';$readOnly=$null
    if(Test-Path -LiteralPath $config){$match=Select-String -LiteralPath $config -Pattern '^read_only:\s*(true|false)'|Select-Object -First 1;if($match){$readOnly=$match.Matches[0].Groups[1].Value-eq'true'}}
    $status=if(-not(Test-Path -LiteralPath $config)){'UNCONFIGURED'}elseif($missing.Count-eq 0){'READY'}elseif($present.Count-gt 0){'PARTIAL'}else{'NEEDS_ONBOARDING'}
    $quality=if($present.Count-eq 0){'NO_DATA'}elseif($needsReview.Count-eq 0){'VERIFIED'}else{'NEEDS_REVIEW'}
    [pscustomobject]@{Path=$full;Managed=(Test-Path -LiteralPath $config);ReadOnly=$readOnly;Status=$status;Quality=$quality;MemoryCount=$existing.Count;Present=$present;Missing=$missing;Verified=$verified;NeedsReview=$needsReview;MemoryDirectory=$memoryDir}
}

function Set-BeeSerenaProjectConfigMode([string]$ProjectPath,[bool]$Managed) {
    $file=Join-Path $ProjectPath '.serena\project.yml';if(-not(Test-Path -LiteralPath $file)){throw "Serena не настроена для проекта: $ProjectPath"}
    $lines=[Collections.Generic.List[string]]::new();$lines.AddRange([IO.File]::ReadAllLines($file,[Text.UTF8Encoding]::new($false)))
    $value=$(if($Managed){'false'}else{'true'});$found=$false
    for($i=0;$i-lt$lines.Count;$i++){if($lines[$i]-match '^read_only:'){$lines[$i]="read_only: $value";$found=$true;break}}
    if(-not$found){$lines.Add("read_only: $value")}
    $prompt='BeeForge project: use durable Serena memories for every activated project; read memory_maintenance first; never store secrets or transient task logs.'
    $escaped=$prompt.Replace('"','\"');$found=$false
    for($i=0;$i-lt$lines.Count;$i++){if($lines[$i]-match '^initial_prompt:'){$lines[$i]="initial_prompt: `"$escaped`"";$found=$true;$next=$i+1;while($next-lt$lines.Count-and$lines[$next]-match'^\s+\S'-and$lines[$next]-notmatch'^\s*#'){$lines.RemoveAt($next)};break}}
    if(-not$found){$lines.Add("initial_prompt: `"$escaped`"")}
    [IO.File]::WriteAllLines($file,$lines,[Text.UTF8Encoding]::new($false))
}

function Enable-BeeSerenaProjectMemory {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectPath)
    $full=Get-BeeCanonicalProjectPath $ProjectPath;if(-not(Test-BeeSafeProjectPath $full)){throw "Недопустимый или отсутствующий каталог проекта: $ProjectPath"}
    $paths=Get-BeeSerenaMemoryPaths
    if(Test-Path -LiteralPath $paths.EnsureScript -PathType Leaf){& $paths.EnsureScript -ProjectPath $full|Out-Null}
    if(-not(Test-Path -LiteralPath (Join-Path $full '.serena\project.yml'))){if((Invoke-BeeSerenaCli @('project','create',$full))-ne0){throw 'Serena не смогла создать конфигурацию проекта'}}
    Set-BeeSerenaProjectConfigMode $full $true
    Register-BeeSerenaProject $full
    $policy=Get-BeeSerenaMemoryPolicy;$policy.version=2;$policy.autoEnableAllProjects=$true
    if($policy.PSObject.Properties['managedProjects']){$policy.PSObject.Properties.Remove('managedProjects')}
    if($policy.PSObject.Properties['defaultExternalMode']){$policy.PSObject.Properties.Remove('defaultExternalMode')}
    Save-BeeSerenaMemoryPolicy $policy
    if((Invoke-BeeSerenaCli @('memories','initialize',$full))-ne0){throw 'Не удалось инициализировать memory_maintenance Serena'}
    return Get-BeeSerenaMemoryStatus $full
}

function Get-BeeSerenaMemoryProjects {
    $policy=Get-BeeSerenaMemoryPolicy;$sources=@{}
    foreach($pair in @(@('Serena',@(Get-BeeSerenaRegisteredProjects)),@('OpenCode',@(Get-BeeOpenCodeProjects)),@('Telegram',@(Get-BeeTelegramProjects)))){
        foreach($raw in $pair[1]){$path=Get-BeeCanonicalProjectPath $raw;if(-not$path){continue};if(-not$sources.ContainsKey($path)){$sources[$path]=[Collections.Generic.List[string]]::new()};if($pair[0]-notin$sources[$path]){$sources[$path].Add($pair[0])}}
    }
    return @($sources.Keys|Sort-Object|ForEach-Object{$s=Get-BeeSerenaMemoryStatus $_;[pscustomobject]@{Name=[IO.Path]::GetFileName($_);Path=$_;Sources=($sources[$_]-join ', ');Mode='Постоянная';Memories="$($s.Present.Count)/$($script:RequiredMemories.Count)";Quality="$($s.Verified.Count)/$($s.Present.Count)";Status=$s.Status;Missing=($s.Missing-join ', ');NeedsReview=($s.NeedsReview-join ', ')}})
}

function Test-BeeSerenaProjectMemories {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ProjectPath)
    $full=Get-BeeCanonicalProjectPath $ProjectPath;$paths=Get-BeeSerenaMemoryPaths
    if((Invoke-BeeSerenaCli @('memories','check',$full))-ne0){throw 'Команда проверки памяти Serena завершилась с ошибкой'}
    return Get-BeeSerenaMemoryStatus $full
}

Export-ModuleMember -Function Get-BeeSerenaMemoryPaths,Get-BeeSerenaMemoryPolicy,Get-BeeSerenaMemoryProjects,Get-BeeSerenaMemoryStatus,Enable-BeeSerenaProjectMemory,Test-BeeSerenaProjectMemories
