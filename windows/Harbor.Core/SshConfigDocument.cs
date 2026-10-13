using System.Text;
using System.Text.RegularExpressions;

namespace Harbor.Core;

public sealed record SshHost(int BlockIndex, string Alias, string HostName, string User,
    string Port, string IdentityFile, string ProxyJump, bool CanEdit)
{
    public string Destination => string.IsNullOrEmpty(HostName) ? Alias : HostName;
    public string Subtitle => $"{(string.IsNullOrEmpty(User) ? "" : User + "@")}{Destination}";
}

public sealed record HostDraft(string Alias, string HostName = "", string User = "",
    string Port = "", string IdentityFile = "", string ProxyJump = "")
{
    public void Validate()
    {
        if (!Regex.IsMatch(Alias, @"\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z"))
            throw new ArgumentException("Use letters, numbers, dots, underscores or hyphens for the alias.");
        if (Port.Length != 0 && (!int.TryParse(Port, out var port) || port is < 1 or > 65535))
            throw new ArgumentException("Port must be between 1 and 65535, or blank to inherit it.");
        foreach (var value in new[] { HostName, User, IdentityFile, ProxyJump })
            if (value.Any(c => char.IsControl(c) || c == '"'))
                throw new ArgumentException("SSH fields cannot contain control characters or double quotes.");
        foreach (var value in new[] { HostName, User, ProxyJump })
            if (value.Any(char.IsWhiteSpace))
                throw new ArgumentException("Address, user and jump hosts cannot contain spaces.");
    }
}

/// <summary>Edits a single simple Host block while preserving every other line verbatim.</summary>
public sealed partial class SshConfigDocument
{
    private readonly List<string> lines;
    private readonly string newline;
    private readonly bool finalNewline;
    private readonly List<Block> blocks = [];
    public IReadOnlyList<SshHost> Hosts { get; }
    public bool HasIncludes { get; }
    private sealed record Block(int Start, int End, string Kind, string Value);

    public SshConfigDocument(string text)
    {
        newline = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        finalNewline = text.EndsWith('\n');
        lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n').ToList();
        if (finalNewline) lines.RemoveAt(lines.Count - 1);
        if (text.Length == 0) lines.Clear();
        var boundaries = lines.Select((line, index) => (Directive: ParseDirective(line), Index: index))
            .Where(item => item.Directive.Key is "host" or "match").ToList();
        for (var i = 0; i < boundaries.Count; i++)
            blocks.Add(new Block(boundaries[i].Index,
                i + 1 < boundaries.Count ? boundaries[i + 1].Index : lines.Count,
                boundaries[i].Directive.Key, boundaries[i].Directive.Value));
        HasIncludes = lines.Any(line => ParseDirective(line).Key == "include");
        var hosts = new List<SshHost>();
        for (var index = 0; index < blocks.Count; index++)
        {
            var block = blocks[index];
            if (block.Kind != "host") continue;
            var aliases = Tokenize(block.Value);
            var directives = lines.Skip(block.Start + 1).Take(block.End - block.Start - 1)
                .Select(ParseDirective).ToList();
            string Get(string key) => Unquote(directives.FirstOrDefault(item => item.Key == key).Value ?? "");
            var repeatedFields = directives.Where(d => d.Key is "hostname" or "user" or "port" or "identityfile" or "proxyjump")
                .GroupBy(d => d.Key).Any(group => group.Count() > 1);
            var editable = aliases.Count == 1 && !repeatedFields && !directives.Any(d => d.Key == "include");
            foreach (var alias in aliases.Where(IsLiteralAlias))
                hosts.Add(new SshHost(index, alias, Get("hostname"), Get("user"), Get("port"),
                    Get("identityfile"), Get("proxyjump"), editable));
        }
        // Repeated aliases can inherit options from several blocks; use OpenSSH to resolve them.
        var duplicates = hosts.GroupBy(h => h.Alias, StringComparer.OrdinalIgnoreCase)
            .Where(g => g.Count() > 1).Select(g => g.Key).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Hosts = hosts.Select(h => duplicates.Contains(h.Alias) ? h with { CanEdit = false } : h).ToList();
    }

