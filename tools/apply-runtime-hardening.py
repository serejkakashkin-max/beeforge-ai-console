from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    p = ROOT / path
    return p.read_text(encoding='utf-8-sig')


def write(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8-sig')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one anchor, found {count}')
    return text.replace(old, new, 1)


def sub_once(text, pattern, repl, label):
    out, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one regex match, found {count}')
    return out


# ---------------------------------------------------------------------------
# Core runtime/profile logic
# ---------------------------------------------------------------------------
core_path = 'scripts/BeeLlamaManager.Core.psm1'
core = read(core_path)

core = replace_once(
    core,
    "    '--reasoning-loop-guard','--reasoning-preserve','--cpu-moe','-cmoe','--n-cpu-moe','-ncmoe','--spec-type','--spec-draft-n-max',",
    "    '--reasoning-loop-guard','--reasoning-preserve','--cpu-moe','-cmoe','--n-cpu-moe','-ncmoe','-ot','--override-tensor','--no-mmap','--mmap','--spec-type','--spec-draft-n-max',",
    'managed flags')

core = replace_once(
    core,
    "        modelLayerCount = 0\n        advancedArgs = @()",
    "        modelLayerCount = 0\n        tensorOverride = ''\n        noMmap = $false\n        advancedArgs = @()",
    'schema defaults')

core = replace_once(
    core,
    "    # Profiles are user-defined; no profile has a privileged or undeletable role.",
    "    # Correct the old template typo without rewriting deliberate custom limits.\n    if ($Profile.PSObject.Properties['openCodeOutput'] -and [int]$Profile.openCodeOutput -eq 32764) { $Profile.openCodeOutput = 32768 }\n    # Profiles are user-defined; no profile has a privileged or undeletable role.",
    'output migration')

core = replace_once(
    core,
    "        cpuMoeLayers=0; cpuMoeAll=$false; moeLayerCount=0; moeExpertWeightFraction=0.0; modelLayerCount=0\n        reasoningEnabled=$true;",
    "        cpuMoeLayers=0; cpuMoeAll=$false; moeLayerCount=0; moeExpertWeightFraction=0.0; modelLayerCount=0; tensorOverride=''; noMmap=$false\n        reasoningEnabled=$true;",
    'new profile runtime fields')
core = core.replace('openCodeOutput=32764;', 'openCodeOutput=32768;', 1)

vision_helpers = r'''
function Get-BeeModelFamilyToken([string]$Path) {
    $name = if ([string]::IsNullOrWhiteSpace($Path)) { '' } else { [IO.Path]::GetFileName($Path) }
    if ($name -match '(?i)(Ornith|Tiel-Coder)') { return 'ornith' }
    if ($name -match '(?i)KAT-Coder') { return 'kat-coder' }
    if ($name -match '(?i)Qwen3[._-]?8') { return 'qwen38' }
    if ($name -match '(?i)Qwen3[._-]?[56]') { return 'qwen3x' }
    if ($name -match '(?i)Gemma4') { return 'gemma4' }
    return ''
}

function Test-BeeVisionProjectorCompatibility([string]$ModelPath,[string]$ProjectorPath) {
    if ([string]::IsNullOrWhiteSpace($ModelPath) -or [string]::IsNullOrWhiteSpace($ProjectorPath)) {
        return [pscustomobject]@{ Compatible=$false; Certain=$false; Message='Model or projector path is empty' }
    }
    $sameFolder = $false
    try { $sameFolder = ([IO.Path]::GetFullPath((Split-Path -Parent $ModelPath)) -eq [IO.Path]::GetFullPath((Split-Path -Parent $ProjectorPath))) } catch {}
    if ($sameFolder) {
        return [pscustomobject]@{ Compatible=$true; Certain=$true; Message='Projector is stored next to the model' }
    }
    $modelFamily = Get-BeeModelFamilyToken $ModelPath
    $projectorFamily = Get-BeeModelFamilyToken $ProjectorPath
    if ($modelFamily -and $projectorFamily -and $modelFamily -ne $projectorFamily) {
        return [pscustomobject]@{ Compatible=$false; Certain=$true; Message="Projector family '$projectorFamily' does not match model family '$modelFamily'" }
    }
    if ($modelFamily -and $projectorFamily -and $modelFamily -eq $projectorFamily) {
        return [pscustomobject]@{ Compatible=$true; Certain=$true; Message="Projector matches model family '$modelFamily'" }
    }
    return [pscustomobject]@{ Compatible=$true; Certain=$false; Message='Projector is outside the model folder and family could not be proven; verify manually' }
}

'''
core = replace_once(core, 'function Test-BeeVisionProfile', vision_helpers + 'function Test-BeeVisionProfile', 'vision helper insertion')

core = replace_once(
    core,
    "    if ($mmprojPath -and $mmprojPath -ne $Profile.modelPath -and (Split-Path -Parent $mmprojPath) -ne (Split-Path -Parent $Profile.modelPath)) {\n        $warnings.Add('Projector is outside the model folder; verify that it matches this model family before launch')\n    }",
    "    if ($mmprojPath -and $Profile.modelPath) {\n        $compatibility = Test-BeeVisionProjectorCompatibility ([string]$Profile.modelPath) $mmprojPath\n        if (-not $compatibility.Compatible -and $compatibility.Certain) { $errors.Add(\"Vision projector is incompatible: $($compatibility.Message)\") }\n        elseif (-not $compatibility.Certain) { $warnings.Add([string]$compatibility.Message) }\n    }",
    'vision compatibility validation')

core = replace_once(
    core,
    "    if ([int]$Profile.openCodeOutput -lt 1 -or [int]$Profile.openCodeOutput -ge [int]$Profile.context) { $errors.Add('OpenCode output must be positive and smaller than context') }",
    "    if ([int]$Profile.openCodeOutput -lt 1 -or [int]$Profile.openCodeOutput -ge [int]$Profile.context) { $errors.Add('OpenCode output must be positive and smaller than context') }\n    elseif ([int]$Profile.openCodeOutput -gt 32768) { $warnings.Add('OpenCode output above 32768 rarely helps agentic work and may reduce usable history before compaction; 32768 is the recommended reasoning-model default') }",
    'output validation warning')

core = replace_once(
    core,
    "    $modelLayerCount = if ($Profile.PSObject.Properties['modelLayerCount']) { [int]$Profile.modelLayerCount } else { 0 }",
    "    $modelLayerCount = if ($Profile.PSObject.Properties['modelLayerCount']) { [int]$Profile.modelLayerCount } else { 0 }\n    $tensorOverride = if ($Profile.PSObject.Properties['tensorOverride']) { [string]$Profile.tensorOverride } else { '' }\n    $noMmap = ($Profile.PSObject.Properties['noMmap'] -and [bool]$Profile.noMmap)",
    'runtime tuning validation vars')

