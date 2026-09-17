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
        IProgress<string>? progress, CancellationToken cancellationToken)
    {
        var candidates = AutoTunePlanner.Candidates(profileJson);
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
        foreach (var candidate in candidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var status = await _runtime.GetStatusAsync(cancellationToken);
            if (status.Running || status.Ready || status.Leased || status.Remote)
                throw new InvalidOperationException("Остановите рабочую модель и выключите удалённый доступ перед автоподбором.");
            if (!MemoryFits(candidate, status))
            {
                trials.Add(new AutoTuneTrial(candidate, 0, 0, "VRAM preflight"));
                if (trials.Count == 1) break;
                continue;
            }
            progress?.Report($"Проверяю {candidate.Name} ({trials.Count + 1}/{candidates.Count})…");
            try
            {
                var sample = await TrialAsync(profileId, profileJson, candidate, cancellationToken);
                trials.Add(new AutoTuneTrial(candidate, sample.PrefillTokensPerSecond,
                    sample.DecodeTokensPerSecond, null));
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                trials.Add(new AutoTuneTrial(candidate, 0, 0, ex.GetType().Name));
                if (trials.Count == 1) break; // No trustworthy baseline.
            }
        }
        // Upstream TPE uses observed outcomes to explore combinations, not only one-field changes.
        if (trials.Count > 0 && trials[0].Valid)
        {
            var search = new AdaptiveAutoTuneSearch(profileJson);
            for (var i = 0; i < 12; i++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var candidate = search.Ask();
                if (candidate.UBatch > candidate.Batch)
                {
                    search.Tell(new AutoTuneTrial(candidate, 0, 0, "UBatch exceeds batch"), trials[0], objective);
                    continue;
                }
                var key = CandidateKey(candidate);
                var previous = trials.FirstOrDefault(t => CandidateKey(t.Candidate) == key);
                if (previous is not null)
                {
                    search.Tell(previous, trials[0], objective);
                    continue; // Reuse evidence; confirmation below is deliberately measured again.
                }
                var status = await _runtime.GetStatusAsync(cancellationToken);
                if (status.Running || status.Ready || status.Leased || status.Remote)
                    throw new InvalidOperationException("Автоподбор остановлен: рабочая модель или удалённый доступ активны.");
                if (!MemoryFits(candidate, status))
                {
                    var rejected = new AutoTuneTrial(candidate, 0, 0, "VRAM preflight");
                    trials.Add(rejected);
                    search.Tell(rejected, trials[0], objective);
                    continue;
                }
                progress?.Report($"Адаптивный поиск TPE {i + 1}/12…");
                AutoTuneTrial trial;
                try
                {
                    var sample = await TrialAsync(profileId, profileJson, candidate, cancellationToken);
                    trial = new AutoTuneTrial(candidate, sample.PrefillTokensPerSecond, sample.DecodeTokensPerSecond, null);
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) { trial = new AutoTuneTrial(candidate, 0, 0, ex.GetType().Name); }
                trials.Add(trial);
                search.Tell(trial, trials[0], objective);
            }
        }
        var provisional = AutoTuneResult.FromTrials(trials, objective);
        if (provisional.Suggested is null) return provisional;
        // Re-run both candidates after the search. A one-off spike must not
        // generate a production profile recommendation.
        var confirmation = new List<AutoTuneTrial>();
        foreach (var candidate in new[] { candidates[0], provisional.Suggested })
        {
            cancellationToken.ThrowIfCancellationRequested();
            var status = await _runtime.GetStatusAsync(cancellationToken);
            if (status.Running || status.Ready || status.Leased || status.Remote)
                throw new InvalidOperationException("Рабочая модель запущена во время проверки; автоподбор остановлен.");
            progress?.Report($"Подтверждаю результат: {candidate.Name}…");
            try
            {
                var sample = await TrialAsync(profileId, profileJson, candidate, cancellationToken);
                confirmation.Add(new AutoTuneTrial(candidate, sample.PrefillTokensPerSecond,
                    sample.DecodeTokensPerSecond, null));
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) { confirmation.Add(new AutoTuneTrial(candidate, 0, 0, ex.GetType().Name)); }
        }
        var confirmed = AutoTuneResult.FromTrials(confirmation, objective);
        return confirmed.Suggested is null ? new AutoTuneResult(trials.Concat(confirmation).ToArray(), null, 0)
            : new AutoTuneResult(trials.Concat(confirmation).ToArray(), confirmed.Suggested,
                confirmed.ImprovementPercent);
    }

    private async Task<BenchmarkSample> TrialAsync(string profileId, string original,
        AutoTuneCandidate candidate, CancellationToken cancellationToken)
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
            // Identical work for every candidate; warmup is deliberately discarded.
            await _probe.MeasureAsync(endpoint, plan.Alias, 1024, 64, TimeSpan.FromMinutes(2), cancellationToken);
            var first = await _probe.MeasureAsync(endpoint, plan.Alias, 1024, 64,
                TimeSpan.FromMinutes(2), cancellationToken);
            var second = await _probe.MeasureAsync(endpoint, plan.Alias, 1024, 64,
                TimeSpan.FromMinutes(2), cancellationToken);
            return new BenchmarkSample((first.PrefillTokensPerSecond + second.PrefillTokensPerSecond) / 2,
                (first.DecodeTokensPerSecond + second.DecodeTokensPerSecond) / 2,
                (first.PromptTokens + second.PromptTokens) / 2,
                (first.OutputTokens + second.OutputTokens) / 2,
                (first.PromptMilliseconds + second.PromptMilliseconds) / 2);
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
