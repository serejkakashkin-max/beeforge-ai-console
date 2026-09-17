using System.Text.Json.Nodes;
using BeeForge.Next.Core.Profiles;

namespace BeeForge.Next.Core.Benchmarking;

public static class AutoTuneProfileCreator
{
    /// <summary>Creates a separate profile after explicit approval. The original bytes are
    /// backed up atomically by File.Replace; the active profile is never changed.</summary>
    public static string CreateCopy(string storePath, string sourceId, string expectedProfileFingerprint,
        AutoTuneCandidate candidate)
    {
        var catalog = LegacyProfileCatalog.Load(storePath);
        var source = catalog.Profiles.Single(p => p.Id == sourceId);
        if (source.ConnectionMode != "LocalHost" ||
            BenchmarkRunRequest.Fingerprint(source.RawJson) != expectedProfileFingerprint)
            throw new IOException("Профиль изменился после подбора; повторите проверку.");
        var root = JsonNode.Parse(catalog.OriginalJson)?.AsObject() ?? throw new InvalidDataException("Invalid profile store.");
        var profiles = root["profiles"]?.AsArray() ?? throw new InvalidDataException("No profiles in store.");
        var clone = JsonNode.Parse(source.RawJson)?.AsObject() ?? throw new InvalidDataException("Invalid source profile.");
        var id = "tuned-" + Guid.NewGuid().ToString("N")[..12];
        clone["id"] = id;
        clone["name"] = (source.Name.Length > 120 ? source.Name[..120] : source.Name) + " · Auto Tune";
        clone["protected"] = false;
        clone["batch"] = candidate.Batch;
        clone["ubatch"] = candidate.UBatch;
        clone["threads"] = candidate.Threads;
        clone["threadsBatch"] = candidate.ThreadsBatch;
        clone["flashAttention"] = candidate.FlashAttention;
        if (candidate.GpuLayers is not null) clone["gpuLayers"] = candidate.GpuLayers;
        if (candidate.CpuMoeLayers is not null) clone["cpuMoeLayers"] = candidate.CpuMoeLayers.Value;
        profiles.Add(clone);
        var fullPath = Path.GetFullPath(storePath);
        var temp = fullPath + ".tune-" + Guid.NewGuid().ToString("N") + ".tmp";
        var backup = fullPath + ".before-tune-" + DateTime.UtcNow.ToString("yyyyMMddHHmmssfff") + ".bak";
        try
        {
            File.WriteAllText(temp, root.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }), new System.Text.UTF8Encoding(true));
            if (File.ReadAllText(fullPath) != catalog.OriginalJson)
                throw new IOException("Хранилище профилей изменилось; сохранение отменено.");
            File.Replace(temp, fullPath, backup);
            return id;
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
