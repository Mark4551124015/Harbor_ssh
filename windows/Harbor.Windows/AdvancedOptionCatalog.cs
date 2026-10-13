namespace Harbor.Desktop;

internal sealed record AdvancedOption(string Name, string Description, string Example);

public sealed partial class MainWindow
{
    private static readonly AdvancedOption[] AdvancedOptions = [
        new("ServerAliveInterval", "Seconds between encrypted keepalive requests.", "30"),
        new("ServerAliveCountMax", "Unanswered keepalives before disconnecting.", "3"),
        new("ConnectTimeout", "Connection and initial handshake timeout, in seconds.", "15"),
        new("ConnectionAttempts", "Number of connection attempts.", "1"),
        new("TCPKeepAlive", "Use operating system TCP keepalive messages.", "yes or no"),
        new("Compression", "Compress data sent through SSH.", "yes or no"),
        new("ForwardAgent", "Forward access to your authentication agent.", "yes or no"),
        new("ForwardX11", "Forward X11 graphical applications.", "yes or no"),
        new("ForwardX11Trusted", "Allow trusted X11 forwarding.", "yes or no"),
        new("ExitOnForwardFailure", "Exit when requested forwarding cannot be established.", "yes or no"),
        new("IdentitiesOnly", "Use only explicitly configured authentication identities.", "yes or no"),
        new("IdentityAgent", "Authentication agent socket path.", "SSH_AUTH_SOCK or none"),
        new("AddKeysToAgent", "Add loaded private keys to your agent.", "yes, no, ask or confirm"),
        new("PreferredAuthentications", "Authentication methods in priority order.", "publickey,password"),
        new("PasswordAuthentication", "Allow password authentication.", "yes or no"),
        new("PubkeyAuthentication", "Allow public key authentication.", "yes or no"),
        new("BatchMode", "Disable interactive authentication prompts.", "yes or no"),
        new("StrictHostKeyChecking", "Control acceptance of server host keys.", "ask, yes, accept-new or no"),
        new("UserKnownHostsFile", "File containing trusted server host keys.", "~/.ssh/known_hosts"),
        new("LogLevel", "Verbosity of SSH diagnostic messages.", "INFO or VERBOSE"),
        new("AddressFamily", "Choose IPv4, IPv6 or either.", "any, inet or inet6"),
        new("ControlMaster", "Share connections through a control socket.", "auto, ask, yes or no"),
        new("ControlPath", "Path for the connection sharing socket.", "~/.ssh/cm-%C"),
        new("ControlPersist", "Keep shared connections after the session exits.", "10m"),
        new("SendEnv", "Environment variable names sent to the server.", "LANG LC_*"),
        new("SetEnv", "Environment variables sent as explicit assignments.", "NAME=value"),
        new("RequestTTY", "When to request a remote terminal.", "auto, yes, no or force"),
        new("RemoteCommand", "Command to execute after connecting.", "tmux attach"),
    ];
}
