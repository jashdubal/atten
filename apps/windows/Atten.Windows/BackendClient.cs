using System.Diagnostics;
using System.Text.Json;

namespace Atten.Windows;

public sealed class BackendClient
{
    private readonly JsonSerializerOptions options = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<BackendInfo> GetInfoAsync(DeviceMode deviceMode, CancellationToken cancellationToken)
    {
        var command = LocateCommand();
        var result = await RunAsync(
            command,
            ["--backend-info", "--device", deviceMode.ToString(), "--json"],
            cancellationToken);

        foreach (var line in result.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            using var document = JsonDocument.Parse(line);
            if (document.RootElement.GetProperty("event").GetString() == "backend_info")
            {
                return JsonSerializer.Deserialize<BackendInfo>(line, options)
                    ?? throw new InvalidOperationException("Backend info was unreadable.");
            }
        }

        throw new InvalidOperationException("Backend did not return backend_info.");
    }

    public async Task<GenerationOutput> GenerateAsync(
        string text,
        string voiceId,
        double speed,
        AudioFormat format,
        string outputDirectory,
        string filename,
        DeviceMode deviceMode,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(outputDirectory);
        var input = Path.Combine(Path.GetTempPath(), $"atten-input-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(input, text, cancellationToken);

        try
        {
            var command = LocateCommand();
            var result = await RunAsync(
                command,
                [
                    "--source", input,
                    "--voice", voiceId,
                    "--speed", speed.ToString("0.###"),
                    "--format", format.ToString(),
                    "--output", outputDirectory,
                    "--filename", filename,
                    "--device", deviceMode.ToString(),
                    "--json"
                ],
                cancellationToken);

            string? completedPath = null;
            var segments = 0;
            var sampleRate = 24000;
            foreach (var line in result.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.GetProperty("event").GetString() == "completed")
                {
                    completedPath = root.GetProperty("path").GetString();
                    if (root.TryGetProperty("segments", out var segmentValue))
                    {
                        segments = segmentValue.GetInt32();
                    }
                    if (root.TryGetProperty("sample_rate", out var rateValue))
                    {
                        sampleRate = rateValue.GetInt32();
                    }
                }
            }

            return completedPath is null
                ? throw new InvalidOperationException("Backend did not return a completed event.")
                : new GenerationOutput(completedPath, segments, sampleRate);
        }
        finally
        {
            try { File.Delete(input); } catch { }
        }
    }

    private static BackendCommand LocateCommand()
    {
        var packaged = Path.Combine(
            AppContext.BaseDirectory,
            "Backend",
            "atten-backend",
            "atten-backend.exe");
        if (File.Exists(packaged))
        {
            return new BackendCommand(packaged, []);
        }

        var root = Environment.GetEnvironmentVariable("ATTEN_BACKEND_ROOT")
            ?? FindRepositoryRoot(Directory.GetCurrentDirectory());
        if (root is not null && File.Exists(Path.Combine(root, "cli.py")))
        {
            return new BackendCommand("python", [Path.Combine(root, "cli.py")])
            {
                WorkingDirectory = root
            };
        }

        throw new FileNotFoundException("Atten could not find its bundled speech engine or development backend.");
    }

    private static string? FindRepositoryRoot(string start)
    {
        var directory = new DirectoryInfo(start);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "cli.py")))
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }
        return null;
    }

    private static async Task<string> RunAsync(
        BackendCommand command,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        using var process = new Process();
        process.StartInfo.FileName = command.Executable;
        process.StartInfo.WorkingDirectory = command.WorkingDirectory ?? AppContext.BaseDirectory;
        process.StartInfo.RedirectStandardOutput = true;
        process.StartInfo.RedirectStandardError = true;
        process.StartInfo.UseShellExecute = false;
        process.StartInfo.CreateNoWindow = true;
        var modelRoot = Path.Combine(AppContext.BaseDirectory, "Models", "Kokoro-82M");
        if (Directory.Exists(modelRoot))
        {
            process.StartInfo.Environment["ATTEN_MODEL_ROOT"] = modelRoot;
            process.StartInfo.Environment["HF_HUB_OFFLINE"] = "1";
            process.StartInfo.Environment["PYTHONNOUSERSITE"] = "1";
            process.StartInfo.Environment["PYTHONDONTWRITEBYTECODE"] = "1";
        }

        foreach (var argument in command.Arguments.Concat(arguments))
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        process.Start();
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var output = await outputTask;
        var error = await errorTask;

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? output : error);
        }
        return output;
    }

    private sealed record BackendCommand(string Executable, IReadOnlyList<string> Arguments)
    {
        public string? WorkingDirectory { get; init; }
    }
}
