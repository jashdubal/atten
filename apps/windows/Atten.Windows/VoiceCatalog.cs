using System.Text.Json;

namespace Atten.Windows;

public static class VoiceCatalog
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public static IReadOnlyList<Voice> All { get; } = Load();

    public static Voice ById(string id)
    {
        return All.FirstOrDefault(voice => voice.Id == id) ?? All[0];
    }

    private static IReadOnlyList<Voice> Load()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "resources", "voices.json"),
            Path.Combine(Directory.GetCurrentDirectory(), "resources", "voices.json")
        };

        foreach (var path in candidates)
        {
            if (!File.Exists(path))
            {
                continue;
            }

            using var stream = File.OpenRead(path);
            var voices = JsonSerializer.Deserialize<List<Voice>>(stream, Options);
            if (voices is { Count: > 0 })
            {
                return voices;
            }
        }

        throw new FileNotFoundException("Atten voice catalog is missing: resources/voices.json");
    }
}
