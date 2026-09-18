namespace BeeForge.Next.Core.Benchmarking;

/// <summary>Exact override scan set from LlamaServerLauncherAvalonia v1.9.8.</summary>
public static class UpstreamTensorOverrides
{
    public static IReadOnlyList<KeyValuePair<string, string>> Patterns { get; } = new[]
    {
        new KeyValuePair<string, string>("none", ""),
        new KeyValuePair<string, string>("ffn_cpu_all", @"blk\.\d+\.ffn_.*_exps\.=CPU"),
        new KeyValuePair<string, string>("ffn_cpu_even", @"blk\.(?:[0-9]*[02468])\.ffn_.*_exps\.=CPU"),
        new KeyValuePair<string, string>("ffn_cpu_odd", @"blk\.(?:[0-9]*[13579])\.ffn_.*_exps\.=CPU"),
        new KeyValuePair<string, string>("ffn_cpu_updown", @"blk\.\d+\.ffn_(?:up|down)_exps\.=CPU"),
        new KeyValuePair<string, string>("ffn_cpu_up", @"blk\.\d+\.ffn_up_exps\.=CPU"),
        new KeyValuePair<string, string>("ffn_cpu_down", @"blk\.\d+\.ffn_down_exps\.=CPU"),
        new KeyValuePair<string, string>("ffn_cpu_last_quarter", @"blk\.(6[0-9]|7[0-9])\.ffn_.*_exps\.=CPU"),
        new KeyValuePair<string, string>("ffn_cpu_from_6", @"blk\.(6|7|8|9|[1-9][0-9]+)\.ffn_.*_exps\.=CPU"),
    };
}
