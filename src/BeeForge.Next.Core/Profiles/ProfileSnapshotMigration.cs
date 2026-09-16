using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BeeForge.Next.Core.Profiles;

/// <summary>
/// Prepares a side-by-side profile snapshot. The legacy store remains the sole
/// live writer until the cutover gate is passed.
/// </summary>
public sealed class ProfileSnapshotMigration
{
    private const string BackupName = "profiles.v1.backup.json";
    private const string SnapshotName = "profiles.v2.json";
    private const string ManifestName = "migration.json";

    public static ProfileSnapshotMigration Prepare(string sourcePath, string destinationDirectory)
    {
        var catalog = LegacyProfileCatalog.Load(sourcePath);
        var sourceBytes = File.ReadAllBytes(catalog.Path);
        var sourceHash = Hash(sourceBytes);
        var root = JsonNode.Parse(sourceBytes) as JsonObject
            ?? throw new InvalidDataException("BeeForge profile store must be a JSON object.");
        if (root["profiles"] is JsonArray profiles)
        {
            foreach (var item in profiles)
            {
                if (item is not JsonObject profile)
                    throw new InvalidDataException("BeeForge profile entry must be a JSON object.");
                if (profile["connectionMode"] is null ||
                    string.IsNullOrWhiteSpace(profile["connectionMode"]?.GetValue<string>()))
                    profile["connectionMode"] = "LocalHost";
            }
        }
        var snapshotBytes = Encoding.UTF8.GetBytes(root.ToJsonString(new JsonSerializerOptions
        {
            WriteIndented = true
        }) + "\n");
        var snapshotHash = Hash(snapshotBytes);
        var manifestBytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new
        {
            format = "BeeForgeProfileSnapshot/1",
            sourceSha256 = sourceHash,
            snapshotSha256 = snapshotHash
        }) + "\n");

        var destination = Path.GetFullPath(destinationDirectory);
        if (Directory.Exists(destination))
            return VerifyExisting(destination, sourceHash, snapshotHash, sourceBytes, snapshotBytes, manifestBytes);
        var parent = Path.GetDirectoryName(destination)
            ?? throw new InvalidOperationException("Migration directory needs a parent.");
        Directory.CreateDirectory(parent);
        var staging = Path.Combine(parent, ".beeforge-profile-migration-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            File.WriteAllBytes(Path.Combine(staging, BackupName), sourceBytes);
            File.WriteAllBytes(Path.Combine(staging, SnapshotName), snapshotBytes);
            File.WriteAllBytes(Path.Combine(staging, ManifestName), manifestBytes);
            Directory.Move(staging, destination);
        }
        finally
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
        }
        return new ProfileSnapshotMigration(destination, sourceHash, snapshotHash);
    }

    private static ProfileSnapshotMigration VerifyExisting(string destination, string sourceHash,
        string snapshotHash, byte[] sourceBytes, byte[] snapshotBytes, byte[] manifestBytes)
    {
        foreach (var (name, expected) in new[]
        {
            (BackupName, sourceBytes), (SnapshotName, snapshotBytes), (ManifestName, manifestBytes)
        })
        {
            var path = Path.Combine(destination, name);
            if (!File.Exists(path) || !File.ReadAllBytes(path).SequenceEqual(expected))
                throw new IOException("Existing profile migration differs from the source; refusing to overwrite it.");
        }
        return new ProfileSnapshotMigration(destination, sourceHash, snapshotHash);
    }

    private ProfileSnapshotMigration(string directory, string sourceHash, string snapshotHash)
    {
        MigrationDirectory = directory;
        SourceSha256 = sourceHash;
        SnapshotSha256 = snapshotHash;
    }

    public string MigrationDirectory { get; }
    public string SourceSha256 { get; }
    public string SnapshotSha256 { get; }
    public string BackupPath => Path.Combine(MigrationDirectory, BackupName);
    public string SnapshotPath => Path.Combine(MigrationDirectory, SnapshotName);

    /// <summary>Restores a copy only to a new path; never overwrites the live store.</summary>
    public void RestoreCopy(string destinationPath)
    {
        if (Hash(File.ReadAllBytes(BackupPath)) != SourceSha256)
            throw new InvalidDataException("Profile backup hash changed; refusing to restore it.");
        if (File.Exists(destinationPath))
            throw new IOException("Refusing to overwrite an existing profile store.");
        File.Copy(BackupPath, destinationPath);
    }

    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
}