core = replace_once(
    core,
    "    if ($cpuMoeLayers -gt 0 -and $moeLayerCount -gt 0 -and $cpuMoeLayers -gt $moeLayerCount) { $warnings.Add(\"CPU MoE layers ($cpuMoeLayers) exceed configured MoE layers ($moeLayerCount); runtime behavior will be authoritative\") }",
    "    if ($cpuMoeLayers -gt 0 -and $moeLayerCount -gt 0 -and $cpuMoeLayers -gt $moeLayerCount) { $warnings.Add(\"CPU MoE layers ($cpuMoeLayers) exceed configured MoE layers ($moeLayerCount); runtime behavior will be authoritative\") }\n    if ($tensorOverride -match \"[`r`n`0]\") { $errors.Add('Tensor override must be a single command-line value without newline or NUL') }\n    if ($tensorOverride -and $tensorOverride -notmatch '=') { $errors.Add('Tensor override must use llama.cpp pattern=backend syntax, for example blk.(24-39).ffn_.*_exps.weight=CPU') }\n    if ($tensorOverride -and ($cpuMoeAll -or $cpuMoeLayers -gt 0)) { $warnings.Add('Both CPU MoE and tensor override are enabled. Prefer one offload strategy unless the combination was intentionally benchmarked.') }\n    $modelNameForWarnings = if ($Profile.modelPath) { [IO.Path]::GetFileName([string]$Profile.modelPath) } else { '' }\n    if ([int]$Profile.cacheReuse -gt 0 -and $modelNameForWarnings -match '(?i)(Ornith|Tiel-Coder)') { $warnings.Add('Cache reuse is not supported by the Ornith/Tiel hybrid-attention context in current BeeLlama builds; set Cache reuse = 0 to avoid a runtime disable warning') }",
    'runtime tuning validation rules')

core = replace_once(
    core,
    "        if ($cpuMoeAll) { $requiredFlags += '--cpu-moe' }\n        elseif ($cpuMoeLayers -gt 0) { $requiredFlags += '--n-cpu-moe' }",
    "        if ($cpuMoeAll) { $requiredFlags += '--cpu-moe' }\n        elseif ($cpuMoeLayers -gt 0) { $requiredFlags += '--n-cpu-moe' }\n        if ($tensorOverride) { $requiredFlags += '-ot' }\n        if ($noMmap) { $requiredFlags += '--no-mmap' }",
    'runtime required flags')

core = replace_once(
    core,
    "    if ($cpuMoeAll) { $args.Add('--cpu-moe') }\n    elseif ($cpuMoeLayers -gt 0) {\n        foreach ($value in @('--n-cpu-moe',[string]$cpuMoeLayers)) { $args.Add($value) }\n    }",
    "    if ($cpuMoeAll) { $args.Add('--cpu-moe') }\n    elseif ($cpuMoeLayers -gt 0) {\n        foreach ($value in @('--n-cpu-moe',[string]$cpuMoeLayers)) { $args.Add($value) }\n    }\n    $tensorOverride = if ($Profile.PSObject.Properties['tensorOverride']) { [string]$Profile.tensorOverride } else { '' }\n    if (-not [string]::IsNullOrWhiteSpace($tensorOverride)) { foreach ($value in @('-ot',$tensorOverride.Trim())) { $args.Add([string]$value) } }\n    if ($Profile.PSObject.Properties['noMmap'] -and [bool]$Profile.noMmap) { $args.Add('--no-mmap') }",
    'runtime args')

fingerprint_fn = r'''
function Get-BeeProfileRuntimeFingerprint([Parameter(Mandatory=$true)]$Profile) {
    $payload = (@(Get-BeeArguments $Profile) -join [char]0)
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

'''
core = replace_once(core, 'function Test-BeeRunningProfileMatch', fingerprint_fn + 'function Test-BeeRunningProfileMatch', 'runtime fingerprint function')

core = replace_once(
    core,
    "        $run = Get-Content -Raw -LiteralPath $script:RunPath | ConvertFrom-Json\n        return ($run.profileId -eq $Profile.id -and",
    "        $run = Get-Content -Raw -LiteralPath $script:RunPath | ConvertFrom-Json\n        if ($run.PSObject.Properties['runtimeFingerprint']) {\n            return ([string]$run.profileId -eq [string]$Profile.id -and [string]$run.runtimeFingerprint -eq (Get-BeeProfileRuntimeFingerprint $Profile))\n        }\n        return ($run.profileId -eq $Profile.id -and",
    'runtime fingerprint match')

core = replace_once(
    core,
    "context=$profile.context; cpuMoeLayers=",
    "context=$profile.context; runtimeFingerprint=(Get-BeeProfileRuntimeFingerprint $profile); cpuMoeLayers=",
    'run metadata fingerprint')

write(core_path, core)

# ---------------------------------------------------------------------------
# UI and resource estimator
# ---------------------------------------------------------------------------
ui_path = 'ui/BeeLlama-Manager.ps1'
ui = read(ui_path)

ui = ui.replace('<Label Grid.Row="2" Content="Threads"/>', '<Label Grid.Row="2" Content="Threads decode"/>', 1)
ui = ui.replace('<Label Grid.Row="2" Grid.Column="2" Content="Threads batch"/>', '<Label Grid.Row="2" Grid.Column="2" Content="Threads prefill"/>', 1)
ui = ui.replace('<Label Grid.Column="2" Content="Output"/><TextBox Grid.Column="3" Name="OpenCodeOutput" ToolTip="OpenCode output limit"/>', '<Label Grid.Column="2" Content="Output (OpenCode)"/><TextBox Grid.Column="3" Name="OpenCodeOutput" ToolTip="Максимум output tokens, рекламируемый OpenCode. На скорость/VRAM llama-server не влияет; для reasoning-моделей обычно 32768."/>', 1)

