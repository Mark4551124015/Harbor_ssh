using System.ComponentModel;
using System.Diagnostics;
using Harbor.Core;

namespace Harbor.Desktop;

internal static class WindowsIntegration
{
    public static string SshDirectory { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ssh");

    public static string FindOpenSsh(string name)
    {
        var system = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "OpenSSH", name);
        if (File.Exists(system)) return system;
        foreach (var entry in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            try
            {
                var candidate = Path.Combine(entry.Trim('"'), name);
                if (Path.IsPathFullyQualified(candidate) && File.Exists(candidate)) return candidate;
            }
            catch (ArgumentException) { }
        }
        throw new FileNotFoundException($"{name} was not found. Install OpenSSH Client from Windows Settings → Optional features.");
    }

    public static void LaunchTerminal(string executable, IReadOnlyList<string> arguments, bool preferTerminal)
    {
        var terminal = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "wt.exe");
        // Terminal treats semicolons as command separators, even in some quoted arguments.
        if (preferTerminal && File.Exists(terminal) && !arguments.Any(a => a.Contains(';')))
        {
            try
            {
                using var launched = Process.Start(SshCommands.StartInfo(terminal,
                    new[] { "-w", "new", "new-tab", "--" , executable }.Concat(arguments), capture: false));
                return;
            }
            catch (Win32Exception) { /* Fall back to the native console host. */ }
        }
        using var console = Process.Start(SshCommands.StartInfo(executable, arguments, capture: false));
    }

    public static void OpenConfig(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (!File.Exists(path)) File.WriteAllText(path, "");
        using var editor = Process.Start(SshCommands.StartInfo(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "notepad.exe"), [path], capture: false));
    }

    public static void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        using var explorer = Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    public static void RevealFile(string path)
    {
        var fullPath = Path.GetFullPath(path);
        if (!File.Exists(fullPath)) { OpenFolder(Path.GetDirectoryName(fullPath)!); return; }
        var explorer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
        using var process = Process.Start(SshCommands.StartInfo(explorer, ["/select,", fullPath], capture: false));
    }
}
