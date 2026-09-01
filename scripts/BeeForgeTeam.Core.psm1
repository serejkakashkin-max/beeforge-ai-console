Set-StrictMode -Version 2.0

$script:TeamRoot = Split-Path $PSScriptRoot -Parent
$script:TeamProfileStorePath = Join-Path $script:TeamRoot 'config\profiles.json'
$script:TeamBackupDir = Join-Path $script:TeamRoot 'backups'
$script:TeamLogDir = Join-Path $script:TeamRoot 'logs'
$script:McpTestPidPath = Join-Path $script:TeamLogDir 'mcp-test.pid'
$script:McpChildPidPath = Join-Path $script:TeamLogDir 'mcp-test.child.pid'
$script:McpTestStatusPath = Join-Path $script:TeamLogDir 'mcp-test.status.json'
$script:McpTestLogPath = Join-Path $script:TeamLogDir 'mcp-test.log'
$script:FullAccessStateDir = Join-Path $script:TeamRoot 'runtime\access'
$script:FullAccessStatePath = Join-Path $script:FullAccessStateDir 'full-access.json'
$script:FullAccessAuditPath = Join-Path $script:TeamLogDir 'full-access.log'

function Read-BeeUtf8Json([Parameter(Mandatory=$true)][string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
    return ([IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false)) | ConvertFrom-Json)
}

function Get-BeeTeamConfigPath {
    $store = Read-BeeUtf8Json $script:TeamProfileStorePath
    $path = [string]$store.openCodeConfigPath
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'openCodeConfigPath is missing from profiles.json' }
    return [IO.Path]::GetFullPath($path)
}

function Get-BeeTeamPaths {
    [pscustomobject]@{
        Config=(Get-BeeTeamConfigPath); Skills=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agents\skills')
        Backups=$script:TeamBackupDir; TestPid=$script:McpTestPidPath; TestChildPid=$script:McpChildPidPath
        TestStatus=$script:McpTestStatusPath; TestLog=$script:McpTestLogPath
    }
}

function Set-BeeObjectProperty($Object,[string]$Name,$Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name=$Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Remove-BeeObjectProperty($Object,[string]$Name) {
    if ($Object -and $Object.PSObject.Properties[$Name]) { $Object.PSObject.Properties.Remove($Name) }
}

function Get-BeeObjectProperty($Object,[string]$Name,$Default=$null) {
    if($Object -and $Object.PSObject.Properties[$Name]){return $Object.PSObject.Properties[$Name].Value}
    return $Default
}

function Get-BeeSkillMetadata([string]$Path,[string]$FallbackName) {
    $result=[ordered]@{Name=$FallbackName;Description='';Valid=$false;Error='SKILL.md отсутствует'}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]$result }
    try {
        $lines=@([IO.File]::ReadAllLines($Path,[Text.UTF8Encoding]::new($false)))
        if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') { throw 'нет YAML frontmatter' }
        $end=-1
        for($i=1;$i-lt$lines.Count;$i++){if($lines[$i].Trim()-eq'---'){$end=$i;break}}
        if($end-lt2){throw 'frontmatter не закрыт'}
        for($i=1;$i-lt$end;$i++){
            if($lines[$i]-match '^name:\s*["'']?(.*?)["'']?\s*$'){$result.Name=$matches[1].Trim()}
            if($lines[$i]-match '^description:\s*(.*)$'){
                $value=$matches[1].Trim().Trim('"').Trim("'")
                if($value -in @('>-','>','|-','|')){
                    $parts=New-Object System.Collections.Generic.List[string]
                    for($j=$i+1;$j-lt$end;$j++){
                        if($lines[$j]-match '^\S'){break}
                        $part=$lines[$j].Trim();if($part){$parts.Add($part)}
                    }
                    $value=$parts -join ' '
                }
                $result.Description=$value
            }
        }
        if([string]::IsNullOrWhiteSpace($result.Name)){throw 'name отсутствует'}
        $result.Valid=$true;$result.Error=''
    } catch {$result.Error=$_.Exception.Message}
    return [pscustomobject]$result
}

function Get-BeeSkillCatalog {
    $root=(Get-BeeTeamPaths).Skills
    if(-not(Test-Path -LiteralPath $root -PathType Container)){return @()}
    $localizedDescriptions=@{
        'find-docs'='Находит актуальную официальную документацию, справочники API и примеры кода для библиотек, фреймворков, SDK, CLI и облачных сервисов.'
        'opencode-appsec-review'='Проводит анализ безопасности исходного кода, конфигурации, зависимостей, API и веб-сценариев с учётом авторизации и границ доступа.'
        'opencode-browser-qa'='Проверяет веб-приложение через браузерный MCP, собирает воспроизводимые доказательства и выполняет E2E-диагностику.'
        'opencode-docker-compose-ops'='Проверяет Docker и Compose и выполняет разрешённые операции сборки и жизненного цикла с обязательным подтверждением.'
        'opencode-github-change-control'='Работает с GitHub: репозиториями, issues, pull requests, Actions, релизами и метаданными; перед удалёнными изменениями запрашивает подтверждение.'
        'opencode-quality-engineering'='Проектирует и выполняет модульные, интеграционные, регрессионные и браузерные тесты на основе рисков, предоставляя воспроизводимые результаты.'
        'opencode-research-decision'='Сравнивает технические варианты и готовит обоснованное архитектурное решение с явно указанными предположениями и компромиссами.'
        'opencode-safe-implementation'='Реализует ограниченные изменения в текущем проекте, сохраняя чужие правки и подтверждая результат целевыми проверками.'
        'opencode-safe-operations'='Безопасно управляет локальным Windows-компьютером или SSH-хостом: ограничивает область действий, предпочитает обратимые операции и использует подтверждения.'
        'opencode-team-coordination'='Координирует сложную задачу и распределяет ограниченные подзадачи между установленными специалистами OpenCode.'
        'opencode-web-research'='Ищет актуальные публичные сведения в интернете и GitHub, проверяет источники, приводит URL и отделяет подтверждённые факты от неподтверждённых.'
        'diagnosing-bugs'='Системно диагностирует сложные ошибки и регрессии производительности: строит воспроизводимый тест, проверяет гипотезы и закрепляет исправление регрессионной проверкой.'
        'frontend-design'='Помогает проектировать выразительные и целостные интерфейсы с осмысленной типографикой, композицией, цветом, анимацией и адаптивностью.'
        'vercel-react-best-practices'='Применяет рекомендации Vercel по производительности React и Next.js: загрузка данных, размер bundle, рендеринг, кэширование и повторные отрисовки.'
        'web-design-guidelines'='Проверяет интерфейсы по актуальным рекомендациям Vercel для UX, доступности, визуальной целостности и поведения элементов.'
        'agent-security-audit'='Проверяет безопасность AI-агентов: полномочия, поверхности prompt injection, утечки данных, цепочки инструментов и защитные барьеры.'
        'mcp-server-review'='Проводит аудит MCP-серверов: транспорт, аутентификация, права инструментов, инъекции, утечки данных, sandboxing и supply chain.'
        'prompt-injection-test'='Выполняет только явно разрешённое тестирование AI-приложений на prompt injection по таксономии Arcanum и проверяет многоуровневую защиту.'
        'sca-audit'='Сканирует зависимости проекта на известные CVE, оценивает достижимость и контекст риска и предлагает точные обновления.'
    }
    return @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue|Where-Object{Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf}|Sort-Object Name|ForEach-Object{
        $skillPath=Join-Path $_.FullName 'SKILL.md';$meta=Get-BeeSkillMetadata $skillPath $_.Name
        $description=$(if($localizedDescriptions.ContainsKey($_.Name)){$localizedDescriptions[$_.Name]}else{$meta.Description})
        [pscustomobject]@{Id=$_.Name;Name=$meta.Name;Description=$description;SourceDescription=$meta.Description;Path=$skillPath;Valid=$meta.Valid;Error=$meta.Error;Status=$(if($meta.Valid){'AVAILABLE'}else{'INVALID'})}
    })
}

