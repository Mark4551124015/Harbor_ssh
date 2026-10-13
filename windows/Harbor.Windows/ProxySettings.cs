using System.Net;
using System.Net.Http;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private async Task CheckStartupVersionAsync()
    {
        try { await CheckVersionAsync(false); }
        catch { /* Offline startup must not interrupt the workspace. Manual checks report errors. */ }
    }
    private Border ProxySettings()
    {
        var section = Stack(24);
        section.Children.Add(SettingsSectionHeading("Proxy", "\uE774"));
        var mode = Segments(["System", "SOCKS5", "HTTP", "Off"], preferences.Value.ProxyMode, async value =>
        {
            preferences.Value.ProxyMode = value;
            await SavePreferencesAsync(); RenderSettings();
        });
        section.Children.Add(SettingRow("Update proxy mode", "System follows the Windows proxy configuration. Applies to version checks.", mode));
        if (preferences.Value.ProxyMode is "SOCKS5" or "HTTP")
        {
            var host = new HarborTextBox { Text = preferences.Value.ProxyHost, Width = 250, PlaceholderText = "127.0.0.1" };
            var port = new NumberBox { Value = preferences.Value.ProxyPort, Minimum = 1, Maximum = 65535, SmallChange = 1, Width = 150, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact };
            var error = Muted("");
            host.LostFocus += async (_, _) => await RunAsync(async () =>
            {
                var value = host.Text.Trim().Trim('[', ']');
                if (Uri.CheckHostName(value) == UriHostNameType.Unknown)
                { error.Text = "Enter a valid hostname or IP address."; host.Text = preferences.Value.ProxyHost; return; }
                preferences.Value.ProxyHost = value; error.Text = ""; await SavePreferencesAsync();
            });
            port.ValueChanged += async (_, _) => await RunAsync(async () =>
            {
                if (!double.IsFinite(port.Value) || port.Value != Math.Truncate(port.Value)) return;
                preferences.Value.ProxyPort = (int)port.Value; await SavePreferencesAsync();
            });
            section.Children.Add(SettingRow("Proxy host", "Hostname or IP address.", host));
            section.Children.Add(SettingRow("Proxy port", "Port number from 1 to 65535.", port));
            section.Children.Add(error);
        }
        if (preferences.Value.ProxyMode != "Off")
        {
            var use = new HarborSwitch { IsOn = preferences.Value.UpdatesUseProxy, OnContent = "", OffContent = "" };
            ApplyAccentToggle(use);
            use.Toggled += async (_, _) => await RunAsync(async () => { preferences.Value.UpdatesUseProxy = use.IsOn; await SavePreferencesAsync(); });
            section.Children.Add(SettingRow("Updates use proxy", "Use the selected proxy for version checks.", use));
        }
        section.Children.Add(Muted("SSH connections continue to use their OpenSSH ProxyJump / ProxyCommand configuration. Update downloads and installation are manual."));
        return Card(section);
    }

    private Task CheckVersionAsync() => CheckVersionAsync(true);
    private async Task CheckVersionAsync(bool showStatus)
    {
        using var handler = new HttpClientHandler();
        var prefs = preferences.Value;
        handler.UseProxy = prefs.UpdatesUseProxy && prefs.ProxyMode != "Off";
        if (handler.UseProxy && prefs.ProxyMode is "SOCKS5" or "HTTP")
        {
            var address = new UriBuilder(prefs.ProxyMode == "SOCKS5" ? "socks5" : "http", prefs.ProxyHost, prefs.ProxyPort).Uri;
            handler.Proxy = new WebProxy(address);
        }
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Harbor-Windows/1.0");
        using var response = await client.GetAsync("https://api.github.com/repos/Mark4551124015/Harbor_ssh/releases/latest");
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var tag = document.RootElement.GetProperty("tag_name").GetString();
        var current = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
        if (showStatus) ShowNotice($"Latest published release: {tag}. Windows version: {current}. Release assets may be platform-specific.", InfoBarSeverity.Informational);
    }
}
