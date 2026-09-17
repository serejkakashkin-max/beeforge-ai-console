using System.Text.Json.Nodes;
using LlamaServerLauncher.Services;

namespace BeeForge.Next.Core.Inference;

public sealed record VramPlan(VramEstimate? Estimate, IReadOnlyList<string> Warnings, bool CanJudgeFit)
{
    public string Describe()
    {
        if (Estimate is not { } e) return "Оценка VRAM недоступна: недостаточно данных GGUF.\n" + string.Join("\n", Warnings);
        string GiB(long bytes) => $"{bytes / 1073741824.0:0.00} GiB";
        return $"Предварительная оценка VRAM: {GiB(e.TotalBytes)} + запас\n" +
            $"Веса GPU: {GiB(e.WeightBytes)} · KV: {GiB(e.KvBytes)} · вычисления: {GiB(e.ComputeBytes)}\n" +
            $"Проектор: {GiB(e.ProjectorBytes)} · служебные: {GiB(e.OverheadBytes)}\n" +
            $"Веса и KV в RAM: {GiB(e.HostBytes)} · GPU-блоки: {e.OffloadedBlocks}/{e.TotalBlocks}\n" +
            "Это расчёт, а не измерение. Фактические VRAM/RAM показаны на вкладке Inference.\n" + string.Join("\n", Warnings);
    }
}

public static class VramPlanner
{
    public static VramPlan Read(string modelPath, string profileJson)
    {
        // Bounded preflight of every shard before entering the upstream detailed parser.
        foreach (var shard in GgufMetadataService.EnumerateShards(modelPath)) GgufMetadataReader.ReadTensorTable(shard);
        var model = GgufMetadataService.TryReadDetailed(modelPath);
        return Estimate(model, profileJson);
    }

    public static VramPlan Estimate(GgufModelInfo? model, string profileJson)
    {
        var profile = JsonNode.Parse(profileJson)!.AsObject();
        var warnings = new List<string>();
        var reliable = true;
        int Number(string name, int fallback) => profile[name] is JsonValue v && v.TryGetValue<int>(out var n) ? n : fallback;
        bool Flag(string name, bool fallback = false) => profile[name] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : fallback;
        string Cache(string name)
        {
            var type = profile[name]?.ToString().ToLowerInvariant() ?? "f16";
            if (type is "f32" or "f16" or "bf16" or "q8_0" or "q5_0" or "q5_1" or "q4_0" or "q4_1" or "iq4_nl") return type;
            reliable = false;
            warnings.Add($"{name}={type}: специальный формат BeeLlama — показан ориентир f16, точный размер требует измерения runtime.");
            return "f16";
        }
        var gpu = profile["gpuLayers"]?.ToString() ?? "all";
        if (model is null || !model.IsSplitComplete) { reliable = false; warnings.Add("Не все части или метаданные модели доступны."); }
        if (Number("kvTailTokens", 0) > 0) { reliable = false; warnings.Add("Дополнительный KV-tail и rollback-буферы не включены в расчёт; нужен замер BeeLlama."); }
        if (Flag("mtpEnabled")) { reliable = false; warnings.Add("MTP может создавать дополнительные буферы, не учтённые в базовой оценке."); }
        if (!string.IsNullOrWhiteSpace(profile["tensorOverride"]?.ToString()) || profile["advancedArgs"] is JsonArray { Count: > 0 })
        { reliable = false; warnings.Add("Tensor override / дополнительные аргументы могут менять распределение памяти."); }
        long projector = 0;
        if (Flag("visionEnabled") && Flag("visionOffload"))
        {
            var path = profile["mmprojPath"]?.ToString();
            if (path is not null && File.Exists(path)) projector = new FileInfo(path).Length;
            else { reliable = false; warnings.Add("Файл GPU-проектора недоступен."); }
        }
        var request = new VramRequest {
            ContextSize = Math.Clamp(Number("context", 4096), 256, 2_000_000),
            GpuLayers = gpu == "all" ? -1 : int.TryParse(gpu, out var layers) ? Math.Clamp(layers, 0, 4096) : 0,
            CacheTypeK = Cache("kvK"), CacheTypeV = Cache("kvV"),
            BatchSize = Math.Clamp(Number("batch", 2048), 1, 65536),
            UBatchSize = Math.Clamp(Number("ubatch", 512), 1, 65536),
            FlashAttention = Flag("flashAttention", true), Parallel = Math.Clamp(Number("parallel", 1), 1, 128),
            CpuMoeBlocks = Flag("cpuMoeAll") ? model?.Tensors?.BlockCount ?? 0 : Number("cpuMoeLayers", 0),
            MmprojBytes = projector
        };
        var estimate = VramEstimator.Estimate(model, request);
        if (estimate?.Approximate == true) warnings.Add("Для этой архитектуры часть параметров вычислена приближённо.");
        return new VramPlan(estimate, warnings, reliable && estimate is { Approximate: false });
    }
}