function Resolve-BeeExecutable([string]$Command) {
    if([string]::IsNullOrWhiteSpace($Command)){return $null}
    if([IO.Path]::IsPathRooted($Command)){return $(if(Test-Path -LiteralPath $Command -PathType Leaf){[IO.Path]::GetFullPath($Command)}else{$null})}
    $found=Get-Command $Command -ErrorAction SilentlyContinue|Select-Object -First 1
    return $(if($found){[string]$found.Source}else{$null})
}

function Get-BeeMcpCatalog($Config) {
    $items=New-Object System.Collections.Generic.List[object]
    $descriptions=@{
        'windows-ui'='Управление окнами и приложениями Windows через UI Automation.'
        'playwright'='Браузерные E2E-тесты и воспроизводимая автоматизация страниц.'
        'chrome-devtools'='Диагностика и управление Chrome через DevTools Protocol.'
        'github'='Репозитории, issues, pull requests, Actions и другие операции GitHub.'
        'docker-research'='Безопасное исследование Docker и Compose без жизненного цикла контейнеров.'
        'docker'='Операции Docker/Compose, включая сборку и управление жизненным циклом.'
        'serena'='Символьная навигация, анализ и точечное редактирование исходного кода.'
        'context7'='Актуальная документация библиотек и фреймворков с примерами API.'
    }
    if(-not$Config.mcp){return @()}
    foreach($property in @($Config.mcp.PSObject.Properties)){
        $id=[string]$property.Name;$m=$property.Value
        $command=@(Get-BeeObjectProperty $m 'command' @());$command0=$(if($command.Count){[string]$command[0]}else{''})
        $resolved=Resolve-BeeExecutable $command0
        $enabled=[bool](Get-BeeObjectProperty $m 'enabled' $true);$type=[string](Get-BeeObjectProperty $m 'type' '')
        $status=if(-not$enabled){'DISABLED'}elseif($type-ne'local'){'CONFIG ERROR'}elseif(-not$resolved){'MISSING'}else{'READY'}
        $environment=Get-BeeObjectProperty $m 'environment' $null;$environmentNames=if($environment){@($environment.PSObject.Properties.Name)}else{@()}
        $description=$(if($descriptions.ContainsKey($id)){$descriptions[$id]}else{'Локальный MCP-сервер OpenCode.'})
        $items.Add([pscustomobject]@{Id=$id;Description=$description;Type=$type;Enabled=$enabled;Command=$command0;Executable=$resolved;PathExists=[bool]$resolved;EnvironmentNames=($environmentNames-join ', ');Status=$status})
    }
    return @($items|ForEach-Object{$_})
}

function Test-BeeAgentMcpAssignment($Agent,[string]$McpId) {
    $permission=Get-BeeObjectProperty $Agent 'permission' $null
    if($permission){
        $rule=$permission.PSObject.Properties["$McpId*"]
        if($rule -and [string]$rule.Value -eq 'allow'){return $true}
    }
    # Backward-compatible read of legacy OpenCode configurations.
    $tools=Get-BeeObjectProperty $Agent 'tools' $null
    if($tools){
        $rule=$tools.PSObject.Properties["$McpId*"]
        if($rule -and [bool]$rule.Value){return $true}
    }
    return $false
}

function Get-BeeSerenaProjectWarnings {
    $warnings=New-Object System.Collections.Generic.List[string]
    $serenaRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.serena'
    $configPath=Join-Path $serenaRoot 'serena_config.yml'
    if(-not(Test-Path -LiteralPath $configPath)){return @($warnings)}
    try{
        $lines=@([IO.File]::ReadAllLines($configPath,[Text.UTF8Encoding]::new($false)))
        $projects=New-Object System.Collections.Generic.List[string]
        $insideProjects=$false
        foreach($line in $lines){
            if($line-match '^projects:\s*$'){$insideProjects=$true;continue}
            if(-not$insideProjects){continue}
            if($line-match '^\s*-\s+(.+?)\s*$'){$projects.Add($matches[1].Trim().Trim('"').Trim("'"));continue}
            if($line-match '^\S') {break}
        }
        foreach($projectPath in $projects){
            if(-not(Test-Path -LiteralPath $projectPath -PathType Container)){continue}
            $projectConfig=Join-Path $projectPath '.serena\project.yml'
            if(-not(Test-Path -LiteralPath $projectConfig)){continue}
            $projectText=[IO.File]::ReadAllText($projectConfig,[Text.UTF8Encoding]::new($false))
            if($projectText-notmatch'(?m)^language_servers:\s*\[\s*\]\s*$'){continue}
            $sourceFiles=New-Object System.Collections.Generic.List[object]
            foreach($candidateRoot in @($projectPath,(Join-Path $projectPath 'src'),(Join-Path $projectPath 'app'))|Select-Object -Unique){
                if(-not(Test-Path -LiteralPath $candidateRoot -PathType Container)){continue}
                $recurse=$candidateRoot-ne$projectPath
                foreach($file in @(Get-ChildItem -LiteralPath $candidateRoot -File -Recurse:$recurse -ErrorAction SilentlyContinue|Select-Object -First 200)){$sourceFiles.Add($file)}
            }
            $extensions=@($sourceFiles|ForEach-Object{$_.Extension.ToLowerInvariant()}|Select-Object -Unique)
            $detected=@()
            if($extensions|Where-Object{$_-in@('.ts','.tsx','.js','.jsx')}){$detected+='typescript'}
            if($extensions-contains'.py'){$detected+='python'}
            if($extensions|Where-Object{$_-in@('.cs','.csx')}){$detected+='csharp'}
            if($extensions|Where-Object{$_-in@('.ps1','.psm1')}){$detected+='powershell'}
            if($detected.Count){$warnings.Add("Serena: '$projectPath' содержит $($detected -join ', '), но language_servers пуст")}
        }
    }catch{$warnings.Add("Serena: не удалось проверить проекты — $($_.Exception.Message)")}
    return @($warnings)
}

