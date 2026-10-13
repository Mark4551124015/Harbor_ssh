using System.Security.Cryptography;
using System.Text;

namespace Harbor.Core;

public sealed class SshConfigStore(string path)
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private byte[] snapshot = [];
    private bool existed;
    private bool loaded;
    private bool utf8Bom;
    public string Path { get; } = System.IO.Path.GetFullPath(path);
    public SshConfigDocument Document { get; private set; } = new("");

    public async Task LoadAsync()
    {
        await gate.WaitAsync();
        try { await LoadCoreAsync(); }
        finally { gate.Release(); }
    }

    private async Task LoadCoreAsync()
    {
        existed = File.Exists(Path);
        snapshot = existed ? await File.ReadAllBytesAsync(Path) : [];
        utf8Bom = snapshot.AsSpan().StartsWith(Encoding.UTF8.Preamble);
        var offset = utf8Bom ? Encoding.UTF8.Preamble.Length : 0;
        Document = new SshConfigDocument(new UTF8Encoding(false, true).GetString(snapshot, offset, snapshot.Length - offset));
        loaded = true;
    }

    public Task SaveHostAsync(HostDraft draft, SshHost? original = null) =>
        WriteAsync(() => Document.Upsert(draft, original));
    public Task DeleteHostAsync(SshHost host) => WriteAsync(() => Document.Remove(host));
    public Task SaveOptionsAsync(SshHost host, IReadOnlyDictionary<string, List<string>> values) => WriteAsync(() => Document.ReplaceHostOptions(host, values));
    public Task SaveHostAndOptionsAsync(HostDraft draft, SshHost host, IReadOnlyDictionary<string, List<string>>? values) => WriteAsync(() =>
    {
        var text = Document.Upsert(draft, host);
        if (values is null) return text;
        var next = new SshConfigDocument(text);
        return next.ReplaceHostOptions(next.Hosts.Single(value => value.Alias == draft.Alias), values);
    });

    private async Task WriteAsync(Func<string> transform)
    {
        await gate.WaitAsync();
        string? temporary = null;
        try
        {
            if (!loaded) throw new InvalidOperationException("Load the SSH config before saving it.");
            var text = transform();
            var folder = System.IO.Path.GetDirectoryName(Path)!;
            Directory.CreateDirectory(folder);
            if (new FileInfo(Path).LinkTarget is not null)
                throw new IOException("This SSH config is a symbolic link. Edit the target file with your config editor.");
            // Hold the existing file against writers while checking and preparing the replacement.
            using (var current = File.Exists(Path) ? new FileStream(Path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete) : null)
            {
                var bytes = current is null ? [] : new byte[current.Length];
                if (current is not null) await current.ReadExactlyAsync(bytes);
                if (existed != (current is not null) || !CryptographicOperations.FixedTimeEquals(bytes, snapshot))
                    throw new IOException("SSH config changed outside Harbor. Refresh before saving your changes.");
                temporary = System.IO.Path.Combine(folder, $".harbor-{Guid.NewGuid():N}.tmp");
                await File.WriteAllTextAsync(temporary, text, new UTF8Encoding(utf8Bom));
                if (current is null) File.Move(temporary, Path, overwrite: false);
                else
                {
                    var archive = System.IO.Path.Combine(folder, "config_bk");
                    Directory.CreateDirectory(archive);
                    var backup = System.IO.Path.Combine(archive, $"harbor-windows-{DateTime.UtcNow:yyyyMMdd-HHmmss-fffffff}-{Guid.NewGuid():N}.config");
                    File.Replace(temporary, Path, backup);
                    try { PruneBackups(archive); }
                    catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
                    {
                        // Saving succeeded; a locked archive must not turn it into a reported write failure.
                    }
                }
            }
            temporary = null;
            await LoadCoreAsync();
        }
        finally
        {
            if (temporary is not null && File.Exists(temporary)) File.Delete(temporary);
            gate.Release();
        }
    }

    private static void PruneBackups(string folder)
    {
        // Only prune this application's own archives; never prune other tools' backups.
        var backups = new DirectoryInfo(folder).GetFiles("harbor-windows-*.config")
            .OrderBy(file => file.CreationTimeUtc).ToList();
        var total = backups.Sum(file => file.Length);
        foreach (var file in backups.Take(Math.Max(0, backups.Count - 1)))
        {
            if (total <= 10 * 1024 * 1024) break;
            total -= file.Length;
            file.Delete();
        }
    }
}
