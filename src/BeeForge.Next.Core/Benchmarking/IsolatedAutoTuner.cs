using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using BeeForge.Next.Core.Inference;
using LlamaServerLauncher.Services;

namespace BeeForge.Next.Core.Benchmarking;

/// <summary>Runs a bounded set of disposable server trials. It never stops the managed server
/// or writes the live profile store; the caller must explicitly confirm the heavy operation.</summary>
public sealed class IsolatedAutoTuner
{
    private readonly string _launchScript;
    private readonly LegacyRuntimeController _runtime;
    private readonly HttpBenchmarkProbe _probe;

    public IsolatedAutoTuner(string launchScript, LegacyRuntimeController runtime,
        HttpBenchmarkProbe? probe = null)
    {
        _launchScript = Path.GetFullPath(launchScript);
        _runtime = runtime;
        _probe = probe ?? new HttpBenchmarkProbe();
    }

    public async Task<AutoTuneResult> RunAsync(string profileId, string profileJson, OptimizationObjective objective,
        IProgress<string>? progress, CancellationToken cancellationToken,
        int numericTrials = UpstreamBenchmarkDefaults.OptimizationTrials,
        bool scanTensorOverrides = false)
    {
        if (numericTrials is < 1 or > 100) throw new ArgumentOutOfRangeException(nameof(numericTrials));
        var candidates = AutoTunePlanner.Candidates(profileJson);
        if (candidates.Count == 0) throw new InvalidDataException("Нет допустимой исходной конфигурации.");
        var trials = new List<AutoTuneTrial>();
        var profileNode = System.Text.Json.Nodes.JsonNode.Parse(profileJson)!.AsObject();
        var modelPath = profileNode["modelPath"]?.ToString();
        GgufModelInfo? modelInfo = null;
        if (!string.IsNullOrWhiteSpace(modelPath) && File.Exists(modelPath))
        {
            try { modelInfo = GgufMetadataService.TryReadDetailed(modelPath); } catch { }
        }
        bool MemoryFits(AutoTuneCandidate candidate, LegacyRuntimeStatus status)
        {
            if (modelInfo is null || status.VramTotalMiB is null) return true;
            var candidateJson = AutoTunePlanner.CreateTrialProfileJson(profileJson, candidate, 18080);
            var estimate = VramPlanner.Estimate(modelInfo, candidateJson);
            if (!estimate.CanJudgeFit || estimate.Estimate is null) return true;
            var budget = status.VramTotalMiB.Value * 1024L * 1024L * 95 / 100;
            return estimate.Estimate.TotalBytes <= budget;
        }
        string CandidateKey(AutoTuneCandidate candidate)
        {
            var p = System.Text.Json.Nodes.JsonNode.Parse(AutoTunePlanner.CreateTrialProfileJson(profileJson, candidate, 18080))!;
            p["gpuLayers"] = p["gpuLayers"]?.ToString() ?? "all";
            p["cpuMoeLayers"] ??= 0;
            return p.ToJsonString();
        }

        (int prompt, int output) SearchWorkload() => objective switch
        {
            OptimizationObjective.Prefill => (UpstreamBenchmarkDefaults.OptimizationTokens * 2, 1),
            OptimizationObjective.Decode => (1, UpstreamBenchmarkDefaults.OptimizationTokens),
            _ => (UpstreamBenchmarkDefaults.OptimizationTokens * 2, UpstreamBenchmarkDefaults.OptimizationTokens)
        };

        double Score(AutoTuneTrial trial) => objective switch
        {
            OptimizationObjective.Prefill => trial.Prefill,
            OptimizationObjective.Decode => trial.Decode,
            _ => (trial.Prefill + trial.Decode) / 2.0
        };

        async Task<AutoTuneTrial> MeasureAsync(AutoTuneCandidate candidate, string label,
            int promptTokens, int outputTokens, int repeats)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var status = await _runtime.GetStatusAsync(cancellationToken);
            if (status.Running || status.Ready || status.Leased || status.Remote)
                throw new InvalidOperationException("Остановите рабочую модель и выключите удалённый доступ перед автоподбором.");
            if (!MemoryFits(candidate, status))
                return new AutoTuneTrial(candidate, 0, 0, "VRAM preflight");
            progress?.Report(label);
            try
            {
                var sample = await TrialAsync(profileId, profileJson, candidate, promptTokens, outputTokens,
                    repeats, cancellationToken);
                return new AutoTuneTrial(candidate, sample.PrefillTokensPerSecond,
                    sample.DecodeTokensPerSecond, null);
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                return new AutoTuneTrial(candidate, 0, 0, ex.GetType().Name);
            }
        }

