using System.Text.Json;

namespace Harbor.Core;

public sealed class ConnectionProxy
{
    public string Mode { get; set; } = "Off";
    public string Host { get; set; } = "127.0.0.1";
    public int Port { get; set; } = 7899;
}

public sealed class Preferences
{
    public string Theme { get; set; } = "System";
    public string Accent { get; set; } = "Copper";
    public bool ReduceMotion { get; set; }
    public bool ShowServerAddresses { get; set; } = true;
    public string StartPage { get; set; } = "workbench";
    public string ProxyMode { get; set; } = "System";
    public string ProxyHost { get; set; } = "127.0.0.1";
    public int ProxyPort { get; set; } = 7899;
    public bool UpdatesUseProxy { get; set; } = true;
    public int ConnectTimeout { get; set; } = 15;
    public int KeepAlive { get; set; } = 30;
    public bool RecordRecent { get; set; } = true;
    public bool AutoCheckUpdates { get; set; } = true;
    public List<string> RecentHosts { get; set; } = [];
    public HashSet<string> ExplicitGroups { get; set; } = [];
    public Dictionary<string, List<string>> HostTags { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, string> HostIcons { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, string> GroupIcons { get; set; } = [];
    public Dictionary<string, string> GroupColors { get; set; } = [];
    public HashSet<string> MappingGroups { get; set; } = [];
    public Dictionary<string, ConnectionProxy> ConnectionProxies { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, List<string>> HostOrder { get; set; } = [];
    public List<string> SectionOrder { get; set; } = [];
    public Dictionary<string, string> HostGroups { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public HashSet<string> CollapsedGroups { get; set; } = [];
    public bool PreferWindowsTerminal { get; set; } = true;
    public HashSet<string> Favorites { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<ForwardRule> Forwards { get; set; } = [];
}

public sealed class PreferencesStore(string path)
{
    private readonly SemaphoreSlim gate = new(1, 1);
    public string Path { get; } = path;
    public Preferences Value { get; private set; } = new();

    public async Task LoadAsync()
    {
        if (!File.Exists(Path)) return;
        var text = await File.ReadAllTextAsync(Path);
        var next = JsonSerializer.Deserialize<Preferences>(text) ?? throw new InvalidDataException("Settings file is empty.");
        if (next.Theme is not ("System" or "Light" or "Dark")) throw new InvalidDataException("Unknown theme in Windows settings.");
        next.Favorites = new HashSet<string>(next.Favorites ?? [], StringComparer.OrdinalIgnoreCase);
        next.Forwards ??= [];
        next.HostGroups = new Dictionary<string, string>(next.HostGroups ?? [], StringComparer.OrdinalIgnoreCase);
        next.CollapsedGroups ??= [];
        next.ExplicitGroups ??= [];
        next.MappingGroups ??= [];
        next.RecentHosts ??= [];
        next.HostTags = new(next.HostTags ?? [], StringComparer.OrdinalIgnoreCase);
        next.HostIcons = new(next.HostIcons ?? [], StringComparer.OrdinalIgnoreCase);
        next.GroupIcons ??= [];
        next.GroupColors ??= [];
        next.ConnectionProxies = new(next.ConnectionProxies ?? [], StringComparer.OrdinalIgnoreCase);
        next.HostOrder ??= [];
        next.SectionOrder ??= [];
        if (next.ConnectTimeout is not (10 or 15 or 30 or 60)) next.ConnectTimeout = 15;
        if (next.KeepAlive is not (0 or 30 or 60)) next.KeepAlive = 30;
        foreach (var rule in next.Forwards)
        {
            if (rule is null) throw new InvalidDataException("A saved forward is empty.");
            rule.Validate();
        }
        if (next.Forwards.Select(rule => rule.Id).Distinct().Count() != next.Forwards.Count)
            throw new InvalidDataException("Saved forwards contain duplicate identifiers.");
        Value = next;
    }

    public async Task SaveAsync()
    {
        await gate.WaitAsync();
        var temporary = Path + ".tmp";
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(Value, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, Path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
            gate.Release();
        }
    }
}
