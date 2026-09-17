namespace BeeForge.Next.Core.Inference;

public static class CrashAdvisor
{
    public static IReadOnlyList<string> Analyze(string? logText)
    {
        var text = logText ?? string.Empty;
        var result = new List<string>();
        if (Contains(text, "failed to allocate") && Contains(text, "pinned memory") ||
            Contains(text, "resource already mapped") && Contains(text, "pinned memory"))
            result.Add("Похоже на сбой pinned memory. Для диагностики попробуйте профиль без no-mmap и проверьте повторный запуск.");
        if (Contains(text, "CUDA error: shared object initialization failed"))
            result.Add("CUDA runtime не инициализировался. Проверьте совместимость CUDA-сборки BeeLlama и драйвера NVIDIA.");
        if (Contains(text, "out of memory") || Contains(text, "CUDA error: out of memory"))
            result.Add("Недостаточно памяти GPU/RAM. Снизьте context/batch/ubatch или число GPU-слоёв; исходный профиль перед правкой сохраните.");
        if (Contains(text, "address already in use") || Contains(text, "bind failed") || Contains(text, "WSAEADDRINUSE"))
            result.Add("Порт уже занят. Проверьте, не остался ли другой управляемый llama-server, прежде чем менять порт профиля.");
        if (Contains(text, "unknown argument") || Contains(text, "unrecognized argument") || Contains(text, "invalid argument"))
            result.Add("Runtime не принимает один из параметров. Сверьте предупреждение совместимости --help в разделе Inference.");
        if (Contains(text, "failed to load model") || Contains(text, "error loading model"))
            result.Add("Не удалось загрузить GGUF. Проверьте наличие всех shard-файлов и соответствие MMProj выбранной модели.");
        return result.Distinct(StringComparer.Ordinal).ToArray();
    }

    public static string AppendAdvice(string logText)
    {
        var advice = Analyze(logText);
        return advice.Count == 0 ? logText : logText + Environment.NewLine + Environment.NewLine +
            "=== BeeForge Next: подсказки по сбою ===" + Environment.NewLine +
            string.Join(Environment.NewLine, advice.Select(x => "• " + x));
    }

    private static bool Contains(string text, string value) =>
        text.Contains(value, StringComparison.OrdinalIgnoreCase);
}
