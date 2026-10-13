using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace Harbor.Desktop;

internal static class SshPortProbe
{
    internal static async Task<IReadOnlyList<long>> MeasureAsync(string endpoint, CancellationToken cancellationToken = default)
    {
        if (!IPEndPoint.TryParse(endpoint, out var target) || target.Port == 0) throw new FormatException("Invalid endpoint.");
        var samples = new List<long>();
        for (var i = 0; i < 3; i++)
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(3));
            using var socket = new TcpClient(target.AddressFamily);
            var watch = Stopwatch.StartNew();
            await socket.ConnectAsync(target.Address, target.Port, timeout.Token);
            samples.Add(watch.ElapsedMilliseconds);
        }
        return samples;
    }
}