function Get-BeeTeamSnapshot {
    $path=Get-BeeTeamConfigPath;$config=Read-BeeUtf8Json $path
    $skills=@(Get-BeeSkillCatalog);$skillMap=@{};foreach($skill in $skills){$skillMap[$skill.Id]=$skill}
    $mcps=@(Get-BeeMcpCatalog $config)
    $serenaWarnings=@(Get-BeeSerenaProjectWarnings)
    $models=@();if($config.provider -and $config.provider.beellama -and $config.provider.beellama.models){$models=@($config.provider.beellama.models.PSObject.Properties.Name|ForEach-Object{"beellama/$_"})}
    $lead=$(if($config.agent){$config.agent.PSObject.Properties['team-lead']}else{$null})
    # Stable display names must not depend on the locale/encoding of a dash in a
    # user-editable description. The map also keeps the navigation list compact.
    $roleNames=@{
        'team-lead'='Team Lead'
        'software-engineer'='Software Engineer'
        'qa-engineer'='Quality Engineer'
        'solution-architect'='Solution Architect'
        'systems-engineer'='Systems Engineer'
        'devops-engineer'='DevOps Engineer'
        'platform-engineer'='Platform Engineer'
        'security-engineer'='Application Security Engineer'
        'build'='build'
    }
    $agents=New-Object System.Collections.Generic.List[object]
    if($config.agent){
        foreach($property in @($config.agent.PSObject.Properties)){
            $id=[string]$property.Name;$agent=$property.Value
            $disabled=[bool]($agent.PSObject.Properties['disable'] -and $agent.disable)
            $mode=[string](Get-BeeObjectProperty $agent 'mode' '');$model=[string](Get-BeeObjectProperty $agent 'model' '');$description=[string](Get-BeeObjectProperty $agent 'description' '')
            $errors=New-Object System.Collections.Generic.List[string]
            if(-not$disabled -and $id-ne'build'){
                if([string]::IsNullOrWhiteSpace($description)){$errors.Add('нет описания')}
                if([string]::IsNullOrWhiteSpace($model)){$errors.Add('не выбрана модель')}
                if($mode -notin @('primary','subagent','all')){$errors.Add('недопустимый mode')}
            }
            $assignedSkills=@()
            $permission=Get-BeeObjectProperty $agent 'permission' $null;$skillRules=Get-BeeObjectProperty $permission 'skill' $null
            if($skillRules){$assignedSkills=@($skillRules.PSObject.Properties|Where-Object{$_.Name-ne'*'-and[string]$_.Value-eq'allow'}|ForEach-Object{$_.Name})}
            foreach($skillId in $assignedSkills){if(-not$skillMap.ContainsKey($skillId)-or-not$skillMap[$skillId].Valid){$errors.Add("skill недоступен: $skillId")}}
            $assignedMcps=@($mcps|Where-Object{Test-BeeAgentMcpAssignment $agent $_.Id}|ForEach-Object{$_.Id})
            $taskRules=Get-BeeObjectProperty $permission 'task' $null;$delegates=@();if($taskRules){$delegates=@($taskRules.PSObject.Properties|Where-Object{$_.Name-ne'*'-and[string]$_.Value-eq'allow'}|ForEach-Object{$_.Name})}
            $delegateAllowed=$false
            $leadPermission=$(if($lead){Get-BeeObjectProperty $lead.Value 'permission' $null}else{$null});$leadTasks=Get-BeeObjectProperty $leadPermission 'task' $null
            if($leadTasks){$rule=$leadTasks.PSObject.Properties[$id];$delegateAllowed=[bool]($rule-and[string]$rule.Value-eq'allow')}
            $permissionRules=@();if($permission){$permissionRules=@($permission.PSObject.Properties|Where-Object{$_.Name-notin@('skill','task')}|ForEach-Object{"$($_.Name): $($_.Value)"})}
            $status=if($disabled){'DISABLED'}elseif($errors.Count){'CONFIG ERROR'}elseif($mode-eq'primary'){'PRIMARY'}else{'ACTIVE'}
            $role=if($roleNames.ContainsKey($id)){
                $roleNames[$id]
            }elseif($description-match '^(.*?)\s*(?:\u2014|\u2013|-)\s+'){
                $matches[1].Trim()
            }elseif($description){
                $description
            }else{
                $id
            }
            $category=if($id-in@('team-lead','software-engineer','qa-engineer')){'Основная команда'}elseif($id-eq'build'){'Системные'}else{'Специалисты по вызову'}
            $priority=if($id-eq'team-lead'){0}elseif($id-eq'software-engineer'){1}elseif($id-eq'qa-engineer'){2}elseif($disabled){4}else{3}
            $agents.Add([pscustomobject]@{Id=$id;Role=$role;DisplayName="$role  [$status]";Category=$category;Description=$description;Mode=$mode;Model=$model;Prompt=[string](Get-BeeObjectProperty $agent 'prompt' '');Disabled=$disabled;Status=$status;Errors=($errors-join '; ');Skills=$assignedSkills;Mcps=$assignedMcps;Delegates=$delegates;DelegateAllowed=$delegateAllowed;Permissions=($permissionRules-join [Environment]::NewLine);Priority=$priority;CanDelete=($id-ne'build')})
        }
    }
    $ordered=@($agents|ForEach-Object{$_}|Sort-Object Priority,Role)
    [pscustomobject]@{ConfigPath=$path;LastWriteTime=(Get-Item -LiteralPath $path).LastWriteTime;Agents=$ordered;Skills=$skills;Mcps=$mcps;Models=$models;SerenaWarnings=$serenaWarnings;SerenaWarningCount=$serenaWarnings.Count;ActiveAgents=@($ordered|Where-Object{$_.Status-ne'DISABLED'}).Count;PrimaryAgents=@($ordered|Where-Object{$_.Status-eq'PRIMARY'}).Count;ErrorCount=@($ordered|Where-Object{$_.Status-eq'CONFIG ERROR'}).Count+@($skills|Where-Object{-not$_.Valid}).Count+@($mcps|Where-Object{$_.Status-in@('MISSING','CONFIG ERROR')}).Count}
}

