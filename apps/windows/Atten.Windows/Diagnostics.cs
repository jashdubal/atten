using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Atten.Windows;

// Atten is a windowed application, so a failure before the first frame is
// otherwise completely silent: no console, no dialog, no trace. Every launch
// writes a breadcrumb here so a failure that happens before managed code runs
// (a missing Visual C++ runtime, for example) can be told apart from a crash
// inside the app by whether the log exists at all.
public static class Diagnostics
{
    public static string LogPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Atten",
        "logs",
        "startup.log");

    [ModuleInitializer]
    internal static void RecordProcessStart()
    {
        Log($"Process started. Base directory: {AppContext.BaseDirectory}");
    }

    public static void Log(string message)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostics must never be the reason a launch fails.
        }
    }

    public static void Fatal(string phase, Exception? error)
    {
        Log($"FATAL ({phase}): {error}");

        // A modal dialog would hang forever during an automated check, where
        // there is nobody to dismiss it. The log is the report in that case.
        if (IsAutomatedCheck())
        {
            return;
        }

        MessageBox(
            IntPtr.Zero,
            $"Atten could not start.\n\n{error?.Message}\n\nDetails were written to:\n{LogPath}",
            "Atten",
            0x00000010 /* MB_ICONERROR */);
    }

    public static bool IsAutomatedCheck()
    {
        return Environment.GetCommandLineArgs().Any(argument =>
            argument.Equals("--validate-launch", StringComparison.OrdinalIgnoreCase) ||
            argument.Equals("--validate-install", StringComparison.OrdinalIgnoreCase));
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
    private static extern int MessageBox(IntPtr window, string text, string caption, uint type);
}