    public string Upsert(HostDraft draft, SshHost? original = null)
    {
        draft.Validate();
        if (Hosts.Any(h => !ReferenceEquals(h, original) &&
            string.Equals(h.Alias, draft.Alias, StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("This host alias already exists.");
        var next = new List<string>(lines);
        var fields = new Dictionary<string, (string Name, string Value)>
        {
            ["hostname"] = ("HostName", draft.HostName), ["user"] = ("User", draft.User),
            ["port"] = ("Port", draft.Port), ["identityfile"] = ("IdentityFile", draft.IdentityFile),
            ["proxyjump"] = ("ProxyJump", draft.ProxyJump)
        };
        if (original is null)
        {
            if (next.Count > 0 && next[^1].Length > 0) next.Add("");
            // Insert after global options and before conditional blocks to keep wildcard precedence predictable.
            var at = blocks.Count > 0 ? blocks[0].Start : next.Count;
            var added = new List<string> { $"Host {draft.Alias}" };
            added.AddRange(fields.Values.Where(f => f.Value.Length > 0).Select(f => $"  {f.Name} {Quote(f.Value)}"));
            added.Add("");
            next.InsertRange(at, added);
        }
        else
        {
            RequireEditable(original);
            var block = blocks[original.BlockIndex];
            next[block.Start] = $"Host {draft.Alias}" + InlineComment(lines[block.Start]);
            var updated = new List<string>();
            var seen = new HashSet<string>();
            for (var i = block.Start + 1; i < block.End; i++)
            {
                var directive = ParseDirective(lines[i]);
                if (!fields.TryGetValue(directive.Key, out var field)) { updated.Add(lines[i]); continue; }
                if (seen.Add(directive.Key) && field.Value.Length > 0)
                    updated.Add($"  {field.Name} {Quote(field.Value)}" + InlineComment(lines[i]));
                else if (InlineComment(lines[i]) is { Length: > 0 } comment)
                    updated.Add("  " + comment.TrimStart());
            }
            var missing = fields.Where(f => !seen.Contains(f.Key) && f.Value.Value.Length > 0)
                .Select(f => $"  {f.Value.Name} {Quote(f.Value.Value)}").ToList();
            updated.InsertRange(0, missing);
            next.RemoveRange(block.Start + 1, block.End - block.Start - 1);
            next.InsertRange(block.Start + 1, updated);
        }
        return string.Join(newline, next) + (finalNewline || original is null ? newline : "");
    }

    public string Remove(SshHost host)
    {
        RequireEditable(host);
        var block = blocks[host.BlockIndex];
        var next = new List<string>(lines);
        // Keep standalone comments and whitespace, even when deleting a host.
        var retained = lines.Skip(block.Start + 1).Take(block.End - block.Start - 1)
            .Where(line => string.IsNullOrWhiteSpace(line) || line.TrimStart().StartsWith('#')).ToList();
        next.RemoveRange(block.Start, block.End - block.Start);
        next.InsertRange(block.Start, retained);
        return string.Join(newline, next) + (finalNewline && next.Count > 0 ? newline : "");
    }

    private void RequireEditable(SshHost host)
    {
        if (!Hosts.Contains(host) || !host.CanEdit)
            throw new InvalidOperationException("Edit this compound or repeated Host block in your SSH config editor.");
    }

    public static bool IsLiteralAlias(string? value) => !string.IsNullOrEmpty(value) && value[0] != '-' &&
        !value.Any(c => char.IsControl(c) || char.IsWhiteSpace(c) || "*?!\"".Contains(c));

    private static string Quote(string value) => value.Any(char.IsWhiteSpace) || value.Contains('#') ? $"\"{value}\"" : value;
    private static string Unquote(string value) => value.Length >= 2 && value[0] == '"' && value[^1] == '"' ? value[1..^1] : value;

    private static (string Key, string Value) ParseDirective(string line)
    {
        var match = DirectivePattern().Match(line);
        return match.Success ? (match.Groups[1].Value.ToLowerInvariant(), StripComment(match.Groups[2].Value).Trim()) : ("", "");
    }

    private static string StripComment(string value)
    {
        var quote = false;
        for (var i = 0; i < value.Length; i++)
        {
            if (value[i] == '"') quote = !quote;
            if (value[i] == '#' && !quote) return value[..i];
        }
        return value;
    }

    private static string InlineComment(string value)
    {
        var stripped = StripComment(value);
        return stripped.Length == value.Length ? "" : " " + value[stripped.Length..];
    }

    private static List<string> Tokenize(string value) => AliasPattern().Matches(value)
        .Select(match => Unquote(match.Value)).ToList();

    [GeneratedRegex(@"^\s*([A-Za-z][A-Za-z0-9]*)(?:\s*=\s*|\s+)(.*)$")]
    private static partial Regex DirectivePattern();
    [GeneratedRegex("\"[^\"]*\"|[^\\s]+")]
    private static partial Regex AliasPattern();
}
