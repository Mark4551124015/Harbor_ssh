using System.Diagnostics;

namespace Harbor.Desktop;

internal sealed record ObservedSshProcess(int ProcessId, DateTimeOffset? StartedAt, string Executable, string Name, string Endpoints, string Listeners);

internal sealed class LocalSshProcessMonitor : IDisposable
{
    private readonly Timer timer;
    private IReadOnlyList<ObservedSshProcess> current = [];
    private int disposed;
    private readonly object refreshLock = new();
    internal string? Error { get; private set; }

    internal event Action? Changed;
    internal IReadOnlyList<ObservedSshProcess> Current => Volatile.Read(ref current);

    internal LocalSshProcessMonitor()
    {
        Refresh();
        timer = new Timer(_ => Refresh(), null, TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(2));
    }

    internal void RefreshNow() => Refresh();

    private void Refresh()
    {
        lock (refreshLock)
        {
        if (Volatile.Read(ref disposed) != 0) return;
        IReadOnlyList<LocalTcpConnection> connections;
        try { connections = LocalTcpConnections.Read(); Error = null; }
        catch (System.ComponentModel.Win32Exception exception) { Error = exception.Message; connections = []; }
        var found = new List<ObservedSshProcess>();
        foreach (var process in Process.GetProcessesByName("ssh"))
        {
            using (process)
            {
                try
                {
                    var name = process.ProcessName;
                    DateTimeOffset? started = null;
                    try { started = new DateTimeOffset(process.StartTime); }
                    catch (InvalidOperationException) { }
                    catch (System.ComponentModel.Win32Exception) { }
                    string executable;
                    try { executable = process.MainModule?.FileName ?? name; }
                    catch (InvalidOperationException) { executable = name; }
                    catch (System.ComponentModel.Win32Exception) { executable = name; }
                    var owned = connections.Where(connection => connection.ProcessId == process.Id).ToArray();
                    var endpoints = string.Join("\n", owned.Where(connection => connection.State == 5).Select(connection => connection.Remote).Distinct().Order());
                    var listeners = string.Join("\n", owned.Where(connection => connection.State == 2).Select(connection => connection.Local).Distinct().Order());
                    found.Add(new ObservedSshProcess(process.Id, started, executable, name, endpoints, listeners));
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception) { }
            }
        }
        var snapshot = found.OrderByDescending(process => process.StartedAt).ToArray();
        var previous = Interlocked.Exchange(ref current, snapshot);
        if (!previous.SequenceEqual(snapshot) && Volatile.Read(ref disposed) == 0) Changed?.Invoke();
        }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        timer.Dispose();
    }
}
