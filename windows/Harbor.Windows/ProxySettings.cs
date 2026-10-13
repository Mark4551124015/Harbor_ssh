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
        section.Children.Add(SettingRow("Update proxy mode", "System follows the Windows proxy configuration. Applies to update checks and downloads.", mode));
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
            section.Children.Add(SettingRow("Updates use proxy", "Use the selected proxy for update checks and downloads.", use));
        }
        section.Children.Add(Muted("SSH connections use their OpenSSH ProxyJump / ProxyCommand configuration. Windows update installation requires confirmation."));
        return Card(section);
    }

}