moe_xaml = '''<GroupBox Name="MoeGroup" Header="MoE / CPU offload"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="160"/><ColumnDefinition Width="180"/><ColumnDefinition Width="190"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <Label Content="CPU MoE layers"/><TextBox Grid.Column="1" Name="CpuMoeLayers" ToolTip="0 = не переносить routed experts принудительно; N = --n-cpu-moe N. Это способ уместить модель, но он может резко снизить decode."/><CheckBox Grid.Column="2" Grid.ColumnSpan="2" Name="CpuMoeAll" Content="Все MoE experts на CPU (--cpu-moe)"/>
       <Label Grid.Row="1" Content="Tensor override"/><TextBox Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Name="TensorOverride" ToolTip="Точечный llama.cpp -ot/--override-tensor, например blk.(24-39).ffn_.*_exps.weight=CPU. Используйте только проверенный рецепт."/><CheckBox Grid.Row="1" Grid.Column="3" Name="NoMmap" Content="--no-mmap" ToolTip="Не memory-map GGUF. Может быть полезно при тяжёлом CPU offload и достаточном объёме RAM; обычно выключено."/>
       <Label Grid.Row="2" Content="MoE layers"/><TextBox Grid.Row="2" Grid.Column="1" Name="MoeLayerCount" ToolTip="Для оценки памяти. 0 = неизвестно/авто по известному имени модели"/><Label Grid.Row="2" Grid.Column="2" Content="Expert weights %"/><TextBox Grid.Row="2" Grid.Column="3" Name="MoeExpertWeightPercent" ToolTip="Доля GGUF, приходящаяся на routed experts. Например Ornith ≈ 93%."/>
       <Label Grid.Row="3" Content="Model layers"/><TextBox Grid.Row="3" Grid.Column="1" Name="ModelLayerCount" ToolTip="Используется для списка GPU layers и оценки. 0 = авто по известному имени модели"/><TextBlock Grid.Row="3" Grid.Column="2" Grid.ColumnSpan="2" Name="MoeHint" Text="Параметры MoE определятся после выбора модели" Foreground="#8FC8EA" TextWrapping="Wrap" Margin="8,5"/>
      </Grid></GroupBox>'''
ui = sub_once(ui, r'<GroupBox Name="MoeGroup" Header="MoE / CPU offload">.*?</Grid></GroupBox>', moe_xaml, 'MoE XAML')

ui = replace_once(ui, "    Threads='Число CPU-потоков при генерации и операциях, выполняемых на CPU.'", "    Threads='CPU-потоки для decode/генерации и операций, оставшихся на CPU. Больше логических потоков не всегда быстрее; для 16-ядерного CPU разумный старт — 16.'", 'threads tooltip')
ui = replace_once(ui, "    ThreadsBatch='Число CPU-потоков для пакетной обработки prompt.'", "    ThreadsBatch='CPU-потоки для prompt processing/prefill. Это отдельный параметр от Threads decode.'", 'threads batch tooltip')
ui = replace_once(ui, "    CacheReuse='Минимальный объём совпавшего префикса для повторного использования prompt cache. Для multimodal runtime может отключить эту функцию.'", "    CacheReuse='Минимальный объём совпавшего префикса для повторного использования prompt cache. 0 отключает. Для Ornith/Tiel hybrid-attention текущий BeeLlama отключает cache reuse автоматически.'", 'cache reuse tooltip')
ui = replace_once(ui, "    OpenCodeOutput='Максимум output tokens, который OpenCode считает доступным. Он должен быть меньше физического context.'", "    OpenCodeOutput='Максимум output tokens, который BeeForge сообщает OpenCode. Это НЕ VRAM и не reasoning budget llama-server. Для очень думающих моделей рекомендуемый default — 32768; значения выше обычно не дают пользы и могут раньше приблизить compaction.'", 'output tooltip')
ui = replace_once(ui, "    MtpNMax='Максимальное число speculative tokens за шаг. Большее значение не гарантирует ускорение и может увеличить расход памяти.'", "    MtpNMax='Максимальное число speculative tokens за шаг. Основной прирост VRAM возникает от самого включения MTP; 2/3/4 обычно меняют память мало, а скорость зависит от acceptance rate.'\n    TensorOverride='Точечный tensor-level offload через -ot. Предпочтительнее грубого CPU MoE, если для конкретной модели опубликован проверенный рецепт.'\n    NoMmap='Передать --no-mmap. Это не универсальное ускорение: используйте при CPU offload только после A/B-теста и при достаточном объёме RAM.'", 'new tooltips')

preset_fn = r'''function Get-MoEPreset([string]$ModelPath) {
    $name = if ([string]::IsNullOrWhiteSpace($ModelPath)) { '' } else { [IO.Path]::GetFileName($ModelPath) }
    if ($name -match '(?i)(Ornith|Tiel-Coder)') {
        return [pscustomobject]@{ IsMoe=$true; MoeLayers=40; ModelLayers=40; ExpertPercent=93.0; CacheReuseDefault=0; Label='Ornith/Tiel: 40 layers, 256 experts / 8 active; routed experts ≈93%. Hybrid attention: cache reuse выключайте. CPU MoE — capacity fallback, не free speed.' }
    }
    if ($name -match '(?i)(KAT-Coder|Qwen3[._-]?6.*35B.*A3B)') {
        return [pscustomobject]@{ IsMoe=$true; MoeLayers=40; ModelLayers=40; ExpertPercent=93.0; CacheReuseDefault=$null; Label='Qwen 35B-A3B/KAT family: 40 MoE layers; expert share ≈93% heuristic. Для скорости предпочитайте проверенный tensor override или quant, почти помещающийся в VRAM.' }
    }
    if ($name -match '(?i)Gemma4.*26B.*A4B') {
        return [pscustomobject]@{ IsMoe=$true; MoeLayers=30; ModelLayers=30; ExpertPercent=90.0; CacheReuseDefault=$null; Label='Gemma4 26B-A4B: 30 MoE layers; expert share = conservative 90% heuristic.' }
    }
    if ($name -match '(?i)Qwen3[._-]?8.*27B') {
        return [pscustomobject]@{ IsMoe=$false; MoeLayers=0; ModelLayers=64; ExpertPercent=0.0; CacheReuseDefault=$null; Label='Qwen3.8-27B Dense: 64 layers. CPU MoE не используется.' }
    }
    return [pscustomobject]@{ IsMoe=$false; MoeLayers=0; ModelLayers=0; ExpertPercent=0.0; CacheReuseDefault=$null; Label='Неизвестная архитектура: при MoE укажите MoE layers / Expert weights % вручную; estimator остаётся консервативным.' }
}'''
ui = sub_once(ui, r'function Get-MoEPreset\(\[string\]\$ModelPath\) \{.*?\n\}', preset_fn, 'Get-MoEPreset')

