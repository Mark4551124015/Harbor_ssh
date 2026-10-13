using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Harbor.Core;

/// <summary>OpenSSH ProxyCommand transport using native .NET sockets and inherited standard handles.</summary>
public static class ProxyRelay
{
    public static async Task RunAsync(string mode, string proxyHost, int proxyPort, string targetHost, int targetPort, Stream input, Stream output)
    {
        if (proxyPort is < 1 or > 65535 || targetPort is < 1 or > 65535 || mode is not ("SOCKS5" or "HTTP")) throw new ArgumentException("Invalid proxy configuration.");
        if (targetHost.Any(c => char.IsControl(c) || char.IsWhiteSpace(c))) throw new ArgumentException("Invalid target hostname.");
        using var client = new TcpClient();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        await client.ConnectAsync(proxyHost, proxyPort, deadline.Token);
        var network = client.GetStream();
        if (mode == "SOCKS5")
        {
            await network.WriteAsync(new byte[] { 5, 1, 0 }, deadline.Token);
            var greeting = new byte[2]; await network.ReadExactlyAsync(greeting, deadline.Token);
            if (greeting[0] != 5 || greeting[1] != 0) throw new IOException("Proxy requires unsupported authentication.");
            byte[] address;
            if (IPAddress.TryParse(targetHost.Trim('[', ']'), out var ip)) address = new[] { (byte)(ip.AddressFamily == AddressFamily.InterNetwork ? 1 : 4) }.Concat(ip.GetAddressBytes()).ToArray();
            else
            {
                var name = Encoding.ASCII.GetBytes(new System.Globalization.IdnMapping().GetAscii(targetHost));
                if (name.Length > 255) throw new IOException("Proxy target name is too long.");
                address = new byte[] { 3, (byte)name.Length }.Concat(name).ToArray();
            }
            var request = new byte[] { 5, 1, 0 }.Concat(address).Concat(new byte[] { (byte)(targetPort >> 8), (byte)targetPort }).ToArray();
            await network.WriteAsync(request, deadline.Token);
            var reply = new byte[4]; await network.ReadExactlyAsync(reply, deadline.Token);
            if (reply[0] != 5 || reply[1] != 0) throw new IOException($"SOCKS5 proxy rejected the connection ({reply[1]}).");
            var length = reply[3] switch { 1 => 4, 4 => 16, 3 => -1, _ => throw new IOException("Invalid SOCKS5 proxy response.") };
            if (length == -1) { var size = new byte[1]; await network.ReadExactlyAsync(size, deadline.Token); length = size[0]; }
            await network.ReadExactlyAsync(new byte[length + 2], deadline.Token);
        }
        else
        {
            var target = targetHost.Contains(':') ? $"[{targetHost.Trim('[', ']')}]:{targetPort}" : $"{targetHost}:{targetPort}";
            await network.WriteAsync(Encoding.ASCII.GetBytes($"CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n\r\n"), deadline.Token);
            var header = new List<byte>(); var single = new byte[1];
            while (header.Count < 16384)
            {
                await network.ReadExactlyAsync(single, deadline.Token); header.Add(single[0]);
                if (header.Count >= 4 && header.TakeLast(4).SequenceEqual(new byte[] { 13, 10, 13, 10 })) break;
            }
            var status = Encoding.ASCII.GetString(header.ToArray()).Split("\r\n")[0].Split(' ');
            if (header.Count >= 16384 || status.Length < 2 || status[1] != "200") throw new IOException("HTTP CONNECT proxy rejected the connection.");
        }
        using var session = new CancellationTokenSource();
        async Task SendAsync()
        {
            await input.CopyToAsync(network, session.Token);
            try { client.Client.Shutdown(SocketShutdown.Send); } catch (SocketException) { }
        }
        var send = SendAsync(); var receive = network.CopyToAsync(output, session.Token);
        var first = await Task.WhenAny(send, receive);
        if (first == receive || first.IsFaulted) session.Cancel();
        try { await Task.WhenAll(send, receive); }
        catch (OperationCanceledException) when (session.IsCancellationRequested) { }
        await output.FlushAsync();
    }
}
