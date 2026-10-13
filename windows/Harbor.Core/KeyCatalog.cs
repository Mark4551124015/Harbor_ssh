using System.Diagnostics;

namespace Harbor.Core;

public sealed record PublicKeyInfo(string Name, string Path, string PublicKey, string Fingerprint);

public static class KeyCatalog
{
    public static async Task<IReadOnlyList<PublicKeyInfo>> ReadAsync(string folder, string keygenExecutable)
    {
        if (!Directory.Exists(folder)) return [];
        var keys = new List<PublicKeyInfo>();
        foreach (var file in Directory.EnumerateFiles(folder, "*.pub").Order(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var publicKey = await File.ReadAllTextAsync(file);
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                using var process = Process.Start(SshCommands.StartInfo(keygenExecutable, ["-l", "-E", "sha256", "-f", file]))
                    ?? throw new IOException("Could not start ssh-keygen.");
                process.StandardInput.Close();
                var output = process.StandardOutput.ReadToEndAsync();
                var error = process.StandardError.ReadToEndAsync();
                try { await process.WaitForExitAsync(timeout.Token); }
                catch (OperationCanceledException)
                {
                    process.Kill(entireProcessTree: true);
                    throw new IOException("ssh-keygen timed out.");
                }
                keys.Add(new PublicKeyInfo(System.IO.Path.GetFileName(file), file, publicKey.Trim(),
                    process.ExitCode == 0 ? (await output).Trim() : (await error).Trim()));
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                keys.Add(new PublicKeyInfo(System.IO.Path.GetFileName(file), file, "", exception.Message));
            }
        }
        return keys;
    }
}
