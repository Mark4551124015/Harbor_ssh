using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Harbor.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Harbor.Desktop;

public sealed partial class MainWindow
{
    private WindowsUpdateRelease? availableUpdate;
    private string updateStatus = "Check for a newer Windows version. Downloads are verified before use.";
    private TextBlock? updateStatusLabel;
    private Button? updateActionButton;
    private bool updateChecking;
    private bool updateDownloading;
    private static Version InstalledVersion => Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0, 0);
    private static string UpdateArchitecture => RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "ARM64" : "x64";
    private static string UpdateVariant => File.Exists(Path.Combine(AppContext.BaseDirectory, "coreclr.dll")) ? "self-contained" : "framework-dependent";

    private HttpClient UpdateClient(TimeSpan timeout)
    {
        var prefs = preferences.Value;
        var handler = new HttpClientHandler { UseProxy = prefs.UpdatesUseProxy && prefs.ProxyMode != "Off" };
        if (handler.UseProxy && prefs.ProxyMode is "SOCKS5" or "HTTP")
            handler.Proxy = new WebProxy(new UriBuilder(prefs.ProxyMode == "SOCKS5" ? "socks5" : "http", prefs.ProxyHost, prefs.ProxyPort).Uri);
        var client = new HttpClient(handler) { Timeout = timeout };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"Harbor-Windows/{InstalledVersion}");
        return client;
    }

    private void SetUpdateStatus(string text)
    {
        updateStatus = text;
        if (updateStatusLabel is not null) updateStatusLabel.Text = text;
        if (updateActionButton is not null)
        {
            var asset = availableUpdate?.Asset;
            updateActionButton.Visibility = asset is not null ? Visibility.Visible : Visibility.Collapsed;
            updateActionButton.IsEnabled = !updateDownloading && !updateChecking;
        }
    }

    private void AddUpdateControls(StackPanel section)
    {
        var actions = new WrapPanel();
        actions.Children.Add(ActionButton("Check for updates", CheckVersionAsync, Symbol.Refresh));
        var installer = availableUpdate?.Asset?.Installer == true;
        updateActionButton = ActionButton(installer ? "Download and install update" : "Download Windows ZIP", DownloadUpdateAsync, Symbol.Download);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(updateActionButton, installer ? "Download and install update" : "Download Windows ZIP");
        actions.Children.Add(updateActionButton);
        actions.Children.Add(ActionButton("Open release page", () =>
        {
            using var process = Process.Start(new ProcessStartInfo((availableUpdate?.Page ?? new Uri("https://github.com/Mark4551124015/Harbor_ssh/releases/latest")).AbsoluteUri) { UseShellExecute = true });
            return Task.CompletedTask;
        }));
        section.Children.Add(actions);
        updateStatusLabel = Muted(updateStatus, 12); section.Children.Add(updateStatusLabel);
        section.Children.Add(Muted($"Windows {UpdateArchitecture} · {UpdateVariant}. Installer updates require confirmation. ZIP-only releases require manual replacement.", 11));
        SetUpdateStatus(updateStatus);
    }

    private Task CheckVersionAsync() => CheckVersionAsync(true);
    private async Task VerifyWindowsUpdateUiAsync()
    {
        settingsCategory = "About"; ShowPage("settings");
        availableUpdate = new WindowsUpdateRelease("v9.0.0", new Version(9, 0, 0, 0), new Uri("https://github.com/Mark4551124015/Harbor_ssh/releases/tag/v9.0.0"),
            new WindowsUpdateAsset("Harbor-Windows-x64-self-contained.zip", new Uri("https://github.com/Mark4551124015/Harbor_ssh/releases/download/v9.0.0/Harbor-Windows-x64-self-contained.zip"), 100, false), null);
        SetUpdateStatus("ZIP-only Windows update available; manual replacement required."); RenderSettings(); await Task.Delay(250); Root.UpdateLayout();
        if (updateActionButton?.Visibility != Visibility.Visible || Microsoft.UI.Xaml.Automation.AutomationProperties.GetName(updateActionButton) != "Download Windows ZIP")
            throw new InvalidOperationException("ZIP update action is incorrect.");
        await CapturePreviewAsync($"{smokeReport}-update-zip.png");
        availableUpdate = availableUpdate with { Asset = availableUpdate.Asset! with { Name = "Harbor-Windows-x64-self-contained-Setup.exe", Installer = true } };
        SetUpdateStatus("Verified Windows installer update available."); RenderSettings(); Root.UpdateLayout();
        if (Microsoft.UI.Xaml.Automation.AutomationProperties.GetName(updateActionButton!) != "Download and install update")
            throw new InvalidOperationException("Installer update action is incorrect.");
        await CapturePreviewAsync($"{smokeReport}-update-installer.png");
        availableUpdate = null; SetUpdateStatus("Windows is up to date."); RenderSettings(); Root.UpdateLayout();
        if (updateActionButton!.Visibility != Visibility.Collapsed) throw new InvalidOperationException("No-update state retained an install action.");
    }

    private async Task<WindowsUpdateRelease> ReadWindowsReleaseAsync(HttpClient client)
    {
        // Published manifests avoid GitHub's unauthenticated API rate limit and
        // carry the build revision used by Windows' four-part assembly version.
        using var manifest = await client.GetAsync("https://github.com/Mark4551124015/Harbor_ssh/releases/latest/download/release-manifest.json");
        if (manifest.IsSuccessStatusCode)
        {
            var release = WindowsUpdateRelease.FromManifest(await manifest.Content.ReadAsStringAsync());
            var baseUrl = $"https://github.com/Mark4551124015/Harbor_ssh/releases/download/{release.Tag}/";
            foreach (var suffix in new[] { "-Setup.exe", "-Setup.msi", ".zip" })
            {
                var name = $"Harbor-Windows-{UpdateArchitecture}-{UpdateVariant}{suffix}";
                var uri = new Uri(baseUrl + name);
                using var request = new HttpRequestMessage(HttpMethod.Head, uri);
                using var probe = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
                if (probe.StatusCode == HttpStatusCode.NotFound) continue;
                probe.EnsureSuccessStatusCode();
                var size = probe.Content.Headers.ContentLength;
                if (size is null || size <= 0 || size > 1024L * 1024 * 1024) throw new InvalidDataException("Update package size is unavailable or invalid.");
                return release with { Asset = new WindowsUpdateAsset(name, uri, size.Value, suffix != ".zip") };
            }
            return release;
        }
        using var api = await client.GetAsync("https://api.github.com/repos/Mark4551124015/Harbor_ssh/releases/latest");
        if (api.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests)
            throw new HttpRequestException("GitHub update checks are rate-limited or blocked. Retry later or open the release page.");
        api.EnsureSuccessStatusCode();
        return WindowsUpdateRelease.Parse(await api.Content.ReadAsStringAsync(), UpdateArchitecture, UpdateVariant);
    }

    private async Task CheckVersionAsync(bool showStatus)
    {
        if (updateChecking || updateDownloading) return;
        updateChecking = true; availableUpdate = null; SetUpdateStatus("Checking for Windows updates…");
        try
        {
            using var client = UpdateClient(TimeSpan.FromSeconds(20));
            var release = await ReadWindowsReleaseAsync(client);
            if (!release.IsNewerThan(InstalledVersion)) SetUpdateStatus($"Windows is up to date. Installed {InstalledVersion}; latest release {release.Tag}.");
            else if (release.Asset is null)
                SetUpdateStatus($"{release.Tag} is newer, but has no Windows {UpdateArchitecture} {UpdateVariant} package. Installed {InstalledVersion}.");
            else
            {
                availableUpdate = release;
                SetUpdateStatus($"Windows {release.Tag} is available. Installed {InstalledVersion}. " + (release.Asset.Installer ? "Download the installer to upgrade." : "This release contains a ZIP, not an installer; download and replace the application manually."));
                if (page == "settings") RenderSettings();
                if (!showStatus)
                {
                    ShowNotice($"Windows {release.Tag} is available.");
                    Notice.ActionButton = ActionButton("View update", () => { settingsCategory = "About"; ShowPage("settings"); return Task.CompletedTask; });
                }
            }
            if (showStatus) ShowNotice(updateStatus);
        }
        catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException or InvalidDataException or System.Text.Json.JsonException)
        {
            SetUpdateStatus($"Could not check Windows updates: {exception.Message}");
            if (showStatus) ShowNotice(updateStatus, InfoBarSeverity.Warning);
        }
        finally { updateChecking = false; SetUpdateStatus(updateStatus); }
    }

    private async Task DownloadUpdateAsync()
    {
        var release = availableUpdate; var asset = release?.Asset;
        if (updateDownloading || release is null || asset is null) return;
        updateDownloading = true; SetUpdateStatus("Preparing verified update download…");
        string? partial = null;
        try
        {
            if (release.Checksums is null) throw new InvalidDataException("The release has no SHA256SUMS.txt. Use the release page to inspect this package.");
            using var client = UpdateClient(TimeSpan.FromMinutes(10));
            using var cancellation = new CancellationTokenSource(TimeSpan.FromMinutes(10));
            var checksum = WindowsUpdateRelease.FindChecksum(await client.GetStringAsync(release.Checksums, cancellation.Token), asset.Name);
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Harbor.Windows", "Updates", release.Tag);
            Directory.CreateDirectory(directory);
            var destination = Path.Combine(directory, asset.Name);
            partial = destination + "." + Guid.NewGuid().ToString("N") + ".partial";
            using (var response = await client.GetAsync(asset.Download, HttpCompletionOption.ResponseHeadersRead, cancellation.Token))
            {
                response.EnsureSuccessStatusCode();
                await using var input = await response.Content.ReadAsStreamAsync(cancellation.Token);
                await using var output = new FileStream(partial, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true);
                var buffer = new byte[81920]; long received = 0; var progress = Stopwatch.StartNew();
                int count;
                while ((count = await input.ReadAsync(buffer, cancellation.Token)) > 0)
                {
                    received += count;
                    if (received > asset.Size) throw new InvalidDataException("Download exceeds the published package size.");
                    await output.WriteAsync(buffer.AsMemory(0, count), cancellation.Token);
                    if (progress.ElapsedMilliseconds > 200) { SetUpdateStatus($"Downloading {release.Tag}: {received * 100 / asset.Size}%"); progress.Restart(); }
                }
                if (received != asset.Size) throw new InvalidDataException("Downloaded package is incomplete.");
            }
            SetUpdateStatus("Verifying SHA256…");
            await using (var downloaded = File.OpenRead(partial))
                if (!Convert.ToHexString(await SHA256.HashDataAsync(downloaded, cancellation.Token)).Equals(checksum, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("The downloaded package failed SHA256 verification.");
            File.Move(partial, destination, true); partial = null;
            if (!asset.Installer)
            {
                SetUpdateStatus($"Verified {release.Tag} ZIP downloaded. Extract it into a new folder and replace your old application manually. This release has no Windows installer.");
                WindowsIntegration.RevealFile(destination);
                return;
            }
            SetUpdateStatus($"Verified {release.Tag} installer downloaded.");
            var prompt = Dialog("Install Windows update?", Text("Harbor will close and run the verified installer. Harbor-managed port forwards will stop. Your SSH configuration and preferences are retained."), "Install and close Harbor");
            prompt.DefaultButton = ContentDialogButton.Close;
            if (await prompt.ShowAsync() != ContentDialogResult.Primary) return;
            using var process = Process.Start(new ProcessStartInfo(destination) { UseShellExecute = true });
            Close();
        }
        catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException or IOException or System.ComponentModel.Win32Exception)
        {
            SetUpdateStatus($"Update download failed: {exception.Message}"); ShowNotice(updateStatus, InfoBarSeverity.Warning);
        }
        finally
        {
            if (partial is not null) try { File.Delete(partial); } catch (IOException) { }
            updateDownloading = false; SetUpdateStatus(updateStatus);
        }
    }
}
