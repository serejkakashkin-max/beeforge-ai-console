namespace BeeForge.Next.Core.Workspace;

public sealed class OfflineHelpService
{
    private readonly string _root;
    private static readonly IReadOnlyDictionary<string, string> Topics = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["main"] = "README.md",
        ["runtime"] = "docs/MODEL-RUNTIME-TUNING.md",
        ["team"] = "docs/TEAM-VERIFICATION.md",
        ["mcp"] = "docs/OPENCODE-MCP-GUIDE.md",
        ["migration"] = "docs/merge/MIGRATION_ARCHITECTURE.md",
        ["regression"] = "docs/merge/REGRESSION_PLAN.md"
    };

    public OfflineHelpService(string root) => _root = Path.GetFullPath(root);

    public IReadOnlyCollection<string> TopicNames => Topics.Keys.ToArray();

    public string Read(string topic)
    {
        if (!Topics.TryGetValue(topic, out var relative)) throw new ArgumentException("Unknown help topic.", nameof(topic));
        var path = Path.GetFullPath(Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!path.StartsWith(_root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !File.Exists(path))
            return "Локальный документ справки недоступен.";
        var info = new FileInfo(path);
        if (info.Length > 2 * 1024 * 1024) return "Документ справки слишком большой для встроенного просмотра.";
        return File.ReadAllText(path);
    }
}
