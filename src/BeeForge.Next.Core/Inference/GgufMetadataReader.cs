using System.Buffers.Binary;
using System.Text;

namespace BeeForge.Next.Core.Inference;

/// <summary>Bounded, read-only GGUF header inspection. Never reads tensor payloads.</summary>
public static class GgufMetadataReader
{
    private const long MaxMetadataBytes = 512L * 1024 * 1024;
    private const ulong MaxEntries = 1_000_000;
    private static readonly UTF8Encoding Utf8 = new(false, true);

    public static GgufMetadataSummary Read(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite,
            4096, FileOptions.SequentialScan);
        return Read(stream, Path.GetFullPath(path));
    }

    public static GgufMetadataSummary Read(Stream stream, string source = "")
    {
        if (!stream.CanRead || !stream.CanSeek) throw new InvalidDataException("GGUF input must be seekable.");
        var origin = stream.Position;
        if (stream.Length - origin < 24) throw new InvalidDataException("GGUF header is incomplete.");
        Span<byte> magic = stackalloc byte[4];
        stream.ReadExactly(magic);
        if (!magic.SequenceEqual("GGUF"u8)) throw new InvalidDataException("Not a little-endian GGUF file.");
        var version = ReadUInt32(stream);
        if (version is not (2 or 3)) throw new InvalidDataException("Unsupported GGUF version.");
        var tensorCount = ReadUInt64(stream);
        var metadataCount = ReadUInt64(stream);
        if (metadataCount > MaxEntries || tensorCount > MaxEntries)
            throw new InvalidDataException("GGUF count exceeds the inspection limit.");
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        for (ulong i = 0; i < metadataCount; i++)
        {
            if (stream.Position - origin > MaxMetadataBytes)
                throw new InvalidDataException("GGUF metadata exceeds the inspection limit.");
            var key = ReadString(stream, 4096);
            var type = ReadUInt32(stream);
            if (IsUseful(key) && type is not 9)
                values[key] = ReadScalar(stream, type);
            else
                SkipValue(stream, type, 0);
            if (stream.Position - origin > MaxMetadataBytes)
                throw new InvalidDataException("GGUF metadata exceeds the inspection limit.");
        }
        return new GgufMetadataSummary(source, version, tensorCount, metadataCount,
            stream.Length, values);
    }

    private static bool IsUseful(string key) =>
        key is "general.architecture" or "general.name" or "general.file_type" or "general.size_label" or
            "general.quantization_version" ||
        key.EndsWith(".context_length", StringComparison.Ordinal) ||
        key.EndsWith(".block_count", StringComparison.Ordinal) ||
        key.EndsWith(".embedding_length", StringComparison.Ordinal) ||
        key.EndsWith(".expert_count", StringComparison.Ordinal) ||
        key.EndsWith(".expert_used_count", StringComparison.Ordinal) ||
        key.EndsWith(".attention.head_count_kv", StringComparison.Ordinal);

    private static string ReadScalar(Stream stream, uint type) => type switch
    {
        0 => ReadByte(stream).ToString(),
        1 => unchecked((sbyte)ReadByte(stream)).ToString(),
        2 => ReadUInt16(stream).ToString(),
        3 => unchecked((short)ReadUInt16(stream)).ToString(),
        4 => ReadUInt32(stream).ToString(),
        5 => unchecked((int)ReadUInt32(stream)).ToString(),
        6 => BitConverter.Int32BitsToSingle(unchecked((int)ReadUInt32(stream))).ToString("R"),
        7 => ReadByte(stream) switch { 0 => "false", 1 => "true", _ => throw new InvalidDataException("Invalid GGUF boolean.") },
        8 => ReadString(stream, 4096),
        10 => ReadUInt64(stream).ToString(),
        11 => unchecked((long)ReadUInt64(stream)).ToString(),
        12 => BitConverter.Int64BitsToDouble(unchecked((long)ReadUInt64(stream))).ToString("R"),
        _ => throw new InvalidDataException("Unknown GGUF metadata type.")
    };

    private static void SkipValue(Stream stream, uint type, int depth)
    {
        if (depth > 4) throw new InvalidDataException("GGUF array nesting exceeds the inspection limit.");
        if (type == 9)
        {
            var elementType = ReadUInt32(stream);
            var count = ReadUInt64(stream);
            if (count > MaxEntries) throw new InvalidDataException("GGUF array exceeds the inspection limit.");
            var width = FixedWidth(elementType);
            if (width > 0) { Skip(stream, checked((long)count * width)); return; }
            for (ulong i = 0; i < count; i++) SkipValue(stream, elementType, depth + 1);
            return;
        }
        if (type == 8) { Skip(stream, CheckedLength(ReadUInt64(stream))); return; }
        var bytes = FixedWidth(type);
        if (bytes == 0) throw new InvalidDataException("Unknown GGUF metadata type.");
        Skip(stream, bytes);
    }

    private static int FixedWidth(uint type) => type switch
    {
        0 or 1 or 7 => 1, 2 or 3 => 2, 4 or 5 or 6 => 4, 10 or 11 or 12 => 8, _ => 0
    };

    private static string ReadString(Stream stream, int maxDecodedBytes)
    {
        var length = CheckedLength(ReadUInt64(stream));
        if (length > maxDecodedBytes) throw new InvalidDataException("GGUF string exceeds the inspection limit.");
        var bytes = new byte[(int)length];
        stream.ReadExactly(bytes);
        return Utf8.GetString(bytes);
    }

    private static long CheckedLength(ulong length) =>
        length > long.MaxValue ? throw new InvalidDataException("GGUF length is invalid.") : (long)length;

    private static void Skip(Stream stream, long length)
    {
        if (length < 0 || length > stream.Length - stream.Position)
            throw new InvalidDataException("GGUF metadata is truncated.");
        stream.Seek(length, SeekOrigin.Current);
    }

    private static byte ReadByte(Stream stream)
    {
        var value = stream.ReadByte();
        return value < 0 ? throw new InvalidDataException("GGUF metadata is truncated.") : (byte)value;
    }

    private static ushort ReadUInt16(Stream stream)
    {
        Span<byte> data = stackalloc byte[2]; stream.ReadExactly(data);
        return BinaryPrimitives.ReadUInt16LittleEndian(data);
    }

    private static uint ReadUInt32(Stream stream)
    {
        Span<byte> data = stackalloc byte[4]; stream.ReadExactly(data);
        return BinaryPrimitives.ReadUInt32LittleEndian(data);
    }

    private static ulong ReadUInt64(Stream stream)
    {
        Span<byte> data = stackalloc byte[8]; stream.ReadExactly(data);
        return BinaryPrimitives.ReadUInt64LittleEndian(data);
    }
}

public sealed record GgufMetadataSummary(string Source, uint Version, ulong TensorCount,
    ulong MetadataCount, long FileSizeBytes, IReadOnlyDictionary<string, string> Values);
