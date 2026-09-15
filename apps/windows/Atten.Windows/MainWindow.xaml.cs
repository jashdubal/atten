using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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

    public MainWindow()
    {
        InitializeComponent();
        Root.DataContext = model;
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
            PlayCurrentOutput();
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

    private void OnRevealClicked(object sender, RoutedEventArgs args)
    {
        if (string.IsNullOrWhiteSpace(model.CurrentAudioPath) || !File.Exists(model.CurrentAudioPath))
        {
            model.Status = "No generated audio is available to reveal.";
            return;
        }

        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = $"/select,\"{model.CurrentAudioPath}\"",
            UseShellExecute = true
        });
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
            player ??= new MediaPlayer();
            player.Source = MediaSource.CreateFromUri(new Uri(model.CurrentAudioPath));
            player.Play();
        }
        catch (Exception error)
        {
            Diagnostics.Log($"Playback failed: {error}");
            model.Status = "Windows could not play this audio file on this system.";
        }
    }
}
