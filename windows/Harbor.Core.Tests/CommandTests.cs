using Xunit;

namespace Harbor.Core.Tests;

public sealed class CommandTests
{
    [Fact]
    public void Connection_uses_alias_and_one_config_path_argument()
    {
        var start = SshCommands.StartInfo("ssh.exe", SshCommands.Connect("C:\\Users\\Example User\\.ssh\\config", "demo"));
        Assert.Equal(new[] { "-F", "C:\\Users\\Example User\\.ssh\\config", "--", "demo" }, start.ArgumentList);
        Assert.False(start.UseShellExecute);
        Assert.Throws<ArgumentException>(() => SshCommands.Connect("config", "-oProxyCommand=whoami"));
    }

    [Theory]
    [InlineData(ForwardKind.Local, "-L", "127.0.0.1:8080:[::1]:80")]
    [InlineData(ForwardKind.Remote, "-R", "127.0.0.1:8080:[::1]:80")]
    [InlineData(ForwardKind.Socks, "-D", "127.0.0.1:8080")]
    public void Managed_forward_is_loopback_only_and_noninteractive(ForwardKind kind, string option, string spec)
    {
        var rule = new ForwardRule(Guid.NewGuid(), "demo", kind, 8080, "::1", 80);
        var args = SshCommands.Forward("config", rule);
        Assert.Contains("BatchMode=yes", args);
        Assert.Contains("ExitOnForwardFailure=yes", args);
        Assert.Contains("ForkAfterAuthentication=no", args);
        Assert.Contains("ControlPath=none", args);
        Assert.Contains(option, args);
        Assert.Contains(spec, args);
        Assert.Equal(new[] { "--", "demo" }, args.TakeLast(2));
    }

    [Fact]
    public void Display_quotes_windows_paths_without_changing_execution_arguments()
    {
        Assert.Equal("& 'ssh.exe' '-F' 'C:\\Users\\A B\\config' '--' 'demo'",
            SshCommands.DisplayCommand("ssh.exe", SshCommands.Connect("C:\\Users\\A B\\config", "demo")));
    }

    [Theory]
    [InlineData(0, 80)]
    [InlineData(8080, 65536)]
    public void Invalid_ports_are_rejected(int listen, int target) =>
        Assert.Throws<ArgumentException>(() => new ForwardRule(Guid.NewGuid(), "demo", ForwardKind.Local, listen, "localhost", target).Validate());

    [Fact]
    public async Task Legacy_preferences_keep_default_workbench_and_motion_settings()
    {
        using var temp = new TemporaryDirectory();
        var path = Path.Combine(temp.Path, "settings.json");
        await File.WriteAllTextAsync(path, "{\"Theme\":\"Dark\",\"PreferWindowsTerminal\":false}");
        var store = new PreferencesStore(path); await store.LoadAsync();
        Assert.Equal("workbench", store.Value.StartPage); Assert.Equal("Copper", store.Value.Accent);
        Assert.False(store.Value.ReduceMotion); Assert.True(store.Value.ShowServerAddresses); Assert.Empty(store.Value.HostGroups);
    }

    [Fact]
    public async Task Workspace_appearance_and_group_preferences_roundtrip()
    {
        using var temp = new TemporaryDirectory();
        var path = Path.Combine(temp.Path, "settings.json");
        var store = new PreferencesStore(path); await store.LoadAsync();
        store.Value.Accent = "Teal"; store.Value.ReduceMotion = true; store.Value.ShowServerAddresses = false;
        store.Value.StartPage = "keys"; store.Value.HostGroups["DEMO"] = "Development"; store.Value.CollapsedGroups.Add("Development");
        await store.SaveAsync(); var restored = new PreferencesStore(path); await restored.LoadAsync();
        Assert.Equal("Teal", restored.Value.Accent); Assert.True(restored.Value.ReduceMotion); Assert.False(restored.Value.ShowServerAddresses);
        Assert.Equal("keys", restored.Value.StartPage); Assert.Equal("Development", restored.Value.HostGroups["demo"]);
        Assert.Contains("Development", restored.Value.CollapsedGroups);
    }

    [Fact]
    public async Task Preferences_roundtrip_separately_from_ssh_config()
    {
        using var temp = new TemporaryDirectory();
        var path = Path.Combine(temp.Path, "preferences", "settings.json");
        var store = new PreferencesStore(path);
        await store.LoadAsync();
        store.Value.Theme = "Dark";
        store.Value.Favorites.Add("DEMO");
        store.Value.Forwards.Add(new ForwardRule(Guid.NewGuid(), "demo", ForwardKind.Socks, 1080));
        await store.SaveAsync();
        var restored = new PreferencesStore(path);
        await restored.LoadAsync();
        Assert.Equal("Dark", restored.Value.Theme);
        Assert.Contains("demo", restored.Value.Favorites, StringComparer.OrdinalIgnoreCase);
        Assert.Equal(StringComparer.OrdinalIgnoreCase, restored.Value.Favorites.Comparer);
        Assert.Equal(1080, Assert.Single(restored.Value.Forwards).ListenPort);
    }
}