update_moe_fn = r'''function Update-MoEHint([switch]$ApplyDefaults,[switch]$ForcePreset) {
    $preset = Get-MoEPreset (UI 'ModelPath').Text
    if ($ApplyDefaults) {
        $value = 0
        if ($preset.ModelLayers -gt 0 -and ($ForcePreset -or ([int]::TryParse((UI 'ModelLayerCount').Text,[ref]$value) -and $value -eq 0))) { (UI 'ModelLayerCount').Text = [string]$preset.ModelLayers }
        $value = 0
        if ($preset.MoeLayers -gt 0 -and ($ForcePreset -or ([int]::TryParse((UI 'MoeLayerCount').Text,[ref]$value) -and $value -eq 0))) { (UI 'MoeLayerCount').Text = [string]$preset.MoeLayers }
        $percent = 0.0
        $percentParsed = [double]::TryParse((UI 'MoeExpertWeightPercent').Text.Replace(',','.'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$percent)
        if ($preset.ExpertPercent -gt 0 -and ($ForcePreset -or ($percentParsed -and $percent -eq 0.0))) { (UI 'MoeExpertWeightPercent').Text = [string]$preset.ExpertPercent }
        if (-not $preset.IsMoe -and $ForcePreset) { (UI 'MoeLayerCount').Text='0'; (UI 'MoeExpertWeightPercent').Text='0'; (UI 'CpuMoeLayers').Text='0'; (UI 'CpuMoeAll').IsChecked=$false; (UI 'TensorOverride').Text='' }
        if ($ForcePreset -and $null -ne $preset.CacheReuseDefault -and (UI 'CacheReuse').Text -eq '256') { (UI 'CacheReuse').Text=[string]$preset.CacheReuseDefault }
    }
    (UI 'MoeHint').Text = [string]$preset.Label
    Update-GpuLayerChoices
}'''
ui = sub_once(ui, r'function Update-MoEHint\(\[switch\]\$ApplyDefaults\) \{.*?\n\}', update_moe_fn, 'Update-MoEHint')

refresh_vision_fn = r'''function Refresh-VisionProjectorList([switch]$PreferDetected) {
    try {
        $modelPath = (UI 'ModelPath').Text.Trim()
        $current = (UI 'MmprojPath').Text.Trim()
        $items = @(Get-BeeVisionProjectorFiles $modelPath)
        (UI 'MmprojPath').ItemsSource = $items
        if ($PreferDetected) {
            $modelDirectory = if ($modelPath) { Split-Path -Parent $modelPath } else { '' }
            $sameFolder = @($items | Where-Object { $modelDirectory -and (Split-Path -Parent $_) -eq $modelDirectory } | Select-Object -First 1)
            if ($sameFolder.Count) { $current = [string]$sameFolder[0] }
            else {
                # Never carry a projector from the previous model into a new family.
                $current = ''
                (UI 'VisionEnabled').IsChecked = $false
            }
        }
        (UI 'MmprojPath').Text = $current
        Update-VisionHint
    } catch { (UI 'VisionHint').Text = "Не удалось найти projector: $($_.Exception.Message)" }
}'''
ui = sub_once(ui, r'function Refresh-VisionProjectorList\(\[switch\]\$PreferDetected\) \{.*?\n\}', refresh_vision_fn, 'Refresh-VisionProjectorList')

vision_hint_fn = r'''function Update-VisionHint {
    $enabled = [bool](UI 'VisionEnabled').IsChecked
    $offload = [bool](UI 'VisionOffload').IsChecked
    $modelPath = (UI 'ModelPath').Text.Trim()
    $mmprojPath = (UI 'MmprojPath').Text.Trim()
    if (-not $enabled) { (UI 'VisionHint').Foreground='#98A4B5'; (UI 'VisionHint').Text='Выключено: OpenCode будет работать только с текстом'; return }
    if ([string]::IsNullOrWhiteSpace($mmprojPath)) { (UI 'VisionHint').Foreground='#FFBA69'; (UI 'VisionHint').Text='Выберите mmproj*.gguf — запуск будет заблокирован до выбора'; return }
    if (-not (Test-Path -LiteralPath $mmprojPath -PathType Leaf)) { (UI 'VisionHint').Foreground='#FF7B7B'; (UI 'VisionHint').Text='Projector-файл не найден'; return }
    $compatibility = Test-BeeVisionProjectorCompatibility $modelPath $mmprojPath
    $sizeMiB = (Get-Item -LiteralPath $mmprojPath).Length / 1MB
    $placement = if ($offload) { "GPU: +$([math]::Round($sizeMiB)) MiB VRAM" } else { "RAM: +$([math]::Round($sizeMiB)) MiB (рекомендуется)" }
    if (-not $compatibility.Compatible -and $compatibility.Certain) { (UI 'VisionHint').Foreground='#FF7B7B'; (UI 'VisionHint').Text="НЕСОВМЕСТИМ: $($compatibility.Message)"; return }
    if ($compatibility.Certain) { (UI 'VisionHint').Foreground='#79D6A3'; (UI 'VisionHint').Text="$($compatibility.Message); $placement" }
    else { (UI 'VisionHint').Foreground='#FFBA69'; (UI 'VisionHint').Text="$($compatibility.Message); $placement" }
}'''
ui = sub_once(ui, r'function Update-VisionHint \{.*?\n\}', vision_hint_fn, 'Update-VisionHint')

ui = replace_once(ui, "ProfileName='name'; ModelPath='modelPath'; ServerPath='serverPath'; Alias='alias'; Context='context'; Parallel='parallel'; Batch='batch'; Ubatch='ubatch'; Threads='threads'; ThreadsBatch='threadsBatch'; CacheReuse='cacheReuse'; Host='host'; Port='port'; RemoteBaseUrl='remoteBaseUrl'; OpenCodeOutput='openCodeOutput'; KvTailTokens='kvTailTokens'; ReasoningBudget='reasoningBudget'; Temperature='temperature'; TopP='topP'; TopK='topK'; MinP='minP'; RepeatPenalty='repeatPenalty'; CpuMoeLayers='cpuMoeLayers'; MoeLayerCount='moeLayerCount'; ModelLayerCount='modelLayerCount'", "ProfileName='name'; ModelPath='modelPath'; ServerPath='serverPath'; Alias='alias'; Context='context'; Parallel='parallel'; Batch='batch'; Ubatch='ubatch'; Threads='threads'; ThreadsBatch='threadsBatch'; CacheReuse='cacheReuse'; Host='host'; Port='port'; RemoteBaseUrl='remoteBaseUrl'; OpenCodeOutput='openCodeOutput'; KvTailTokens='kvTailTokens'; ReasoningBudget='reasoningBudget'; Temperature='temperature'; TopP='topP'; TopK='topK'; MinP='minP'; RepeatPenalty='repeatPenalty'; CpuMoeLayers='cpuMoeLayers'; MoeLayerCount='moeLayerCount'; ModelLayerCount='modelLayerCount'; TensorOverride='tensorOverride'", 'load map')
ui = replace_once(ui, "@('MtpEnabled','mtpEnabled'),@('CpuMoeAll','cpuMoeAll')", "@('MtpEnabled','mtpEnabled'),@('CpuMoeAll','cpuMoeAll'),@('NoMmap','noMmap')", 'checkbox load map')

