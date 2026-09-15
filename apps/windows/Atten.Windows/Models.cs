using System.ComponentModel;
using System.Text.Json.Serialization;
using Microsoft.UI.Xaml;

namespace Atten.Windows;

public enum AudioFormat
{
    mp3,
    wav
}

public enum DeviceMode
{
    auto,
    cpu,
    cuda,
    mps
}

public sealed record Voice(
    string Id,
    string Name,
    string Language,
    [property: JsonPropertyName("language_code")] string LanguageCode = "en",
    string Gender = "Neutral",
    IReadOnlyList<string>? Traits = null,
    string Quality = "neural",
    string EngineName = "")
{
    public IReadOnlyList<string> Traits { get; init; } = Traits ?? [];
    public string ModelEngine => !string.IsNullOrEmpty(EngineName)
        ? EngineName
        : (Id.StartsWith("ar_") || Id.StartsWith("de_") || Id.StartsWith("ru_") || Id.StartsWith("tr_") || Id.StartsWith("nl_") || Id.StartsWith("pl_") || Id.StartsWith("xtts_")
            ? "XTTS-v2 & Multilingual Neural"
            : "Kokoro-82M");

    public string ShortName => Name.Contains("(") ? Name.Split('(')[0].Trim() : Name;
    public string DisplayTitle => $"{Name} • {Gender} ({Quality})";
}

public sealed record VoiceGroup(string Language, string ModelEngine, IReadOnlyList<Voice> Voices)
{
    public string Header => $"{Language} • {Voices.Count} voices ({ModelEngine})";
}

public sealed class HfModelInfo : INotifyPropertyChanged
{
    public static readonly Dictionary<string, string[]> LanguageToCodes = new(StringComparer.OrdinalIgnoreCase)
    {
        { "Arabic", ["ara", "arb", "ar"] },
        { "English", ["eng", "en"] },
        { "German", ["deu", "de"] },
        { "Spanish", ["spa", "es"] },
        { "French", ["fra", "fr"] },
        { "Italian", ["ita", "it"] },
        { "Portuguese", ["por", "pt"] },
        { "Russian", ["rus", "ru"] },
        { "Turkish", ["tur", "tr"] },
        { "Dutch", ["nld", "nl"] },
        { "Polish", ["pol", "pl"] },
        { "Japanese", ["jpn", "ja"] },
        { "Chinese", ["cmn", "zho", "zh"] },
        { "Hindi", ["hin", "hi"] },
        { "Korean", ["kor", "ko"] },
        { "Vietnamese", ["vie", "vi"] },
        { "Indonesian", ["ind", "id"] },
        { "Ukrainian", ["ukr", "uk"] },
        { "Greek", ["ell", "el"] },
        { "Hebrew", ["heb", "he"] },
        { "Czech", ["ces", "cs"] },
        { "Romanian", ["ron", "ro"] },
        { "Hungarian", ["hun", "hu"] },
        { "Danish", ["dan", "da"] },
        { "Norwegian", ["nor", "no"] },
        { "Finnish", ["fin", "fi"] },
        { "Swedish", ["swe", "sv"] },
        { "Thai", ["tha", "th"] },
        { "Tamil", ["tam", "ta"] },
        { "Telugu", ["tel", "te"] },
        { "Urdu", ["urd", "ur"] },
        { "Bengali", ["ben", "bn"] },
        { "Persian", ["pes", "fas", "fa"] },
        { "Swahili", ["swh", "sw"] },
        { "Catalan", ["cat", "ca"] }
    };

