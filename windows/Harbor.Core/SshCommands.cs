using System.Diagnostics;

namespace Harbor.Core;

public enum ForwardKind { Local, Remote, Socks }

public sealed record ForwardRule(Guid Id, string HostAlias, ForwardKind Kind, int ListenPort,
    string TargetHost = "127.0.0.1", int TargetPort = 0)
{
    public string Group { get; init; } = "";
    public List<string> Tags { get; init; } = [];
    public string Label => Kind == ForwardKind.Socks ? $"SOCKS · localhost:{ListenPort}" :
        $"{Kind} · localhost:{ListenPort} → {TargetHost}:{TargetPort}";

    public void Validate()
    {
        if (!SshConfigDocument.IsLiteralAlias(HostAlias)) throw new ArgumentException("Select a concrete SSH host alias.");
        if (ListenPort is < 1 or > 65535 || (Kind != ForwardKind.Socks && TargetPort is < 1 or > 65535))
            throw new ArgumentException("Ports must be between 1 and 65535.");
        if (Kind != ForwardKind.Socks && (string.IsNullOrWhiteSpace(TargetHost) ||
            TargetHost.Any(c => char.IsWhiteSpace(c) || char.IsControl(c)) || TargetHost.StartsWith('-')))
            throw new ArgumentException("Enter a valid destination host or IP address.");
        if (!Enum.IsDefined(Kind)) throw new ArgumentException("Unknown forwarding type.");
    }
}

public static class SshCommands
{
    public static IReadOnlyList<string> Connect(string configPath, string alias)
    {
        if (!SshConfigDocument.IsLiteralAlias(alias)) throw new ArgumentException("Invalid SSH host alias.");
        // Let OpenSSH resolve Include, Match, wildcard defaults, keys and jump hosts itself.
        return ["-F", configPath, "--", alias];
    }

    public static IReadOnlyList<string> Forward(string configPath, ForwardRule rule)
    {
        rule.Validate();
        var target = rule.TargetHost.Contains(':') && !rule.TargetHost.StartsWith('[') ? $"[{rule.TargetHost}]" : rule.TargetHost;
        var specification = rule.Kind == ForwardKind.Socks ? $"127.0.0.1:{rule.ListenPort}" :
            $"127.0.0.1:{rule.ListenPort}:{target}:{rule.TargetPort}";
        return ["-F", configPath, "-N", "-T", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
            "-o", "ClearAllForwardings=no", "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "ControlPersist=no", "-o", "ForkAfterAuthentication=no", "-o", "PermitLocalCommand=no",
            "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
            rule.Kind switch { ForwardKind.Local => "-L", ForwardKind.Remote => "-R", _ => "-D" },
            specification, "--", rule.HostAlias];
    }

    public static ProcessStartInfo StartInfo(string executable, IEnumerable<string> arguments, bool capture = true)
    {
        var start = new ProcessStartInfo(executable)
        {
            UseShellExecute = false, CreateNoWindow = capture,
            RedirectStandardOutput = capture, RedirectStandardError = capture,
            RedirectStandardInput = capture
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        return start;
    }

    // PowerShell quoting for the clipboard. Execution always uses ArgumentList, never a shell.
    public static string DisplayCommand(string executable, IEnumerable<string> arguments) =>
        "& " + string.Join(" ", new[] { executable }.Concat(arguments).Select(value => "'" + value.Replace("'", "''", StringComparison.Ordinal) + "'"));
}
