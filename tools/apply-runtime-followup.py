from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / 'ui/BeeLlama-Manager.ps1'
text = path.read_text(encoding='utf-8-sig')

old = """    if ($ApplyDefaults) {
        $value = 0
        if ($preset.ModelLayers -gt 0 -and ($ForcePreset -or ([int]::TryParse((UI 'ModelLayerCount').Text,[ref]$value) -and $value -eq 0))) { (UI 'ModelLayerCount').Text = [string]$preset.ModelLayers }
        $value = 0
        if ($preset.MoeLayers -gt 0 -and ($ForcePreset -or ([int]::TryParse((UI 'MoeLayerCount').Text,[ref]$value) -and $value -eq 0))) { (UI 'MoeLayerCount').Text = [string]$preset.MoeLayers }
        $percent = 0.0
        $percentParsed = [double]::TryParse((UI 'MoeExpertWeightPercent').Text.Replace(',','.'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$percent)
        if ($preset.ExpertPercent -gt 0 -and ($ForcePreset -or ($percentParsed -and $percent -eq 0.0))) { (UI 'MoeExpertWeightPercent').Text = [string]$preset.ExpertPercent }
        if (-not $preset.IsMoe -and $ForcePreset) { (UI 'MoeLayerCount').Text='0'; (UI 'MoeExpertWeightPercent').Text='0'; (UI 'CpuMoeLayers').Text='0'; (UI 'CpuMoeAll').IsChecked=$false; (UI 'TensorOverride').Text='' }
        if ($ForcePreset -and $null -ne $preset.CacheReuseDefault -and (UI 'CacheReuse').Text -eq '256') { (UI 'CacheReuse').Text=[string]$preset.CacheReuseDefault }
    }"""
new = """    if ($ApplyDefaults) {
        if ($ForcePreset) {
            # Offload recipes are model-specific. Never carry CPU MoE / -ot / no-mmap
            # from the previous GGUF into a newly selected model.
            (UI 'CpuMoeLayers').Text='0'; (UI 'CpuMoeAll').IsChecked=$false; (UI 'TensorOverride').Text=''; (UI 'NoMmap').IsChecked=$false
            (UI 'ModelLayerCount').Text = if ($preset.ModelLayers -gt 0) { [string]$preset.ModelLayers } else { '0' }
            (UI 'MoeLayerCount').Text = if ($preset.MoeLayers -gt 0) { [string]$preset.MoeLayers } else { '0' }
            (UI 'MoeExpertWeightPercent').Text = if ($preset.ExpertPercent -gt 0) { [string]$preset.ExpertPercent } else { '0' }
        } else {
            $value = 0
            if ($preset.ModelLayers -gt 0 -and [int]::TryParse((UI 'ModelLayerCount').Text,[ref]$value) -and $value -eq 0) { (UI 'ModelLayerCount').Text = [string]$preset.ModelLayers }
            $value = 0
            if ($preset.MoeLayers -gt 0 -and [int]::TryParse((UI 'MoeLayerCount').Text,[ref]$value) -and $value -eq 0) { (UI 'MoeLayerCount').Text = [string]$preset.MoeLayers }
            $percent = 0.0
            if ($preset.ExpertPercent -gt 0 -and [double]::TryParse((UI 'MoeExpertWeightPercent').Text.Replace(',','.'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$percent) -and $percent -eq 0.0) { (UI 'MoeExpertWeightPercent').Text = [string]$preset.ExpertPercent }
        }
        if ($ForcePreset -and $null -ne $preset.CacheReuseDefault -and (UI 'CacheReuse').Text -eq '256') { (UI 'CacheReuse').Text=[string]$preset.CacheReuseDefault }
    }"""
if text.count(old) != 1:
    raise SystemExit(f'Update-MoEHint anchor count: {text.count(old)}')
text = text.replace(old, new, 1)

old2 = """        $actualHeadroomMiB = $null
        if ($runningMatch -and $status.VramUsedMiB) { $actualHeadroomMiB = [double]$status.VramTotalMiB - [double]$status.VramUsedMiB }

        (UI 'EstimateModelSize').Text"""
new2 = """        $actualHeadroomMiB = $null
        if ($runningMatch -and $status.VramUsedMiB) { $actualHeadroomMiB = [double]$status.VramTotalMiB - [double]$status.VramUsedMiB }
        $ramAvailableMiB = if ($status.RamAvailableGiB) { [double]$status.RamAvailableGiB * 1024.0 } else { 0.0 }
        # Before launch, projected CPU/offloaded weights need physical RAM in addition
        # to the currently running Windows/apps. Keep 2 GiB reserve to avoid paging.
        $ramRisk = (-not $runningMatch -and -not $fineOverride -and $ramSpillMiB -gt 0 -and $ramAvailableMiB -gt 0 -and ($ramSpillMiB + 2048.0) -gt $ramAvailableMiB)
        $runningRamRisk = ($runningMatch -and $ramAvailableMiB -gt 0 -and $ramAvailableMiB -lt 2048.0)
        $ramPressureNote = if ($ramRisk) { "RAM risk: ожидаемый CPU/RAM spill $('{0:N2}'-f($ramSpillMiB/1024.0)) GiB при доступных сейчас $('{0:N2}'-f($ramAvailableMiB/1024.0)) GiB. Освободите RAM, уменьшите offload или используйте меньший quant." } elseif ($runningRamRisk) { "RAM risk: после загрузки доступно меньше 2 GiB физической RAM; возможен pagefile и резкое падение скорости." } else { '' }

        (UI 'EstimateModelSize').Text"""
if text.count(old2) != 1:
    raise SystemExit(f'RAM anchor count: {text.count(old2)}')
text = text.replace(old2, new2, 1)

old3 = """        $card = UI 'ResourceRiskCard'
        if ($null -ne $actualHeadroomMiB) {"""
new3 = """        if ($ramPressureNote) { (UI 'ResourceRecommendation').Text = ((UI 'ResourceRecommendation').Text + ' ' + $ramPressureNote).Trim() }

        $card = UI 'ResourceRiskCard'
        if ($null -ne $actualHeadroomMiB) {"""
if text.count(old3) != 1:
    raise SystemExit(f'recommendation anchor count: {text.count(old3)}')
text = text.replace(old3, new3, 1)

old4 = """        (UI 'ResourceVerdict').Text = $verdict
        $mmapNote"""
new4 = """        if ($ramRisk -or $runningRamRisk) { $card.Background='#4A2428';$card.BorderBrush='#D85862';$verdict = $ramPressureNote + ' ' + $verdict }
        (UI 'ResourceVerdict').Text = $verdict.Trim()
        $mmapNote"""
if text.count(old4) != 1:
    raise SystemExit(f'verdict anchor count: {text.count(old4)}')
text = text.replace(old4, new4, 1)

path.write_text(text, encoding='utf-8-sig')
(Path(__file__)).unlink()
print('Follow-up patch applied.')