        var (searchPrompt, searchOutput) = SearchWorkload();
        var baseline = await MeasureAsync(candidates[0], "Исходная конфигурация…", searchPrompt, searchOutput,
            UpstreamBenchmarkDefaults.OptimizationRepeats);
        trials.Add(baseline);
        if (!baseline.Valid) return new AutoTuneResult(trials, null, 0);

        // Stage 1: exact upstream numeric search shape (TPE over batch/ubatch/threads/GPU/CPU-MoE).
        var stage1Search = new AdaptiveAutoTuneSearch(profileJson, seed: 42);
        for (var i = 0; i < numericTrials; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var candidate = stage1Search.Ask();
            AutoTuneTrial trial;
            if (candidate.UBatch > candidate.Batch)
                trial = new AutoTuneTrial(candidate, 0, 0, "UBatch exceeds batch");
            else
            {
                var key = CandidateKey(candidate);
                var previous = trials.FirstOrDefault(t => CandidateKey(t.Candidate) == key);
                trial = previous ?? await MeasureAsync(candidate,
                    $"Этап 1/3 · TPE {i + 1}/{numericTrials}…", searchPrompt, searchOutput,
                    UpstreamBenchmarkDefaults.OptimizationRepeats);
            }
            if (!trials.Contains(trial)) trials.Add(trial);
            stage1Search.Tell(trial, baseline, objective);
        }

        var best1 = trials.Where(t => t.Valid).OrderByDescending(Score).First();

        // Stage 2: exact upstream categorical grid. Quantized KV keeps FA enabled.
        var quantizedKv = new[] { "kvK", "kvV" }.Any(k => profileNode[k]?.ToString() is { } s &&
            s is not ("f16" or "f32" or "bf16"));
        var flashChoices = quantizedKv ? new[] { true } : new[] { false, true };
        var overrideChoices = scanTensorOverrides
            ? UpstreamTensorOverrides.Patterns
            : new[] { new KeyValuePair<string, string>("current", best1.Candidate.TensorOverride ?? string.Empty) };
        var stage2 = new List<AutoTuneTrial>();
        var stage2Total = flashChoices.Length * overrideChoices.Count;
        var stage2Index = 0;
        foreach (var flash in flashChoices)
        {
            foreach (var pattern in overrideChoices)
            {
                stage2Index++;
                var candidate = best1.Candidate with
                {
                    Name = $"Grid FA={(flash ? "on" : "off")} / {pattern.Key}",
                    FlashAttention = flash,
                    TensorOverride = pattern.Value
                };
                var previous = trials.FirstOrDefault(t => CandidateKey(t.Candidate) == CandidateKey(candidate));
                var trial = previous ?? await MeasureAsync(candidate,
                    $"Этап 2/3 · Grid {stage2Index}/{stage2Total}…", searchPrompt, searchOutput,
                    UpstreamBenchmarkDefaults.OptimizationRepeats);
                stage2.Add(trial);
                if (!trials.Contains(trial)) trials.Add(trial);
            }
        }
        var best2 = stage2.Where(t => t.Valid).DefaultIfEmpty(best1).OrderByDescending(Score).First();

        // Stage 3: a second full numeric TPE pass with the best categorical choice fixed.
        var stage3Search = new AdaptiveAutoTuneSearch(profileJson, seed: 43,
            fixedFlash: best2.Candidate.FlashAttention, fixedOverride: best2.Candidate.TensorOverride);
        var stage3 = new List<AutoTuneTrial>();
        for (var i = 0; i < numericTrials; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var candidate = stage3Search.Ask();
            AutoTuneTrial trial;
            if (candidate.UBatch > candidate.Batch)
                trial = new AutoTuneTrial(candidate, 0, 0, "UBatch exceeds batch");
            else
            {
                var previous = trials.FirstOrDefault(t => CandidateKey(t.Candidate) == CandidateKey(candidate));
                trial = previous ?? await MeasureAsync(candidate,
                    $"Этап 3/3 · TPE {i + 1}/{numericTrials}…", searchPrompt, searchOutput,
                    UpstreamBenchmarkDefaults.OptimizationRepeats);
            }
            stage3.Add(trial);
            if (!trials.Contains(trial)) trials.Add(trial);
            stage3Search.Tell(trial, baseline, objective);
        }
        var best3 = stage3.Where(t => t.Valid).DefaultIfEmpty(best2).OrderByDescending(Score).First();

