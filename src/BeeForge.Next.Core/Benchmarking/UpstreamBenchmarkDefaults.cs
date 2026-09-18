namespace BeeForge.Next.Core.Benchmarking;

/// <summary>
/// Defaults copied from LlamaServerLauncherAvalonia v1.9.8 benchmark/optimizer.
/// Keeping them in one place makes BeeForge's UI and engine use the same workload.
/// </summary>
public static class UpstreamBenchmarkDefaults
{
    public const int StandardPromptTokens = 512;
    public const int StandardOutputTokens = 128;
    public const int StandardRepeats = 3;
    public const int OptimizationTrials = 45;
    public const int OptimizationRepeats = 3;
    public const int OptimizationTokens = 192;
    public const int WarmupRuns = 35;
    public const int MinimumWarmupRuns = 4;
    public const int WarmupTokens = 128;
    public const int MaximumGpuLayers = 149;
    public const int MaximumCpuMoeLayers = 64;
    public const int FitMarginMiB = 1024;
    public const int BenchmarkTimeoutSeconds = 820;
    public const int ServerHealthTimeoutSeconds = 300;
}
