using System.Net;
using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private async Task<IReadOnlyList<string>> ConnectionArgumentsAsync(string alias)
    {
        var arguments = SshCommands.Connect(config.Path, alias).ToList();
        if (await BuildProxyCommandAsync(alias) is string proxy) arguments.InsertRange(0, ["-o", $"ProxyCommand={proxy}"]);
        return arguments;
    }
    private async Task<string?> BuildProxyCommandAsync(string alias)
    {
        var settings = preferences.Value.ConnectionProxies.GetValueOrDefault(alias);
        if (settings is null || settings.Mode == "Off") return null;
        var effective = await ProcessRunner.CaptureAsync(WindowsIntegration.FindOpenSsh("ssh.exe"), new[] { "-G" }.Concat(SshCommands.Connect(config.Path, alias)), TimeSpan.FromSeconds(15));
        if (effective.ExitCode != 0) throw new IOException(effective.Error);
        var options = effective.Output.Split('\n').Select(line => line.Trim().Split(' ', 2)).Where(parts => parts.Length == 2).GroupBy(parts => parts[0]).ToDictionary(group => group.Key, group => group.First()[1]);
        if (options.TryGetValue("proxycommand", out var custom) && custom != "none") return null;
        var mode = settings.Mode; var host = settings.Host; var port = settings.Port;
        if (mode == "System")
        {
            var target = new UriBuilder("http", options.GetValueOrDefault("hostname", alias), int.TryParse(options.GetValueOrDefault("port"), out var sshPort) ? sshPort : 22).Uri;
            var proxy = System.Net.Http.HttpClient.DefaultProxy;
            if (proxy.IsBypassed(target)) return null;
            var address = proxy.GetProxy(target);
            if (address is null || address == target) return null;
            mode = address.Scheme.StartsWith("socks", StringComparison.OrdinalIgnoreCase) ? "SOCKS5" : address.Scheme == "http" ? "HTTP" : throw new IOException("System proxy must use HTTP CONNECT or SOCKS5.");
            host = address.Host; port = address.Port;
        }
        if (mode is not ("HTTP" or "SOCKS5") || Uri.CheckHostName(host) == UriHostNameType.Unknown || port is < 1 or > 65535) throw new ArgumentException("Invalid connection proxy configuration.");
        var executable = Environment.ProcessPath ?? throw new IOException("Harbor executable is unavailable.");
        return $"\"{executable.Replace('\\', '/')}\" --ssh-proxy {mode} {host} {port} %h %p";
    }

    private Border ConnectionProxySettings(SshHost host)
    {
        var section = Stack(18);
        void Populate()
        {
            section.Children.Clear();
            section.Children.Add(Text("Connection", 18));
            var prefs = preferences.Value.ConnectionProxies.GetValueOrDefault(host.Alias) ?? new ConnectionProxy();
            var mode = Segments(["Off", "System", "SOCKS5", "HTTP"], prefs.Mode, async value =>
            {
                prefs.Mode = value; preferences.Value.ConnectionProxies[host.Alias] = prefs; await SavePreferencesAsync(); Populate();
            });
            section.Children.Add(SettingRow("SSH over proxy", "Applies to new SSH sessions and this connection's port mappings.", mode));
            if (prefs.Mode is "SOCKS5" or "HTTP")
            {
                var address = new HarborTextBox { Text = prefs.Host, MinWidth = 240 };
                var port = new NumberBox { Value = prefs.Port, Minimum = 1, Maximum = 65535, SmallChange = 1, Width = 150 };
                var error = Muted("");
                address.LostFocus += async (_, _) => await RunAsync(async () =>
                {
                    var value = address.Text.Trim().Trim('[', ']');
                    if (Uri.CheckHostName(value) == UriHostNameType.Unknown) { error.Text = "Enter a hostname or IP address."; address.Text = prefs.Host; return; }
                    prefs.Host = value; preferences.Value.ConnectionProxies[host.Alias] = prefs; await SavePreferencesAsync(); error.Text = "";
                });
                port.ValueChanged += async (_, _) => await RunAsync(async () =>
                {
                    if (!double.IsFinite(port.Value) || port.Value != Math.Truncate(port.Value)) return;
                    prefs.Port = (int)port.Value; preferences.Value.ConnectionProxies[host.Alias] = prefs; await SavePreferencesAsync();
                });
                section.Children.Add(SettingRow("Proxy host", "Hostname or IP address.", address));
                section.Children.Add(SettingRow("Proxy port", "Port number from 1 to 65535.", port)); section.Children.Add(error);
            }
            section.Children.Add(Muted("A custom ProxyCommand takes precedence. Proxy authentication is not supported."));
            section.Children.Add(SettingRow("Jump host (ProxyJump)", host.ProxyJump.Length == 0 ? "None" : host.ProxyJump, ActionButton("Edit…", () => EditHostAsync(host), Symbol.Edit)));
        }
        Populate(); return Card(section);
    }
}
