using System.Text;

namespace BeeForge.Next.Core.Inference;

/// <summary>Reads only the trailing bytes of known BeeForge log files.</summary>
public sealed class LegacyLogTailReader
{
    private const int MaxBytes = 64 * 1024;
    private readonly string _logDirectory;

    public LegacyLogTailReader(string beeForgeRoot)
    {
        _logDirectory = Path.Combine(Path.GetFullPath(beeForgeRoot), "logs");
    }

    public string Read(string kind)
    {
        var fileName = kind switch
        {
            "server" => "current.stderr.log",
            "server-output" => "current.stdout.log",
            "telegram" => "telegram-runner.log",
            _ => throw new ArgumentOutOfRangeException(nameof(kind))
        };
        var path = Path.Combine(_logDirectory, fileName);
        if (!File.Exists(path)) return "Журнал ещё не создан.";
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite,
            4096, FileOptions.SequentialScan);
        var count = (int)Math.Min(stream.Length, MaxBytes);
        stream.Seek(-count, SeekOrigin.End);
        var bytes = new byte[count];
        stream.ReadExactly(bytes);
        var text = Encoding.UTF8.GetString(bytes);
        if (stream.Length > MaxBytes)
        {
            var newline = text.IndexOf('\n');
            if (newline >= 0) text = text[(newline + 1)..];
            text = "… показан конец журнала (не более 64 KiB) …" + Environment.NewLine + text;
        }
        return text.Length == 0 ? "Журнал пуст." : text;
    }
}
