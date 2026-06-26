using System.Text.Json;
using System.Text.Json.Serialization;

namespace Atten.Windows;

public sealed class StorageService
{
    private readonly JsonSerializerOptions options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    public string ApplicationRoot { get; }
    public string ProjectsFile => Path.Combine(ApplicationRoot, "projects.json");
    public string SettingsFile => Path.Combine(ApplicationRoot, "settings.json");
    public string DefaultExports => Path.Combine(ApplicationRoot, "Exports");
    public string VoicePreviews => Path.Combine(ApplicationRoot, "Voice Previews");

    public StorageService()
    {
        ApplicationRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Atten");
    }

    public void Prepare()
    {
        Directory.CreateDirectory(ApplicationRoot);
        Directory.CreateDirectory(DefaultExports);
        Directory.CreateDirectory(VoicePreviews);
    }

    public async Task<AppSettings> LoadSettingsAsync()
    {
        if (!File.Exists(SettingsFile))
        {
            return new AppSettings { OutputDirectory = DefaultExports };
        }

        await using var stream = File.OpenRead(SettingsFile);
        var settings = await JsonSerializer.DeserializeAsync<AppSettings>(stream, options);
        if (settings is null)
        {
            return new AppSettings { OutputDirectory = DefaultExports };
        }

        if (string.IsNullOrWhiteSpace(settings.OutputDirectory))
        {
            settings.OutputDirectory = DefaultExports;
        }
        return settings;
    }

    public async Task SaveSettingsAsync(AppSettings settings)
    {
        Directory.CreateDirectory(ApplicationRoot);
        await using var stream = File.Create(SettingsFile);
        await JsonSerializer.SerializeAsync(stream, settings, options);
    }

    public async Task<List<ProjectRecord>> LoadProjectsAsync()
    {
        if (!File.Exists(ProjectsFile))
        {
            return [];
        }

        await using var stream = File.OpenRead(ProjectsFile);
        return await JsonSerializer.DeserializeAsync<List<ProjectRecord>>(stream, options) ?? [];
    }

    public async Task SaveProjectsAsync(IEnumerable<ProjectRecord> projects)
    {
        Directory.CreateDirectory(ApplicationRoot);
        await using var stream = File.Create(ProjectsFile);
        await JsonSerializer.SerializeAsync(stream, projects, options);
    }
}
