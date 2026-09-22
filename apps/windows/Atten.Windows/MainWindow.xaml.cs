using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Windows.Media.Core;
using Windows.Media.Playback;

namespace Atten.Windows;

public sealed partial class MainWindow : Window
{
    private readonly MainViewModel model = new();
    // Windows N and KN editions have no media stack until the Media Feature
    // Pack is installed, and constructing a MediaPlayer there throws. Creating
    // it on first playback keeps that failure out of the window's constructor,
    // where it would take the whole app down before anything is shown.
    private MediaPlayer? player;
    private readonly DispatcherTimer playbackTimer = new();
    private bool isUserSeeking;

    /// The player, made on first use. Everything the window listens to it for
    /// is wired here rather than in the constructor, because until this is
    /// called there is nothing to listen to.
    private MediaPlayer Player
    {
        get
        {
            if (player is null)
            {
                player = new MediaPlayer();
                player.PlaybackSession.PlaybackStateChanged += OnPlaybackStateChanged;
                player.MediaEnded += OnMediaEnded;
            }
            return player;
        }
    }

    public MainWindow()
    {
        InitializeComponent();
        Root.DataContext = model;

        Title = "Atten";

        var iconPath = Path.Combine(AppContext.BaseDirectory, "AttenIcon.ico");
        if (File.Exists(iconPath))
        {
            AppWindow.SetIcon(iconPath);
        }

        if (Microsoft.UI.Windowing.AppWindowTitleBar.IsCustomizationSupported())
        {
            var titleBar = AppWindow.TitleBar;
            titleBar.BackgroundColor = global::Windows.UI.Color.FromArgb(255, 15, 17, 23);
            titleBar.ForegroundColor = global::Windows.UI.Color.FromArgb(255, 231, 238, 248);
            titleBar.InactiveBackgroundColor = global::Windows.UI.Color.FromArgb(255, 12, 14, 18);
            titleBar.InactiveForegroundColor = global::Windows.UI.Color.FromArgb(255, 120, 130, 145);
            titleBar.ButtonBackgroundColor = global::Windows.UI.Color.FromArgb(0, 0, 0, 0);
            titleBar.ButtonForegroundColor = global::Windows.UI.Color.FromArgb(255, 231, 238, 248);
            titleBar.ButtonHoverBackgroundColor = global::Windows.UI.Color.FromArgb(255, 30, 36, 48);
            titleBar.ButtonHoverForegroundColor = global::Windows.UI.Color.FromArgb(255, 255, 255, 255);
            titleBar.ButtonPressedBackgroundColor = global::Windows.UI.Color.FromArgb(255, 45, 55, 75);
            titleBar.ButtonPressedForegroundColor = global::Windows.UI.Color.FromArgb(255, 255, 255, 255);
            titleBar.ButtonInactiveBackgroundColor = global::Windows.UI.Color.FromArgb(0, 0, 0, 0);
            titleBar.ButtonInactiveForegroundColor = global::Windows.UI.Color.FromArgb(255, 120, 130, 145);
        }

        playbackTimer.Interval = TimeSpan.FromMilliseconds(200);
        playbackTimer.Tick += OnPlaybackTimerTick;
        playbackTimer.Start();

        _ = StartModelAsync();
    }

    private async Task StartModelAsync()
    {
        try
        {
            await model.StartAsync();
        }
        catch (Exception error)
        {
            Diagnostics.Log($"Model startup failed: {error}");
            model.Status = error.Message;
        }
    }

