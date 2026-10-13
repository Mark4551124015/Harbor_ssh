using System.Text;
using Xunit;

namespace Harbor.Core.Tests;

public sealed class ConfigTests
{
    [Fact]
    public void Editing_preserves_comments_unknown_options_and_other_scopes()
    {
        const string original = "# workspace\r\nInclude conf.d/*\r\nHost demo # keep\r\n  HostName old.example # address\r\n  User deploy\r\n  IdentityFile \"C:/Keys/my key\"\r\n  CustomOption value\r\n\r\nMatch host demo exec \"echo yes\"\r\n  Port 2222\r\nHost *\r\n  ServerAliveInterval 30\r\n";
        var doc = new SshConfigDocument(original);
        var host = Assert.Single(doc.Hosts);
        Assert.Equal("C:/Keys/my key", host.IdentityFile);
        var next = doc.Upsert(new HostDraft("demo", "new.example", "deploy", "", host.IdentityFile), host);
        Assert.StartsWith("# workspace\r\nInclude conf.d/*\r\nHost demo # keep\r\n", next);
        Assert.Contains("  HostName new.example # address\r\n", next);
        Assert.Contains("  CustomOption value\r\n", next);
        Assert.EndsWith("Match host demo exec \"echo yes\"\r\n  Port 2222\r\nHost *\r\n  ServerAliveInterval 30\r\n", next);
    }

    [Fact]
    public void Compound_wildcard_included_and_repeated_blocks_are_not_rewritten()
    {
        var doc = new SshConfigDocument("Host first second\n HostName combined\nHost *.example !excluded\n User someone\nHost repeated\n Port 22\nHost repeated\n User other\nHost included\n Include private.conf\n");
        Assert.Equal(new[] { "first", "second", "repeated", "repeated", "included" }, doc.Hosts.Select(h => h.Alias));
        Assert.All(doc.Hosts, host =>
        {
            Assert.False(host.CanEdit);
            Assert.Throws<InvalidOperationException>(() => doc.Remove(host));
        });
    }

    [Fact]
    public void Adding_before_conditional_scopes_preserves_global_options()
    {
        var doc = new SshConfigDocument("# header\nServerAliveInterval 30\nMatch all\n User special\nHost *\n Port 2222\n");
        var next = doc.Upsert(new HostDraft("demo", "example.invalid", "", "22"));
        Assert.StartsWith("# header\nServerAliveInterval 30\nHost demo\n", next);
        Assert.Contains("  Port 22\n\nMatch all\n User special\nHost *\n Port 2222\n", next);
    }

    [Fact]
    public void Removing_host_keeps_standalone_comments_and_following_match()
    {
        var doc = new SshConfigDocument("Host demo\n HostName example.invalid\n# next condition\nMatch all\n User special\n");
        Assert.Equal("# next condition\nMatch all\n User special\n", doc.Remove(Assert.Single(doc.Hosts)));
    }

    [Theory]
    [InlineData("-oProxyCommand=whoami", "22")]
    [InlineData("two hosts", "22")]
    [InlineData("good", "0")]
    [InlineData("good", "65536")]
    public void Invalid_host_input_is_rejected(string alias, string port) =>
        Assert.Throws<ArgumentException>(() => new HostDraft(alias, Port: port).Validate());

    [Fact]
    public void Repeated_identity_files_require_manual_editing()
    {
        var doc = new SshConfigDocument("Host demo\n IdentityFile first\n IdentityFile second\n");
        Assert.False(Assert.Single(doc.Hosts).CanEdit);
    }

    [Fact]
    public async Task Saving_is_atomic_backed_up_and_preserves_utf8_bom()
    {
        using var temp = new TemporaryDirectory();
        var path = Path.Combine(temp.Path, "config");
        await File.WriteAllTextAsync(path, "# original\r\nHost demo\r\n HostName before.invalid\r\n", new UTF8Encoding(true));
        var original = await File.ReadAllBytesAsync(path);
        var store = new SshConfigStore(path);
        await store.LoadAsync();
        await store.SaveHostAsync(new HostDraft("demo", "after.invalid"), Assert.Single(store.Document.Hosts));
        Assert.Contains("after.invalid", await File.ReadAllTextAsync(path));
        var backup = Assert.Single(Directory.GetFiles(Path.Combine(temp.Path, "config_bk")));
        Assert.Equal(original, await File.ReadAllBytesAsync(backup));
        Assert.True((await File.ReadAllBytesAsync(path)).AsSpan().StartsWith(Encoding.UTF8.Preamble));
        Assert.Empty(Directory.GetFiles(temp.Path, "*.tmp"));
    }

    [Fact]
    public async Task External_changes_are_not_overwritten()
    {
        using var temp = new TemporaryDirectory();
        var path = Path.Combine(temp.Path, "config");
        await File.WriteAllTextAsync(path, "Host demo\n HostName before.invalid\n");
        var store = new SshConfigStore(path);
        await store.LoadAsync();
        await File.WriteAllTextAsync(path, "# external edit\n");
        await Assert.ThrowsAsync<IOException>(() => store.SaveHostAsync(new HostDraft("demo", "after.invalid"), Assert.Single(store.Document.Hosts)));
        Assert.Equal("# external edit\n", await File.ReadAllTextAsync(path));
    }

    [Fact]
    public async Task First_save_creates_missing_folder_and_config()
    {
        using var temp = new TemporaryDirectory();
        var path = Path.Combine(temp.Path, ".ssh", "config");
        var store = new SshConfigStore(path);
        await store.LoadAsync();
        await store.SaveHostAsync(new HostDraft("demo", "example.invalid"));
        Assert.Equal("demo", Assert.Single(store.Document.Hosts).Alias);
    }
}

internal sealed class TemporaryDirectory : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "Harbor.Tests", Guid.NewGuid().ToString("N"));
    public TemporaryDirectory() => Directory.CreateDirectory(Path);
    public void Dispose() => Directory.Delete(Path, recursive: true);
}