        // Upstream performs a separate final comparison with 256 prompt / 128 generation / 6 repeats.
        var comparison = new List<AutoTuneTrial>
        {
            await MeasureAsync(candidates[0], "Контроль: исходные настройки…", 256, 128, 6),
            await MeasureAsync(best3.Candidate, "Контроль: найденные настройки…", 256, 128, 6)
        };
        trials.AddRange(comparison);
        var confirmed = AutoTuneResult.FromTrials(comparison, objective);
        return confirmed.Suggested is null
            ? new AutoTuneResult(trials, null, confirmed.ImprovementPercent)
            : new AutoTuneResult(trials, confirmed.Suggested, confirmed.ImprovementPercent);
    }

    private async Task<BenchmarkSample> TrialAsync(string profileId, string original,
        AutoTuneCandidate candidate, int promptTokens, int outputTokens, int repeats,
        CancellationToken cancellationToken)
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), "beeforge-tune-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporaryDirectory);
        Process? process = null;
        using var processJob = new WindowsProcessJob();
        Task? outputDrain = null;
        Task? errorDrain = null;
        try
        {
            var port = FreeLoopbackPort();
            var candidateJson = AutoTunePlanner.CreateTrialProfileJson(original, candidate, port);
            using var candidateDocument = JsonDocument.Parse(candidateJson);
            var storePath = Path.Combine(temporaryDirectory, "profiles.json");
            await File.WriteAllTextAsync(storePath,
                JsonSerializer.Serialize(new { profiles = new[] { candidateDocument.RootElement } }), cancellationToken);
            var plan = await LegacyLaunchPlanReader.ReadAsync(_launchScript, storePath, profileId, cancellationToken);
            if (plan.Mode != "LocalHost" || !File.Exists(plan.ServerPath))
                throw new InvalidDataException("Локальный сервер профиля недоступен.");
            var start = new ProcessStartInfo(plan.ServerPath)
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                WorkingDirectory = Path.GetDirectoryName(plan.ServerPath)!
            };
            foreach (var arg in plan.Arguments) start.ArgumentList.Add(arg);
            process = Process.Start(start) ?? throw new IOException("Не удалось запустить пробный сервер.");
            processJob.Assign(process); // Fail closed if Windows cannot supervise this trial.
            outputDrain = process.StandardOutput.BaseStream.CopyToAsync(Stream.Null);
            errorDrain = process.StandardError.BaseStream.CopyToAsync(Stream.Null);
            var endpoint = new Uri($"http://127.0.0.1:{port}/v1");
            using var wait = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            wait.CancelAfter(TimeSpan.FromMinutes(3));
            while (true)
            {
                wait.Token.ThrowIfCancellationRequested();
                if (process.HasExited) throw new IOException("Пробный сервер завершился до готовности.");
                try { await _probe.VerifyModelAsync(endpoint, plan.Alias, wait.Token); break; }
                catch (HttpRequestException) { }
                catch (InvalidDataException) { }
                await Task.Delay(1000, wait.Token);
            }
            var samples = new List<BenchmarkSample>();
            for (var i = 0; i < repeats; i++)
            {
                var sample = await _probe.MeasureAsync(endpoint, plan.Alias, promptTokens, outputTokens,
                    TimeSpan.FromSeconds(UpstreamBenchmarkDefaults.BenchmarkTimeoutSeconds), cancellationToken);
                if (!(repeats > 1 && i == 0)) samples.Add(sample);
            }
            if (samples.Count == 0) throw new InvalidDataException("Пробный benchmark не вернул измерений.");
            return new BenchmarkSample(samples.Average(x => x.PrefillTokensPerSecond),
                samples.Average(x => x.DecodeTokensPerSecond),
                (int)Math.Round(samples.Average(x => x.PromptTokens)),
                (int)Math.Round(samples.Average(x => x.OutputTokens)),
                samples.Average(x => x.PromptMilliseconds));
        }
        finally
        {
            if (process is not null)
            {
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
                catch (InvalidOperationException) { /* Exited concurrently. */ }
                await process.WaitForExitAsync(CancellationToken.None);
                try { if (outputDrain is not null) await outputDrain; } catch (IOException) { }
                try { if (errorDrain is not null) await errorDrain; } catch (IOException) { }
                process.Dispose();
            }
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    private static int FreeLoopbackPort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }
}
