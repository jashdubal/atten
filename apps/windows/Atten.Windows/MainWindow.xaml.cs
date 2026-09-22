using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.UI.ViewManagement;

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
    private readonly AccessibilitySettings accessibilitySettings = new();
    private readonly UISettings uiSettings = new();
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
        Root.ActualThemeChanged += OnActualThemeChanged;
        accessibilitySettings.HighContrastChanged += OnHighContrastChanged;

        // A minimum effective size keeps the two supported Studio panes
        // usable when Windows is scaled to 150% or 200%. The app remains
        // resizable above this floor and all long pages scroll vertically.
        if (AppWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = 920;
            presenter.PreferredMinimumHeight = 640;
        }

        var iconPath = Path.Combine(AppContext.BaseDirectory, "AttenIcon.ico");
        if (File.Exists(iconPath))
        {
            AppWindow.SetIcon(iconPath);
        }

        ApplyTitleBarAppearance();

        // WinUI controls already follow the system's animation preference.
        // The app-owned indeterminate indicator is the one continuous motion
        // we control, so make it static when Reduce Motion is enabled.
        GeneratingProgress.IsIndeterminate = uiSettings.AnimationsEnabled;

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
        UpdateScreenHeader(tag);
    }

    private void UpdateScreenHeader(string tag)
    {
        (ScreenTitle.Text, ScreenSubtitle.Text) = tag switch
        {
            "Studio" => ("Studio", "Create speech locally"),
            "Playground" => ("Playground", "Experiment with installed voices"),
            "Voices" => ("Voices", "Browse supported local voices and languages"),
            "Projects" => ("Projects", "Previously generated speech"),
            "Exports" => ("Exports", "Find generated audio in the export folder"),
            "Settings" => ("Settings & Models", "Local storage and speech engines"),
            _ => ("Atten", "Offline text to speech")
        };
    }

    private void OnActualThemeChanged(FrameworkElement sender, object args) => ApplyTitleBarAppearance();

    private void OnHighContrastChanged(AccessibilitySettings sender, object args) => ApplyTitleBarAppearance();

    private void ApplyTitleBarAppearance()
    {
        if (!Microsoft.UI.Windowing.AppWindowTitleBar.IsCustomizationSupported())
        {
            return;
        }

        var titleBar = AppWindow.TitleBar;
        if (accessibilitySettings.HighContrast)
        {
            // System caption colours are part of a user's high-contrast
            // contract. Returning control to Windows is safer than painting
            // an app palette over those settings.
            titleBar.BackgroundColor = null;
            titleBar.ForegroundColor = null;
            titleBar.InactiveBackgroundColor = null;
            titleBar.InactiveForegroundColor = null;
            titleBar.ButtonBackgroundColor = null;
            titleBar.ButtonForegroundColor = null;
            titleBar.ButtonHoverBackgroundColor = null;
            titleBar.ButtonHoverForegroundColor = null;
            titleBar.ButtonPressedBackgroundColor = null;
            titleBar.ButtonPressedForegroundColor = null;
            titleBar.ButtonInactiveBackgroundColor = null;
            titleBar.ButtonInactiveForegroundColor = null;
            return;
        }

        var dark = Root.ActualTheme == ElementTheme.Dark;
        var background = dark
            ? global::Windows.UI.Color.FromArgb(255, 6, 8, 12)
            : global::Windows.UI.Color.FromArgb(255, 247, 248, 250);
        var inactiveBackground = dark
            ? global::Windows.UI.Color.FromArgb(255, 11, 15, 22)
            : global::Windows.UI.Color.FromArgb(255, 237, 240, 245);
        var foreground = dark
            ? global::Windows.UI.Color.FromArgb(255, 231, 238, 248)
            : global::Windows.UI.Color.FromArgb(255, 11, 18, 28);
        var inactiveForeground = dark
            ? global::Windows.UI.Color.FromArgb(255, 143, 162, 186)
            : global::Windows.UI.Color.FromArgb(255, 85, 99, 122);
        var hover = dark
            ? global::Windows.UI.Color.FromArgb(255, 31, 39, 52)
            : global::Windows.UI.Color.FromArgb(255, 208, 216, 227);

        titleBar.BackgroundColor = background;
        titleBar.ForegroundColor = foreground;
        titleBar.InactiveBackgroundColor = inactiveBackground;
        titleBar.InactiveForegroundColor = inactiveForeground;
        titleBar.ButtonBackgroundColor = global::Windows.UI.Color.FromArgb(0, 0, 0, 0);
        titleBar.ButtonForegroundColor = foreground;
        titleBar.ButtonHoverBackgroundColor = hover;
        titleBar.ButtonHoverForegroundColor = foreground;
        titleBar.ButtonPressedBackgroundColor = hover;
        titleBar.ButtonPressedForegroundColor = foreground;
        titleBar.ButtonInactiveBackgroundColor = global::Windows.UI.Color.FromArgb(0, 0, 0, 0);
        titleBar.ButtonInactiveForegroundColor = inactiveForeground;
    }

    private void OnGenerateKeyboardAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        if (GenerateButton.IsEnabled)
        {
            OnGenerateClicked(GenerateButton, new RoutedEventArgs());
            args.Handled = true;
        }
    }

    private void OnCancelKeyboardAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        if (model.IsGenerating)
        {
            OnCancelClicked(sender, new RoutedEventArgs());
            args.Handled = true;
        }
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
