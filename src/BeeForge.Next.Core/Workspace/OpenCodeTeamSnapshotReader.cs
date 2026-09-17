using System.Text.Json;

namespace BeeForge.Next.Core.Workspace;

/// <summary>Whitelisted OpenCode inventory; never returns prompts, MCP commands, URLs or credentials.</summary>
public static class OpenCodeTeamSnapshotReader
{
    public static OpenCodeTeamSnapshot Read(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        if (stream.Length > 16 * 1024 * 1024)
            throw new InvalidDataException("OpenCode configuration exceeds the inventory limit.");
        using var document = JsonDocument.Parse(stream);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("OpenCode configuration root must be an object.");
        var agents = new List<OpenCodeAgentSummary>();
        if (root.TryGetProperty("agent", out var agentMap) && agentMap.ValueKind == JsonValueKind.Object)
        {
            foreach (var item in agentMap.EnumerateObject())
            {
                if (item.Value.ValueKind != JsonValueKind.Object) continue;
                agents.Add(new OpenCodeAgentSummary(SafeName(item.Name),
                    SafeMode(StringValue(item.Value, "mode")), SafeModel(StringValue(item.Value, "model")),
                    BoolValue(item.Value, "disable")));
            }
        }
        var mcp = new List<OpenCodeMcpSummary>();
        if (root.TryGetProperty("mcp", out var mcpMap) && mcpMap.ValueKind == JsonValueKind.Object)
        {
            foreach (var item in mcpMap.EnumerateObject())
            {
                if (item.Value.ValueKind != JsonValueKind.Object) continue;
                mcp.Add(new OpenCodeMcpSummary(SafeName(item.Name), BoolValue(item.Value, "enabled", true)));
            }
        }
        return new OpenCodeTeamSnapshot(SafeModel(StringValue(root, "model")), agents, mcp);
    }

    private static string SafeName(string value) => value.Length <= 80 &&
        value.All(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.') ? value : "[invalid identifier]";
    private static string SafeMode(string value) => value is "primary" or "subagent" or "all" ? value : "—";
    private static string SafeModel(string value) => value.Length <= 160 &&
        value.All(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.' or '/' or ':' or '@')
        ? value : "[hidden]";
    private static string StringValue(JsonElement source, string name) =>
        source.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String &&
        value.GetString() is { Length: <= 160 } text ? text : "";
    private static bool BoolValue(JsonElement source, string name, bool fallback = false) =>
        source.TryGetProperty(name, out var value) ? value.ValueKind switch
        {
            JsonValueKind.True => true, JsonValueKind.False => false, _ => fallback
        } : fallback;
}

public sealed record OpenCodeTeamSnapshot(string PrimaryModel, IReadOnlyList<OpenCodeAgentSummary> Agents,
    IReadOnlyList<OpenCodeMcpSummary> McpServers);
public sealed record OpenCodeAgentSummary(string Id, string Mode, string Model, bool Disabled);
public sealed record OpenCodeMcpSummary(string Id, bool Enabled);
