using Microsoft.UI.Xaml;

namespace Atten.Windows;

public partial class App : Application
{
    private Window? window;

    public App()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            Diagnostics.Fatal("runtime", args.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, args) =>
            Diagnostics.Log($"Unobserved task exception: {args.Exception}");

        InitializeComponent();
        UnhandledException += (_, args) =>
        {
            args.Handled = true;
            Diagnostics.Fatal("xaml", args.Exception);
            Environment.Exit(1);
        };
        Diagnostics.Log("Application initialized.");
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var commandLine = Environment.GetCommandLineArgs();
        if (commandLine.Contains("--validate-install", StringComparer.OrdinalIgnoreCase))
        {
            _ = ValidateInstallationAsync();
            return;
        }

        var isProbe = commandLine.Contains("--validate-launch", StringComparer.OrdinalIgnoreCase);
        Diagnostics.Log(isProbe ? "Creating the main window for a launch probe." : "Creating the main window.");
        window = new MainWindow();
        window.Activate();
        Diagnostics.Log("Main window activated.");

        if (isProbe)
        {
            ExitAfterFirstFrame(window);
        }
    }

    // The launch probe proves that XAML, the Windows App SDK, and the window's
    // own startup work on a clean machine. It runs in the release build and in
    // CI, because a crash while the first window is built is invisible to a
    // user: the process simply disappears with no window and no message.
    private static void ExitAfterFirstFrame(Window probeWindow)
    {
        var timer = probeWindow.DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromSeconds(3);
        timer.IsRepeating = false;
        timer.Tick += (_, _) =>
        {
            Diagnostics.Log("Launch probe succeeded.");
            Environment.Exit(0);
        };
        timer.Start();
    }

    // The release build invokes this mode from the staged publish directory.
    // It proves that WinUI can initialize without a separately installed
    // Windows App SDK and that the bundled backend, model, and voice catalog
    // are all reachable before an installer is published.
    private static async Task ValidateInstallationAsync()
    {
        var errorPath = Path.Combine(AppContext.BaseDirectory, "install-validation-error.txt");
        try
        {
            if (File.Exists(errorPath))
            {
                File.Delete(errorPath);
            }

            _ = VoiceCatalog.All.Count;
            var info = await new BackendClient().GetInfoAsync(DeviceMode.cpu, CancellationToken.None);
            if (!info.ModelRootValid)
            {
                throw new InvalidOperationException("The bundled Kokoro model failed validation.");
            }

            Environment.Exit(0);
        }
        catch (Exception error)
        {
            Diagnostics.Log($"Installation validation failed: {error}");
            try { File.WriteAllText(errorPath, error.ToString()); } catch { }
            Environment.Exit(1);
        }
    }
}