    private void OnNavigationSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem item || item.Tag is not string tag)
        {
            return;
        }

        // Selection can be raised while the window's content is still being
        // built, before the named panels below have been assigned.
        if (StudioPanel is null)
        {
            return;
        }

        StudioPanel.Visibility = tag == "Studio" ? Visibility.Visible : Visibility.Collapsed;
        PlaygroundPanel.Visibility = tag == "Playground" ? Visibility.Visible : Visibility.Collapsed;
        VoicesPanel.Visibility = tag == "Voices" ? Visibility.Visible : Visibility.Collapsed;
        ProjectsPanel.Visibility = tag == "Projects" ? Visibility.Visible : Visibility.Collapsed;
        ExportsPanel.Visibility = tag == "Exports" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = tag == "Settings" ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnGenerateClicked(object sender, RoutedEventArgs args)
    {
        GenerateButton.IsEnabled = false;
        try
        {
            await model.GenerateAsync();
            if (!string.IsNullOrWhiteSpace(model.CurrentAudioPath) && File.Exists(model.CurrentAudioPath))
            {
                PlayCurrentOutput();
            }
        }
        finally
        {
            GenerateButton.IsEnabled = true;
        }
    }

    private void OnCancelClicked(object sender, RoutedEventArgs args)
    {
        model.CancelGeneration();
    }

    private void OnPlayClicked(object sender, RoutedEventArgs args)
    {
        PlayCurrentOutput();
    }

    private void OnTogglePlayPauseClicked(object sender, RoutedEventArgs args)
    {
        if (string.IsNullOrWhiteSpace(model.CurrentAudioPath) || !File.Exists(model.CurrentAudioPath))
        {
            return;
        }

        if (Player.PlaybackSession.PlaybackState == MediaPlaybackState.Playing)
        {
            Player.Pause();
            model.IsPlaying = false;
        }
        else
        {
            if (Player.Source is null)
            {
                Player.Source = MediaSource.CreateFromUri(new Uri(model.CurrentAudioPath));
            }
            Player.Play();
            model.IsPlaying = true;
        }
    }

    private void OnPlayerSeekValueChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        // Not through `Player`: dragging a scrubber that has never played
        // anything is no reason to go looking for a media stack.
        if (isUserSeeking && player is { } playing && playing.PlaybackSession.CanSeek)
        {
            playing.PlaybackSession.Position = TimeSpan.FromSeconds(args.NewValue);
        }
    }

    private void OnPlayerSeekPointerEntered(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        isUserSeeking = true;
    }

    private void OnPlayerSeekPointerCaptureLost(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        isUserSeeking = false;
    }

    private void OnClosePlayerClicked(object sender, RoutedEventArgs args)
    {
        player?.Pause();
        model.IsPlaying = false;
        model.IsPlayerVisible = false;
    }

    private void OnRevealClicked(object sender, RoutedEventArgs args)
    {
        if (string.IsNullOrWhiteSpace(model.CurrentAudioPath) || !File.Exists(model.CurrentAudioPath))
        {
            model.Status = "No generated audio is available to reveal.";
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = $"/select,\"{model.CurrentAudioPath}\"",
            UseShellExecute = true
        });
    }

    private void OnPlaybackStateChanged(MediaPlaybackSession sender, object args)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            model.IsPlaying = sender.PlaybackState == MediaPlaybackState.Playing;
        });
    }

    private void OnMediaEnded(MediaPlayer sender, object args)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            model.IsPlaying = false;
            model.PlayerPosition = 0;
            model.PlayerTimeText = $"00:00 / {FormatTime(sender.PlaybackSession.NaturalDuration.TotalSeconds)}";
        });
    }

    private void OnPlaybackTimerTick(object? sender, object e)
    {
        // The timer runs from the moment the window opens, long before there
        // is a player, so this is the one place that must never make one.
        if (player is not { } playing || playing.Source is null) return;

        var session = playing.PlaybackSession;
        var duration = session.NaturalDuration.TotalSeconds;
        var position = session.Position.TotalSeconds;

        if (duration > 0)
        {
            model.PlayerDuration = duration;
            if (!isUserSeeking)
            {
                model.PlayerPosition = position;
            }
            model.PlayerTimeText = $"{FormatTime(position)} / {FormatTime(duration)}";
        }
    }

    private static string FormatTime(double totalSeconds)
    {
        if (double.IsNaN(totalSeconds) || totalSeconds < 0) totalSeconds = 0;
        var ts = TimeSpan.FromSeconds(totalSeconds);
        return ts.Hours > 0 ? $"{ts.Hours:D2}:{ts.Minutes:D2}:{ts.Seconds:D2}" : $"{ts.Minutes:D2}:{ts.Seconds:D2}";
    }

    private async void OnDownloadInstalledEngineClicked(object sender, RoutedEventArgs args)
    {
        if (sender is Button btn && btn.Tag is string modelId && !string.IsNullOrWhiteSpace(modelId))
        {
            await model.DownloadHfModelAsync(modelId);
        }
    }

    private async void OnDownloadXttsClicked(object sender, RoutedEventArgs args)
    {
        await model.DownloadXttsModelAsync();
    }

    private void OnPauseEngineClicked(object sender, RoutedEventArgs args)
    {
        if (sender is Button btn && btn.Tag is string modelId && !string.IsNullOrWhiteSpace(modelId))
        {
            model.PauseEngineDownload(modelId);
        }
        else
        {
            model.PauseModelDownload();
        }
    }

    private void OnCancelEngineClicked(object sender, RoutedEventArgs args)
    {
        if (sender is Button btn && btn.Tag is string modelId && !string.IsNullOrWhiteSpace(modelId))
        {
            model.CancelEngineDownload(modelId);
        }
    }

    private void OnPauseXttsClicked(object sender, RoutedEventArgs args)
    {
        if (model.IsDownloadingModel)
        {
            model.PauseModelDownload();
        }
        else
        {
            _ = model.DownloadXttsModelAsync();
        }
    }

    private async void OnDownloadHfModelClicked(object sender, RoutedEventArgs args)
    {
        if (sender is Button btn && btn.Tag is string modelId)
        {
            await model.DownloadHfModelAsync(modelId);
        }
    }

    private async void OnDeleteEngineClicked(object sender, RoutedEventArgs args)
    {
        if (sender is Button btn && btn.Tag is string modelId && !string.IsNullOrWhiteSpace(modelId))
        {
            await model.DeleteModelAsync(modelId);
        }
    }

    private async void OnDeleteHfModelClicked(object sender, RoutedEventArgs args)
    {
        if (sender is Button btn && btn.Tag is string modelId && !string.IsNullOrWhiteSpace(modelId))
        {
            await model.DeleteModelAsync(modelId);
        }
    }

    private async void OnRefreshHfModelsClicked(object sender, RoutedEventArgs args)
    {
        await model.FetchHfModelsAsync();
    }

    private void OnUseVoiceClicked(object sender, RoutedEventArgs args)
    {
        if (sender is Button btn && btn.Tag is string voiceId && !string.IsNullOrWhiteSpace(voiceId))
        {
            var voice = VoiceCatalog.ById(voiceId);
            model.SelectVoice(voice);

            // Switch UI navigation to Studio panel
            Navigation.SelectedItem = Navigation.MenuItems[0];
            StudioPanel.Visibility = Visibility.Visible;
            PlaygroundPanel.Visibility = Visibility.Collapsed;
            VoicesPanel.Visibility = Visibility.Collapsed;
            ProjectsPanel.Visibility = Visibility.Collapsed;
            ExportsPanel.Visibility = Visibility.Collapsed;
            SettingsPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void PlayCurrentOutput()
    {
        if (string.IsNullOrWhiteSpace(model.CurrentAudioPath) || !File.Exists(model.CurrentAudioPath))
        {
            model.Status = "No generated audio is available to play.";
            return;
        }

        try
        {
            Player.Source = MediaSource.CreateFromUri(new Uri(model.CurrentAudioPath));
            Player.Play();
            model.IsPlaying = true;
            model.IsPlayerVisible = true;
        }
        catch (Exception error)
        {
            Diagnostics.Log($"Playback failed: {error}");
            model.Status = "Windows could not play this audio file on this system.";
        }
    }
}
