using System.Text.Json;

namespace BeeForge.Next.Core.Profiles;

/// <summary>
/// Passive adapter for the existing BeeForge profile store. It intentionally
/// does not migrate or rewrite the user's file while the legacy UI owns it.
/// </summary>
public sealed class LegacyProfileCatalog
{
    public static LegacyProfileCatalog Load(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = System.IO.Path.GetFullPath(path);
        var json = File.ReadAllText(fullPath);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("BeeForge profile store must be a JSON object.");

        var activeId = GetString(root, "activeProfileId");
        var lastGoodId = GetString(root, "lastGoodProfileId");
        var openCodeConfigPath = GetString(root, "openCodeConfigPath");
        var profiles = new List<LegacyProfile>();
        if (root.TryGetProperty("profiles", out var entries))
        {
            if (entries.ValueKind != JsonValueKind.Array)
                throw new InvalidDataException("BeeForge profiles must be a JSON array.");
            foreach (var entry in entries.EnumerateArray())
            {
                if (entry.ValueKind != JsonValueKind.Object)
                    throw new InvalidDataException("BeeForge profile entry must be a JSON object.");
                var id = GetString(entry, "id");
                if (string.IsNullOrWhiteSpace(id))
                    throw new InvalidDataException("BeeForge profile ID is missing.");
                var mode = GetString(entry, "connectionMode");
                if (string.IsNullOrWhiteSpace(mode)) mode = "LocalHost";
                if (mode is not ("LocalHost" or "RemoteClient"))
                    throw new InvalidDataException($"Unknown BeeForge profile mode: {mode}.");
                profiles.Add(new LegacyProfile(
                    id,
                    GetString(entry, "name"),
                    GetString(entry, "alias"),
                    mode,
                    GetInt32(entry, "context"),
                    GetString(entry, "serverPath"),
                    GetString(entry, "modelPath"),
                    entry.GetRawText()));
            }
        }

        return new LegacyProfileCatalog(fullPath, json, activeId, lastGoodId, openCodeConfigPath, profiles);
    }

    private LegacyProfileCatalog(string path, string originalJson, string activeId,
        string lastGoodId, string openCodeConfigPath, IReadOnlyList<LegacyProfile> profiles)
    {
        Path = path;
        OriginalJson = originalJson;
        ActiveProfileId = activeId;
        LastGoodProfileId = lastGoodId;
        OpenCodeConfigPath = openCodeConfigPath;
        Profiles = profiles;
    }

    public string Path { get; }
    public string OriginalJson { get; }
    public string ActiveProfileId { get; }
    public string LastGoodProfileId { get; }
    public string OpenCodeConfigPath { get; }
    public IReadOnlyList<LegacyProfile> Profiles { get; }
    public LegacyProfile? ActiveProfile => Profiles.FirstOrDefault(p => p.Id == ActiveProfileId);

    private static string GetString(JsonElement source, string name) =>
        source.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? ""
            : "";

    private static int GetInt32(JsonElement source, string name) =>
        source.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
            && value.TryGetInt32(out var number) ? number : 0;
}

public sealed record LegacyProfile(string Id, string Name, string Alias, string ConnectionMode,
    int Context, string ServerPath, string ModelPath, string RawJson);
