using System.Collections.Concurrent;
using System.Diagnostics;

namespace Harbor.Core;

public sealed class ForwardSession(ForwardRule rule, Process process)
{
    internal string? DefaultsFile { get; set; }
    public ForwardRule Rule { get; } = rule;
    internal Process Process { get; } = process;
    public int ProcessId { get; } = process.Id;
    public DateTimeOffset StartedAt { get; } = DateTimeOffset.Now;
    public string Status { get; internal set; } = "SSH process active";
    public string Error { get; internal set; } = "";
    public bool Active { get; internal set; } = true;
    internal bool StopRequested { get; set; }
}

public sealed class SshProcessManager(string sshExecutable, string configPath, Func<(int Timeout, int KeepAlive)>? connectionDefaults = null, Func<string, Task<string?>>? proxyCommand = null) : IDisposable
{
    private readonly ConcurrentDictionary<Guid, ForwardSession> sessions = new();
    private readonly SemaphoreSlim gate = new(1, 1);
    private bool disposed;
    public event Action? Changed;
    public IReadOnlyList<ForwardSession> Sessions => sessions.Values.OrderByDescending(s => s.StartedAt).ToList();

    public async Task StartAsync(ForwardRule rule)
    {
        await gate.WaitAsync();
        string? defaultsFile = null;
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (sessions.TryGetValue(rule.Id, out var existing) && existing.Active) return;
            var effectivePath = configPath;
            if (connectionDefaults is not null)
            {
                var defaults = connectionDefaults();
                defaultsFile = Path.Combine(Path.GetTempPath(), $"harbor-ssh-defaults-{Guid.NewGuid():N}.config");
                var include = Path.GetFullPath(configPath).Replace('\\', '/');
                if (include.Any(c => char.IsControl(c) || c == '"')) throw new IOException("Invalid SSH configuration path.");
                // First values win: host-specific and included options precede Harbor's defaults.
                await File.WriteAllTextAsync(defaultsFile, $"Include \"{include}\"\nHost *\n ConnectTimeout {defaults.Timeout}\n ServerAliveInterval {defaults.KeepAlive}\n ServerAliveCountMax 3\n");
                effectivePath = defaultsFile;
            }
            var arguments = SshCommands.Forward(effectivePath, rule).ToList();
            if (proxyCommand is not null && await proxyCommand(rule.HostAlias) is string proxy)
                arguments.InsertRange(0, ["-o", $"ProxyCommand={proxy}"]);
            if (connectionDefaults is not null)
                for (var i = arguments.Count - 1; i > 0; i--)
                    if (arguments[i] is "ConnectTimeout=15" or "ServerAliveInterval=30" or "ServerAliveCountMax=3") { arguments.RemoveAt(i); arguments.RemoveAt(i - 1); i--; }
            var effective = await ProcessRunner.CaptureAsync(sshExecutable, new[] { "-G" }.Concat(arguments), TimeSpan.FromSeconds(15));
            if (effective.ExitCode != 0) throw new IOException(effective.Error.Trim());
            var forwardCount = effective.Output.Split('\n').Count(line =>
                line.StartsWith("localforward ", StringComparison.Ordinal) ||
                line.StartsWith("remoteforward ", StringComparison.Ordinal) ||
                line.StartsWith("dynamicforward ", StringComparison.Ordinal));
            if (forwardCount != 1)
                throw new InvalidOperationException("This host inherits additional forwards from SSH config. Remove those directives or use Connect in Servers to run the configured forwards together.");
            ObjectDisposedException.ThrowIf(disposed, this);
            var process = new Process { StartInfo = SshCommands.StartInfo(sshExecutable, arguments) };
            if (!process.Start()) throw new IOException("Could not start OpenSSH.");
            process.StandardInput.Close();
            var session = new ForwardSession(rule, process) { DefaultsFile = defaultsFile };
            defaultsFile = null;
            sessions[rule.Id] = session;
            _ = ObserveAsync(session);
            Changed?.Invoke();
        }
        finally
        {
            try { if (defaultsFile is not null) File.Delete(defaultsFile); }
            finally { gate.Release(); }
        }
    }

    private async Task ObserveAsync(ForwardSession session)
    {
        var error = new System.Text.StringBuilder();
        try
        {
            var output = session.Process.StandardOutput.BaseStream.CopyToAsync(Stream.Null);
            // Bound diagnostics while draining continuously so an SSH process never blocks on a full pipe.
            var buffer = new char[1024];
            int count;
            while ((count = await session.Process.StandardError.ReadAsync(buffer)) > 0)
            {
                error.Append(buffer, 0, count);
                if (error.Length > 8192) error.Remove(0, error.Length - 8192);
            }
            await session.Process.WaitForExitAsync();
            await output;
            session.Error = error.ToString().Trim();
            session.Status = session.StopRequested ? "Stopped" :
                session.Process.ExitCode == 0 ? "Finished" : $"Exited ({session.Process.ExitCode})";
        }
        catch (Exception exception) when (exception is IOException or InvalidOperationException or ObjectDisposedException)
        {
            session.Error = exception.Message;
            session.Status = "Stopped";
        }
        finally
        {
            session.Active = false;
            session.Process.Dispose();
            if (session.DefaultsFile is not null)
                try { File.Delete(session.DefaultsFile); } catch (IOException) { }
            Changed?.Invoke();
        }
    }

    public void Stop(Guid id)
    {
        if (!sessions.TryGetValue(id, out var session) || !session.Active) return;
        session.StopRequested = true;
        try { session.Process.Kill(entireProcessTree: true); }
        catch (InvalidOperationException) { }
    }

    public async Task StopAsync(Guid id)
    {
        if (!sessions.TryGetValue(id, out var session) || !session.Active) return;
        Stop(id);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (session.Active) await Task.Delay(10, timeout.Token);
    }

    public void Dispose()
    {
        disposed = true;
        foreach (var session in Sessions) Stop(session.Rule.Id);
    }
}
