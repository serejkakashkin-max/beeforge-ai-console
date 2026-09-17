using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BeeForge.Next.Core.Profiles;

/// <summary>Edits the existing schema without discarding unknown fields or changing runtime state.</summary>
public sealed class ProfileStoreEditor
{
    private readonly string _path;
    public ProfileStoreEditor(string path) => _path = Path.GetFullPath(path);

    public string Save(string expectedStore, string profileId, string editedProfile)
    {
        var root = ParseStore(expectedStore);
        var profiles = root["profiles"]!.AsArray();
        var index = Find(profiles, profileId);
        var edited = ParseProfile(editedProfile);
        if (edited["id"]?.GetValue<string>() != profileId)
            throw new InvalidDataException("ID существующего профиля нельзя менять.");
        profiles[index] = edited;
        return Commit(expectedStore, root);
    }

    public string Add(string expectedStore, string profileJson, bool copyName = true)
    {
        var root = ParseStore(expectedStore);
        var profiles = root["profiles"]!.AsArray();
        var profile = ParseProfile(profileJson);
        var id = "profile-" + Guid.NewGuid().ToString("N")[..10];
        profile["id"] = id;
        profile["protected"] = false;
        if (copyName) profile["name"] = profile["name"]!.GetValue<string>() + " — копия";
        var used = profiles.Select(p => p?["alias"]?.GetValue<string>() ?? "").ToHashSet(StringComparer.OrdinalIgnoreCase);
        var alias = profile["alias"]!.GetValue<string>();
        var originalAlias = alias;
        for (var n = 1; used.Contains(alias); n++) alias = originalAlias + "-copy" + (n == 1 ? "" : "-" + n);
        profile["alias"] = alias;
        profiles.Add(profile);
        Commit(expectedStore, root);
        return id;
    }

    public string Delete(string expectedStore, string profileId)
    {
        var root = ParseStore(expectedStore);
        var profiles = root["profiles"]!.AsArray();
        if (profiles.Count <= 1) throw new InvalidOperationException("Нельзя удалить единственный профиль.");
        profiles.RemoveAt(Find(profiles, profileId));
        var next = profiles[0]!["id"]!.GetValue<string>();
        foreach (var field in new[] { "activeProfileId", "lastGoodProfileId" })
            if (root[field]?.GetValue<string>() == profileId) root[field] = next;
        Commit(expectedStore, root);
        return next;
    }

    public static JsonObject ParseProfile(string json)
    {
        if (json.Length > 1024 * 1024) throw new InvalidDataException("Профиль слишком большой.");
        var profile = JsonNode.Parse(json)?.AsObject() ?? throw new InvalidDataException("Ожидается JSON-профиль.");
        foreach (var field in new[] { "name", "alias" })
            if (profile[field] is not JsonValue value || !value.TryGetValue<string>(out var text) ||
                string.IsNullOrWhiteSpace(text) || text.Length > 200)
                throw new InvalidDataException($"Заполните поле {field} (до 200 символов).");
        var mode = profile["connectionMode"]?.GetValue<string>() ?? "LocalHost";
        if (mode is not ("LocalHost" or "RemoteClient")) throw new InvalidDataException("Неизвестный тип подключения.");
        if (profile["context"] is not JsonValue context || !context.TryGetValue<int>(out var count) || count < 256)
            throw new InvalidDataException("Контекст должен быть целым числом не меньше 256.");
        foreach (var field in new[] { "batch", "ubatch", "threads", "threadsBatch", "parallel" })
            if (profile[field] is JsonValue number && (!number.TryGetValue<int>(out var n) || n < 1))
                throw new InvalidDataException($"{field}: требуется положительное целое число.");
        if (profile["advancedArgs"] is not null && profile["advancedArgs"] is not JsonArray)
            throw new InvalidDataException("advancedArgs должен быть массивом.");
        if (mode == "RemoteClient")
        {
            var endpoint = profile["remoteBaseUrl"]?.GetValue<string>()?.Trim().TrimEnd('/') ?? "";
            if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                !uri.Host.EndsWith(".ts.net", StringComparison.OrdinalIgnoreCase) ||
                uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0)
                throw new InvalidDataException("Укажите приватный HTTPS-адрес Tailscale (*.ts.net).");
            if (uri.AbsolutePath == "/") endpoint += "/v1";
            else if (!uri.AbsolutePath.TrimEnd('/').EndsWith("/v1", StringComparison.Ordinal))
                throw new InvalidDataException("Адрес API должен заканчиваться /v1.");
            profile["remoteBaseUrl"] = endpoint;
        }
        return profile;
    }

    private static JsonObject ParseStore(string json)
    {
        var root = JsonNode.Parse(json)?.AsObject() ?? throw new InvalidDataException("Повреждено хранилище профилей.");
        if (root["profiles"] is not JsonArray) throw new InvalidDataException("Не найден список профилей.");
        return root;
    }

    private static int Find(JsonArray profiles, string id)
    {
        for (var i = 0; i < profiles.Count; i++) if (profiles[i]?["id"]?.GetValue<string>() == id) return i;
        throw new InvalidDataException("Профиль больше не существует. Обновите список.");
    }

    private string Commit(string expected, JsonObject root)
    {
        var directory = Path.GetDirectoryName(_path)!;
        var backups = Path.Combine(directory, ".profile-backups");
        var temporary = Path.Combine(directory, ".profile-save-" + Guid.NewGuid().ToString("N") + ".tmp");
        var backup = Path.Combine(backups, DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            if (File.ReadAllText(_path) != expected) throw new IOException("Профили изменены другим окном. Обновите список и повторите правку.");
            Directory.CreateDirectory(backups);
            File.WriteAllText(temporary, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(true));
            // Recheck after serialization so a stale editor cannot replace newer state.
            if (File.ReadAllText(_path) != expected) throw new IOException("Профили изменились во время сохранения.");
            File.Replace(temporary, _path, backup);
            return backup;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