function Backup-BeeTeamConfig([string]$Path,[string]$Reason='save') {
    if(-not(Test-Path -LiteralPath $script:TeamBackupDir)){New-Item -ItemType Directory -Path $script:TeamBackupDir -Force|Out-Null}
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmssfff';$backup=Join-Path $script:TeamBackupDir "opencode.team-manager-$stamp-$Reason.json"
    Copy-Item -LiteralPath $Path -Destination $backup
    $all=@(Get-ChildItem -LiteralPath $script:TeamBackupDir -File -Filter 'opencode.*.json'|Sort-Object LastWriteTime -Descending)
    for($i=10;$i-lt$all.Count;$i++){Remove-Item -LiteralPath $all[$i].FullName -Force}
    return $backup
}

function Write-BeeTeamConfig($Config,[string]$Reason='save') {
    $path=Get-BeeTeamConfigPath;[void](Backup-BeeTeamConfig $path $Reason)
    if($Reason-ne'full-access-disable'-and(Test-Path -LiteralPath $script:FullAccessStatePath -PathType Leaf)){
        try{
            $accessState=Read-BeeUtf8Json $script:FullAccessStatePath
            if([bool](Get-BeeObjectProperty $accessState 'enabled' $false)-and-not[bool](Get-BeeObjectProperty $accessState 'pending' $false)){
                $known=@{};foreach($snapshot in @($accessState.agents)){$known[[string]$snapshot.id]=$true}
                foreach($agentProperty in @($Config.agent.PSObject.Properties)){
                    if(-not$known.ContainsKey([string]$agentProperty.Name)){
                        $permissionExisted=[bool]$agentProperty.Value.PSObject.Properties['permission']
                        $permission=Get-BeeObjectProperty $agentProperty.Value 'permission' $null
                        $snapshot=[pscustomobject]@{id=[string]$agentProperty.Name;permissionExisted=$permissionExisted;permission=(Copy-BeeJsonValue $permission)}
                        Set-BeeObjectProperty $accessState 'agents' (@($accessState.agents)+@($snapshot));$known[[string]$agentProperty.Name]=$true
                    }
                }
                Set-BeeObjectProperty $Config 'permission' (New-BeeFullAccessPermission)
                foreach($agentProperty in @($Config.agent.PSObject.Properties)){Set-BeeObjectProperty $agentProperty.Value 'permission' (New-BeeFullAccessPermission)}
                Write-BeeFullAccessState $accessState
            }
        }catch{throw "Не удалось сохранить инвариант полного доступа: $($_.Exception.Message)"}
    }
    $temp="$path.tmp";$json=$Config|ConvertTo-Json -Depth 40
    [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($true))
    try{[void](Read-BeeUtf8Json $temp);Move-Item -LiteralPath $temp -Destination $path -Force}catch{Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue;throw}
    return $path
}

function Copy-BeeJsonValue($Value) {
    if($null-eq$Value){return $null}
    return ($Value|ConvertTo-Json -Depth 40|ConvertFrom-Json)
}

function Write-BeeFullAccessState($State) {
    if(-not(Test-Path -LiteralPath $script:FullAccessStateDir)){New-Item -ItemType Directory -Path $script:FullAccessStateDir -Force|Out-Null}
    $temp="$script:FullAccessStatePath.tmp";$json=$State|ConvertTo-Json -Depth 50
    [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($true))
    try{[void](Read-BeeUtf8Json $temp);Move-Item -LiteralPath $temp -Destination $script:FullAccessStatePath -Force}catch{Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue;throw}
}

function Write-BeeFullAccessAudit([string]$Action,[string]$Source,[bool]$Succeeded,[string]$Detail='') {
    if(-not(Test-Path -LiteralPath $script:TeamLogDir)){New-Item -ItemType Directory -Path $script:TeamLogDir -Force|Out-Null}
    $safeSource=(([string]$Source)-replace'[\r\n\t]',' ').Trim();if($safeSource.Length-gt120){$safeSource=$safeSource.Substring(0,120)}
    $safeDetail=(([string]$Detail)-replace'[\r\n\t]',' ').Trim();if($safeDetail.Length-gt500){$safeDetail=$safeDetail.Substring(0,500)}
    $line='{0}`t{1}`t{2}`t{3}`t{4}{5}' -f (Get-Date).ToString('o'),$Action,$Succeeded,$safeSource,$safeDetail,[Environment]::NewLine
    [IO.File]::AppendAllText($script:FullAccessAuditPath,$line,[Text.UTF8Encoding]::new($false))
}

function New-BeeFullAccessPermission {
    return [pscustomobject]@{'*'='allow'}
}

function Test-BeePermissionFullAccess($Permission) {
    if(-not$Permission){return $false}
    $rules=@($Permission.PSObject.Properties)
    return $rules.Count-eq1-and$rules[0].Name-eq'*'-and[string]$rules[0].Value-eq'allow'
}

function Get-BeeFullAccessStatus {
    $state=$null
    if(Test-Path -LiteralPath $script:FullAccessStatePath -PathType Leaf){try{$state=Read-BeeUtf8Json $script:FullAccessStatePath}catch{}}
    $config=Read-BeeUtf8Json (Get-BeeTeamConfigPath)
    $globalPermission=Get-BeeObjectProperty $config 'permission' $null
    $globalAllowed=Test-BeePermissionFullAccess $globalPermission
    $agents=@($config.agent.PSObject.Properties)
    $agentsAllowed=@($agents|Where-Object{Test-BeePermissionFullAccess (Get-BeeObjectProperty $_.Value 'permission' $null)}).Count
    $configured=$globalAllowed-and$agentsAllowed-eq$agents.Count
    $stateEnabled=[bool]($state-and$state.PSObject.Properties['enabled']-and$state.enabled)
    return [pscustomobject]@{
        Enabled=($stateEnabled-and$configured);Configured=$configured;Inconsistent=($stateEnabled-ne$configured)
        EnabledAt=$(if($state){[string](Get-BeeObjectProperty $state 'enabledAt' '')}else{''})
        Source=$(if($state){[string](Get-BeeObjectProperty $state 'source' '')}else{''})
        AgentCount=$agents.Count;ConfigPath=(Get-BeeTeamConfigPath);StatePath=$script:FullAccessStatePath
    }
}

