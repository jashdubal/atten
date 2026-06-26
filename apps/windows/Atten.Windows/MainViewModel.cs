using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Atten.Windows;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly StorageService storage = new();
    private readonly BackendClient backend = new();
    private CancellationTokenSource? generationCts;
    private string draftTitle = "Untitled narration";
    private string draftText = "";
    private string selectedVoiceID = "af_heart";
    private double speed = 1.0;
    private AudioFormat format = AudioFormat.mp3;
    private DeviceMode deviceMode = DeviceMode.auto;
    private string outputDirectory = "";
    private string status = "";
    private string? currentAudioPath;
    private bool isGenerating;
    private BackendInfo? backendInfo;

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<ProjectRecord> Projects { get; } = [];
    public IReadOnlyList<Voice> Voices => VoiceCatalog.All;
    public IReadOnlyList<AudioFormat> Formats { get; } = Enum.GetValues<AudioFormat>();
    public IReadOnlyList<DeviceMode> DeviceModes { get; } = Enum.GetValues<DeviceMode>();

    public string DraftTitle
    {
        get => draftTitle;
        set => Set(ref draftTitle, value);
    }

    public string DraftText
    {
        get => draftText;
        set => Set(ref draftText, value);
    }

    public string SelectedVoiceID
    {
        get => selectedVoiceID;
        set => Set(ref selectedVoiceID, value);
    }

    public double Speed
    {
        get => speed;
        set => Set(ref speed, value);
    }

    public AudioFormat Format
    {
        get => format;
        set => Set(ref format, value);
    }

    public DeviceMode DeviceMode
    {
        get => deviceMode;
        set => Set(ref deviceMode, value);
    }

    public string OutputDirectory
    {
        get => outputDirectory;
        set => Set(ref outputDirectory, value);
    }

    public string Status
    {
        get => status;
        set => Set(ref status, value);
    }

    public string? CurrentAudioPath
    {
        get => currentAudioPath;
        set => Set(ref currentAudioPath, value);
    }

    public bool IsGenerating
    {
        get => isGenerating;
        set => Set(ref isGenerating, value);
    }

    public BackendInfo? BackendInfo
    {
        get => backendInfo;
        set => Set(ref backendInfo, value);
    }

    public async Task StartAsync()
    {
        storage.Prepare();
        var settings = await storage.LoadSettingsAsync();
        OutputDirectory = settings.OutputDirectory;
        Format = settings.DefaultFormat;
        Speed = settings.DefaultSpeed;
        SelectedVoiceID = settings.SelectedVoiceID;
        DeviceMode = settings.DeviceMode;

        Projects.Clear();
        foreach (var project in (await storage.LoadProjectsAsync()).OrderByDescending(project => project.UpdatedAt))
        {
            Projects.Add(project);
        }

        try
        {
            BackendInfo = await backend.GetInfoAsync(DeviceMode, CancellationToken.None);
            Status = $"Backend ready on {BackendInfo.SelectedDevice}.";
        }
        catch (Exception error)
        {
            Status = error.Message;
        }
    }

    public async Task SaveSettingsAsync()
    {
        await storage.SaveSettingsAsync(new AppSettings
        {
            OutputDirectory = OutputDirectory,
            DefaultFormat = Format,
            DefaultSpeed = Speed,
            SelectedVoiceID = SelectedVoiceID,
            DeviceMode = DeviceMode
        });
    }

    public async Task GenerateAsync()
    {
        var cleanText = DraftText.Trim();
        if (cleanText.Length == 0)
        {
            Status = "Enter text before generating speech.";
            return;
        }

        generationCts?.Cancel();
        generationCts = new CancellationTokenSource();
        IsGenerating = true;
        Status = "Generating speech...";

        try
        {
            await SaveSettingsAsync();
            var title = SafeFilename(string.IsNullOrWhiteSpace(DraftTitle) ? "Atten narration" : DraftTitle);
            var filename = UniqueFilename(title, OutputDirectory, Format);
            var output = await backend.GenerateAsync(
                cleanText,
                SelectedVoiceID,
                Speed,
                Format,
                OutputDirectory,
                filename,
                DeviceMode,
                generationCts.Token);

            var now = DateTimeOffset.Now;
            var project = new ProjectRecord
            {
                Title = title,
                Text = cleanText,
                VoiceID = SelectedVoiceID,
                Speed = Speed,
                Format = Format,
                AudioPath = output.Path,
                CreatedAt = now,
                UpdatedAt = now
            };
            Projects.Insert(0, project);
            await storage.SaveProjectsAsync(Projects);
            CurrentAudioPath = output.Path;
            Status = "Speech is ready.";
        }
        catch (OperationCanceledException)
        {
            Status = "Generation cancelled.";
        }
        catch (Exception error)
        {
            Status = error.Message;
        }
        finally
        {
            IsGenerating = false;
        }
    }

    public void CancelGeneration()
    {
        generationCts?.Cancel();
    }

    private static string UniqueFilename(string title, string directory, AudioFormat format)
    {
        Directory.CreateDirectory(directory);
        var candidate = title;
        var counter = 2;
        while (File.Exists(Path.Combine(directory, $"{candidate}.{format}")))
        {
            candidate = $"{title} {counter}";
            counter++;
        }
        return candidate;
    }

    private static string SafeFilename(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var clean = new string(value.Select(character => invalid.Contains(character) ? '-' : character).ToArray());
        return clean.Trim();
    }

    private void Set<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
