using System.Diagnostics;

namespace Harbor.Core;

public sealed record CommandResult(int ExitCode, string Output, string Error);

public static class ProcessRunner
{
    public static async Task<CommandResult> CaptureAsync(string executable, IEnumerable<string> arguments, TimeSpan timeout)
    {
        using var process = Process.Start(SshCommands.StartInfo(executable, arguments))
            ?? throw new IOException($"Could not start {executable}.");
        process.StandardInput.Close();
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        using var cancellation = new CancellationTokenSource(timeout);
        try { await process.WaitForExitAsync(cancellation.Token); }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
            await process.WaitForExitAsync();
            await Task.WhenAll(output, error);
            throw new IOException($"{System.IO.Path.GetFileName(executable)} timed out.");
        }
        return new CommandResult(process.ExitCode, await output, await error);
    }
}
