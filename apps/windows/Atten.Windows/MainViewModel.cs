using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text.Json;
using Microsoft.UI.Xaml;

namespace Atten.Windows;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private static readonly HttpClient httpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(15)
    };

    private readonly StorageService storage = new();
    private readonly BackendClient backend = new();
    private CancellationTokenSource? generationCts;
    private string draftTitle = "Untitled narration";
    private string draftText = "";
    private string selectedModel = "All Models";
    private string selectedLanguage = "All Languages";
    private string selectedVoiceID = "af_heart";
    private string voiceSearchText = "";
    private double speed = 1.0;
    private AudioFormat format = AudioFormat.mp3;
    private DeviceMode deviceMode = DeviceMode.auto;
    private string outputDirectory = "";
    private string status = "";
    private string? currentAudioPath;
    private bool isGenerating;
    private BackendInfo? backendInfo;
    private bool isXttsInstalled;
    private bool isDownloadingModel;
    private bool isDownloadPaused;
    private int downloadProgress;
    private string downloadStatus = "";
    private string downloadSpeed = "";
    private string downloadEta = "";
    private string downloadSizeText = "";
    private CancellationTokenSource? downloadCts;

    // Player Bar State
    private bool isPlayerVisible;
    private bool isPlaying;
    private double playerPosition;
    private double playerDuration;
    private string playerTimeText = "00:00 / 00:00";
    private string playerTitle = "";

    // HF Models Filter State
    private bool isFetchingHfModels;
    private string selectedHfLanguage = "All Languages";
    private string selectedHfFilter = "All Models";
    private string hfSearchText = "";

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<ProjectRecord> Projects { get; } = [];
    public IReadOnlyList<Voice> Voices => VoiceCatalog.All;
    public ObservableCollection<Voice> FilteredVoices { get; } = [];
    public ObservableCollection<VoiceGroup> GroupedVoices { get; } = [];
    public ObservableCollection<string> AvailableModels { get; } = ["All Models", "Kokoro-82M", "XTTS-v2 & Multilingual Neural"];
    public ObservableCollection<string> AvailableLanguages { get; } = [];
    public ObservableCollection<Voice> StudioVoices { get; } = [];
    public ObservableCollection<InstalledModelItem> InstalledEngines { get; } = [];
    public ObservableCollection<HfModelInfo> HfModels { get; } = [];
    public ObservableCollection<HfModelInfo> FilteredHfModels { get; } = [];
    public ObservableCollection<string> HfLanguages { get; } = [
        "All Languages", "Arabic", "English", "German", "Spanish", "French", "Italian", "Portuguese",
        "Russian", "Turkish", "Dutch", "Polish", "Japanese", "Chinese", "Hindi", "Korean", "Vietnamese",
        "Indonesian", "Ukrainian", "Greek", "Hebrew", "Czech", "Romanian", "Hungarian", "Danish",
        "Norwegian", "Finnish", "Swedish", "Thai", "Tamil", "Telugu", "Urdu", "Bengali", "Persian", "Swahili", "Catalan"
    ];
    public ObservableCollection<string> HfSortOptions { get; } = ["Most Downloads", "Most Stars", "Smallest Size", "Largest Size", "Provider (A-Z)", "Model Name (A-Z)"];
    public ObservableCollection<string> HfFilters { get; } = ["All Models", "Installed", "Available to Download"];
    public IReadOnlyList<AudioFormat> Formats { get; } = Enum.GetValues<AudioFormat>();
    public IReadOnlyList<DeviceMode> DeviceModes { get; } = Enum.GetValues<DeviceMode>();

    private string selectedHfSort = "Most Downloads";

    public string SelectedHfSort
    {
        get => selectedHfSort;
        set
        {
            if (Set(ref selectedHfSort, value))
            {
                UpdateFilteredHfModels();
                _ = FetchHfModelsAsync();
            }
        }
    }

    public string SelectedHfLanguage
    {
        get => selectedHfLanguage;
        set
        {
            if (Set(ref selectedHfLanguage, value))
            {
                UpdateFilteredHfModels();
                _ = FetchHfModelsAsync();
            }
        }
    }

    public string SelectedHfFilter
    {
        get => selectedHfFilter;
        set
        {
            if (Set(ref selectedHfFilter, value))
            {
                UpdateFilteredHfModels();
            }
        }
    }

    private CancellationTokenSource? hfSearchCts;

    private void TriggerDebouncedHfSearch()
    {
        hfSearchCts?.Cancel();
        hfSearchCts = new CancellationTokenSource();
        var token = hfSearchCts.Token;

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(400, token);
                if (!token.IsCancellationRequested)
                {
                    await FetchHfModelsAsync();
                }
            }
            catch (OperationCanceledException)
            {
            }
        }, token);
    }

    public string HfSearchText
    {
        get => hfSearchText;
        set
        {
            if (Set(ref hfSearchText, value))
            {
                UpdateFilteredHfModels();
                TriggerDebouncedHfSearch();
            }
        }
    }

    public Visibility XttsInstalledVisibility => isXttsInstalled ? Visibility.Visible : Visibility.Collapsed;
    public Visibility XttsNotInstalledVisibility => !isXttsInstalled ? Visibility.Visible : Visibility.Collapsed;
    public Visibility XttsDownloadingVisibility => isDownloadingModel ? Visibility.Visible : Visibility.Collapsed;

    public bool IsPlayerVisible
    {
        get => isPlayerVisible;
        set
        {
            if (Set(ref isPlayerVisible, value))
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(PlayerVisibility)));
            }
        }
    }

    public Visibility PlayerVisibility => isPlayerVisible ? Visibility.Visible : Visibility.Collapsed;

    public bool IsPlaying
    {
        get => isPlaying;
        set
        {
            if (Set(ref isPlaying, value))
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(PlayPauseIcon)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(PlayPauseLabel)));
            }
        }
    }

    public string PlayPauseIcon => isPlaying ? "\uE769" : "\uE768";
    public string PlayPauseLabel => isPlaying ? "Pause" : "Play";

    public double PlayerPosition
    {
        get => playerPosition;
        set => Set(ref playerPosition, value);
    }

    public double PlayerDuration
    {
        get => playerDuration;
        set => Set(ref playerDuration, value);
    }

    public string PlayerTimeText
    {
        get => playerTimeText;
        set => Set(ref playerTimeText, value);
    }

    public string PlayerTitle
    {
        get => playerTitle;
        set => Set(ref playerTitle, value);
    }

    public bool IsFetchingHfModels
    {
        get => isFetchingHfModels;
        set => Set(ref isFetchingHfModels, value);
    }

    public string SelectedModel
    {
        get => selectedModel;
        set
        {
            if (Set(ref selectedModel, value))
            {
                UpdateAvailableLanguages();
                UpdateStudioVoices();
            }
        }
    }

    public string SelectedLanguage
    {
        get => selectedLanguage;
        set
        {
            if (Set(ref selectedLanguage, value))
            {
                UpdateStudioVoices();
            }
        }
    }

    public string VoiceSearchText
    {
        get => voiceSearchText;
        set
        {
            if (Set(ref voiceSearchText, value))
            {
                UpdateFilteredVoices();
            }
        }
    }

    public bool IsXttsInstalled
    {
        get => isXttsInstalled;
        set
        {
            if (Set(ref isXttsInstalled, value))
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(XttsInstalledVisibility)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(XttsNotInstalledVisibility)));
                var xttsEngine = InstalledEngines.FirstOrDefault(e => e.Id.Contains("xtts", StringComparison.OrdinalIgnoreCase));
                if (xttsEngine is not null)
                {
                    xttsEngine.IsInstalled = value;
                }
                UpdateHfInstalledStatuses();
            }
        }
    }

    public bool IsDownloadingModel
    {
        get => isDownloadingModel;
        set
        {
            if (Set(ref isDownloadingModel, value))
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(XttsDownloadingVisibility)));
            }
        }
    }

    public bool IsDownloadPaused
    {
        get => isDownloadPaused;
        set => Set(ref isDownloadPaused, value);
    }

    public int DownloadProgress
    {
        get => downloadProgress;
        set => Set(ref downloadProgress, value);
    }

    public string DownloadStatus
    {
        get => downloadStatus;
        set => Set(ref downloadStatus, value);
    }

    public string DownloadSpeed
    {
        get => downloadSpeed;
        set => Set(ref downloadSpeed, value);
    }

    public string DownloadEta
    {
        get => downloadEta;
        set => Set(ref downloadEta, value);
    }

    public string DownloadSizeText
    {
        get => downloadSizeText;
        set => Set(ref downloadSizeText, value);
    }

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

    public Voice? SelectedVoice
    {
        get => StudioVoices.FirstOrDefault(v => v.Id == selectedVoiceID) ?? VoiceCatalog.ById(selectedVoiceID);
        set
        {
            if (value is not null && selectedVoiceID != value.Id)
            {
                selectedVoiceID = value.Id;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SelectedVoiceID)));
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SelectedVoice)));
            }
        }
    }

    public string SelectedVoiceID
    {
        get => selectedVoiceID;
        set
        {
            if (Set(ref selectedVoiceID, value))
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SelectedVoice)));
            }
        }
    }

    public void SelectVoice(Voice voice)
    {
        if (voice is null) return;
        selectedVoiceID = voice.Id;

        if (SelectedModel != "All Models" && !voice.ModelEngine.Contains(SelectedModel, StringComparison.OrdinalIgnoreCase) && !SelectedModel.Contains(voice.ModelEngine, StringComparison.OrdinalIgnoreCase))
        {
            SelectedModel = "All Models";
        }

        if (SelectedLanguage != "All Languages" && !voice.Language.Equals(SelectedLanguage, StringComparison.OrdinalIgnoreCase))
        {
            SelectedLanguage = "All Languages";
        }

        UpdateStudioVoices();
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SelectedVoiceID)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SelectedVoice)));
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
        set
        {
            if (Set(ref isGenerating, value))
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(GeneratingVisibility)));
            }
        }
    }

    public Visibility GeneratingVisibility => isGenerating ? Visibility.Visible : Visibility.Collapsed;

    public BackendInfo? BackendInfo
    {
        get => backendInfo;
        set
        {
            Set(ref backendInfo, value);
            if (value is not null)
            {
                IsXttsInstalled = value.XttsInstalled;
            }
        }
    }

    public void UpdateAvailableLanguages()
    {
        var current = SelectedLanguage;
        AvailableLanguages.Clear();
        AvailableLanguages.Add("All Languages");

        var query = Voices.AsEnumerable();
        if (SelectedModel != "All Models")
        {
            query = query.Where(v => v.ModelEngine.Contains(SelectedModel, StringComparison.OrdinalIgnoreCase) ||
                                     SelectedModel.Contains(v.ModelEngine, StringComparison.OrdinalIgnoreCase));
        }

        var distinctLanguages = query.Select(v => v.Language).Distinct().OrderBy(l => l);
        foreach (var lang in distinctLanguages)
        {
            AvailableLanguages.Add(lang);
        }

        if (AvailableLanguages.Contains(current))
        {
            SelectedLanguage = current;
        }
        else
        {
            SelectedLanguage = "All Languages";
        }
    }

    public void UpdateStudioVoices()
    {
        var targetVoiceId = selectedVoiceID;
        StudioVoices.Clear();
        var query = Voices.AsEnumerable();
        if (SelectedModel != "All Models")
        {
            query = query.Where(v => v.ModelEngine.Contains(SelectedModel, StringComparison.OrdinalIgnoreCase) ||
                                     SelectedModel.Contains(v.ModelEngine, StringComparison.OrdinalIgnoreCase));
        }
        if (SelectedLanguage != "All Languages" && !string.IsNullOrEmpty(SelectedLanguage))
        {
            query = query.Where(v => v.Language.Equals(SelectedLanguage, StringComparison.OrdinalIgnoreCase));
        }

        var matching = query.ToList();
        foreach (var v in matching)
        {
            StudioVoices.Add(v);
        }

        if (StudioVoices.Count > 0)
        {
            var match = StudioVoices.FirstOrDefault(v => v.Id == targetVoiceId);
            if (match is not null)
            {
                selectedVoiceID = match.Id;
            }
            else
            {
                selectedVoiceID = StudioVoices[0].Id;
            }
        }
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SelectedVoiceID)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SelectedVoice)));
    }

    public void UpdateFilteredVoices()
    {
        FilteredVoices.Clear();
        GroupedVoices.Clear();
        var query = (voiceSearchText ?? "").Trim().ToLowerInvariant();

        var matched = Voices.Where(v =>
            string.IsNullOrEmpty(query) ||
            v.Name.ToLowerInvariant().Contains(query) ||
            v.Language.ToLowerInvariant().Contains(query) ||
            v.Gender.ToLowerInvariant().Contains(query) ||
            v.ModelEngine.ToLowerInvariant().Contains(query) ||
            v.Traits.Any(t => t.ToLowerInvariant().Contains(query))).ToList();

        foreach (var v in matched)
        {
            FilteredVoices.Add(v);
        }

        var groups = matched
            .GroupBy(v => (v.Language, v.ModelEngine))
            .OrderBy(g => g.Key.Language)
            .Select(g => new VoiceGroup(g.Key.Language, g.Key.ModelEngine, g.ToList()));

        foreach (var group in groups)
        {
            GroupedVoices.Add(group);
        }
    }

    public void UpdateFilteredHfModels()
    {
        var query = (hfSearchText ?? "").Trim().ToLowerInvariant();
        var list = new List<HfModelInfo>();

        foreach (var m in HfModels)
        {
            // Language filter
            if (SelectedHfLanguage != "All Languages" && !string.IsNullOrEmpty(SelectedHfLanguage))
            {
                if (!m.SupportsLanguage(SelectedHfLanguage))
                {
                    continue;
                }
            }

            // Installed filter
            if (SelectedHfFilter == "Installed" && !m.IsInstalled)
            {
                continue;
            }
            if (SelectedHfFilter == "Available to Download" && m.IsInstalled)
            {
                continue;
            }

            // Search query filter
            if (!string.IsNullOrEmpty(query))
            {
                var matches = m.Name.ToLowerInvariant().Contains(query) ||
                              m.Author.ToLowerInvariant().Contains(query) ||
                              m.Id.ToLowerInvariant().Contains(query) ||
                              m.LanguagesText.ToLowerInvariant().Contains(query);
                if (!matches) continue;
            }

            list.Add(m);
        }

        // Apply sorting
        IEnumerable<HfModelInfo> sorted = SelectedHfSort switch
        {
            "Most Stars" => list.OrderByDescending(m => m.Likes),
            "Smallest Size" => list.OrderBy(m => ParseSizeBytes(m.SizeText)),
            "Largest Size" => list.OrderByDescending(m => ParseSizeBytes(m.SizeText)),
            "Provider (A-Z)" => list.OrderBy(m => string.IsNullOrEmpty(m.Author) ? m.Name : m.Author).ThenBy(m => m.Name),
            "Model Name (A-Z)" => list.OrderBy(m => m.Name),
            _ => list.OrderByDescending(m => m.Downloads)
        };

        FilteredHfModels.Clear();
        foreach (var item in sorted)
        {
            FilteredHfModels.Add(item);
        }
    }

    private static long ParseSizeBytes(string sizeText)
    {
        if (string.IsNullOrWhiteSpace(sizeText)) return 0L;
        var trimmed = sizeText.Trim();
        if (trimmed.StartsWith("~")) trimmed = trimmed[1..].Trim();

        var parts = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || !double.TryParse(parts[0], System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var num))
        {
            return 0L;
        }

        var unit = parts[1].ToUpperInvariant();
        if (unit.StartsWith("GB")) return (long)(num * 1024 * 1024 * 1024);
        if (unit.StartsWith("MB")) return (long)(num * 1024 * 1024);
        if (unit.StartsWith("KB")) return (long)(num * 1024);
        return (long)num;
    }

    private static bool IsCompatibleModel(string id, IEnumerable<string> tags)
    {
        if (string.IsNullOrWhiteSpace(id)) return false;

        // Incompatible / unsupported runtimes
        if (id.Contains("Qwen", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("MOSS", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("magpie", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("chatterbox", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("supertonic", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("audio.cpp", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("OmniVoice", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("VoxCPM", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("Irodori", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("sanoTTS", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("kaburi", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("Breeze-TTS", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("AuK", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("ZeroTTS", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("Kahya", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("ChatTTS", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("FishAudio", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("fish-speech", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("F5-TTS", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("CosyVoice", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        // Supported architectures and model publishers
        if (id.StartsWith("facebook/mms-tts", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("mms-tts", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("hexgrad/Kokoro", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("kokoro", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("coqui/XTTS", StringComparison.OrdinalIgnoreCase) ||
            id.Contains("xtts", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("kakao-enterprise/vits", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("ylacombe/vits", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("espnet/", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("Matthijs/vits", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("rodrigo-v/vits", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("csukuangfj/vits", StringComparison.OrdinalIgnoreCase) ||
            id.StartsWith("microsoft/speecht5", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return tags.Any(t => t.Equals("vits", StringComparison.OrdinalIgnoreCase) ||
                             t.Equals("mms-tts", StringComparison.OrdinalIgnoreCase) ||
                             t.Equals("mms", StringComparison.OrdinalIgnoreCase) ||
                             t.Equals("kokoro", StringComparison.OrdinalIgnoreCase) ||
                             t.Equals("xtts", StringComparison.OrdinalIgnoreCase) ||
                             t.Equals("speecht5", StringComparison.OrdinalIgnoreCase));
    }

    public async Task FetchHfModelsAsync()
    {
        if (IsFetchingHfModels) return;
        IsFetchingHfModels = true;

        try
        {
            var sortParam = SelectedHfSort == "Most Stars" ? "likes" : "downloads";
            var queryUrls = new List<string>();
            var query = (hfSearchText ?? "").Trim();

            if (!string.IsNullOrWhiteSpace(query))
            {
                var escaped = Uri.EscapeDataString(query);
                queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search={escaped}&sort={sortParam}&direction=-1&limit=60&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
            }

            if (!string.IsNullOrWhiteSpace(SelectedHfLanguage) && SelectedHfLanguage != "All Languages")
            {
                if (HfModelInfo.LanguageToCodes.TryGetValue(SelectedHfLanguage, out var codes))
                {
                    foreach (var code in codes)
                    {
                        queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search=mms-tts-{code}&sort={sortParam}&direction=-1&limit=30&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                        queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&filter={code}&sort={sortParam}&direction=-1&limit=30&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                        queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search=vits-{code}&sort={sortParam}&direction=-1&limit=20&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                    }
                }
            }
            else if (string.IsNullOrWhiteSpace(query))
            {
                queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search=facebook/mms-tts&sort={sortParam}&direction=-1&limit=100&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search=kokoro&sort={sortParam}&direction=-1&limit=40&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search=xtts&sort={sortParam}&direction=-1&limit=40&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&other=vits&sort={sortParam}&direction=-1&limit=60&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search=espnet&sort={sortParam}&direction=-1&limit=25&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
                queryUrls.Add($"https://huggingface.co/api/models?pipeline_tag=text-to-speech&search=speecht5&sort={sortParam}&direction=-1&limit=25&expand[]=likes&expand[]=downloads&expand[]=safetensors&expand[]=gguf&expand[]=tags&expand[]=cardData");
            }

            var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var fetchedList = new List<HfModelInfo>();

            foreach (var url in queryUrls)
            {
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Get, url);
                    request.Headers.Add("User-Agent", "Atten/0.2.1");
                    var response = await httpClient.SendAsync(request);
                    if (!response.IsSuccessStatusCode) continue;

                    var json = await response.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);

                    foreach (var item in doc.RootElement.EnumerateArray())
                    {
                        var id = item.GetProperty("id").GetString() ?? "";
                        if (string.IsNullOrWhiteSpace(id) || seenIds.Contains(id)) continue;

                        var rawTags = new List<string>();
                        if (item.TryGetProperty("tags", out var tagsElem))
                        {
                            foreach (var tag in tagsElem.EnumerateArray())
                            {
                                var t = (tag.GetString() ?? "").ToLowerInvariant();
                                rawTags.Add(t);
                            }
                        }

                        // Strictly filter for compatibility
                        if (!IsCompatibleModel(id, rawTags))
                        {
                            continue;
                        }

                        seenIds.Add(id);
                        var parts = id.Split('/');
                        var author = parts.Length > 1 ? parts[0] : "";
                        var name = parts.Length > 1 ? parts[1] : id;
                        var downloads = item.TryGetProperty("downloads", out var d) ? d.GetInt32() : 0;
                        var likes = item.TryGetProperty("likes", out var l) ? l.GetInt32() : 0;

                        var langCodes = new List<string>();
                        var langNames = new List<string>();

                        if (item.TryGetProperty("cardData", out var cardData) && cardData.TryGetProperty("language", out var cardLang))
                        {
                            if (cardLang.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var lElem in cardLang.EnumerateArray())
                                {
                                    var code = (lElem.GetString() ?? "").ToLowerInvariant();
                                    if (!string.IsNullOrEmpty(code) && !langCodes.Contains(code)) langCodes.Add(code);
                                    if (HfModelInfo.CodeToLanguage.TryGetValue(code, out var langName) && !langNames.Contains(langName))
                                    {
                                        langNames.Add(langName);
                                    }
                                }
                            }
                            else if (cardLang.ValueKind == JsonValueKind.String)
                            {
                                var code = (cardLang.GetString() ?? "").ToLowerInvariant();
                                if (!string.IsNullOrEmpty(code) && !langCodes.Contains(code)) langCodes.Add(code);
                                if (HfModelInfo.CodeToLanguage.TryGetValue(code, out var langName) && !langNames.Contains(langName))
                                {
                                    langNames.Add(langName);
                                }
                            }
                        }

                        foreach (var tag in rawTags)
                        {
                            var t = tag;
                            if (t.StartsWith("language:"))
                            {
                                t = t.Substring("language:".Length);
                            }
                            if (!langCodes.Contains(t)) langCodes.Add(t);
                            if (HfModelInfo.CodeToLanguage.TryGetValue(t, out var langName))
                            {
                                if (!langNames.Contains(langName)) langNames.Add(langName);
                            }
                        }

                        if (id.StartsWith("facebook/mms-tts-", StringComparison.OrdinalIgnoreCase))
                        {
                            var sub = id.Substring("facebook/mms-tts-".Length).ToLowerInvariant();
                            if (HfModelInfo.CodeToLanguage.TryGetValue(sub, out var foundLang) && !langNames.Contains(foundLang))
                            {
                                langNames.Add(foundLang);
                                langCodes.Add(sub);
                            }
                        }

                        string langText;
                        if (langNames.Count > 0)
                        {
                            langText = string.Join(", ", langNames.Take(5));
                            if (langNames.Count > 5) langText += $", +{langNames.Count - 5} more";
                        }
                        else
                        {
                            langText = id.Contains("ara", StringComparison.OrdinalIgnoreCase) ? "Arabic" : 
                                       (id.Contains("deu", StringComparison.OrdinalIgnoreCase) ? "German" : 
                                       (id.Contains("rus", StringComparison.OrdinalIgnoreCase) ? "Russian" : "Multilingual"));
                        }

                        var downloadsText = downloads >= 1_000_000 ? $"{downloads / 1_000_000.0:F1}M downloads" :
                                            downloads >= 1_000 ? $"{downloads / 1_000.0:F1}K downloads" : $"{downloads} downloads";

                        var likesText = likes >= 1_000_000 ? $"{likes / 1_000_000.0:F1}M" :
                                        likes >= 1_000 ? $"{likes / 1_000.0:F1}k" : $"{likes}";

                        string sizeText = "";
                        if (ManifestSizeCache.TryGetValue(id, out var cachedSize))
                        {
                            sizeText = cachedSize;
                        }
                        else if (item.TryGetProperty("safetensors", out var safetensors) && safetensors.TryGetProperty("total", out var total))
                        {
                            var totalBytes = total.GetInt64();
                            if (totalBytes >= 1_073_741_824)
                                sizeText = $"{totalBytes / 1_073_741_824.0:F1} GB";
                            else if (totalBytes >= 1_048_576)
                                sizeText = $"{totalBytes / 1_048_576.0:F0} MB";
                            else if (totalBytes > 0)
                                sizeText = $"{totalBytes / 1024.0:F0} KB";
                        }

                        if (string.IsNullOrEmpty(sizeText))
                        {
                            if (id.Contains("Kokoro", StringComparison.OrdinalIgnoreCase)) sizeText = "82 MB";
                            else if (id.Contains("XTTS", StringComparison.OrdinalIgnoreCase)) sizeText = "1.87 GB";
                            else if (id.Contains("mms-tts", StringComparison.OrdinalIgnoreCase)) sizeText = "145 MB";
                            else sizeText = "~145 MB";
                        }

                        var installedIds = InstalledEngines.Where(e => e.IsInstalled).Select(e => e.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
                        var isInstalled = installedIds.Contains(id) ||
                                          id.Equals("hexgrad/Kokoro-82M", StringComparison.OrdinalIgnoreCase) ||
                                          (id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase) && IsXttsInstalled);

                        fetchedList.Add(new HfModelInfo
                        {
                            Id = id,
                            Name = name,
                            Author = author,
                            Downloads = downloads,
                            Likes = likes,
                            DownloadsText = downloadsText,
                            LikesText = likesText,
                            SizeText = sizeText,
                            LanguagesText = langText,
                            LanguageCodes = langCodes,
                            IsInstalled = isInstalled
                        });
                    }
                }
                catch
                {
                }
            }

            if (fetchedList.Count > 0)
            {
                // Retain existing installed models so they never vanish from the list
                var existingInstalled = HfModels.Where(m => m.IsInstalled).ToList();
                foreach (var inst in existingInstalled)
                {
                    if (!fetchedList.Any(f => f.Id.Equals(inst.Id, StringComparison.OrdinalIgnoreCase)))
                    {
                        fetchedList.Add(inst);
                    }
                }

                HfModels.Clear();
                foreach (var m in fetchedList)
                {
                    HfModels.Add(m);
                }
            }
            else
            {
                PopulateFallbackHfModels();
            }
        }
        catch
        {
            if (HfModels.Count == 0)
            {
                PopulateFallbackHfModels();
            }
        }
        finally
        {
            if (HfModels.Count == 0)
            {
                PopulateFallbackHfModels();
            }
            ScanInstalledEngines();
            UpdateDynamicVoices();
            UpdateAvailableModels();
            UpdateAvailableLanguages();
            UpdateStudioVoices();
            UpdateFilteredVoices();
            UpdateHfInstalledStatuses();
            IsFetchingHfModels = false;

            var snapshot = HfModels.ToList();
            _ = FetchManifestSizesForModelsAsync(snapshot);
        }
    }

    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string> ManifestSizeCache = new(StringComparer.OrdinalIgnoreCase);

    private async Task FetchManifestSizesForModelsAsync(List<HfModelInfo> models)
    {
        var uncached = models.Where(m => !ManifestSizeCache.ContainsKey(m.Id)).ToList();
        if (uncached.Count == 0) return;

        var sem = new SemaphoreSlim(4);
        bool updatedAny = false;
        var tasks = uncached.Select(async m =>
        {
            await sem.WaitAsync();
            try
            {
                var exactSize = await GetExactHfModelSizeAsync(m.Id);
                if (!string.IsNullOrEmpty(exactSize))
                {
                    m.SizeText = exactSize;
                    updatedAny = true;
                }
            }
            catch
            {
            }
            finally
            {
                sem.Release();
            }
        });

        await Task.WhenAll(tasks);

        if (updatedAny)
        {
            await storage.SaveModelSizesCacheAsync(ManifestSizeCache);
        }
    }

    public async Task<string> GetExactHfModelSizeAsync(string cleanId)
    {
        if (string.IsNullOrWhiteSpace(cleanId)) return "";
        if (cleanId.Equals("hexgrad/Kokoro-82M", StringComparison.OrdinalIgnoreCase)) return "82 MB";
        if (cleanId.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase)) return "1.87 GB";

        if (ManifestSizeCache.TryGetValue(cleanId, out var cached))
        {
            return cached;
        }

        try
        {
            var url = $"https://huggingface.co/api/models/{cleanId}/tree/main?recursive=true";
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.Add("User-Agent", "Atten/0.2.1");
            var res = await httpClient.SendAsync(req);
            if (!res.IsSuccessStatusCode) return "";

            var json = await res.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);

            var ignoredExts = new[] { ".png", ".jpg", ".jpeg", ".gif", ".mp4", ".wav", ".flac", ".mp3", ".gitattributes", ".gitignore" };
            var allFiles = new List<(string path, long size)>();

            foreach (var elem in doc.RootElement.EnumerateArray())
            {
                if (elem.TryGetProperty("type", out var tProp) && tProp.GetString() == "file")
                {
                    var path = elem.GetProperty("path").GetString() ?? "";
                    var size = elem.TryGetProperty("size", out var sProp) ? sProp.GetInt64() : 0L;
                    allFiles.Add((path, size));
                }
            }

            var safetensorStems = allFiles
                .Where(f => f.path.EndsWith(".safetensors", StringComparison.OrdinalIgnoreCase))
                .Select(f => f.path[..^".safetensors".Length])
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            var ggufFiles = new List<(string path, long size)>();
            var filtered = new List<(string path, long size)>();

            foreach (var (path, size) in allFiles)
            {
                var lower = path.ToLowerInvariant();
                if (ignoredExts.Any(ext => lower.EndsWith(ext)) || lower.Contains("assets/") || lower.Contains("demo/") || lower.Contains("examples/"))
                {
                    continue;
                }

                if (lower.EndsWith(".gguf"))
                {
                    ggufFiles.Add((path, size));
                    continue;
                }

                if (lower.EndsWith(".pt") || lower.EndsWith(".bin") || lower.EndsWith(".pth") || lower.EndsWith(".ckpt"))
                {
                    var lastDot = path.LastIndexOf('.');
                    var stem = lastDot >= 0 ? path[..lastDot] : path;
                    if (safetensorStems.Contains(stem))
                    {
                        continue;
                    }
                }

                filtered.Add((path, size));
            }

            if (ggufFiles.Count > 0)
            {
                var quantRegex = new System.Text.RegularExpressions.Regex(@"[-_](q[0-9]_[a-z0-9_]+|bf16|f16|f32|q8_0|q4_k_m|q5_k_m)\.gguf$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                var groups = new Dictionary<string, List<(string path, long size, string quant)>>(StringComparer.OrdinalIgnoreCase);

                foreach (var (path, size) in ggufFiles)
                {
                    var match = quantRegex.Match(path);
                    if (match.Success)
                    {
                        var baseName = path[..match.Index];
                        if (!groups.TryGetValue(baseName, out var grp))
                        {
                            grp = new List<(string, long, string)>();
                            groups[baseName] = grp;
                        }
                        grp.Add((path, size, match.Groups[1].Value.ToUpperInvariant()));
                    }
                    else
                    {
                        if (!groups.TryGetValue(path, out var grp))
                        {
                            grp = new List<(string, long, string)>();
                            groups[path] = grp;
                        }
                        grp.Add((path, size, "RAW"));
                    }
                }

                var prefOrder = new[] { "Q4_K_M", "Q8_0", "BF16", "Q5_K_M", "Q6_K", "F16", "F32" };
                foreach (var grp in groups.Values)
                {
                    (string path, long size) chosen = default;
                    bool found = false;
                    foreach (var p in prefOrder)
                    {
                        var match = grp.FirstOrDefault(x => x.quant == p);
                        if (match.path != null)
                        {
                            chosen = (match.path, match.size);
                            found = true;
                            break;
                        }
                    }
                    if (!found && grp.Count > 0)
                    {
                        chosen = (grp[0].path, grp[0].size);
                    }
                    if (chosen.path != null)
                    {
                        filtered.Add(chosen);
                    }
                }
            }

            long totalBytes = filtered.Sum(f => f.size);
            if (totalBytes > 0)
            {
                string formatted;
                if (totalBytes >= 1_073_741_824)
                    formatted = $"{totalBytes / 1_073_741_824.0:F2} GB";
                else if (totalBytes >= 1_048_576)
                    formatted = $"{totalBytes / 1_048_576.0:F1} MB";
                else if (totalBytes >= 1024)
                    formatted = $"{totalBytes / 1024.0:F0} KB";
                else
                    formatted = $"{totalBytes} B";

                ManifestSizeCache[cleanId] = formatted;
                return formatted;
            }
        }
        catch
        {
        }

        return "";
    }

    private void PopulateFallbackHfModels()
    {
        HfModels.Clear();
        HfModels.Add(new HfModelInfo
        {
            Id = "hexgrad/Kokoro-82M",
            Name = "Kokoro-82M",
            Author = "hexgrad",
            Downloads = 11500000,
            Likes = 6900,
            DownloadsText = "11.5M downloads",
            LikesText = "6.9k",
            SizeText = "82 MB",
            LanguagesText = "English, Spanish, French, Italian, Portuguese, Japanese, Chinese, Hindi",
            LanguageCodes = ["en", "es", "fr", "it", "pt", "ja", "zh", "hi"],
            IsInstalled = true
        });
        HfModels.Add(new HfModelInfo
        {
            Id = "coqui/XTTS-v2",
            Name = "XTTS-v2",
            Author = "coqui",
            Downloads = 7300000,
            Likes = 3800,
            DownloadsText = "7.3M downloads",
            LikesText = "3.8k",
            SizeText = "1.87 GB",
            LanguagesText = "Arabic, German, Russian, Turkish, Dutch, Polish, and 16+ languages",
            LanguageCodes = ["ar", "de", "ru", "tr", "nl", "pl", "es", "fr", "it", "pt", "ja", "zh", "hi", "ko"],
            IsInstalled = IsXttsInstalled
        });
        HfModels.Add(new HfModelInfo
        {
            Id = "facebook/mms-tts-ara",
            Name = "MMS-TTS Arabic",
            Author = "facebook",
            Downloads = 1200000,
            Likes = 1450,
            DownloadsText = "1.2M downloads",
            LikesText = "1.5k",
            SizeText = "145 MB",
            LanguagesText = "Arabic (العربية)",
            LanguageCodes = ["ar", "ara"],
            IsInstalled = false
        });
        HfModels.Add(new HfModelInfo
        {
            Id = "facebook/mms-tts-deu",
            Name = "MMS-TTS German",
            Author = "facebook",
            Downloads = 450000,
            Likes = 620,
            DownloadsText = "450K downloads",
            LikesText = "620",
            SizeText = "145 MB",
            LanguagesText = "German",
            LanguageCodes = ["de", "deu"],
            IsInstalled = false
        });
        HfModels.Add(new HfModelInfo
        {
            Id = "facebook/mms-tts-spa",
            Name = "MMS-TTS Spanish",
            Author = "facebook",
            Downloads = 580000,
            Likes = 790,
            DownloadsText = "580K downloads",
            LikesText = "790",
            SizeText = "145 MB",
            LanguagesText = "Spanish",
            LanguageCodes = ["es", "spa"],
            IsInstalled = false
        });
        HfModels.Add(new HfModelInfo
        {
            Id = "facebook/mms-tts-fra",
            Name = "MMS-TTS French",
            Author = "facebook",
            Downloads = 390000,
            Likes = 510,
            DownloadsText = "390K downloads",
            LikesText = "510",
            SizeText = "145 MB",
            LanguagesText = "French",
            LanguageCodes = ["fr", "fra"],
            IsInstalled = false
        });
        HfModels.Add(new HfModelInfo
        {
            Id = "facebook/mms-tts-eng",
            Name = "MMS-TTS English",
            Author = "facebook",
            Downloads = 890000,
            Likes = 940,
            DownloadsText = "890K downloads",
            LikesText = "940",
            SizeText = "145 MB",
            LanguagesText = "English",
            LanguageCodes = ["en", "eng"],
            IsInstalled = false
        });
    }

    private void UpdateHfInstalledStatuses()
    {
        var installedIds = InstalledEngines.Where(e => e.IsInstalled).Select(e => e.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var m in HfModels)
        {
            if (installedIds.Contains(m.Id) || (m.Id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase) && IsXttsInstalled))
            {
                m.IsInstalled = true;
            }
        }
        UpdateFilteredHfModels();
    }

    public void InitializeInstalledEngines()
    {
        InstalledEngines.Clear();
        InstalledEngines.Add(new InstalledModelItem
        {
            Id = "hexgrad/Kokoro-82M",
            Name = "Kokoro-82M (Default Engine)",
            Description = "Bundled offline model (English US/UK, Spanish, French, Italian, Portuguese, Japanese, Mandarin, Hindi)",
            SupportedLanguages = "English, Spanish, French, Italian, Portuguese, Japanese, Chinese, Hindi",
            IsInstalled = true,
            IsBundled = true
        });

        InstalledEngines.Add(new InstalledModelItem
        {
            Id = "coqui/XTTS-v2",
            Name = "XTTS-v2 & Multilingual Neural Models",
            Description = "High-quality neural model with Arabic (العربية), German, Russian, Turkish, Dutch, Polish and 16+ languages",
            SupportedLanguages = "Arabic, German, Russian, Turkish, Dutch, Polish, and 16+ languages",
            IsInstalled = IsXttsInstalled
        });

        ScanInstalledEngines();
        UpdateDynamicVoices();
        UpdateAvailableModels();
        UpdateAvailableLanguages();
        UpdateStudioVoices();
        UpdateFilteredVoices();
    }

    public void ScanInstalledEngines()
    {
        var modelsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Atten", "Models");

        var xttsItem = InstalledEngines.FirstOrDefault(e => e.Id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase));
        var xttsDir = Path.Combine(modelsDir, "XTTS-v2");
        var xttsModelFile = Path.Combine(xttsDir, "model.pth");
        bool xttsOnDisk = Directory.Exists(xttsDir) && File.Exists(xttsModelFile) && new FileInfo(xttsModelFile).Length > 100_000_000;
        if (xttsOnDisk)
        {
            IsXttsInstalled = true;
            if (xttsItem is not null) xttsItem.IsInstalled = true;
        }

        if (!Directory.Exists(modelsDir)) return;

        var validInstalledIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var dir in Directory.GetDirectories(modelsDir))
        {
            var folderName = Path.GetFileName(dir);
            if (folderName.Equals("XTTS-v2", StringComparison.OrdinalIgnoreCase)) continue;

            if (folderName.Contains("--"))
            {
                var modelId = folderName.Replace("--", "/");

                // Check for incomplete download files (.part, .tmp, .download)
                var allFiles = Directory.GetFiles(dir, "*", SearchOption.AllDirectories);
                if (allFiles.Length == 0) continue;

                if (allFiles.Any(f => f.EndsWith(".part", StringComparison.OrdinalIgnoreCase) ||
                                      f.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase) ||
                                      f.EndsWith(".download", StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }

                // Check for valid weights (>1MB) or completion marker
                bool hasModelWeights = allFiles.Any(f =>
                {
                    var name = Path.GetFileName(f).ToLowerInvariant();
                    if (name is ".atten_complete" or ".complete") return true;
                    if (name is "readme.md" or ".gitattributes" or ".gitignore" or "license" or "license.txt") return false;
                    var ext = Path.GetExtension(f).ToLowerInvariant();
                    return ext is ".bin" or ".pt" or ".pth" or ".safetensors" or ".onnx" or ".gguf" or ".nemo" or ".tflite" or ".engine" or ".model"
                           && new FileInfo(f).Length > 1024 * 1024;
                });

                if (!hasModelWeights) continue;

                validInstalledIds.Add(modelId);

                var existing = InstalledEngines.FirstOrDefault(e => e.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
                if (existing is not null)
                {
                    existing.IsInstalled = true;
                }
                else
                {
                    var parts = modelId.Split('/');
                    var name = parts.Length > 1 ? parts[1] : modelId;
                    var hfMatch = HfModels.FirstOrDefault(m => m.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
                    var langText = hfMatch?.LanguagesText ?? (name.Contains("ara", StringComparison.OrdinalIgnoreCase) ? "Arabic" : "Multilingual");

                    InstalledEngines.Add(new InstalledModelItem
                    {
                        Id = modelId,
                        Name = name,
                        Description = $"{modelId} • {langText}",
                        SupportedLanguages = langText,
                        IsInstalled = true,
                        IsBundled = false
                    });
                }

                var hf = HfModels.FirstOrDefault(m => m.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
                if (hf is not null)
                {
                    hf.IsInstalled = true;
                    hf.IsDownloading = false;
                }
            }
        }

        // Clean up any dynamic InstalledEngines that are not fully on disk
        var toRemove = InstalledEngines.Where(e => !e.IsBundled && !e.Id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase) && !validInstalledIds.Contains(e.Id)).ToList();
        foreach (var item in toRemove)
        {
            InstalledEngines.Remove(item);
        }

        // Update HfModels statuses
        foreach (var hf in HfModels)
        {
            if (hf.Id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase))
            {
                hf.IsInstalled = IsXttsInstalled;
            }
            else
            {
                hf.IsInstalled = validInstalledIds.Contains(hf.Id);
            }
        }
    }

    public void UpdateDynamicVoices()
    {
        var dynList = new List<Voice>();
        foreach (var engine in InstalledEngines.Where(e => e.IsInstalled && !e.IsBundled && !e.Id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase)))
        {
            var hfMatch = HfModels.FirstOrDefault(m => m.Id.Equals(engine.Id, StringComparison.OrdinalIgnoreCase));
            var langs = hfMatch?.LanguagesText ?? engine.SupportedLanguages;
            var primaryLang = "English";
            if (!string.IsNullOrWhiteSpace(langs))
            {
                var split = langs.Split([',', '•'], StringSplitOptions.RemoveEmptyEntries);
                if (split.Length > 0) primaryLang = split[0].Trim();
            }

            var voiceId = $"dyn_{engine.Name.ToLowerInvariant().Replace(' ', '_').Replace('-', '_')}";
            dynList.Add(new Voice(
                voiceId,
                $"{engine.Name} (Default Voice)",
                primaryLang,
                "en",
                "Neutral",
                ["Neural", "Local", "Community"],
                "neural",
                engine.Name));
        }

        VoiceCatalog.SetDynamicVoices(dynList);
    }

    public void UpdateAvailableModels()
    {
        var current = SelectedModel;
        var models = new List<string>
        {
            "All Models",
            "Kokoro-82M"
        };

        if (IsXttsInstalled)
        {
            models.Add("XTTS-v2 & Multilingual Neural");
        }

        foreach (var engine in InstalledEngines.Where(e => e.IsInstalled && !e.IsBundled && !e.Id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase)))
        {
            if (!string.IsNullOrWhiteSpace(engine.Name) && !models.Contains(engine.Name, StringComparer.OrdinalIgnoreCase))
            {
                models.Add(engine.Name);
            }
        }

        AvailableModels.Clear();
        foreach (var m in models)
        {
            AvailableModels.Add(m);
        }

        if (AvailableModels.Contains(current))
        {
            SelectedModel = current;
        }
        else
        {
            SelectedModel = "All Models";
        }
    }

    private readonly HashSet<string> pendingDownloadModelIds = [];

    public async Task DownloadHfModelAsync(string modelId)
    {
        if (IsDownloadingModel) return;

        pendingDownloadModelIds.Add(modelId);
        _ = SaveSettingsAsync();

        var targetModel = HfModels.FirstOrDefault(m => m.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
        if (targetModel is not null)
        {
            targetModel.IsDownloading = true;
        }

        // Add or retrieve entry in InstalledEngines list
        var engine = InstalledEngines.FirstOrDefault(e => e.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
        if (engine is null)
        {
            var displayName = targetModel?.Name ?? (modelId.Contains('/') ? modelId.Split('/')[1] : modelId);
            var author = targetModel?.Author ?? (modelId.Contains('/') ? modelId.Split('/')[0] : "");
            var desc = !string.IsNullOrEmpty(author) 
                ? $"{author}/{displayName} • {targetModel?.LanguagesText ?? "Multilingual"}"
                : $"{displayName} • {targetModel?.LanguagesText ?? "Multilingual"}";

            engine = new InstalledModelItem
            {
                Id = modelId,
                Name = displayName,
                Description = desc,
                SupportedLanguages = targetModel?.LanguagesText ?? "Multilingual",
                IsInstalled = false,
                IsDownloading = true,
                IsPaused = false,
                DownloadStatus = $"Resuming / Connecting to Hugging Face for {modelId}..."
            };
            InstalledEngines.Add(engine);
        }
        else
        {
            engine.IsDownloading = true;
            engine.IsPaused = false;
            engine.DownloadStatus = $"Resuming / Connecting to Hugging Face for {modelId}...";
        }

        IsDownloadingModel = true;
        IsDownloadPaused = false;
        DownloadStatus = $"Resuming download for {modelId}...";
        downloadCts?.Cancel();
        downloadCts = new CancellationTokenSource();

        try
        {
            var progress = new Progress<ModelDownloadProgress>(update =>
            {
                DownloadProgress = update.Percent;
                DownloadStatus = update.Status;
                DownloadSpeed = update.Speed;
                DownloadEta = string.IsNullOrWhiteSpace(update.Eta) ? "" : $"ETA: {update.Eta}";
                DownloadSizeText = update.SizeText;

                engine.DownloadProgress = update.Percent;
                engine.DownloadStatus = update.Status;
                engine.DownloadSpeed = update.Speed;
                engine.DownloadEta = string.IsNullOrWhiteSpace(update.Eta) ? "" : $"ETA: {update.Eta}";
                engine.DownloadSize = update.SizeText;
            });

            await backend.DownloadModelAsync(modelId, progress, downloadCts.Token);

            if (targetModel is not null)
            {
                targetModel.IsInstalled = true;
                targetModel.IsDownloading = false;
            }

            engine.IsInstalled = true;
            engine.IsDownloading = false;
            engine.IsPaused = false;
            engine.DownloadSpeed = "";
            engine.DownloadEta = "";
            engine.DownloadStatus = "Download complete and model ready!";

            if (modelId.Contains("xtts", StringComparison.OrdinalIgnoreCase))
            {
                IsXttsInstalled = true;
            }

            pendingDownloadModelIds.Remove(modelId);
            _ = SaveSettingsAsync();

            IsDownloadPaused = false;
            DownloadSpeed = "";
            DownloadEta = "";
            DownloadStatus = $"{modelId} downloaded successfully!";
            Status = $"{modelId} model ready.";

            ScanInstalledEngines();
            UpdateDynamicVoices();
            UpdateAvailableModels();
            UpdateAvailableLanguages();
            UpdateStudioVoices();
            UpdateFilteredVoices();
            UpdateHfInstalledStatuses();
        }
        catch (OperationCanceledException)
        {
            if (targetModel is not null) targetModel.IsDownloading = false;
            engine.IsDownloading = false;
            engine.IsPaused = true;
            engine.DownloadSpeed = "";
            engine.DownloadEta = "";
            engine.DownloadStatus = "Download paused (resumable).";
            IsDownloadPaused = true;
            DownloadSpeed = "";
            DownloadEta = "";
            DownloadStatus = "Download paused (resumable).";
            _ = SaveSettingsAsync();
        }
        catch (Exception ex)
        {
            if (targetModel is not null) targetModel.IsDownloading = false;
            engine.IsDownloading = false;
            engine.IsPaused = true;
            engine.DownloadSpeed = "";
            engine.DownloadEta = "";
            engine.DownloadStatus = $"Download stopped: {ex.Message}";
            IsDownloadPaused = true;
            DownloadSpeed = "";
            DownloadEta = "";
            DownloadStatus = $"Download stopped: {ex.Message}";
            _ = SaveSettingsAsync();
        }
        finally
        {
            IsDownloadingModel = false;
        }
    }

    public async Task DownloadXttsModelAsync()
    {
        await DownloadHfModelAsync("coqui/XTTS-v2");
    }

    public void PauseModelDownload()
    {
        downloadCts?.Cancel();
    }

    public void PauseEngineDownload(string modelId)
    {
        downloadCts?.Cancel();
    }

    public void CancelEngineDownload(string modelId)
    {
        if (IsDownloadingModel)
        {
            downloadCts?.Cancel();
        }

        pendingDownloadModelIds.Remove(modelId);
        _ = SaveSettingsAsync();

        var engine = InstalledEngines.FirstOrDefault(e => e.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
        if (engine is not null)
        {
            engine.IsDownloading = false;
            engine.IsPaused = false;
            engine.DownloadSpeed = "";
            engine.DownloadEta = "";
            engine.DownloadStatus = "Download cancelled.";
            if (!engine.IsBundled && !engine.IsInstalled)
            {
                InstalledEngines.Remove(engine);
            }
        }

        var targetModel = HfModels.FirstOrDefault(m => m.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
        if (targetModel is not null)
        {
            targetModel.IsDownloading = false;
        }

        IsDownloadPaused = false;
        DownloadSpeed = "";
        DownloadEta = "";
        DownloadStatus = $"Download for {modelId} cancelled.";
        Status = $"Download for {modelId} cancelled.";

        ScanInstalledEngines();
        UpdateDynamicVoices();
        UpdateAvailableModels();
        UpdateAvailableLanguages();
        UpdateStudioVoices();
        UpdateFilteredVoices();
        UpdateFilteredHfModels();
    }

    public async Task DeleteModelAsync(string modelId)
    {
        if (string.IsNullOrWhiteSpace(modelId)) return;

        if (modelId.Equals("hexgrad/Kokoro-82M", StringComparison.OrdinalIgnoreCase))
        {
            Status = "Bundled default engine cannot be deleted.";
            return;
        }

        if (IsDownloadingModel)
        {
            downloadCts?.Cancel();
        }

        pendingDownloadModelIds.Remove(modelId);
        await SaveSettingsAsync();

        var modelsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Atten", "Models");

        try
        {
            if (Directory.Exists(modelsDir))
            {
                if (modelId.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase) || modelId.Equals("XTTS-v2", StringComparison.OrdinalIgnoreCase))
                {
                    var xttsDir = Path.Combine(modelsDir, "XTTS-v2");
                    if (Directory.Exists(xttsDir))
                    {
                        Directory.Delete(xttsDir, recursive: true);
                    }
                    IsXttsInstalled = false;
                }
                else
                {
                    var folderName = modelId.Replace("/", "--");
                    var targetDir = Path.Combine(modelsDir, folderName);
                    if (Directory.Exists(targetDir))
                    {
                        Directory.Delete(targetDir, recursive: true);
                    }
                    else
                    {
                        var directDir = Path.Combine(modelsDir, modelId);
                        if (Directory.Exists(directDir))
                        {
                            Directory.Delete(directDir, recursive: true);
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Status = $"Failed to delete model {modelId}: {ex.Message}";
        }

        var engine = InstalledEngines.FirstOrDefault(e => e.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
        if (engine is not null)
        {
            engine.IsInstalled = false;
            engine.IsDownloading = false;
            engine.DownloadProgress = 0;
            engine.DownloadStatus = "";
            if (!engine.IsBundled && !engine.Id.Equals("coqui/XTTS-v2", StringComparison.OrdinalIgnoreCase))
            {
                InstalledEngines.Remove(engine);
            }
        }

        var hf = HfModels.FirstOrDefault(m => m.Id.Equals(modelId, StringComparison.OrdinalIgnoreCase));
        if (hf is not null)
        {
            hf.IsInstalled = false;
            hf.IsDownloading = false;
        }

        ScanInstalledEngines();
        UpdateDynamicVoices();
        UpdateAvailableModels();
        UpdateAvailableLanguages();
        UpdateStudioVoices();
        UpdateFilteredVoices();
        UpdateFilteredHfModels();

        Status = $"Model {modelId} deleted successfully and disk space freed.";
    }

    public async Task StartAsync()
    {
        InitializeInstalledEngines();
        UpdateAvailableLanguages();
        UpdateStudioVoices();
        UpdateFilteredVoices();

        storage.Prepare();
        var cachedSizes = await storage.LoadModelSizesCacheAsync();
        foreach (var (k, v) in cachedSizes)
        {
            ManifestSizeCache[k] = v;
        }

        var settings = await storage.LoadSettingsAsync();
        OutputDirectory = settings.OutputDirectory;
        Format = settings.DefaultFormat;
        Speed = settings.DefaultSpeed;
        SelectedVoiceID = settings.SelectedVoiceID;
        DeviceMode = settings.DeviceMode;

        pendingDownloadModelIds.Clear();
        foreach (var id in settings.PendingDownloadModelIds)
        {
            pendingDownloadModelIds.Add(id);
        }

        Projects.Clear();
        foreach (var project in (await storage.LoadProjectsAsync()).OrderByDescending(project => project.UpdatedAt))
        {
            Projects.Add(project);
        }

        try
        {
            BackendInfo = await backend.GetInfoAsync(DeviceMode, CancellationToken.None);
            Status = $"Backend ready on {BackendInfo.SelectedDevice}. ({Voices.Count} voices available across {AvailableLanguages.Count - 1} languages)";
        }
        catch (Exception error)
        {
            Status = error.Message;
        }

        _ = FetchHfModelsAsync();

        // Automatically resume any downloads that were in progress when the app was closed
        if (pendingDownloadModelIds.Count > 0)
        {
            var toResume = pendingDownloadModelIds.ToList();
            foreach (var pendingId in toResume)
            {
                if (pendingId.Contains("xtts", StringComparison.OrdinalIgnoreCase) && (BackendInfo?.XttsInstalled == true || IsXttsInstalled))
                {
                    pendingDownloadModelIds.Remove(pendingId);
                    continue;
                }

                _ = DownloadHfModelAsync(pendingId);
            }
            _ = SaveSettingsAsync();
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
            DeviceMode = DeviceMode,
            PendingDownloadModelIds = pendingDownloadModelIds
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

        var voice = VoiceCatalog.ById(SelectedVoiceID);
        generationCts?.Cancel();
        generationCts = new CancellationTokenSource();
        IsGenerating = true;
        Status = $"Generating speech with {voice.Name}...";

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
            PlayerTitle = $"{title}.{Format}";
            IsPlayerVisible = true;
            Status = $"Speech ready! Saved to {Path.GetFileName(output.Path)}";
        }
        catch (OperationCanceledException)
        {
            Status = "Generation cancelled.";
        }
        catch (Exception error)
        {
            Status = $"Error: {error.Message}";
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

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        return true;
    }
}
