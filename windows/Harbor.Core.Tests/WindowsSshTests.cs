using System.Net;
using System.Net.Sockets;
using Xunit;

namespace Harbor.Core.Tests;

public sealed class WindowsSshTests
{
    private static string? FindSsh()
    {
        var paths = new[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "OpenSSH") }
            .Concat((Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator));
        return paths.Select(path => Path.Combine(path.Trim('"'), OperatingSystem.IsWindows() ? "ssh.exe" : "ssh"))
            .FirstOrDefault(File.Exists);
    }

    [Theory]
    [InlineData(ForwardKind.Local, "localforward ")]
    [InlineData(ForwardKind.Remote, "remoteforward ")]
    [InlineData(ForwardKind.Socks, "dynamicforward ")]
    public async Task OpenSsh_resolves_each_managed_rule_without_connecting(ForwardKind kind, string directive)
    {
        var ssh = FindSsh() ?? throw new FileNotFoundException("OpenSSH Client is required for integration tests.");
        using var temp = new TemporaryDirectory();
        var config = Path.Combine(temp.Path, "config");
        await File.WriteAllTextAsync(config, "Host demo\n HostName 127.0.0.1\n User fictional\n");
        var rule = new ForwardRule(Guid.NewGuid(), "demo", kind, 18080, "127.0.0.1", 80);
        var result = await ProcessRunner.CaptureAsync(ssh, new[] { "-G" }.Concat(SshCommands.Forward(config, rule)), TimeSpan.FromSeconds(10));
        Assert.True(result.ExitCode == 0, result.Error);
        Assert.Contains(directive, result.Output);
    }

    [Fact]
    public async Task Additional_config_forwards_are_rejected_before_launch()
    {
        var ssh = FindSsh() ?? throw new FileNotFoundException("OpenSSH Client is required for integration tests.");
        using var temp = new TemporaryDirectory();
        var config = Path.Combine(temp.Path, "config");
        await File.WriteAllTextAsync(config, "Host demo\n HostName 127.0.0.1\n LocalForward 18081 127.0.0.1:80\n");
        using var manager = new SshProcessManager(ssh, config);
        await Assert.ThrowsAsync<InvalidOperationException>(() => manager.StartAsync(new ForwardRule(Guid.NewGuid(), "demo", ForwardKind.Socks, 18080)));
        Assert.Empty(manager.Sessions);
    }

    [Fact]
    public async Task Process_exit_captures_diagnostics_and_cleans_up()
    {
        var ssh = FindSsh() ?? throw new FileNotFoundException("OpenSSH Client is required for integration tests.");
        using var temp = new TemporaryDirectory();
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var config = Path.Combine(temp.Path, "config");
        await File.WriteAllTextAsync(config, $"Host demo\n HostName 127.0.0.1\n User fictional\n Port {port}\n");
        using var manager = new SshProcessManager(ssh, config);
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        await manager.StartAsync(new ForwardRule(Guid.NewGuid(), "demo", ForwardKind.Socks, 18080));
        using var client = await listener.AcceptTcpClientAsync(deadline.Token);
        await client.GetStream().WriteAsync("SSH-2.0-Harbor-Test\r\n"u8.ToArray(), deadline.Token);
        client.Close();
        while (manager.Sessions.Any(session => session.Active)) await Task.Delay(25, deadline.Token);
        var session = Assert.Single(manager.Sessions);
        Assert.StartsWith("Exited", session.Status);
        Assert.NotEmpty(session.Error);
    }

    [Fact]
    public async Task Key_catalog_reads_generated_public_key_and_fingerprint()
    {
        var ssh = FindSsh() ?? throw new FileNotFoundException("OpenSSH Client is required for integration tests.");
        var keygen = Path.Combine(Path.GetDirectoryName(ssh)!, OperatingSystem.IsWindows() ? "ssh-keygen.exe" : "ssh-keygen");
        using var temp = new TemporaryDirectory();
        var path = Path.Combine(temp.Path, "test_key");
        var result = await ProcessRunner.CaptureAsync(keygen, ["-t", "ed25519", "-N", "", "-f", path, "-C", "fictional@example.invalid"], TimeSpan.FromSeconds(10));
        Assert.True(result.ExitCode == 0, result.Error);
        var key = Assert.Single(await KeyCatalog.ReadAsync(temp.Path, keygen));
        Assert.StartsWith("ssh-ed25519 ", key.PublicKey);
        Assert.Contains("SHA256:", key.Fingerprint);
        Assert.DoesNotContain("PRIVATE", key.PublicKey);
    }

    [Fact]
    public async Task Stopping_only_terminates_the_owned_process()
    {
        var ssh = FindSsh() ?? throw new FileNotFoundException("OpenSSH Client is required for integration tests.");
        using var temp = new TemporaryDirectory();
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var config = Path.Combine(temp.Path, "config");
        await File.WriteAllTextAsync(config, $"Host demo\n HostName 127.0.0.1\n Port {((IPEndPoint)listener.LocalEndpoint).Port}\n");
        using var manager = new SshProcessManager(ssh, config);
        var id = Guid.NewGuid();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        await manager.StartAsync(new ForwardRule(id, "demo", ForwardKind.Socks, 18080));
        using var client = await listener.AcceptTcpClientAsync(deadline.Token);
        Assert.True(Assert.Single(manager.Sessions).Active);
        manager.Stop(Guid.NewGuid());
        Assert.True(Assert.Single(manager.Sessions).Active);
        manager.Stop(id);
        while (manager.Sessions.Any(session => session.Active)) await Task.Delay(25, deadline.Token);
        Assert.Equal("Stopped", Assert.Single(manager.Sessions).Status);
    }
}