ui = replace_once(ui, "    foreach ($field in @('connectionMode','remoteBaseUrl','visionEnabled','visionOffload','mmprojPath')) {", "    foreach ($field in @('connectionMode','remoteBaseUrl','visionEnabled','visionOffload','mmprojPath','tensorOverride','noMmap')) {", 'form schema fields')
ui = replace_once(ui, "            $defaultValue = if ($field -eq 'connectionMode') { 'LocalHost' } elseif($field-in@('mmprojPath','remoteBaseUrl')) { '' } else { $false }", "            $defaultValue = if ($field -eq 'connectionMode') { 'LocalHost' } elseif($field-in@('mmprojPath','remoteBaseUrl','tensorOverride')) { '' } else { $false }", 'form schema defaults')
ui = replace_once(ui, "    $p.cpuMoeLayers=[int](UI 'CpuMoeLayers').Text; $p.cpuMoeAll=[bool](UI 'CpuMoeAll').IsChecked; $p.moeLayerCount=[int](UI 'MoeLayerCount').Text; $p.modelLayerCount=[int](UI 'ModelLayerCount').Text", "    $p.cpuMoeLayers=[int](UI 'CpuMoeLayers').Text; $p.cpuMoeAll=[bool](UI 'CpuMoeAll').IsChecked; $p.moeLayerCount=[int](UI 'MoeLayerCount').Text; $p.modelLayerCount=[int](UI 'ModelLayerCount').Text; $p.tensorOverride=(UI 'TensorOverride').Text.Trim(); $p.noMmap=[bool](UI 'NoMmap').IsChecked", 'form runtime fields')

