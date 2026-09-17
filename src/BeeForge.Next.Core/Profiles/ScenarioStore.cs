using System.Text;
using System.Text.Json;

namespace BeeForge.Next.Core.Profiles;

public sealed record BeeScenario(string Id, string Name, IReadOnlyList<string> ProfileIds, int IntervalSeconds = 0)
{
    public override string ToString() => $"{Name} · профилей: {ProfileIds.Count}";
}

public sealed class ScenarioStore
{
    private readonly string _path;
    public ScenarioStore(string root) => _path = Path.Combine(Path.GetFullPath(root), "config", "next-scenarios.json");

    public IReadOnlyList<BeeScenario> Load()
    {
        if (!File.Exists(_path)) return Array.Empty<BeeScenario>();
        using var doc = JsonDocument.Parse(File.ReadAllText(_path));
        if (doc.RootElement.ValueKind != JsonValueKind.Array) throw new InvalidDataException("Повреждён файл сценариев.");
        var result = new List<BeeScenario>();
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            var id = item.TryGetProperty("id", out var i) ? i.GetString() : null;
            var name = item.TryGetProperty("name", out var n) ? n.GetString() : null;
            if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(name)) continue;
            var profiles = item.TryGetProperty("profileIds", out var p) && p.ValueKind == JsonValueKind.Array
                ? p.EnumerateArray().Select(x => x.GetString()).Where(x => !string.IsNullOrWhiteSpace(x)).Cast<string>().Distinct(StringComparer.Ordinal).ToArray()
                : Array.Empty<string>();
            var interval = item.TryGetProperty("intervalSeconds", out var t) && t.TryGetInt32(out var seconds) ? Math.Clamp(seconds, 0, 86400) : 0;
            if (profiles.Length > 0) result.Add(new BeeScenario(id, name, profiles, interval));
        }
        return result;
    }

    public BeeScenario Add(string name, IReadOnlyList<string> profileIds, int intervalSeconds = 0)
    {
        var cleanName = (name ?? string.Empty).Trim();
        if (cleanName.Length is < 1 or > 100) throw new InvalidDataException("Название сценария должно содержать 1–100 символов.");
        var ids = profileIds.Where(x => !string.IsNullOrWhiteSpace(x)).Distinct(StringComparer.Ordinal).ToArray();
        if (ids.Length == 0) throw new InvalidDataException("Выберите хотя бы один профиль.");
        var all = Load().ToList();
        if (all.Any(x => string.Equals(x.Name, cleanName, StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException("Сценарий с таким именем уже существует.");
        var scenario = new BeeScenario("scenario-" + Guid.NewGuid().ToString("N")[..10], cleanName, ids, Math.Clamp(intervalSeconds, 0, 86400));
        all.Add(scenario); Save(all); return scenario;
    }

    public void Delete(string id)
    {
        var all = Load().ToList();
        if (all.RemoveAll(x => x.Id == id) == 0) return;
        Save(all);
    }

    private void Save(IReadOnlyList<BeeScenario> scenarios)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temp = _path + ".tmp." + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(scenarios, new JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            }), new UTF8Encoding(false));
            if (File.Exists(_path))
            {
                var backup = _path + ".bak";
                File.Replace(temp, _path, backup, ignoreMetadataErrors: true);
            }
            else File.Move(temp, _path);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