    public static readonly Dictionary<string, string> CodeToLanguage = new(StringComparer.OrdinalIgnoreCase)
    {
        { "ar", "Arabic" },
        { "ara", "Arabic" },
        { "arb", "Arabic" },
        { "en", "English" },
        { "eng", "English" },
        { "de", "German" },
        { "deu", "German" },
        { "es", "Spanish" },
        { "spa", "Spanish" },
        { "fr", "French" },
        { "fra", "French" },
        { "it", "Italian" },
        { "ita", "Italian" },
        { "pt", "Portuguese" },
        { "por", "Portuguese" },
        { "ru", "Russian" },
        { "rus", "Russian" },
        { "tr", "Turkish" },
        { "tur", "Turkish" },
        { "nl", "Dutch" },
        { "nld", "Dutch" },
        { "pl", "Polish" },
        { "pol", "Polish" },
        { "ja", "Japanese" },
        { "jpn", "Japanese" },
        { "zh", "Chinese" },
        { "zho", "Chinese" },
        { "cmn", "Chinese" },
        { "hi", "Hindi" },
        { "hin", "Hindi" },
        { "ko", "Korean" },
        { "kor", "Korean" },
        { "vi", "Vietnamese" },
        { "vie", "Vietnamese" },
        { "id", "Indonesian" },
        { "ind", "Indonesian" },
        { "uk", "Ukrainian" },
        { "ukr", "Ukrainian" },
        { "el", "Greek" },
        { "ell", "Greek" },
        { "he", "Hebrew" },
        { "heb", "Hebrew" },
        { "cs", "Czech" },
        { "ces", "Czech" },
        { "ro", "Romanian" },
        { "ron", "Romanian" },
        { "hu", "Hungarian" },
        { "hun", "Hungarian" },
        { "da", "Danish" },
        { "dan", "Danish" },
        { "no", "Norwegian" },
        { "nor", "Norwegian" },
        { "fi", "Finnish" },
        { "fin", "Finnish" },
        { "sv", "Swedish" },
        { "swe", "Swedish" },
        { "th", "Thai" },
        { "tha", "Thai" },
        { "ta", "Tamil" },
        { "tam", "Tamil" },
        { "te", "Telugu" },
        { "tel", "Telugu" },
        { "ur", "Urdu" },
        { "urd", "Urdu" },
        { "bn", "Bengali" },
        { "ben", "Bengali" },
        { "fa", "Persian" },
        { "fas", "Persian" },
        { "pes", "Persian" },
        { "sw", "Swahili" },
        { "swh", "Swahili" },
        { "ca", "Catalan" },
        { "cat", "Catalan" }
    };

    private bool isInstalled;
    private bool isDownloading;

    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string Author { get; init; } = "";
    public int Downloads { get; init; }
    public int Likes { get; init; }
    private string sizeText = "";
    public string DownloadsText { get; init; } = "";
    public string LikesText { get; init; } = "";
    public string SizeText
    {
        get => sizeText;
        set
        {
            if (sizeText != value)
            {
                sizeText = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SizeText)));
            }
        }
    }
    public string LanguagesText { get; init; } = "";
    public IReadOnlyList<string> LanguageCodes { get; init; } = [];

    public bool SupportsLanguage(string language)
    {
        if (string.IsNullOrWhiteSpace(language) || language.Equals("All Languages", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        // Multilingual models
        if (Id.Contains("xtts", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (Id.Contains("kokoro", StringComparison.OrdinalIgnoreCase))
        {
            var kokoroLangs = new[] { "English", "Spanish", "French", "Italian", "Portuguese", "Japanese", "Chinese", "Hindi" };
            return kokoroLangs.Contains(language, StringComparer.OrdinalIgnoreCase);
        }

        if (LanguageToCodes.TryGetValue(language, out var codes))
        {
            foreach (var code in codes)
            {
                if (Id.EndsWith($"-{code}", StringComparison.OrdinalIgnoreCase) ||
                    Id.Contains($"-{code}-", StringComparison.OrdinalIgnoreCase) ||
                    Id.Contains($"_{code}", StringComparison.OrdinalIgnoreCase) ||
                    LanguageCodes.Any(t => t.Equals(code, StringComparison.OrdinalIgnoreCase)))
                {
                    return true;
                }
            }
        }

        return LanguagesText.Contains(language, StringComparison.OrdinalIgnoreCase);
    }

    public bool IsInstalled
    {
        get => isInstalled;
        set
        {
            if (isInstalled != value)
            {
                isInstalled = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsInstalled)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(InstallButtonVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(InstalledBadgeVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadButtonEnabled)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CanDelete)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DeleteButtonVisibility)));
            }
        }
    }

    public bool IsDownloading
    {
        get => isDownloading;
        set
        {
            if (isDownloading != value)
            {
                isDownloading = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsDownloading)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadButtonEnabled)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CanDelete)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DeleteButtonVisibility)));
            }
        }
    }

    public bool CanDelete => isInstalled && !Id.Equals("hexgrad/Kokoro-82M", StringComparison.OrdinalIgnoreCase) && !isDownloading;
    public Visibility DeleteButtonVisibility => CanDelete ? Visibility.Visible : Visibility.Collapsed;
    public bool DownloadButtonEnabled => !isDownloading && !isInstalled;
    public Visibility InstallButtonVisibility => isInstalled ? Visibility.Collapsed : Visibility.Visible;
    public Visibility InstalledBadgeVisibility => isInstalled ? Visibility.Visible : Visibility.Collapsed;

    public event PropertyChangedEventHandler? PropertyChanged;
}

public sealed record ProjectRecord
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Title { get; set; } = "Untitled narration";
    public string Text { get; set; } = "";
    public string VoiceID { get; set; } = "af_heart";
    public double Speed { get; set; } = 1.0;
    public AudioFormat Format { get; set; } = AudioFormat.mp3;
    public string AudioPath { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.Now;
    public bool IsLegacyImport { get; set; }
}