resource_fn = r'''function Update-ResourceEstimate {
    try {
        $p = Get-FormProfile
        if((Get-BeeProfileConnectionMode $p)-eq'RemoteClient'){throw 'Удалённый профиль использует ресурсы основного ПК; локальная оценка VRAM/RAM неприменима.'}
        if (-not (Test-Path -LiteralPath $p.modelPath -PathType Leaf)) { throw 'Сначала выберите существующий GGUF-файл' }
        $modelMiB = (Get-Item -LiteralPath $p.modelPath).Length / 1MB
        $visionMiB = 0.0
        if ([bool]$p.visionEnabled -and -not [string]::IsNullOrWhiteSpace([string]$p.mmprojPath) -and (Test-Path -LiteralPath $p.mmprojPath -PathType Leaf)) { $visionMiB = (Get-Item -LiteralPath $p.mmprojPath).Length / 1MB }
        $visionGpuMiB = if ([bool]$p.visionOffload) { $visionMiB } else { 0.0 }
        $visionRamMiB = if ([bool]$p.visionOffload) { 0.0 } else { $visionMiB }
        $status = Get-BeeServerStatus
        $gpuTotalMiB = if ($status.VramTotalMiB) { [double]$status.VramTotalMiB } else { 16303.0 }

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
        $tensorOverride = [string]$p.tensorOverride
        $fineOverride = -not [string]::IsNullOrWhiteSpace($tensorOverride)
        $cpuMoeWeightFraction = 0.0
        if ([bool]$p.cpuMoeAll -and $moeWeightFraction -gt 0) { $cpuMoeWeightFraction = $moeWeightFraction }
        elseif ($cpuMoeLayers -gt 0 -and $moeLayerCount -gt 0 -and $moeWeightFraction -gt 0) { $cpuMoeWeightFraction = $moeWeightFraction * [math]::Min(1.0,$cpuMoeLayers/[double]$moeLayerCount) }
        $effectiveGpuWeightFraction = [math]::Max(0.0,[math]::Min(1.0,$gpuFraction * (1.0-$cpuMoeWeightFraction)))
        $moeNote = if ($fineOverride) { "tensor override активен: $tensorOverride; точную долю CPU/GPU estimator не знает" } elseif ([bool]$p.cpuMoeAll) { "все routed MoE experts на CPU; оценочная доля experts $('{0:P0}' -f $moeWeightFraction)" } elseif ($cpuMoeLayers -gt 0) { "CPU MoE $cpuMoeLayers/$moeLayerCount; оценочно в RAM уходит $('{0:P0}' -f $cpuMoeWeightFraction) весов" } else { 'CPU MoE выключен' }

        $context = [double]$p.context
        $tail = [math]::Min([double]$p.kvTailTokens,$context)
        $mainFactor = ((Get-KvMemoryFactor ([string]$p.kvK)) + (Get-KvMemoryFactor ([string]$p.kvV))) / 2.0
        $tailFactor = Get-KvMemoryFactor ([string]$p.kvTailType)
        $effectiveKvFactor = if ($context -gt 0) { ((($context-$tail)*$mainFactor)+($tail*$tailFactor))/$context } else { 1.0 }
        # Conservative Qwen38-calibrated upper estimate. Hybrid/linear attention may use materially less classic KV.
        $kvMiB = 2306.0 * ($context / 162000.0) * $effectiveKvFactor
        $weightVramMiB = $modelMiB * 1.02 * $effectiveGpuWeightFraction
        $bufferScale = [math]::Sqrt(([math]::Max(1,[double]$p.batch)/2048.0) * ([math]::Max(1,[double]$p.ubatch)/512.0))
        $buffersMiB = 350.0 * $bufferScale + (50.0 * [math]::Max(0,[int]$p.parallel-1)) + $visionGpuMiB
        if (-not [bool]$p.flashAttention) { $buffersMiB += 250.0 }
        if ([bool]$p.mtpEnabled) { $buffersMiB += 350.0 }
        $idleMiB = if (-not $status.Running -and $status.VramUsedMiB) { [math]::Max(760.0,[double]$status.VramUsedMiB) } else { 760.0 }
        $estimateMiB = $idleMiB + $weightVramMiB + $kvMiB + $buffersMiB
        $headroomMiB = $gpuTotalMiB - $estimateMiB
        $ramSpillMiB = $modelMiB * (1.0-$effectiveGpuWeightFraction) * 1.05 + $visionRamMiB
        $runningMatch = $false
        try { $runningMatch = [bool](Test-BeeRunningProfileMatch $p) } catch {}
        $actualHeadroomMiB = $null
        if ($runningMatch -and $status.VramUsedMiB) { $actualHeadroomMiB = [double]$status.VramTotalMiB - [double]$status.VramUsedMiB }

        (UI 'EstimateModelSize').Text = ('{0:N2} GiB' -f ($modelMiB/1024.0))
        (UI 'EstimateVram').Text = if ($fineOverride) { ('≤ {0:N2} GiB*' -f ($estimateMiB/1024.0)) } else { ('{0:N2} GiB' -f ($estimateMiB/1024.0)) }
        (UI 'EstimateHeadroom').Text = if ($null -ne $actualHeadroomMiB) { ('{0:N0} MiB фактически' -f $actualHeadroomMiB) } elseif ($fineOverride) { 'н/д до запуска' } else { ('{0:N0} MiB' -f $headroomMiB) }
        (UI 'EstimateSpill').Text = if ($fineOverride) { 'н/д (tensor override)' } else { ('{0:N2} GiB' -f ($ramSpillMiB/1024.0)) }
        (UI 'ActualVram').Text = if ($status.VramUsedMiB) { '{0:N2} / {1:N2} GiB' -f ($status.VramUsedMiB/1024.0),($status.VramTotalMiB/1024.0) } else { 'н/д' }
        (UI 'ActualRam').Text = if ($status.RamUsedGiB) { '{0:N1} / {1:N1} GiB' -f $status.RamUsedGiB,$status.RamTotalGiB } else { 'н/д' }
        (UI 'ResourceWeights').Text = if ($fineOverride) { ('≤ {0:N2} GiB*' -f ($weightVramMiB/1024.0)) } else { ('{0:N2} GiB' -f ($weightVramMiB/1024.0)) }
        (UI 'ResourceKv').Text = ('{0:N0} MiB' -f $kvMiB)
        (UI 'ResourceBuffers').Text = ('{0:N0} MiB' -f $buffersMiB)
        (UI 'ResourceBackground').Text = ('{0:N0} MiB' -f $idleMiB)
        $offloadMode = if ($fineOverride) { 'tensor override' } elseif ([bool]$p.cpuMoeAll) { 'all CPU MoE' } elseif ($cpuMoeLayers -gt 0) { "CPU MoE $cpuMoeLayers" } else { 'GPU/default' }
        (UI 'ResourceCalculatedFrom').Text = "Рассчитано $(Get-Date -Format 'HH:mm:ss') из формы: ctx $([int]$p.context) | KV $($p.kvK)/$($p.kvV) | GPU layers $($p.gpuLayers)/$modelLayerCount | $offloadMode"

        $baselineContext = 162000.0
        $baselineTail = [math]::Min([double]$p.kvTailTokens,$baselineContext)
        $baselineEffective = ((($baselineContext-$baselineTail)*$mainFactor)+($baselineTail*$tailFactor))/$baselineContext
        $baselineKvMiB = 2306.0 * $baselineEffective
        $contextSavingMiB = $baselineKvMiB - $kvMiB
        $kvComparison = if ($p.kvK -eq 'q4_0' -and $p.kvV -eq 'q4_0') { 'q4_0/q4_0 и KVarN4/KVarN4 оцениваются почти одинаково: оба хранят KV примерно в 4 битах.' } else { "Коэффициент KV относительно KVarN4/KVarN4: $('{0:N2}'-f$mainFactor)x." }
        $visionImpact = if ([bool]$p.visionEnabled) { if ($visionMiB -gt 0) { if ([bool]$p.visionOffload) { "Vision projector добавляет примерно $('{0:N0}' -f $visionGpuMiB) MiB к VRAM." } else { "Vision projector остаётся в RAM: примерно $('{0:N0}' -f $visionRamMiB) MiB; VRAM сохраняется для контекста." } } else { 'Vision включён, но projector пока не выбран или не найден.' } } else { 'Vision выключен.' }
        $moeImpact = if ($fineOverride) { 'Точечный tensor override активен; его реальный memory split определяется runtime и проверяется запуском.' } elseif ($cpuMoeWeightFraction -gt 0) { "CPU MoE уменьшает оценочную GPU-долю весов примерно на $('{0:P0}'-f$cpuMoeWeightFraction), но это может резко снизить decode из-за RAM/CPU bottleneck." } elseif ($moeWeightFraction -gt 0) { 'MoE experts остаются GPU/default; это лучший режим скорости, если quant действительно помещается.' } else { 'CPU MoE не используется.' }
        (UI 'ResourceImpact').Text = "Что изменилось: context $([int]$p.context) уменьшает KV примерно на $('{0:N0}'-f[math]::Max(0,$contextSavingMiB)) MiB относительно 162K при тех же KV-настройках. $kvComparison $moeImpact $visionImpact KV для hybrid/linear-attention архитектур показан как консервативная Qwen38-оценка до реального запуска."

        $targetHeadroomMiB = 800.0
        if ($fineOverride) {
            (UI 'ResourceRecommendation').Text='Рекомендация: tensor override нельзя надёжно оценить по размеру GGUF. Запустите короткий 16–32K профиль, проверьте фактические VRAM/RAM и decode, затем увеличивайте context. Не комбинируйте с CPU MoE без отдельного A/B-теста.'
        } elseif ($moeWeightFraction -gt 0) {
            if ($cpuMoeWeightFraction -gt 0) {
                (UI 'ResourceRecommendation').Text='Рекомендация MoE: CPU MoE — способ УМЕСТИТЬ модель, а не бесплатное ускорение. Если decode сильно падает, выбирайте меньший quant, который почти целиком помещается в VRAM, либо используйте опубликованный tensor-level override.'
            } elseif ($headroomMiB -ge $targetHeadroomMiB) {
                (UI 'ResourceRecommendation').Text='Рекомендация MoE: оставьте CPU MoE = 0 — модель по оценке помещается с рабочим запасом. Сначала измерьте decode на 16–32K, затем увеличивайте context.'
            } else {
                (UI 'ResourceRecommendation').Text='Рекомендация MoE: модель не помещается целиком. Для daily-driver сначала возьмите меньший quant; не уменьшайте GPU layers как первый шаг. CPU MoE используйте только как capacity fallback, а точечный -ot — когда есть проверенный рецепт.'
            }
        } else {
            $fullWeightMiB = $modelMiB*1.02
            $availableForWeights = $gpuTotalMiB-$targetHeadroomMiB-$idleMiB-$kvMiB-$buffersMiB
            $recommendedFraction = [math]::Max(0.0,[math]::Min(1.0,$availableForWeights/$fullWeightMiB))
            $recommendedLayers = [math]::Floor($recommendedFraction*$modelLayerCount)
            $recommendedRamMiB = $modelMiB*(1.0-$recommendedFraction)*1.05
            if ($recommendedFraction -ge 0.995) { (UI 'ResourceRecommendation').Text='Рекомендация: все GPU layers должны помещаться с целевым запасом около 800 MiB.' }
            else { (UI 'ResourceRecommendation').Text="Рекомендация для запаса около 800 MiB: начните примерно с GPU layers = $recommendedLayers из $modelLayerCount. Около $('{0:N2}'-f($recommendedRamMiB/1024.0)) GiB весов перейдёт в RAM. Точное число слоёв подтвердите реальным запуском." }
        }

        $card = UI 'ResourceRiskCard'
        if ($null -ne $actualHeadroomMiB) {
            if ($actualHeadroomMiB -ge 1200) { $card.Background='#213A2B';$card.BorderBrush='#3EA66B' }
            elseif ($actualHeadroomMiB -ge 500) { $card.Background='#394024';$card.BorderBrush='#A6A63E' }
            else { $card.Background='#49351F';$card.BorderBrush='#D58A36' }
            $verdict="Фактический текущий запуск: запас dedicated VRAM около $([math]::Round($actualHeadroomMiB)) MiB. Это надёжнее расчётной модели."
        } elseif ($fineOverride) {
            $card.Background='#49351F';$card.BorderBrush='#D58A36';$verdict='Tensor override активен: точный VRAM split неизвестен до запуска. Показанная VRAM — консервативная верхняя граница без учёта точечного offload.'
        } elseif ($headroomMiB -ge 1200) { $card.Background='#213A2B';$card.BorderBrush='#3EA66B';$verdict="Хороший запас: ожидается размещение с запасом около $([math]::Round($headroomMiB)) MiB." }
        elseif ($headroomMiB -ge 500) { $card.Background='#394024';$card.BorderBrush='#A6A63E';$verdict="Допустимо, но близко к пределу: расчётный запас около $([math]::Round($headroomMiB)) MiB. Проверьте real peak VRAM." }
        elseif ($headroomMiB -ge 0) { $card.Background='#49351F';$card.BorderBrush='#D58A36';$verdict='Высокий риск: практический запас меньше 500 MiB. Возможен Shared GPU Memory spill или OOM.' }
        else { $card.Background='#4A2428';$card.BorderBrush='#D85862';$verdict="Не помещается по консервативной оценке: превышение VRAM примерно на $([math]::Round(-$headroomMiB)) MiB." }
        (UI 'ResourceVerdict').Text = $verdict
        $mmapNote = if ([bool]$p.noMmap) { '--no-mmap ON' } else { 'mmap default' }
        (UI 'ResourceDetails').Text = "Модель: $([IO.Path]::GetFileName($p.modelPath))`nРаскладка: $layerNote`nMoE: $moeNote`nMemory mapping: $mmapNote`nДля MoE/hybrid не принимайте расчёт за benchmark: окончательная проверка — реальный запуск, dedicated VRAM/RAM, prompt tok/s и decode tok/s."
    } catch {
        (UI 'ResourceVerdict').Text = "Не удалось рассчитать: $($_.Exception.Message)"
        (UI 'ResourceRiskCard').Background='#4A2428'; (UI 'ResourceRiskCard').BorderBrush='#D85862'
    }
}'''
ui = sub_once(ui, r'function Update-ResourceEstimate \{.*?\n\}\n\nfunction Confirm-Warnings', resource_fn + '\n\nfunction Confirm-Warnings', 'resource estimator')

