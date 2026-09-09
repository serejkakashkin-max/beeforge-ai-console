[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$utf8Bom = [Text.UTF8Encoding]::new($true)

function Read-Text([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
}

function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $utf8Bom)
}

function Replace-Once([string]$Path, [string]$Old, [string]$New) {
    $text = Read-Text $Path
    $index = $text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($index -lt 0) { throw "Patch anchor not found in $Path`n--- anchor ---`n$Old" }
    if ($text.IndexOf($Old, $index + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Patch anchor is not unique in $Path`n--- anchor ---`n$Old"
    }
    $text = $text.Substring(0,$index) + $New + $text.Substring($index + $Old.Length)
    Write-Text $Path $text
}

function Ensure-NotAlreadyApplied([string]$Path, [string]$Marker) {
    $text = Read-Text $Path
    if ($text.Contains($Marker)) {
        Write-Host "MoE patch already present in $Path"
        exit 0
    }
}

$core = Join-Path $root 'scripts\BeeLlamaManager.Core.psm1'
$ui = Join-Path $root 'ui\BeeLlama-Manager.ps1'
$template = Join-Path $root 'config\templates\profiles.example.json'
$readme = Join-Path $root 'README.md'

Ensure-NotAlreadyApplied $core "cpuMoeLayers = 0"

# Core: managed flags, schema/migration, validation, arguments and run-state matching.
Replace-Once $core @'
    '--reasoning-loop-guard','--reasoning-preserve','--spec-type','--spec-draft-n-max',
'@ @'
    '--reasoning-loop-guard','--reasoning-preserve','--cpu-moe','-cmoe','--n-cpu-moe','-ncmoe','--spec-type','--spec-draft-n-max',
'@

Replace-Once $core @'
        visionEnabled = $false
        visionOffload = $false
        mmprojPath = ''
'@ @'
        visionEnabled = $false
        visionOffload = $false
        mmprojPath = ''
        cpuMoeLayers = 0
        cpuMoeAll = $false
        moeLayerCount = 0
        moeExpertWeightFraction = 0.0
        modelLayerCount = 0
        advancedArgs = @()
'@

Replace-Once $core @'
    foreach ($entry in $defaults.GetEnumerator()) {
        if (-not $Profile.PSObject.Properties[$entry.Key]) {
            $Profile | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value
        }
    }
    # Profiles are user-defined; no profile has a privileged or undeletable role.
'@ @'
    foreach ($entry in $defaults.GetEnumerator()) {
        if (-not $Profile.PSObject.Properties[$entry.Key]) {
            $Profile | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value
        }
    }
    # Migrate older profiles that carried MoE flags in Advanced into native fields.
    $cleanAdvanced = @()
    foreach ($advancedEntry in @($Profile.advancedArgs)) {
        $advancedFlag = [string]$advancedEntry.flag
        if ($advancedFlag -in @('--n-cpu-moe','-ncmoe')) {
            $parsedCpuMoe = 0
            if ([int]::TryParse([string]$advancedEntry.value,[ref]$parsedCpuMoe) -and $parsedCpuMoe -ge 0 -and [int]$Profile.cpuMoeLayers -eq 0) {
                $Profile.cpuMoeLayers = $parsedCpuMoe
            }
            continue
        }
        if ($advancedFlag -in @('--cpu-moe','-cmoe')) {
            $Profile.cpuMoeAll = $true
            continue
        }
        $cleanAdvanced += $advancedEntry
    }
    $Profile.advancedArgs = @($cleanAdvanced)
    # Profiles are user-defined; no profile has a privileged or undeletable role.
'@

Replace-Once $core @'
        kvTailTokens=1024; kvTailType='f16'; cacheReuse=256; parallel=1
        reasoningEnabled=$true; reasoningBudget=32768; reasoningPreserve=$true
'@ @'
        kvTailTokens=1024; kvTailType='f16'; cacheReuse=256; parallel=1
        cpuMoeLayers=0; cpuMoeAll=$false; moeLayerCount=0; moeExpertWeightFraction=0.0; modelLayerCount=0
        reasoningEnabled=$true; reasoningBudget=32768; reasoningPreserve=$true
'@

Replace-Once $core @'
    if ([string]$Profile.host -notin @('127.0.0.1','localhost')) { $warnings.Add('Non-local host exposes the API beyond localhost') }

    $helpText = $null
'@ @'
    if ([string]$Profile.host -notin @('127.0.0.1','localhost')) { $warnings.Add('Non-local host exposes the API beyond localhost') }

    $cpuMoeLayers = if ($Profile.PSObject.Properties['cpuMoeLayers']) { [int]$Profile.cpuMoeLayers } else { 0 }
    $cpuMoeAll = ($Profile.PSObject.Properties['cpuMoeAll'] -and [bool]$Profile.cpuMoeAll)
    $moeLayerCount = if ($Profile.PSObject.Properties['moeLayerCount']) { [int]$Profile.moeLayerCount } else { 0 }
    $moeExpertWeightFraction = if ($Profile.PSObject.Properties['moeExpertWeightFraction']) { [double]$Profile.moeExpertWeightFraction } else { 0.0 }
    $modelLayerCount = if ($Profile.PSObject.Properties['modelLayerCount']) { [int]$Profile.modelLayerCount } else { 0 }
    if ($cpuMoeLayers -lt 0) { $errors.Add('CPU MoE layers must be 0 or greater') }
    if ($cpuMoeAll -and $cpuMoeLayers -gt 0) { $errors.Add('Use either all CPU MoE or a numeric CPU MoE layer count, not both') }
    if ($moeLayerCount -lt 0) { $errors.Add('MoE layer count must be 0 or greater') }
    if ($modelLayerCount -lt 0) { $errors.Add('Model layer count must be 0 or greater') }
    if ($moeExpertWeightFraction -lt 0.0 -or $moeExpertWeightFraction -gt 1.0) { $errors.Add('MoE expert weight fraction must be between 0 and 1') }
    if ($cpuMoeLayers -gt 0 -and $moeLayerCount -gt 0 -and $cpuMoeLayers -gt $moeLayerCount) { $warnings.Add("CPU MoE layers ($cpuMoeLayers) exceed configured MoE layers ($moeLayerCount); runtime behavior will be authoritative") }

    $helpText = $null
'@

Replace-Once $core @'
        if ([bool]$Profile.reasoningPreserve) { $requiredFlags += '--reasoning-preserve' }
        if ([bool]$Profile.mtpEnabled) { $requiredFlags += @('--spec-type','--spec-draft-n-max') }
'@ @'
        if ([bool]$Profile.reasoningPreserve) { $requiredFlags += '--reasoning-preserve' }
        if ([bool]$Profile.mtpEnabled) { $requiredFlags += @('--spec-type','--spec-draft-n-max') }
        if ($cpuMoeAll) { $requiredFlags += '--cpu-moe' }
        elseif ($cpuMoeLayers -gt 0) { $requiredFlags += '--n-cpu-moe' }
'@

Replace-Once $core @'
    if ([bool]$Profile.mtpEnabled) {
        foreach ($value in @('--spec-type','draft-mtp','--spec-draft-n-max',[string]$Profile.mtpNMax)) { $args.Add($value) }
    }
    foreach ($entry in @($Profile.advancedArgs)) {
'@ @'
    if ([bool]$Profile.mtpEnabled) {
        foreach ($value in @('--spec-type','draft-mtp','--spec-draft-n-max',[string]$Profile.mtpNMax)) { $args.Add($value) }
    }
    $cpuMoeAll = ($Profile.PSObject.Properties['cpuMoeAll'] -and [bool]$Profile.cpuMoeAll)
    $cpuMoeLayers = if ($Profile.PSObject.Properties['cpuMoeLayers']) { [int]$Profile.cpuMoeLayers } else { 0 }
    if ($cpuMoeAll) { $args.Add('--cpu-moe') }
    elseif ($cpuMoeLayers -gt 0) {
        foreach ($value in @('--n-cpu-moe',[string]$cpuMoeLayers)) { $args.Add($value) }
    }
    foreach ($entry in @($Profile.advancedArgs)) {
'@

Replace-Once $core @'
            [string]$run.alias -eq [string]$Profile.alias -and
            [int]$run.context -eq [int]$Profile.context -and
            [bool]$run.visionEnabled -eq [bool]($Profile.PSObject.Properties['visionEnabled'] -and $Profile.visionEnabled) -and
'@ @'
            [string]$run.alias -eq [string]$Profile.alias -and
            [int]$run.context -eq [int]$Profile.context -and
            [int]$(if ($run.PSObject.Properties['cpuMoeLayers']) { $run.cpuMoeLayers } else { 0 }) -eq [int]$(if ($Profile.PSObject.Properties['cpuMoeLayers']) { $Profile.cpuMoeLayers } else { 0 }) -and
            [bool]$(if ($run.PSObject.Properties['cpuMoeAll']) { $run.cpuMoeAll } else { $false }) -eq [bool]($Profile.PSObject.Properties['cpuMoeAll'] -and $Profile.cpuMoeAll) -and
            [bool]$run.visionEnabled -eq [bool]($Profile.PSObject.Properties['visionEnabled'] -and $Profile.visionEnabled) -and
'@

Replace-Once $core @'
    [pscustomobject]@{ profileId=$profile.id; profileName=$profile.name; alias=$profile.alias; modelPath=$profile.modelPath; serverPath=$profile.serverPath; context=$profile.context; visionEnabled=[bool]($profile.PSObject.Properties['visionEnabled'] -and $profile.visionEnabled); visionOffload=[bool]($profile.PSObject.Properties['visionOffload'] -and $profile.visionOffload); mmprojPath=[string]$(if ($profile.PSObject.Properties['mmprojPath']) { $profile.mmprojPath } else { '' }); host=$profile.host; port=$profile.port; pid=$process.Id; startedAt=(Get-Date).ToString('o') } |
'@ @'
    [pscustomobject]@{ profileId=$profile.id; profileName=$profile.name; alias=$profile.alias; modelPath=$profile.modelPath; serverPath=$profile.serverPath; context=$profile.context; cpuMoeLayers=[int]$(if ($profile.PSObject.Properties['cpuMoeLayers']) { $profile.cpuMoeLayers } else { 0 }); cpuMoeAll=[bool]($profile.PSObject.Properties['cpuMoeAll'] -and $profile.cpuMoeAll); visionEnabled=[bool]($profile.PSObject.Properties['visionEnabled'] -and $profile.visionEnabled); visionOffload=[bool]($profile.PSObject.Properties['visionOffload'] -and $profile.visionOffload); mmprojPath=[string]$(if ($profile.PSObject.Properties['mmprojPath']) { $profile.mmprojPath } else { '' }); host=$profile.host; port=$profile.port; pid=$process.Id; startedAt=(Get-Date).ToString('o') } |
'@

# UI: add a native MoE panel and model-aware layer/resource controls.
Replace-Once $ui @'
      <GroupBox Name="ReasoningGroup" Header="Reasoning"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="160"/><ColumnDefinition Width="200"/><ColumnDefinition Width="160"/></Grid.ColumnDefinitions>
'@ @'
      <GroupBox Name="MoeGroup" Header="MoE / CPU offload"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="140"/><ColumnDefinition Width="180"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <Label Content="CPU MoE layers"/><TextBox Grid.Column="1" Name="CpuMoeLayers" ToolTip="0 = не переносить routed experts принудительно; N = --n-cpu-moe N"/><CheckBox Grid.Column="2" Grid.ColumnSpan="2" Name="CpuMoeAll" Content="Все MoE experts на CPU (--cpu-moe)"/>
       <Label Grid.Row="1" Content="MoE layers"/><TextBox Grid.Row="1" Grid.Column="1" Name="MoeLayerCount" ToolTip="Для оценки памяти. 0 = неизвестно/авто по известному имени модели"/><Label Grid.Row="1" Grid.Column="2" Content="Expert weights %"/><TextBox Grid.Row="1" Grid.Column="3" Name="MoeExpertWeightPercent" ToolTip="Доля GGUF, приходящаяся на routed experts. Например Ornith ≈ 93%."/>
       <Label Grid.Row="2" Content="Model layers"/><TextBox Grid.Row="2" Grid.Column="1" Name="ModelLayerCount" ToolTip="Используется для списка GPU layers и оценки. 0 = авто по известному имени модели"/><TextBlock Grid.Row="2" Grid.Column="2" Grid.ColumnSpan="2" Name="MoeHint" Text="Параметры MoE определятся после выбора модели" Foreground="#8FC8EA" TextWrapping="Wrap" Margin="8,5"/>
      </Grid></GroupBox>
      <GroupBox Name="ReasoningGroup" Header="Reasoning"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="160"/><ColumnDefinition Width="200"/><ColumnDefinition Width="160"/></Grid.ColumnDefinitions>
'@

Replace-Once $ui @'
foreach ($name in @('KvK','KvV')) { (UI $name).ItemsSource = @('f16','bf16','q8_0','q4_0','iq4_nl','kvarn4','kvarn3') }
'@ @'
function Get-MoEPreset([string]$ModelPath) {
    $name = if ([string]::IsNullOrWhiteSpace($ModelPath)) { '' } else { [IO.Path]::GetFileName($ModelPath) }
    if ($name -match '(?i)(Ornith|Tiel-Coder|KAT-Coder|Qwen3[._-]?6.*35B.*A3B)') {
        return [pscustomobject]@{ IsMoe=$true; MoeLayers=40; ModelLayers=40; ExpertPercent=93.0; Label='Qwen35MoE/Ornith family: 40 layers, routed experts ≈93% of main weights' }
    }
    if ($name -match '(?i)Gemma4.*26B.*A4B') {
        return [pscustomobject]@{ IsMoe=$true; MoeLayers=30; ModelLayers=30; ExpertPercent=90.0; Label='Gemma4 26B-A4B: 30 layers; expert share uses a conservative 90% heuristic' }
    }
    if ($name -match '(?i)Qwen3[._-]?8.*27B') {
        return [pscustomobject]@{ IsMoe=$false; MoeLayers=0; ModelLayers=64; ExpertPercent=0.0; Label='Qwen3.8-27B Dense preset: 64 layers' }
    }
    return [pscustomobject]@{ IsMoe=$false; MoeLayers=0; ModelLayers=0; ExpertPercent=0.0; Label='Неизвестная архитектура: при MoE укажите MoE layers / Expert weights % вручную' }
}

function Update-GpuLayerChoices {
    $current = (UI 'GpuLayers').Text
    $count = 0
    [void][int]::TryParse((UI 'ModelLayerCount').Text,[ref]$count)
    if ($count -le 0) {
        $preset = Get-MoEPreset (UI 'ModelPath').Text
        $count = [int]$preset.ModelLayers
    }
    if ($count -le 0) { $count = 128 }
    (UI 'GpuLayers').ItemsSource = @('all') + @($count..0 | ForEach-Object { [string]$_ })
    if (-not [string]::IsNullOrWhiteSpace($current)) { (UI 'GpuLayers').Text = $current }
}

function Update-MoEHint([switch]$ApplyDefaults) {
    $preset = Get-MoEPreset (UI 'ModelPath').Text
    if ($ApplyDefaults) {
        $value = 0
        if ([int]::TryParse((UI 'ModelLayerCount').Text,[ref]$value) -and $value -eq 0 -and $preset.ModelLayers -gt 0) { (UI 'ModelLayerCount').Text = [string]$preset.ModelLayers }
        $value = 0
        if ([int]::TryParse((UI 'MoeLayerCount').Text,[ref]$value) -and $value -eq 0 -and $preset.MoeLayers -gt 0) { (UI 'MoeLayerCount').Text = [string]$preset.MoeLayers }
        $percent = 0.0
        if ([double]::TryParse((UI 'MoeExpertWeightPercent').Text.Replace(',','.'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$percent) -and $percent -eq 0.0 -and $preset.ExpertPercent -gt 0) { (UI 'MoeExpertWeightPercent').Text = [string]$preset.ExpertPercent }
    }
    (UI 'MoeHint').Text = [string]$preset.Label
    Update-GpuLayerChoices
}

foreach ($name in @('KvK','KvV')) { (UI $name).ItemsSource = @('f16','bf16','q8_0','q4_0','iq4_nl','kvarn4','kvarn3') }
'@

Replace-Once $ui @'
(UI 'GpuLayers').ItemsSource = @('all') + @(64..0 | ForEach-Object { [string]$_ })
'@ @'
Update-GpuLayerChoices
'@

Replace-Once $ui @'
    foreach($name in @('ComputeGroup','KvGroup','ReasoningGroup','MtpGroup','SamplingGroup','ResourcesTab','AdvancedGrid','AddAdvanced','RemoveAdvanced','OpenLiveLog')){(UI $name).IsEnabled=-not$remote}
'@ @'
    foreach($name in @('ComputeGroup','KvGroup','MoeGroup','ReasoningGroup','MtpGroup','SamplingGroup','ResourcesTab','AdvancedGrid','AddAdvanced','RemoveAdvanced','OpenLiveLog')){(UI $name).IsEnabled=-not$remote}
'@

Replace-Once $ui @'
        ProfileName='name'; ModelPath='modelPath'; ServerPath='serverPath'; Alias='alias'; Context='context'; Parallel='parallel'; Batch='batch'; Ubatch='ubatch'; Threads='threads'; ThreadsBatch='threadsBatch'; CacheReuse='cacheReuse'; Host='host'; Port='port'; RemoteBaseUrl='remoteBaseUrl'; OpenCodeOutput='openCodeOutput'; KvTailTokens='kvTailTokens'; ReasoningBudget='reasoningBudget'; Temperature='temperature'; TopP='topP'; TopK='topK'; MinP='minP'; RepeatPenalty='repeatPenalty'
'@ @'
        ProfileName='name'; ModelPath='modelPath'; ServerPath='serverPath'; Alias='alias'; Context='context'; Parallel='parallel'; Batch='batch'; Ubatch='ubatch'; Threads='threads'; ThreadsBatch='threadsBatch'; CacheReuse='cacheReuse'; Host='host'; Port='port'; RemoteBaseUrl='remoteBaseUrl'; OpenCodeOutput='openCodeOutput'; KvTailTokens='kvTailTokens'; ReasoningBudget='reasoningBudget'; Temperature='temperature'; TopP='topP'; TopK='topK'; MinP='minP'; RepeatPenalty='repeatPenalty'; CpuMoeLayers='cpuMoeLayers'; MoeLayerCount='moeLayerCount'; ModelLayerCount='modelLayerCount'
'@

Replace-Once $ui @'
    foreach ($pair in @(@('FlashAttention','flashAttention'),@('OpenCodeSync','openCodeSync'),@('ReasoningEnabled','reasoningEnabled'),@('ReasoningPreserve','reasoningPreserve'),@('MtpEnabled','mtpEnabled'))) { (UI $pair[0]).IsChecked = [bool]$Profile.($pair[1]) }
'@ @'
    foreach ($pair in @(@('FlashAttention','flashAttention'),@('OpenCodeSync','openCodeSync'),@('ReasoningEnabled','reasoningEnabled'),@('ReasoningPreserve','reasoningPreserve'),@('MtpEnabled','mtpEnabled'),@('CpuMoeAll','cpuMoeAll'))) { (UI $pair[0]).IsChecked = [bool]$Profile.($pair[1]) }
    (UI 'MoeExpertWeightPercent').Text = ('{0:0.##}' -f ([double]$Profile.moeExpertWeightFraction * 100.0))
'@

Replace-Once $ui @'
    Update-Preview
    Update-VisionHint
    Update-ResourceEstimate
'@ @'
    Update-MoEHint -ApplyDefaults
    Update-Preview
    Update-VisionHint
    Update-ResourceEstimate
'@

Replace-Once $ui @'
    $p.reasoningEnabled=[bool](UI 'ReasoningEnabled').IsChecked; $p.reasoningBudget=[int](UI 'ReasoningBudget').Text; $p.reasoningPreserve=[bool](UI 'ReasoningPreserve').IsChecked; $p.mtpEnabled=[bool](UI 'MtpEnabled').IsChecked; $p.mtpNMax=[int](UI 'MtpNMax').SelectedItem
'@ @'
    $p.cpuMoeLayers=[int](UI 'CpuMoeLayers').Text; $p.cpuMoeAll=[bool](UI 'CpuMoeAll').IsChecked; $p.moeLayerCount=[int](UI 'MoeLayerCount').Text; $p.modelLayerCount=[int](UI 'ModelLayerCount').Text
    $moePercent=[double]::Parse((UI 'MoeExpertWeightPercent').Text.Replace(',','.'),[Globalization.CultureInfo]::InvariantCulture); $p.moeExpertWeightFraction=$moePercent/100.0
    $p.reasoningEnabled=[bool](UI 'ReasoningEnabled').IsChecked; $p.reasoningBudget=[int](UI 'ReasoningBudget').Text; $p.reasoningPreserve=[bool](UI 'ReasoningPreserve').IsChecked; $p.mtpEnabled=[bool](UI 'MtpEnabled').IsChecked; $p.mtpNMax=[int](UI 'MtpNMax').SelectedItem
'@

Replace-Once $ui @'
        $gpuFraction = 1.0
        $layerNote = 'все слои на GPU'
        if ([string]$p.gpuLayers -ne 'all') {
            $layerCount = 0
            if (-not [int]::TryParse([string]$p.gpuLayers,[ref]$layerCount)) { throw 'GPU layers должен быть all или целым числом' }
            $gpuFraction = [math]::Max(0.0,[math]::Min(1.0,$layerCount / 64.0))
            $layerNote = "примерно $([math]::Round($gpuFraction*100))% весов на GPU (для прогноза принято 64 слоя)"
        }
'@ @'
        $modelLayerCount = if ([int]$p.modelLayerCount -gt 0) { [int]$p.modelLayerCount } else { 64 }
        $gpuFraction = 1.0
        $layerNote = 'все слои на GPU'
        if ([string]$p.gpuLayers -ne 'all') {
            $layerCount = 0
            if (-not [int]::TryParse([string]$p.gpuLayers,[ref]$layerCount)) { throw 'GPU layers должен быть all или целым числом' }
            $gpuFraction = [math]::Max(0.0,[math]::Min(1.0,$layerCount / [double]$modelLayerCount))
            $layerNote = "примерно $([math]::Round($gpuFraction*100))% слоёв на GPU ($layerCount/$modelLayerCount)"
        }
        $cpuMoeLayers = [math]::Max(0,[int]$p.cpuMoeLayers)
        $moeLayerCount = [math]::Max(0,[int]$p.moeLayerCount)
        $moeWeightFraction = [math]::Max(0.0,[math]::Min(1.0,[double]$p.moeExpertWeightFraction))
        $cpuMoeWeightFraction = 0.0
        if ([bool]$p.cpuMoeAll -and $moeWeightFraction -gt 0) { $cpuMoeWeightFraction = $moeWeightFraction }
        elseif ($cpuMoeLayers -gt 0 -and $moeLayerCount -gt 0 -and $moeWeightFraction -gt 0) {
            $cpuMoeWeightFraction = $moeWeightFraction * [math]::Min(1.0,$cpuMoeLayers/[double]$moeLayerCount)
        }
        $effectiveGpuWeightFraction = [math]::Max(0.0,[math]::Min(1.0,$gpuFraction * (1.0-$cpuMoeWeightFraction)))
        $moeNote = if ([bool]$p.cpuMoeAll) { "все routed MoE experts на CPU; оценочная доля experts $('{0:P0}' -f $moeWeightFraction)" } elseif ($cpuMoeLayers -gt 0) { "CPU MoE $cpuMoeLayers/$moeLayerCount; оценочно в RAM уходит $('{0:P0}' -f $cpuMoeWeightFraction) весов" } else { 'CPU MoE выключен' }
'@

Replace-Once $ui @'
        $weightVramMiB = $modelMiB * 1.02 * $gpuFraction
'@ @'
        $weightVramMiB = $modelMiB * 1.02 * $effectiveGpuWeightFraction
'@

Replace-Once $ui @'
        $ramSpillMiB = $modelMiB * (1.0-$gpuFraction) * 1.05 + $visionRamMiB
'@ @'
        $ramSpillMiB = $modelMiB * (1.0-$effectiveGpuWeightFraction) * 1.05 + $visionRamMiB
'@

Replace-Once $ui @'
        (UI 'ResourceCalculatedFrom').Text = "Рассчитано $(Get-Date -Format 'HH:mm:ss') из формы: ctx $([int]$p.context) | KV $($p.kvK)/$($p.kvV) | tail $($p.kvTailTokens) $($p.kvTailType) | GPU layers $($p.gpuLayers)"
'@ @'
        (UI 'ResourceCalculatedFrom').Text = "Рассчитано $(Get-Date -Format 'HH:mm:ss') из формы: ctx $([int]$p.context) | KV $($p.kvK)/$($p.kvV) | GPU layers $($p.gpuLayers)/$modelLayerCount | CPU MoE $cpuMoeLayers"
'@

Replace-Once $ui @'
        (UI 'ResourceImpact').Text = "Что изменилось: context $([int]$p.context) уменьшает KV примерно на $('{0:N0}'-f[math]::Max(0,$contextSavingMiB)) MiB относительно 162K при тех же KV-настройках. $kvComparison $visionImpact Главный потребитель здесь — веса выбранной модели ($('{0:N2}'-f($weightVramMiB/1024.0)) GiB). Итоговые параметры следует проверять тестом именно для этой модели."
'@ @'
        $moeImpact = if ($cpuMoeWeightFraction -gt 0) { "MoE offload по текущей модели уменьшает оценочную GPU-долю весов примерно на $('{0:P0}'-f$cpuMoeWeightFraction)." } elseif ($cpuMoeLayers -gt 0 -or [bool]$p.cpuMoeAll) { 'CPU MoE задан, но доля expert weights или число MoE-слоёв неизвестны — заполните поля MoE для корректного прогноза.' } else { 'CPU MoE не используется.' }
        (UI 'ResourceImpact').Text = "Что изменилось: context $([int]$p.context) уменьшает KV примерно на $('{0:N0}'-f[math]::Max(0,$contextSavingMiB)) MiB относительно 162K при тех же KV-настройках. $kvComparison $moeImpact $visionImpact GPU-веса модели по оценке: $('{0:N2}'-f($weightVramMiB/1024.0)) GiB. KV для hybrid/linear-attention архитектур остаётся консервативной оценкой по Qwen38 до первого реального запуска."
'@

Replace-Once $ui @'
        $fullWeightMiB = $modelMiB*1.02
        $availableForWeights = $gpuTotalMiB-$targetHeadroomMiB-$idleMiB-$kvMiB-$buffersMiB
        $recommendedFraction = [math]::Max(0.0,[math]::Min(1.0,$availableForWeights/$fullWeightMiB))
        $recommendedLayers = [math]::Floor($recommendedFraction*64.0)
        $recommendedRamMiB = $modelMiB*(1.0-$recommendedFraction)*1.05
'@ @'
        $fullWeightMiB = $modelMiB*1.02*[math]::Max(0.01,(1.0-$cpuMoeWeightFraction))
        $availableForWeights = $gpuTotalMiB-$targetHeadroomMiB-$idleMiB-$kvMiB-$buffersMiB
        $recommendedFraction = [math]::Max(0.0,[math]::Min(1.0,$availableForWeights/$fullWeightMiB))
        $recommendedLayers = [math]::Floor($recommendedFraction*$modelLayerCount)
        $recommendedEffectiveGpuFraction = $recommendedFraction*(1.0-$cpuMoeWeightFraction)
        $recommendedRamMiB = $modelMiB*(1.0-$recommendedEffectiveGpuFraction)*1.05
'@

Replace-Once $ui @'
        (UI 'ResourceDetails').Text = "Модель: $([IO.Path]::GetFileName($p.modelPath))`nРаскладка: $layerNote`nФактический Shared GPU Memory через nvidia-smi на Windows надёжно не доступен; отрицательный или очень малый запас помечается как риск spill. Прогноз откалиброван по рабочему Qwen38 162K KVarN4/KVarN4 (факт около 15.7 GiB)."
'@ @'
        (UI 'ResourceDetails').Text = "Модель: $([IO.Path]::GetFileName($p.modelPath))`nРаскладка: $layerNote`nMoE: $moeNote`nФактический Shared GPU Memory через nvidia-smi на Windows надёжно не доступен; отрицательный или очень малый запас помечается как риск spill. Для Dense Qwen прогноз откалиброван по рабочему Qwen38 162K; для MoE/hybrid окончательная проверка — реальный запуск и фактические VRAM/RAM."
'@

Replace-Once $ui @'
foreach($controlName in @('Context','Parallel','Batch','Ubatch','KvTailTokens')) { (UI $controlName).Add_TextChanged({ Queue-ResourceEstimate }) }
'@ @'
foreach($controlName in @('Context','Parallel','Batch','Ubatch','KvTailTokens','CpuMoeLayers','MoeLayerCount','MoeExpertWeightPercent','ModelLayerCount')) { (UI $controlName).Add_TextChanged({ Queue-ResourceEstimate; Update-Preview }) }
(UI 'ModelLayerCount').Add_LostKeyboardFocus({ Update-GpuLayerChoices })
'@

Replace-Once $ui @'
foreach($controlName in @('FlashAttention','MtpEnabled','VisionEnabled','VisionOffload')) { (UI $controlName).Add_Checked({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview }); (UI $controlName).Add_Unchecked({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview }) }
'@ @'
foreach($controlName in @('FlashAttention','MtpEnabled','VisionEnabled','VisionOffload','CpuMoeAll')) { (UI $controlName).Add_Checked({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview }); (UI $controlName).Add_Unchecked({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview }) }
'@

Replace-Once $ui @'
(UI 'ModelPath').Add_SelectionChanged({ Refresh-VisionProjectorList -PreferDetected; Queue-ResourceEstimate; Update-Preview })
(UI 'ModelPath').Add_LostKeyboardFocus({ Refresh-VisionProjectorList -PreferDetected; Queue-ResourceEstimate; Update-Preview })
'@ @'
(UI 'ModelPath').Add_SelectionChanged({ Refresh-VisionProjectorList -PreferDetected; Update-MoEHint -ApplyDefaults; Queue-ResourceEstimate; Update-Preview })
(UI 'ModelPath').Add_LostKeyboardFocus({ Refresh-VisionProjectorList -PreferDetected; Update-MoEHint -ApplyDefaults; Queue-ResourceEstimate; Update-Preview })
'@

# Template profile fields.
Replace-Once $template @'
      "parallel": 1,
      "reasoningEnabled": true,
'@ @'
      "parallel": 1,
      "cpuMoeLayers": 0,
      "cpuMoeAll": false,
      "moeLayerCount": 0,
      "moeExpertWeightFraction": 0.0,
      "modelLayerCount": 0,
      "reasoningEnabled": true,
'@

# README documentation.
Replace-Once $readme @'
## Встроенный benchmark
'@ @'
## MoE и перенос routed experts на CPU

Для MoE-моделей BeeForge имеет отдельный блок **MoE / CPU offload** на вкладке
**Производительность**. Поле **CPU MoE layers** напрямую управляет
`--n-cpu-moe N`; значение `0` отключает принудительный перенос. Флажок
**Все MoE experts на CPU** соответствует `--cpu-moe` и взаимоисключаем с числом
CPU MoE layers.

Поля **MoE layers**, **Expert weights %** и **Model layers** используются только
для оценки ресурсов и динамического списка GPU layers. Для известных семейств
(Ornith/Tiel/KAT/Qwen3.6-35B-A3B, Gemma4-26B-A4B, Qwen3.8-27B) интерфейс подставляет
разумный пресет; значения можно скорректировать вручную. Старые профили, где
`--n-cpu-moe` или `--cpu-moe` были записаны во вкладке Advanced, автоматически
мигрируют в нативные поля.

Для MoE/hybrid-attention вкладка **Ресурсы** учитывает оценочную долю routed expert
weights, переносимую в RAM. Оценка KV остаётся консервативной до первого реального
запуска, потому что разные hybrid/linear-attention архитектуры имеют разную стоимость
контекста. После запуска ориентируйтесь на фактические VRAM/RAM и встроенный benchmark.

Пример стартовой конфигурации Ornith-1.5-35B-A3B на 16 GiB GPU:

```text
GPU layers:       all
CPU MoE layers:   16
MoE layers:       40
Expert weights:   93%
Model layers:     40
Flash Attention:  on
MTP:              off (для первого baseline)
```

## Встроенный benchmark
'@

# Add a durable smoke test and CI workflow.
$testsDir = Join-Path $root 'tests'
if (-not (Test-Path -LiteralPath $testsDir)) { New-Item -ItemType Directory -Path $testsDir -Force | Out-Null }
$smoke = @'
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BeeLlamaManager.Core.psm1') -Force

$p = Get-BeeNewProfileTemplate
$p.cpuMoeLayers = 16
$p.cpuMoeAll = $false
$args1 = @(Get-BeeArguments $p)
$i = [Array]::IndexOf($args1,'--n-cpu-moe')
if ($i -lt 0 -or $i + 1 -ge $args1.Count -or $args1[$i+1] -ne '16') { throw '--n-cpu-moe 16 was not emitted' }

$p.cpuMoeLayers = 0
$p.cpuMoeAll = $true
$args2 = @(Get-BeeArguments $p)
if ($args2 -notcontains '--cpu-moe') { throw '--cpu-moe was not emitted' }

if ($args2 -contains '--n-cpu-moe') { throw 'numeric CPU MoE flag must not be emitted with cpuMoeAll' }
Write-Host 'MoE profile smoke test passed.'
'@
Write-Text (Join-Path $testsDir 'MoEProfile.Smoke.ps1') $smoke

$workflowDir = Join-Path $root '.github\workflows'
if (-not (Test-Path -LiteralPath $workflowDir)) { New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null }
$ci = @'
name: PowerShell smoke
on:
  push:
    branches: [ main ]
  pull_request:
permissions:
  contents: read
jobs:
  smoke:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Parse PowerShell
        shell: pwsh
        run: |
          $files = @('scripts/BeeLlamaManager.Core.psm1','ui/BeeLlama-Manager.ps1','tests/MoEProfile.Smoke.ps1')
          foreach ($file in $files) {
            $tokens = $null; $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file),[ref]$tokens,[ref]$errors)
            if ($errors.Count) { $errors | Format-List | Out-String | Write-Error; exit 1 }
          }
      - name: MoE profile smoke
        shell: pwsh
        run: pwsh -NoProfile -File tests/MoEProfile.Smoke.ps1
'@
Write-Text (Join-Path $workflowDir 'powershell-smoke.yml') $ci

Write-Host 'MoE upgrade applied successfully.'
