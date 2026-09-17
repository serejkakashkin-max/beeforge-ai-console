using System.Security.Cryptography;
using System.Text;
using BeeForge.Next.Core.Inference;
using BeeForge.Next.Core.Benchmarking;
using BeeForge.Next.Core.Profiles;
using BeeForge.Next.Core.Workspace;

var temp = Path.Combine(Path.GetTempPath(), "beeforge-next-profile-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(temp);
try
{
    var path = Path.Combine(temp, "profiles.json");
    const string original = """
        {"schemaVersion":1,"activeProfileId":"local","lastGoodProfileId":"remote","modelRoots":["X:\\models"],"unknownTop":{"keep":true},"profiles":[{"id":"local","name":"Локальная модель","alias":"Q2","context":190000,"serverPath":"X:\\bee\\llama-server.exe","modelPath":"X:\\models\\a.gguf","kvK":"kvarn4","kvV":"kvarn6","kvTailTokens":1024,"cpuMoeLayers":12,"mtpEnabled":true,"visionEnabled":true,"unknownField":"preserve"},{"id":"remote","name":"Ноутбук","alias":"Q2","context":190000,"connectionMode":"RemoteClient","remoteBaseUrl":"https://example.ts.net/v1"}]}
        """;
    File.WriteAllText(path, original, new UTF8Encoding(false));
    var before = SHA256.HashData(File.ReadAllBytes(path));
    var catalog = LegacyProfileCatalog.Load(path);
    Assert(catalog.ActiveProfileId == "local", "active profile ID");
    Assert(catalog.LastGoodProfileId == "remote", "last-good profile ID");
    Assert(catalog.ActiveProfile?.Name == "Локальная модель", "UTF-8 profile name");
    Assert(catalog.ActiveProfile?.ConnectionMode == "LocalHost", "legacy mode defaults to LocalHost");
    Assert(catalog.Profiles[1].ConnectionMode == "RemoteClient", "remote mode preserved");
    Assert(catalog.ActiveProfile?.RawJson.Contains("\"unknownField\":\"preserve\"", StringComparison.Ordinal) == true,
        "unknown profile fields retained in raw view");
    Assert(catalog.OriginalJson == original, "full store retained verbatim in memory");
    Assert(SHA256.HashData(File.ReadAllBytes(path)).SequenceEqual(before), "profile store not modified");

    var openCodeFixture = Path.Combine(temp, "opencode.json");
    File.WriteAllText(openCodeFixture, """
        {"model":"beellama/Q2","agent":{"team-lead":{"mode":"primary","model":"beellama/Q2","prompt":"SECRET_PROMPT_VALUE","disable":false},"qa-engineer":{"mode":"subagent","disable":true}},"mcp":{"serena":{"enabled":true,"command":["SECRET_MCP_VALUE"]},"docker":{"enabled":false}}}
        """);
    var openCodeHash = SHA256.HashData(File.ReadAllBytes(openCodeFixture));
    var team = OpenCodeTeamSnapshotReader.Read(openCodeFixture);
    Assert(team.PrimaryModel == "beellama/Q2" && team.Agents.Count == 2 && team.McpServers.Count == 2,
        "OpenCode team inventory");
    Assert(team.Agents.Single(a => a.Id == "qa-engineer").Disabled &&
        !team.McpServers.Single(m => m.Id == "docker").Enabled, "disabled agent and MCP preserved");
    Assert(!team.ToString()!.Contains("SECRET_", StringComparison.Ordinal) &&
        !string.Join(' ', team.Agents).Contains("SECRET_", StringComparison.Ordinal),
        "OpenCode inventory excludes prompts and MCP commands");
    Assert(SHA256.HashData(File.ReadAllBytes(openCodeFixture)).SequenceEqual(openCodeHash),
        "OpenCode inventory is read-only");

    var benchmarkRoot = Path.Combine(temp, "benchmark-fixture");
    var benchmarkCalls = 0;
    using var benchmarkClient = new HttpClient(new FakeBenchmarkHandler(request =>
    {
        if (request.RequestUri!.AbsolutePath == "/v1/models")
            return new System.Net.Http.HttpResponseMessage(System.Net.HttpStatusCode.OK)
                { Content = new StringContent("{\"data\":[{\"id\":\"Q2\"}]}") };
        benchmarkCalls++;
        var speed = benchmarkCalls == 1 ? 1 : benchmarkCalls == 2 ? 10 : 20;
        return new System.Net.Http.HttpResponseMessage(System.Net.HttpStatusCode.OK)
            { Content = new StringContent($"{{\"timings\":{{\"prompt_per_second\":{speed},\"predicted_per_second\":{speed * 2},\"prompt_n\":256,\"predicted_n\":16,\"prompt_ms\":123}}}}") };
    }));
    var benchmarkStore = new BenchmarkRunStore(benchmarkRoot);
    var benchmarkRunner = new StandardBenchmarkRunner(new HttpBenchmarkProbe(benchmarkClient), benchmarkStore);
    var benchmarkRequest = new BenchmarkRunRequest("local", "Локальная", "Q2", "http://127.0.0.1:8080/v1",
        BenchmarkRunRequest.Fingerprint("{\"batch\":2048}"), 256, 16, 2, 30);
    var benchmarkRun = await benchmarkRunner.RunAsync(benchmarkRequest, null, CancellationToken.None);
    Assert(benchmarkCalls == 3 && benchmarkRun.PrefillTokensPerSecond == 15 &&
        benchmarkRun.DecodeTokensPerSecond == 30 && benchmarkRun.PrefillStdDev == 5,
        "benchmark discards warmup and computes repeated metrics");
    Assert(benchmarkStore.Load("local").Single().Id == benchmarkRun.Id,
        "benchmark history survives reload");
    var comparisonRun = benchmarkRun with { Id = "comparison2", ProfileName = "Test|Profile",
        PrefillTokensPerSecond = 30, DecodeTokensPerSecond = 60 };
    var comparison = BenchmarkComparisonReport.Render(new[] { comparisonRun, benchmarkRun });
    Assert(comparison.Contains("+100.0%", StringComparison.Ordinal) &&
        comparison.Contains("Test\\|Profile", StringComparison.Ordinal) &&
        !comparison.Contains("SECRET_", StringComparison.Ordinal),
        "comparison report uses matching workload and escapes profile name");
    try { _ = HttpBenchmarkProbe.CompletionUrl(new Uri("http://example.com/v1")); throw new Exception("public HTTP benchmark accepted"); }
    catch (ArgumentException) { }
    var tuningCandidates = AutoTunePlanner.Candidates(catalog.Profiles[0].RawJson);
    Assert(tuningCandidates.Count is >= 3 and <= 6 && tuningCandidates[0].Name == "Исходные",
        "bounded auto-tune trial plan includes baseline");
    var trialJson = AutoTunePlanner.CreateTrialProfileJson(catalog.Profiles[0].RawJson, tuningCandidates[1], 29876);
    Assert(trialJson.Contains("\"port\":29876", StringComparison.Ordinal) &&
        catalog.Profiles[0].RawJson.Contains("\"unknownField\":\"preserve\"", StringComparison.Ordinal),
        "trial profile has isolated port and source remains unchanged");
    var noGain = AutoTuneResult.FromTrials(new[] {
        new AutoTuneTrial(tuningCandidates[0], 100, 100, null),
        new AutoTuneTrial(tuningCandidates[1], 102, 102, null) });
    Assert(noGain.Suggested is null, "optimizer rejects noise-level gain");
    var gain = AutoTuneResult.FromTrials(new[] {
        new AutoTuneTrial(tuningCandidates[0], 100, 100, null),
        new AutoTuneTrial(tuningCandidates[1], 130, 130, null) });
    Assert(gain.Suggested == tuningCandidates[1], "optimizer selects verified improvement");
    var objectiveTrials = new[] {
        new AutoTuneTrial(tuningCandidates[0], 100, 100, null),
        new AutoTuneTrial(tuningCandidates[1], 120, 96, null) };
    Assert(AutoTuneResult.FromTrials(objectiveTrials, OptimizationObjective.Prefill).Suggested == tuningCandidates[1] &&
        AutoTuneResult.FromTrials(objectiveTrials, OptimizationObjective.Decode).Suggested is null,
        "optimizer respects PP/TG objective");
    var tuneStorePath = Path.Combine(temp, "tune-profiles.json");
    File.WriteAllText(tuneStorePath, original, new UTF8Encoding(false));
    var tunedId = AutoTuneProfileCreator.CreateCopy(tuneStorePath, "local",
        BenchmarkRunRequest.Fingerprint(catalog.Profiles[0].RawJson), tuningCandidates[1]);
    var tunedCatalog = LegacyProfileCatalog.Load(tuneStorePath);
    Assert(tunedCatalog.ActiveProfileId == "local" && tunedCatalog.Profiles.Count == 3 &&
        System.Text.Json.Nodes.JsonNode.DeepEquals(
            System.Text.Json.Nodes.JsonNode.Parse(tunedCatalog.Profiles.Single(p => p.Id == "local").RawJson),
            System.Text.Json.Nodes.JsonNode.Parse(catalog.Profiles[0].RawJson)) &&
        tunedCatalog.Profiles.Any(p => p.Id == tunedId), "autotune creates separate inactive profile");
    var tuneBackups = Directory.EnumerateFiles(temp, "tune-profiles.json.before-tune-*.bak").ToArray();
    Assert(tuneBackups.Length == 1 && File.ReadAllText(tuneBackups[0]) == original,
        "autotune creates byte-exact backup");
    try { _ = HttpBenchmarkProbe.CompletionUrl(new Uri("https://example.ts.net/v2")); throw new Exception("wrong API path accepted"); }
    catch (ArgumentException) { }

    var logs = Path.Combine(temp, "logs");
    Directory.CreateDirectory(logs);
    var logPath = Path.Combine(logs, "current.stderr.log");
    File.WriteAllText(logPath, new string('x', 70000) + "\nlast known line\n");
    var logHash = SHA256.HashData(File.ReadAllBytes(logPath));
    var logReader = new LegacyLogTailReader(temp);
    var tail = logReader.Read("server");
    Assert(tail.Contains("last known line", StringComparison.Ordinal) && tail.Length < 66000,
        "log tail is bounded and includes the latest line");
    Assert(SHA256.HashData(File.ReadAllBytes(logPath)).SequenceEqual(logHash), "log read does not modify file");
    try { logReader.Read("../config/profiles.json"); throw new Exception("arbitrary log path accepted"); }
    catch (ArgumentOutOfRangeException) { }

    using (var gguf = new MemoryStream())
    {
        using (var writer = new BinaryWriter(gguf, Encoding.UTF8, leaveOpen: true))
        {
            writer.Write(Encoding.ASCII.GetBytes("GGUF"));
            writer.Write(3u);
            writer.Write(2UL);
            writer.Write(4UL);
            WriteGgufString(writer, "general.architecture"); writer.Write(8u); WriteGgufString(writer, "qwen3");
            WriteGgufString(writer, "qwen3.context_length"); writer.Write(4u); writer.Write(190000u);
            WriteGgufString(writer, "qwen3.expert_count"); writer.Write(10u); writer.Write(128UL);
            WriteGgufString(writer, "tokenizer.ggml.tokens"); writer.Write(9u); writer.Write(8u);
            writer.Write(2UL); WriteGgufString(writer, "hello"); WriteGgufString(writer, "world");
            WriteGgufString(writer, "blk.0.attn_q.weight"); writer.Write(2u);
            writer.Write(128UL); writer.Write(128UL); writer.Write(10u); writer.Write(0UL);
            WriteGgufString(writer, "blk.0.attn_k.weight"); writer.Write(2u);
            writer.Write(128UL); writer.Write(128UL); writer.Write(1u); writer.Write(4096UL);
        }
        gguf.Position = 0;
        var info = GgufMetadataReader.Read(gguf);
        Assert(info.Version == 3 && info.TensorCount == 2 && info.MetadataCount == 4, "GGUF header parsed");
        Assert(info.Values["general.architecture"] == "qwen3" &&
            info.Values["qwen3.context_length"] == "190000" &&
            info.Values["qwen3.expert_count"] == "128", "GGUF architecture metadata parsed");
        Assert(!info.Values.ContainsKey("tokenizer.ggml.tokens"), "large tokenizer arrays skipped");
        gguf.Position = 0;
        var tensors = GgufMetadataReader.ReadTensorTable(gguf);
        Assert(tensors.TypeCounts[10] == 1 && tensors.TypeCounts[1] == 1 &&
            GgmlTensorTypes.Name(10) == "Q2_K", "GGUF tensor table and type names parsed");
        gguf.SetLength(gguf.Length - 2);
        gguf.Position = 0;
        try { GgufMetadataReader.ReadTensorTable(gguf); throw new Exception("truncated GGUF was accepted"); }
        catch (EndOfStreamException) { }
    }

    var migrationPath = Path.Combine(temp, "prepared-migration");
    var migration = ProfileSnapshotMigration.Prepare(path, migrationPath);
    Assert(File.ReadAllBytes(migration.BackupPath).SequenceEqual(File.ReadAllBytes(path)), "byte-exact backup");
    var migrated = LegacyProfileCatalog.Load(migration.SnapshotPath);
    Assert(migrated.ActiveProfileId == catalog.ActiveProfileId, "active ID retained in snapshot");
    Assert(migrated.LastGoodProfileId == catalog.LastGoodProfileId, "last-good ID retained in snapshot");
    Assert(migrated.Profiles[0].ConnectionMode == "LocalHost", "missing mode normalized");
    Assert(migrated.Profiles[1].ConnectionMode == "RemoteClient", "remote mode retained");
    Assert(migrated.OriginalJson.Contains("\"unknownTop\"", StringComparison.Ordinal), "unknown root retained");
    Assert(migrated.Profiles[0].RawJson.Contains("\"unknownField\"", StringComparison.Ordinal), "unknown profile retained");
    Assert(ProfileSnapshotMigration.Prepare(path, migrationPath).SnapshotSha256 == migration.SnapshotSha256,
        "migration idempotent");
    var restoredPath = Path.Combine(temp, "restored.json");
    migration.RestoreCopy(restoredPath);
    Assert(File.ReadAllBytes(restoredPath).SequenceEqual(File.ReadAllBytes(path)), "reversible exact restore copy");
    try { migration.RestoreCopy(restoredPath); throw new Exception("existing restore copy was overwritten"); }
    catch (IOException) { }
    Assert(SHA256.HashData(File.ReadAllBytes(path)).SequenceEqual(before), "live source still not modified");

    File.WriteAllText(path, original.Replace("Q2", "new", StringComparison.Ordinal));
    try { ProfileSnapshotMigration.Prepare(path, migrationPath); throw new Exception("stale snapshot was accepted"); }
    catch (IOException) { }

    var malformedModePath = Path.Combine(temp, "numeric-mode.json");
    File.WriteAllText(malformedModePath, "{\"profiles\":[{\"id\":\"one\",\"connectionMode\":12}]}");
    var numericMigration = ProfileSnapshotMigration.Prepare(malformedModePath, Path.Combine(temp, "numeric-prepared"));
    Assert(LegacyProfileCatalog.Load(numericMigration.SnapshotPath).Profiles[0].ConnectionMode == "LocalHost",
        "non-string legacy mode normalizes without dropping profile");

    var repo = new DirectoryInfo(AppContext.BaseDirectory);
    while (repo is not null && !File.Exists(Path.Combine(repo.FullName, "scripts", "Get-BeeForgeNextLaunchPlan.ps1")))
        repo = repo.Parent;
    Assert(repo is not null, "repository launch-plan adapter found");
    var script = Path.Combine(repo!.FullName, "scripts", "Get-BeeForgeNextLaunchPlan.ps1");
    var templatePath = Path.Combine(repo.FullName, "config", "templates", "profiles.example.json");
    var templateCopy = Path.Combine(temp, "launch-fixture.json");
    File.Copy(templatePath, templateCopy);
    var local = await LegacyLaunchPlanReader.ReadAsync(script, templateCopy, "profile-b453573d18");
    Assert(local.Mode == "LocalHost" && local.Arguments.Count > 50, "local argv from legacy module");
    Assert(local.Arguments.Contains("kvarn4") && local.Arguments.Contains("--spec-draft-n-max") &&
        local.Arguments.Contains("-mm"), "BeeLlama KVarN, MTP and vision retained");
    var autoTuneSource = LegacyProfileCatalog.Load(templateCopy).Profiles.Single(p => p.Id == "profile-b453573d18");
    var autoTuneCandidate = AutoTunePlanner.Candidates(autoTuneSource.RawJson)[1];
    var autoTuneTrial = AutoTunePlanner.CreateTrialProfileJson(autoTuneSource.RawJson, autoTuneCandidate, 29876);
    var autoTuneStore = Path.Combine(temp, "auto-tune-launch.json");
    File.WriteAllText(autoTuneStore, "{\"profiles\":[" + autoTuneTrial + "]}");
    var autoTunePlan = await LegacyLaunchPlanReader.ReadAsync(script, autoTuneStore, autoTuneSource.Id);
    Assert(autoTunePlan.Arguments.Contains("29876") && autoTunePlan.Arguments.Contains(autoTuneCandidate.Batch.ToString()) &&
        autoTunePlan.Arguments.Contains("kvarn4") && autoTunePlan.Arguments.Contains("--spec-draft-n-max"),
        "autotune trial uses actual BeeLlama argv and retains special flags");
    File.WriteAllText(templateCopy, original, new UTF8Encoding(false));
    var remote = await LegacyLaunchPlanReader.ReadAsync(script, templateCopy, "remote");
    Assert(remote.Mode == "RemoteClient" && remote.Arguments.Count == 0, "remote profile cannot launch local server");

    var runtimeScript = Path.Combine(repo.FullName, "scripts", "Invoke-BeeForgeNextRuntime.ps1");
    File.Copy(templatePath, templateCopy, overwrite: true);
    var runtime = new LegacyRuntimeController(runtimeScript, templateCopy);
    var fixtureStatus = await runtime.GetStatusAsync();
    Assert(!fixtureStatus.Ready && !fixtureStatus.Remote, "local fixture status uses legacy backend");
    File.WriteAllText(templateCopy, original, new UTF8Encoding(false));
    runtime = new LegacyRuntimeController(runtimeScript, templateCopy);
    var remoteBefore = SHA256.HashData(File.ReadAllBytes(templateCopy));
    try { await runtime.StartAsync("remote"); throw new Exception("remote profile started local runtime"); }
    catch (InvalidDataException) { }
    try { await runtime.StopAsync("remote"); throw new Exception("remote profile stopped inference host"); }
    catch (InvalidDataException) { }
    try { await runtime.ConnectRemoteAsync("local"); throw new Exception("local profile connected as remote"); }
    catch (InvalidDataException) { }
    try { await runtime.ConnectRemoteAsync("remote"); throw new Exception("offline remote connected"); }
    catch (InvalidDataException) { }
    Assert(SHA256.HashData(File.ReadAllBytes(templateCopy)).SequenceEqual(remoteBefore),
        "rejected remote and offline actions did not change the fixture profile");

    var leaseConfig = Path.Combine(temp, "remote-lease.json");
    File.WriteAllText(leaseConfig, "{\"Enabled\":true,\"Managed\":true}");
    var oldRemoteConfig = Environment.GetEnvironmentVariable("BEEFORGE_REMOTE_CONFIG");
    try
    {
        Environment.SetEnvironmentVariable("BEEFORGE_REMOTE_CONFIG", leaseConfig);
        File.Copy(templatePath, templateCopy, overwrite: true);
        runtime = new LegacyRuntimeController(runtimeScript, templateCopy);
        var leasedStatus = await runtime.GetStatusAsync();
        Assert(leasedStatus.Leased, "remote lease surfaced to new UI");
        try { await runtime.StartAsync("profile-b453573d18"); throw new Exception("leased model started locally"); }
        catch (InvalidDataException) { }
        try { await runtime.StopAsync("profile-b453573d18"); throw new Exception("leased model stopped locally"); }
        catch (InvalidDataException) { }
    }
    finally { Environment.SetEnvironmentVariable("BEEFORGE_REMOTE_CONFIG", oldRemoteConfig); }

    File.WriteAllText(path, "{\"profiles\":[{\"name\":\"missing id\"}]}");
    try { LegacyProfileCatalog.Load(path); throw new Exception("missing ID was accepted"); }
    catch (InvalidDataException) { }

    Console.WriteLine("NEXT_PROFILE_READONLY_TEST_OK");
}
finally
{
    Directory.Delete(temp, recursive: true);
}

static void Assert(bool condition, string name)
{
    if (!condition) throw new Exception("Profile compatibility check failed: " + name);
}

static void WriteGgufString(BinaryWriter writer, string value)
{
    var bytes = Encoding.UTF8.GetBytes(value);
    writer.Write((ulong)bytes.Length);
    writer.Write(bytes);
}

sealed class FakeBenchmarkHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
        Task.FromResult(response(request));
}