ui = replace_once(ui, "foreach($controlName in @('Context','Parallel','Batch','Ubatch','KvTailTokens','CpuMoeLayers','MoeLayerCount','MoeExpertWeightPercent','ModelLayerCount'))", "foreach($controlName in @('Context','Parallel','Batch','Ubatch','KvTailTokens','CpuMoeLayers','MoeLayerCount','MoeExpertWeightPercent','ModelLayerCount','TensorOverride'))", 'resource text events')
ui = replace_once(ui, "foreach($controlName in @('FlashAttention','MtpEnabled','VisionEnabled','VisionOffload','CpuMoeAll'))", "foreach($controlName in @('FlashAttention','MtpEnabled','VisionEnabled','VisionOffload','CpuMoeAll','NoMmap'))", 'resource checkbox events')
ui = ui.replace("Update-MoEHint -ApplyDefaults; Queue-ResourceEstimate; Update-Preview })", "Update-MoEHint -ApplyDefaults -ForcePreset; Queue-ResourceEstimate; Update-Preview })", 2)

clone_old = "(UI 'CloneProfile').Add_Click({ try { $p=Get-FormProfile;$p.id='profile-'+[guid]::NewGuid().ToString('N').Substring(0,10);$p.name=$p.name+' — копия';$p.protected=$false;$s=Get-BeeProfileStore;$s.profiles=@($s.profiles)+$p;Save-BeeProfileStore $s;Refresh-ProfileList $p.id } catch { Show-Message $_.Exception.Message 'Ошибка' Error } })"
clone_new = "(UI 'CloneProfile').Add_Click({ try { $p=Get-FormProfile;$p.id='profile-'+[guid]::NewGuid().ToString('N').Substring(0,10);$p.name=$p.name+' — копия';$p.protected=$false;$s=Get-BeeProfileStore;$used=@($s.profiles|ForEach-Object{[string]$_.alias});$baseAlias=([string]$p.alias+'-copy');$candidate=$baseAlias;$n=2;while($used-contains$candidate){$candidate=$baseAlias+'-'+$n;$n++};$p.alias=$candidate;$s.profiles=@($s.profiles)+$p;Save-BeeProfileStore $s;Refresh-ProfileList $p.id } catch { Show-Message $_.Exception.Message 'Ошибка' Error } })"
ui = replace_once(ui, clone_old, clone_new, 'unique clone alias')

write(ui_path, ui)

# ---------------------------------------------------------------------------
# Example profiles: safe defaults + new fields
# ---------------------------------------------------------------------------
profile_path = ROOT / 'config/templates/profiles.example.json'
profiles = json.loads(profile_path.read_text(encoding='utf-8-sig'))
for p in profiles.get('profiles', []):
    if p.get('openCodeOutput') in (32764, 65528):
        p['openCodeOutput'] = 32768
    p.setdefault('tensorOverride', '')
    p.setdefault('noMmap', False)