public sealed record AppSettings
{
    public string OutputDirectory { get; set; } = "";
    public AudioFormat DefaultFormat { get; set; } = AudioFormat.mp3;
    public double DefaultSpeed { get; set; } = 1.0;
    public string SelectedVoiceID { get; set; } = "af_heart";
    public DeviceMode DeviceMode { get; set; } = DeviceMode.auto;
    public HashSet<string> FavoriteVoiceIDs { get; set; } = ["af_heart", "af_bella", "bf_emma"];
    public HashSet<string> PendingDownloadModelIds { get; set; } = [];
}

public sealed record BackendInfo
{
    [JsonPropertyName("selected_device")]
    public string SelectedDevice { get; init; } = "cpu";

    [JsonPropertyName("requested_device")]
    public string RequestedDevice { get; init; } = "auto";

    [JsonPropertyName("torch_version")]
    public string? TorchVersion { get; init; }

    [JsonPropertyName("cuda_available")]
    public bool CudaAvailable { get; init; }

    [JsonPropertyName("cuda_version")]
    public string? CudaVersion { get; init; }

    [JsonPropertyName("mps_available")]
    public bool MpsAvailable { get; init; }

    [JsonPropertyName("model_root_valid")]
    public bool ModelRootValid { get; init; }

    [JsonPropertyName("xtts_installed")]
    public bool XttsInstalled { get; init; }

    [JsonPropertyName("voice_count")]
    public int VoiceCount { get; init; }
}

public sealed record GenerationOutput(string Path, int Segments, int SampleRate);

public sealed record ModelDownloadProgress(
    int Percent,
    string Status,
    string Speed,
    string Eta,
    string SizeText);

public sealed class InstalledModelItem : INotifyPropertyChanged
{
    private bool isInstalled;
    private bool isDownloading;
    private bool isPaused;
    private int downloadProgress;
    private string downloadSpeed = "";
    private string downloadEta = "";
    private string downloadSize = "";
    private string downloadStatus = "";

    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string Description { get; init; } = "";
    public string SupportedLanguages { get; init; } = "";
    public bool IsBundled { get; init; }

    public bool IsPaused
    {
        get => isPaused;
        set
        {
            if (isPaused != value)
            {
                isPaused = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsPaused)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadButtonText)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CancelButtonVisibility)));
            }
        }
    }

    public string DownloadButtonText => (isPaused || downloadProgress > 0) ? "Resume Download" : "Download Model";

    public bool IsInstalled
    {
        get => isInstalled;
        set
        {
            if (isInstalled != value)
            {
                isInstalled = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsInstalled)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(InstalledBadgeVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadButtonVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CancelButtonVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CanDelete)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DeleteButtonVisibility)));
            }
        }
    }

    public bool IsDownloading
    {
        get => isDownloading;
        set
        {
            if (isDownloading != value)
            {
                isDownloading = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsDownloading)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadingVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadButtonVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CancelButtonVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CanDelete)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DeleteButtonVisibility)));
            }
        }
    }

    public int DownloadProgress
    {
        get => downloadProgress;
        set
        {
            if (downloadProgress != value)
            {
                downloadProgress = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadProgress)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadButtonText)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CancelButtonVisibility)));
            }
        }
    }

    public string DownloadSpeed
    {
        get => downloadSpeed;
        set
        {
            if (downloadSpeed != value)
            {
                downloadSpeed = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadSpeed)));
            }
        }
    }

    public string DownloadEta
    {
        get => downloadEta;
        set
        {
            if (downloadEta != value)
            {
                downloadEta = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadEta)));
            }
        }
    }

    public string DownloadSize
    {
        get => downloadSize;
        set
        {
            if (downloadSize != value)
            {
                downloadSize = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadSize)));
            }
        }
    }

    public string DownloadStatus
    {
        get => downloadStatus;
        set
        {
            if (downloadStatus != value)
            {
                downloadStatus = value;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DownloadStatus)));
            }
        }
    }

    public bool CanDelete => !IsBundled && IsInstalled && !IsDownloading;
    public Visibility DeleteButtonVisibility => CanDelete ? Visibility.Visible : Visibility.Collapsed;
    public Visibility InstalledBadgeVisibility => IsInstalled ? Visibility.Visible : Visibility.Collapsed;
    public Visibility DownloadButtonVisibility => (!IsInstalled && !IsDownloading) ? Visibility.Visible : Visibility.Collapsed;
    public Visibility DownloadingVisibility => IsDownloading ? Visibility.Visible : Visibility.Collapsed;
    public Visibility CancelButtonVisibility => (!IsBundled && !IsInstalled && (IsDownloading || isPaused || downloadProgress > 0)) ? Visibility.Visible : Visibility.Collapsed;

    public event PropertyChangedEventHandler? PropertyChanged;
}