function Set-BeeFullAccess([bool]$Enabled,[string]$Source='BeeForge AI Console') {
    $mutex=New-Object Threading.Mutex($false,'Global\BeeForgeFullAccessPolicy')
    $locked=$false
    try{
        $locked=$mutex.WaitOne([TimeSpan]::FromSeconds(15));if(-not$locked){throw 'Другой процесс уже изменяет режим полного доступа.'}
        $path=Get-BeeTeamConfigPath;$config=Read-BeeUtf8Json $path
        $existingState=$null;if(Test-Path -LiteralPath $script:FullAccessStatePath){try{$existingState=Read-BeeUtf8Json $script:FullAccessStatePath}catch{}}
        if($Enabled){
            $current=Get-BeeFullAccessStatus;if($current.Enabled){return $current}
            if($existingState-and[bool](Get-BeeObjectProperty $existingState 'enabled' $false)-and$existingState.PSObject.Properties['agents']){
                $state=$existingState
                $agentSnapshotCount=@($state.agents).Count
            }else{
                $globalExisted=[bool]$config.PSObject.Properties['permission']
                $agentSnapshots=New-Object System.Collections.Generic.List[object]
                foreach($agentProperty in @($config.agent.PSObject.Properties)){
                    $permissionExisted=[bool]$agentProperty.Value.PSObject.Properties['permission']
                    $permission=Get-BeeObjectProperty $agentProperty.Value 'permission' $null
                    $agentSnapshots.Add([pscustomobject]@{id=[string]$agentProperty.Name;permissionExisted=$permissionExisted;permission=(Copy-BeeJsonValue $permission)})
                }
                $agentSnapshotCount=$agentSnapshots.Count
                $state=[pscustomobject]@{version=2;enabled=$false;pending=$true;enabledAt=(Get-Date).ToString('o');source=$Source;globalPermissionExisted=$globalExisted;globalPermission=(Copy-BeeJsonValue (Get-BeeObjectProperty $config 'permission' $null));agents=$agentSnapshots.ToArray()}
            }
            Set-BeeObjectProperty $state 'version' 2;Set-BeeObjectProperty $state 'pending' $true;Set-BeeObjectProperty $state 'enabled' $false;Set-BeeObjectProperty $state 'source' $Source
            Write-BeeFullAccessState $state
            Set-BeeObjectProperty $config 'permission' (New-BeeFullAccessPermission)
            foreach($agentProperty in @($config.agent.PSObject.Properties)){
                Set-BeeObjectProperty $agentProperty.Value 'permission' (New-BeeFullAccessPermission)
            }
            [void](Write-BeeTeamConfig $config 'full-access-enable')
            $state.enabled=$true;$state.pending=$false;Write-BeeFullAccessState $state
            Write-BeeFullAccessAudit 'enable' $Source $true "agents=$agentSnapshotCount unrestricted=true"
        }else{
            if(-not$existingState-or-not$existingState.PSObject.Properties['agents']){
                $status=Get-BeeFullAccessStatus;if(-not$status.Configured){return $status}
                throw 'Не найден снимок обычных разрешений. Автоматическое выключение остановлено, чтобы не повредить пользовательские правила.'
            }
            if([bool]$existingState.globalPermissionExisted){Set-BeeObjectProperty $config 'permission' (Copy-BeeJsonValue $existingState.globalPermission)}else{Remove-BeeObjectProperty $config 'permission'}
            $known=@{}
            foreach($snapshot in @($existingState.agents)){
                $known[[string]$snapshot.id]=$true;$property=$config.agent.PSObject.Properties[[string]$snapshot.id];if(-not$property){continue}
                if([bool]$snapshot.permissionExisted){Set-BeeObjectProperty $property.Value 'permission' (Copy-BeeJsonValue $snapshot.permission)}else{Remove-BeeObjectProperty $property.Value 'permission'}
            }
            foreach($agentProperty in @($config.agent.PSObject.Properties)){
                if($known.ContainsKey([string]$agentProperty.Name)){continue}
                $permission=Get-BeeObjectProperty $agentProperty.Value 'permission' $null
                if($permission-and$permission.PSObject.Properties['*']-and[string]$permission.'*'-eq'allow'){Remove-BeeObjectProperty $permission '*'}
            }
            [void](Write-BeeTeamConfig $config 'full-access-disable')
            $existingState.enabled=$false;$existingState.pending=$false;Set-BeeObjectProperty $existingState 'disabledAt' (Get-Date).ToString('o');Set-BeeObjectProperty $existingState 'disabledBy' $Source;Write-BeeFullAccessState $existingState
            Write-BeeFullAccessAudit 'disable' $Source $true ''
        }
        return Get-BeeFullAccessStatus
    }catch{try{Write-BeeFullAccessAudit $(if($Enabled){'enable'}else{'disable'}) $Source $false $_.Exception.Message}catch{};throw}
    finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

function Assert-BeeAgentId([string]$Id) {
    if($Id-notmatch'^[a-z][a-z0-9-]{1,48}$'){throw 'ID агента: 2–49 символов, строчные латинские буквы, цифры и дефисы; первый символ — буква.'}
}

function New-BeeAgent([string]$Id,[string]$Description,[string]$Model) {
    Assert-BeeAgentId $Id;$config=Read-BeeUtf8Json (Get-BeeTeamConfigPath)
    if($config.agent.PSObject.Properties[$Id]){throw "Агент '$Id' уже существует"}
    if([string]::IsNullOrWhiteSpace($Description)){throw 'Введите описание агента'}
    $agent=[pscustomobject]@{description=$Description;mode='all';model=$Model;temperature=0.2;top_p=0.95;top_k=20;prompt='';permission=[pscustomobject]@{read='allow';glob='allow';grep='allow';list='allow';edit='ask';bash='ask';external_directory='ask';task=[pscustomobject]@{'*'='deny'};todowrite='allow';webfetch='ask';websearch='ask';skill=[pscustomobject]@{'*'='deny'}}}
    $config.agent|Add-Member -NotePropertyName $Id -NotePropertyValue $agent
    Write-BeeTeamConfig $config 'new-agent'|Out-Null
    return Get-BeeTeamSnapshot
}

function Copy-BeeAgent([string]$SourceId,[string]$NewId) {
    Assert-BeeAgentId $NewId;$config=Read-BeeUtf8Json (Get-BeeTeamConfigPath)
    $source=$config.agent.PSObject.Properties[$SourceId];if(-not$source){throw "Агент '$SourceId' не найден"}
    if($config.agent.PSObject.Properties[$NewId]){throw "Агент '$NewId' уже существует"}
    $copy=($source.Value|ConvertTo-Json -Depth 30|ConvertFrom-Json)
    Set-BeeObjectProperty $copy 'description' (([string]$copy.description)+' — копия')
    Set-BeeObjectProperty $copy 'mode' 'all';Set-BeeObjectProperty $copy 'disable' $false
    $config.agent|Add-Member -NotePropertyName $NewId -NotePropertyValue $copy
    Write-BeeTeamConfig $config 'clone-agent'|Out-Null
    return Get-BeeTeamSnapshot
}

function Remove-BeeAgent([string]$Id) {
    $config=Read-BeeUtf8Json (Get-BeeTeamConfigPath);$property=$config.agent.PSObject.Properties[$Id]
    if(-not$property){throw "Агент '$Id' не найден"};if($Id-eq'build'){throw 'Встроенный build можно отключить, но нельзя удалить.'}
    $agent=$property.Value
    if(-not[bool]($agent.PSObject.Properties['disable']-and$agent.disable)-and[string]$agent.mode-eq'primary'){
        $other=@($config.agent.PSObject.Properties|Where-Object{$_.Name-ne$Id-and[string](Get-BeeObjectProperty $_.Value 'mode' '')-eq'primary'-and-not[bool]($_.Value.PSObject.Properties['disable']-and$_.Value.disable)})
        if(-not$other.Count){throw 'Нельзя удалить последнего активного primary-агента.'}
    }
    foreach($other in @($config.agent.PSObject.Properties)){
        $otherPermission=Get-BeeObjectProperty $other.Value 'permission' $null
        $otherTasks=Get-BeeObjectProperty $otherPermission 'task' $null
        if($otherTasks){Remove-BeeObjectProperty $otherTasks $Id}
    }
    if($config.command){$refs=@($config.command.PSObject.Properties|Where-Object{[string]$_.Value.agent-eq$Id});if($refs){throw "Агент используется командами: $(@($refs.Name)-join ', ')"}}
    $config.agent.PSObject.Properties.Remove($Id)
    Write-BeeTeamConfig $config 'delete-agent'|Out-Null
    return Get-BeeTeamSnapshot
}

function Save-BeeAgent([string]$Id,[string]$Description,[string]$Model,[string]$Mode,[bool]$Disabled,[string]$Prompt,[string[]]$SkillIds,[string[]]$McpIds,[string[]]$EnabledMcpIds,[bool]$DelegateAllowed) {
    $config=Read-BeeUtf8Json (Get-BeeTeamConfigPath);$property=$config.agent.PSObject.Properties[$Id]
    if(-not$property){throw "Агент '$Id' не найден"};if([string]::IsNullOrWhiteSpace($Description)-and$Id-ne'build'){throw 'Описание обязательно'}
    if($Mode-notin@('primary','subagent','all')-and$Id-ne'build'){throw 'Недопустимый режим агента'}
    $availableModels=@($config.provider.beellama.models.PSObject.Properties.Name|ForEach-Object{"beellama/$_"})
    if($Model-and$Model-notin$availableModels){throw "Модель '$Model' отсутствует в provider.beellama.models"}
    $validSkills=@(Get-BeeSkillCatalog|Where-Object{$_.Valid}|ForEach-Object{$_.Id});foreach($skill in @($SkillIds)){if($skill-notin$validSkills){throw "Skill '$skill' отсутствует или повреждён"}}
    $allMcpIds=@($config.mcp.PSObject.Properties.Name);foreach($mcp in @($McpIds+$EnabledMcpIds)){if($mcp-notin$allMcpIds){throw "MCP '$mcp' отсутствует"}}
    $globalPermission=Get-BeeObjectProperty $config 'permission' $null
    if(-not$globalPermission){$globalPermission=[pscustomobject]@{};Set-BeeObjectProperty $config 'permission' $globalPermission}
    foreach($mcp in $allMcpIds){Set-BeeObjectProperty $globalPermission "$mcp*" 'deny'}
    Remove-BeeObjectProperty $config 'tools'
    $agent=$property.Value;Set-BeeObjectProperty $agent 'description' $Description
    if($Model){Set-BeeObjectProperty $agent 'model' $Model};if($Mode){Set-BeeObjectProperty $agent 'mode' $Mode};Set-BeeObjectProperty $agent 'prompt' $Prompt;Set-BeeObjectProperty $agent 'disable' $Disabled
    $permission=Get-BeeObjectProperty $agent 'permission' $null
    if(-not$permission){$permission=[pscustomobject]@{};Set-BeeObjectProperty $agent 'permission' $permission}
    $skillPermission=Get-BeeObjectProperty $permission 'skill' $null
    if(-not$skillPermission){$skillPermission=[pscustomobject]@{'*'='deny'};Set-BeeObjectProperty $permission 'skill' $skillPermission}
    foreach($rule in @($agent.permission.skill.PSObject.Properties)){if($rule.Name-ne'*'-and[string]$rule.Value-eq'allow'){Remove-BeeObjectProperty $agent.permission.skill $rule.Name}}
    if(-not$agent.permission.skill.PSObject.Properties['*']){Set-BeeObjectProperty $agent.permission.skill '*' 'deny'}
    foreach($skill in @($SkillIds)){Set-BeeObjectProperty $agent.permission.skill $skill 'allow'}
    foreach($mcp in $allMcpIds){Remove-BeeObjectProperty $permission "$mcp*"}
    foreach($mcp in @($McpIds)){Set-BeeObjectProperty $permission "$mcp*" 'allow'}
    # OpenCode deprecated per-agent `tools`; write only permission rules going forward.
    Remove-BeeObjectProperty $agent 'tools'
    foreach($mcpProperty in @($config.mcp.PSObject.Properties)){Set-BeeObjectProperty $mcpProperty.Value 'enabled' ([bool]($mcpProperty.Name-in$EnabledMcpIds))}
    $lead=$config.agent.PSObject.Properties['team-lead'];if($lead-and$Id-ne'team-lead'){
        if(-not$lead.Value.permission){Set-BeeObjectProperty $lead.Value 'permission' ([pscustomobject]@{})};if(-not$lead.Value.permission.task){Set-BeeObjectProperty $lead.Value.permission 'task' ([pscustomobject]@{'*'='deny'})}
        if($DelegateAllowed){Set-BeeObjectProperty $lead.Value.permission.task $Id 'allow'}else{Remove-BeeObjectProperty $lead.Value.permission.task $Id}
    }
    if($Disabled-or$Mode-ne'primary'){
        $other=@($config.agent.PSObject.Properties|Where-Object{$_.Name-ne$Id-and[string](Get-BeeObjectProperty $_.Value 'mode' '')-eq'primary'-and-not[bool]($_.Value.PSObject.Properties['disable']-and$_.Value.disable)})
        if(-not$other.Count-and$Id-ne'build'){throw 'Должен остаться хотя бы один активный primary-агент.'}
    }
    Write-BeeTeamConfig $config 'save-agent'|Out-Null
    return Get-BeeTeamSnapshot
}

function Restore-BeeTeamConfig {
    $path=Get-BeeTeamConfigPath;$backup=Get-ChildItem -LiteralPath $script:TeamBackupDir -File -Filter 'opencode.team-manager-*.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if(-not$backup){throw 'Резервная копия AI-команды не найдена'}
    [void](Read-BeeUtf8Json $backup.FullName);[void](Backup-BeeTeamConfig $path 'pre-restore')
    $temp="$path.tmp";Copy-Item -LiteralPath $backup.FullName -Destination $temp -Force;Move-Item -LiteralPath $temp -Destination $path -Force
    return [pscustomobject]@{Restored=$backup.FullName;Snapshot=(Get-BeeTeamSnapshot)}
}

function Set-BeeResearchRoleDefaults {
    $config=Read-BeeUtf8Json (Get-BeeTeamConfigPath)
    $policies=@(
        [pscustomobject]@{Id='solution-architect';Web=$true;GitHub=$true;Research=$true;Docs=$true},
        [pscustomobject]@{Id='devops-engineer';Web=$true;GitHub=$true;Research=$true;Docs=$true},
        [pscustomobject]@{Id='security-engineer';Web=$true;GitHub=$false;Research=$true;Docs=$true},
        [pscustomobject]@{Id='systems-engineer';Web=$false;GitHub=$false;Research=$false;Docs=$true},
        [pscustomobject]@{Id='platform-engineer';Web=$false;GitHub=$false;Research=$false;Docs=$true},
        [pscustomobject]@{Id='qa-engineer';Web=$false;GitHub=$false;Research=$false;Docs=$true}
    )
    foreach($policy in $policies){
        $property=$config.agent.PSObject.Properties[$policy.Id]
        if(-not$property){throw "Агент '$($policy.Id)' не найден"}
        $agent=$property.Value
        $permission=Get-BeeObjectProperty $agent 'permission' $null
        if(-not$permission){$permission=[pscustomobject]@{};Set-BeeObjectProperty $agent 'permission' $permission}
        Set-BeeObjectProperty $permission 'websearch' $(if($policy.Web){'allow'}else{'deny'})
        Set-BeeObjectProperty $permission 'webfetch' $(if($policy.Web){'allow'}else{'deny'})
        $skills=Get-BeeObjectProperty $permission 'skill' $null
        if(-not$skills){$skills=[pscustomobject]@{'*'='deny'};Set-BeeObjectProperty $permission 'skill' $skills}
        if($policy.Docs){Set-BeeObjectProperty $skills 'find-docs' 'allow'}else{Remove-BeeObjectProperty $skills 'find-docs'}
        if($policy.Research){Set-BeeObjectProperty $skills 'opencode-web-research' 'allow'}else{Remove-BeeObjectProperty $skills 'opencode-web-research'}
        if($policy.GitHub){Set-BeeObjectProperty $permission 'github*' 'allow'}elseif($policy.Id-ne'devops-engineer'){Remove-BeeObjectProperty $permission 'github*'}
        Remove-BeeObjectProperty $agent 'tools'
    }
    Write-BeeTeamConfig $config 'research-role-defaults'|Out-Null
    return Get-BeeTeamSnapshot
}

function Write-BeeMcpTestStatus($Value) {
    if(-not(Test-Path -LiteralPath $script:TeamLogDir)){New-Item -ItemType Directory -Path $script:TeamLogDir -Force|Out-Null}
    $temp="$script:McpTestStatusPath.tmp";$json=$Value|ConvertTo-Json -Depth 10;[IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($true));Move-Item -LiteralPath $temp -Destination $script:McpTestStatusPath -Force
}

function ConvertTo-BeeTeamArgument([string]$Value) {if($Value-notmatch'[\s"]'){return $Value};return '"'+($Value-replace'(\\*)"','$1$1\"'-replace'(\\+)$','$1$1')+'"'}

function Stop-BeeProcessTree([int]$RootPid) {
    $children=Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Group-Object ParentProcessId -AsHashTable -AsString
    function Stop-Node([int]$Id){$group=$children[[string]$Id];if($group){foreach($child in @($group)){Stop-Node ([int]$child.ProcessId)}};Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue}
    if($RootPid-gt0){Stop-Node $RootPid}
}

function Invoke-BeeMcpHandshake([string]$McpId,[int]$TimeoutSec=10) {
    $config=Read-BeeUtf8Json (Get-BeeTeamConfigPath);$property=$config.mcp.PSObject.Properties[$McpId];if(-not$property){throw "MCP '$McpId' не найден"}
    $m=$property.Value;$command=@($m.command);if(-not$command.Count){throw 'Пустая MCP command'};$exe=Resolve-BeeExecutable ([string]$command[0]);if(-not$exe){throw "Executable не найден: $($command[0])"}
    Write-BeeMcpTestStatus ([pscustomobject]@{state='Running';mcp=$McpId;message='Запуск проверки';startedAt=(Get-Date).ToString('o')})
    $process=$null
    try{
        $psi=New-Object Diagnostics.ProcessStartInfo;$isCmd=[IO.Path]::GetExtension($exe)-in@('.cmd','.bat')
        if([IO.Path]::GetFileName($exe)-ieq'docker.exe'){$psi.FileName=$exe;$psi.Arguments='info --format "{{.ServerVersion}}"'}
        elseif($isCmd){
            $psi.FileName=$env:ComSpec
            $inner=@((ConvertTo-BeeTeamArgument $exe))+@($command|Select-Object -Skip 1|ForEach-Object{ConvertTo-BeeTeamArgument ([string]$_)})
            $psi.Arguments='/d /s /c "'+($inner-join' ')+'"'
        }
        else{$psi.FileName=$exe;$psi.Arguments=(@($command|Select-Object -Skip 1|ForEach-Object{ConvertTo-BeeTeamArgument ([string]$_)})-join' ')}
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        if($m.PSObject.Properties['cwd']-and(Test-Path -LiteralPath ([string]$m.cwd))){$psi.WorkingDirectory=[string]$m.cwd}else{$psi.WorkingDirectory=Split-Path $exe -Parent}
        $mcpEnvironment=Get-BeeObjectProperty $m 'environment' $null
        if($mcpEnvironment){foreach($envProp in @($mcpEnvironment.PSObject.Properties)){if($envProp.Name-ne'cwd'){$psi.EnvironmentVariables[$envProp.Name]=[Environment]::ExpandEnvironmentVariables([string]$envProp.Value)}}}
        $process=New-Object Diagnostics.Process;$process.StartInfo=$psi;if(-not$process.Start()){throw 'Процесс не запустился'}
        [IO.File]::WriteAllText($script:McpChildPidPath,[string]$process.Id,[Text.Encoding]::ASCII)
        if([IO.Path]::GetFileName($exe)-ieq'docker.exe'){
            if(-not$process.WaitForExit($TimeoutSec*1000)){throw 'TIMEOUT: Docker Engine не ответил'}
            $stdout=$process.StandardOutput.ReadToEnd();$stderr=$process.StandardError.ReadToEnd();if($process.ExitCode-ne0){throw "Docker check failed: $stderr"};$message="Docker Engine доступен: $($stdout.Trim())"
        }else{
            $request=[ordered]@{jsonrpc='2.0';id=1;method='initialize';params=[ordered]@{protocolVersion='2025-03-26';capabilities=[pscustomobject]@{};clientInfo=[ordered]@{name='BeeForge AI Console';version='1.0'}}}|ConvertTo-Json -Depth 8 -Compress
            $process.StandardInput.WriteLine($request);$process.StandardInput.Flush();$deadline=(Get-Date).AddSeconds($TimeoutSec);$response=$null;$readTask=$process.StandardOutput.ReadLineAsync()
            while((Get-Date)-lt$deadline-and-not$process.HasExited){
                if($readTask.Wait(250)){
                    $line=$readTask.Result
                    if($line){try{$candidate=$line|ConvertFrom-Json;if($candidate.id-eq1){$response=$candidate;break}}catch{}}
                    $readTask=$process.StandardOutput.ReadLineAsync()
                }
            }
            if(-not$response){
                $detail=$(if($process.HasExited){$process.StandardError.ReadToEnd().Trim()}else{''})
                if($detail){throw "MCP initialize не получен: $detail"}
                throw "MCP initialize не получен за $TimeoutSec секунд"
            }
            $responseError=Get-BeeObjectProperty $response 'error' $null
            if($responseError){throw "MCP error: $($responseError.message)"}
            $result=Get-BeeObjectProperty $response 'result' $null;$serverInfo=Get-BeeObjectProperty $result 'serverInfo' $null
            $serverName=[string](Get-BeeObjectProperty $serverInfo 'name' 'unknown');$serverVersion=[string](Get-BeeObjectProperty $serverInfo 'version' '')
            $message="MCP initialize OK: $serverName $serverVersion".Trim()
        }
        [IO.File]::WriteAllText($script:McpTestLogPath,$message,[Text.UTF8Encoding]::new($true));Write-BeeMcpTestStatus ([pscustomobject]@{state='Completed';mcp=$McpId;message=$message;finishedAt=(Get-Date).ToString('o')})
    }catch{[IO.File]::WriteAllText($script:McpTestLogPath,$_.Exception.Message,[Text.UTF8Encoding]::new($true));Write-BeeMcpTestStatus ([pscustomobject]@{state=$(if($_.Exception.Message-like'TIMEOUT*'){'Timeout'}else{'Failed'});mcp=$McpId;message=$_.Exception.Message;finishedAt=(Get-Date).ToString('o')});throw}
    finally{if($process-and-not$process.HasExited){Stop-BeeProcessTree $process.Id};Remove-Item -LiteralPath $script:McpChildPidPath -Force -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $script:McpTestPidPath -Force -ErrorAction SilentlyContinue}
}

function Start-BeeMcpTest([string]$McpId,[int]$TimeoutSec=10) {
    Stop-BeeMcpTest|Out-Null;Remove-Item -LiteralPath $script:McpTestStatusPath,$script:McpTestLogPath -Force -ErrorAction SilentlyContinue
    $worker=Join-Path $script:TeamRoot 'scripts\test-mcp.ps1';$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$worker,'-McpId',$McpId,'-TimeoutSec',[string]$TimeoutSec)
    $line=@($args|ForEach-Object{ConvertTo-BeeTeamArgument ([string]$_)})-join' ';$p=Start-Process powershell.exe -ArgumentList $line -PassThru -WindowStyle Hidden
    [IO.File]::WriteAllText($script:McpTestPidPath,[string]$p.Id,[Text.Encoding]::ASCII);return [pscustomobject]@{Started=$true;Pid=$p.Id;Mcp=$McpId}
}