profile_path.write_text(json.dumps(profiles, ensure_ascii=False, indent=2) + '\n', encoding='utf-8-sig')

# ---------------------------------------------------------------------------
# Tests + CI
# ---------------------------------------------------------------------------
smoke = r'''﻿Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BeeLlamaManager.Core.psm1') -Force

$p = Get-BeeNewProfileTemplate
if ([int]$p.openCodeOutput -ne 32768) { throw 'New profile output default must be 32768' }

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

$p.cpuMoeAll = $false
$p.tensorOverride = 'blk.(24-39).ffn_.*_exps.weight=CPU'
$p.noMmap = $true
$args3 = @(Get-BeeArguments $p)
$oi = [Array]::IndexOf($args3,'-ot')
if ($oi -lt 0 -or $args3[$oi+1] -ne $p.tensorOverride) { throw 'tensor override was not emitted' }
if ($args3 -notcontains '--no-mmap') { throw '--no-mmap was not emitted' }

$f1 = Get-BeeProfileRuntimeFingerprint $p
$p.batch = 1024
$f2 = Get-BeeProfileRuntimeFingerprint $p
if ($f1 -eq $f2) { throw 'runtime fingerprint did not change after batch change' }

$ok = Test-BeeVisionProjectorCompatibility 'C:\Models\Qwen3.8-27B\model.gguf' 'C:\Models\Qwen3.8-27B\mmproj-F16.gguf'
if (-not $ok.Compatible -or -not $ok.Certain) { throw 'same-folder projector should be accepted' }
$bad = Test-BeeVisionProjectorCompatibility 'C:\Models\Ornith-1.5\model.gguf' 'C:\Models\Qwen3.8-27B\mmproj-Qwen3.8-BF16.gguf'
if ($bad.Compatible -or -not $bad.Certain) { throw 'obvious cross-family projector mismatch should be rejected' }

Write-Host 'Runtime profile smoke test passed.'
'''
write('tests/RuntimeProfile.Smoke.ps1', smoke)

workflow = read('.github/workflows/powershell-smoke.yml')
workflow = workflow.replace("          $files = @('scripts/BeeLlamaManager.Core.psm1','ui/BeeLlama-Manager.ps1','tests/MoEProfile.Smoke.ps1')", "          $files = @('scripts/BeeLlamaManager.Core.psm1','ui/BeeLlama-Manager.ps1') + @(Get-ChildItem tests -Filter '*.ps1' | ForEach-Object { $_.FullName })")
workflow = workflow.replace("      - name: MoE profile smoke\n        shell: pwsh\n        run: pwsh -NoProfile -File tests/MoEProfile.Smoke.ps1", "      - name: Profile smoke tests\n        shell: pwsh\n        run: |\n          pwsh -NoProfile -File tests/MoEProfile.Smoke.ps1\n          pwsh -NoProfile -File tests/RuntimeProfile.Smoke.ps1")
write('.github/workflows/powershell-smoke.yml', workflow)

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------
doc = r'''# Model/runtime tuning notes

BeeForge profiles distinguish settings that affect the **llama-server runtime** from metadata advertised to **OpenCode**.

## CPU threads

- `Threads decode` maps to `-t/--threads` and mainly affects decode plus operations left on CPU.
- `Threads prefill` maps to `-tb/--threads-batch` and mainly affects prompt processing/prefill.
- More logical threads are not automatically faster. Benchmark both values on the target CPU.

## OpenCode output

`Output (OpenCode)` is written to `provider.beellama.models.<alias>.limit.output`. It is **not** a VRAM setting and is not passed to llama-server. For reasoning models BeeForge uses `32768` as the default so long reasoning turns are not cramped without advertising an unnecessarily huge 65K response.

The server-side `Reasoning budget` is a separate setting.

## Vision projector safety

When the main GGUF changes, BeeForge only auto-selects a projector located in the **same model directory**. It no longer silently carries a projector from the previous model. Obvious cross-family combinations such as Ornith + Qwen3.8 mmproj are rejected before launch. Projectors stored elsewhere can still be selected manually; unknown family matches produce a warning.

## MoE on limited VRAM

`CPU MoE layers` / `--n-cpu-moe` is primarily a **capacity fallback**. It can make a large GGUF load, but substantial routed-expert offload can make decode RAM/CPU-bound. Do not assume a 20 GB Q4 MoE will stay fast on a 16 GB GPU just because it starts successfully.

Preferred order for a daily driver:

1. choose the largest quant that nearly fits in VRAM at the context you actually need;
2. keep `GPU layers = all` where possible;
3. benchmark short context (16–32K) first to establish decode potential;
4. increase context after speed is confirmed;
5. use `CPU MoE` only when the quality benefit is worth the speed loss;
6. when a model author publishes a tested tensor-level recipe, use `Tensor override` (`-ot`) instead of broad offload and A/B-test it.

`--no-mmap` is exposed as an opt-in switch for CPU-heavy offload experiments. It is not a universal speed switch and requires enough physical RAM.

## Runtime-state correctness

BeeForge stores a SHA-256 fingerprint of the effective llama-server argument list for each launch. Saving a profile after changing batch, KV, MTP, threads, MoE or other runtime settings no longer makes the UI assume that the already-running server matches the edited profile.

## Resource estimator

The resource tab is intentionally conservative. Hybrid/linear-attention models can use materially less classic KV cache than the Qwen3.8 calibration. Fine-grained tensor overrides cannot be inferred from GGUF size, so the estimator marks their split as unknown and prefers actual dedicated VRAM/RAM after a real launch.
'''
write('docs/MODEL-RUNTIME-TUNING.md', doc)

readme = read('README.md')
marker = 'docs/MODEL-RUNTIME-TUNING.md'
if marker not in readme:
    readme += '\n\n## Runtime tuning\n\nДля различий `Threads decode` / `Threads prefill`, OpenCode Output, безопасного vision projector, MoE CPU offload и tensor override см. [`docs/MODEL-RUNTIME-TUNING.md`](docs/MODEL-RUNTIME-TUNING.md).\n'
write('README.md', readme)

# Remove the one-shot bootstrap files from the final feature commit.
for rel in ['tools/apply-runtime-hardening.py', '.github/workflows/runtime-hardening-bootstrap.yml']:
    p = ROOT / rel
    if p.exists():
        p.unlink()

print('Runtime hardening patch applied successfully.')
