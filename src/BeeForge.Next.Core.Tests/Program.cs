using System.Security.Cryptography;
using System.Text;
using BeeForge.Next.Core.Profiles;

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