function Stop-BeeMcpTest {
    $stopped=$false
    foreach($pidPath in @($script:McpChildPidPath,$script:McpTestPidPath)){if(Test-Path -LiteralPath $pidPath){$id=0;if([int]::TryParse(([IO.File]::ReadAllText($pidPath)).Trim(),[ref]$id)-and(Get-Process -Id $id -ErrorAction SilentlyContinue)){Stop-BeeProcessTree $id;$stopped=$true};Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue}}
    if($stopped){Write-BeeMcpTestStatus ([pscustomobject]@{state='Stopped';message='Проверка MCP остановлена';finishedAt=(Get-Date).ToString('o')})}
    return [pscustomobject]@{Stopped=$stopped}
}

function Get-BeeMcpTestStatus {
    if(-not(Test-Path -LiteralPath $script:McpTestStatusPath)){return [pscustomobject]@{state='Idle';message='Проверка не запускалась';mcp=''}}
    try{return Read-BeeUtf8Json $script:McpTestStatusPath}catch{return [pscustomobject]@{state='Failed';message=$_.Exception.Message;mcp=''}}
}

Export-ModuleMember -Function Get-BeeTeamPaths,Get-BeeSkillCatalog,Get-BeeTeamSnapshot,New-BeeAgent,Copy-BeeAgent,Remove-BeeAgent,Save-BeeAgent,Restore-BeeTeamConfig,Set-BeeResearchRoleDefaults,Get-BeeFullAccessStatus,Set-BeeFullAccess,Start-BeeMcpTest,Stop-BeeMcpTest,Get-BeeMcpTestStatus,Invoke-BeeMcpHandshake
