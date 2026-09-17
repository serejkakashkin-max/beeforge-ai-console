using System.Globalization;
using System.Text;

namespace BeeForge.Next.Core.Benchmarking;

public static class BenchmarkComparisonReport
{
    public static string Render(IEnumerable<StoredBenchmarkRun> selectedRuns)
    {
        var runs = selectedRuns.Take(10).ToArray();
        if (runs.Length == 0) throw new ArgumentException("Select at least one run.", nameof(selectedRuns));
        if (runs.Select(r => r.Id).Distinct(StringComparer.Ordinal).Count() != runs.Length)
            throw new ArgumentException("Duplicate benchmark run.", nameof(selectedRuns));
        var builder = new StringBuilder("# BeeForge benchmark comparison\n\n");
        builder.AppendLine("Scores are measured server timings, not model-quality scores. A delta is shown only for identical alias and workload.");
        builder.AppendLine();
        builder.AppendLine("| Run | Profile | Date (UTC) | Input | Output | Repeats | PP tok/s | TG tok/s | PP σ | TG σ | Configuration |");
        builder.AppendLine("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |");
        foreach (var run in runs)
        {
            builder.Append("| ").Append(Cell(run.Id[..Math.Min(8, run.Id.Length)]));
            builder.Append(" | ").Append(Cell(run.ProfileName));
            builder.Append(" | ").Append(run.CompletedAt.UtcDateTime.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture));
            builder.Append(" | ").Append(run.PromptTokens).Append(" | ").Append(run.OutputTokens);
            builder.Append(" | ").Append(run.Repeats);
            builder.Append(" | ").Append(Format(run.PrefillTokensPerSecond));
            builder.Append(" | ").Append(Format(run.DecodeTokensPerSecond));
            builder.Append(" | ").Append(Format(run.PrefillStdDev));
            builder.Append(" | ").Append(Format(run.DecodeStdDev));
            builder.Append(" | ").Append(Cell(run.ProfileSha256[..Math.Min(8, run.ProfileSha256.Length)]));
            builder.AppendLine(" |");
        }
        if (runs.Length == 2 && runs[0].ModelAlias == runs[1].ModelAlias &&
            runs[0].PromptTokens == runs[1].PromptTokens && runs[0].OutputTokens == runs[1].OutputTokens &&
            runs[1].PrefillTokensPerSecond > 0 && runs[1].DecodeTokensPerSecond > 0)
        {
            builder.AppendLine();
            builder.Append("First vs second: PP ").Append(FormatPercent(runs[0].PrefillTokensPerSecond /
                runs[1].PrefillTokensPerSecond - 1));
            builder.Append(", TG ").Append(FormatPercent(runs[0].DecodeTokensPerSecond /
                runs[1].DecodeTokensPerSecond - 1)).AppendLine(".");
        }
        return builder.ToString();
    }

    private static string Cell(string text) => text.Replace("|", "\\|", StringComparison.Ordinal)
        .Replace("\r", " ", StringComparison.Ordinal).Replace("\n", " ", StringComparison.Ordinal);
    private static string Format(double number) => number.ToString("0.00", CultureInfo.InvariantCulture);
    private static string FormatPercent(double delta) =>
        (delta * 100).ToString("+0.0;-0.0;0.0", CultureInfo.InvariantCulture) + "%";
}
