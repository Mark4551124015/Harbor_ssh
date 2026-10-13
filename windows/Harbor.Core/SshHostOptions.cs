using System.Text.RegularExpressions;

namespace Harbor.Core;

public sealed partial class SshConfigDocument
{
    public IReadOnlyList<(string Key, string Value)> HostOptions(SshHost host)
    {
        if (!Hosts.Contains(host)) throw new ArgumentException("Unknown host.");
        var block = blocks[host.BlockIndex];
        return lines.Skip(block.Start + 1).Take(block.End - block.Start - 1).Select(ParseDirective).Where(option => option.Key.Length > 0).ToList();
    }

    public string ReplaceHostOptions(SshHost host, IReadOnlyDictionary<string, List<string>> values)
    {
        RequireEditable(host);
        var replacements = new Dictionary<string, List<string>>(values, StringComparer.OrdinalIgnoreCase);
        foreach (var entry in replacements)
        {
            if (!Regex.IsMatch(entry.Key, "^[a-zA-Z][a-zA-Z0-9]*$") || entry.Key.ToLowerInvariant() is "host" or "match" or "include") throw new ArgumentException("Invalid SSH option name.");
            if (entry.Value.Any(value => value.Any(char.IsControl))) throw new ArgumentException("SSH option values cannot contain control characters.");
        }
        var block = blocks[host.BlockIndex];
        var updated = new List<string>(); var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var i = block.Start + 1; i < block.End; i++)
        {
            var option = ParseDirective(lines[i]);
            if (!replacements.TryGetValue(option.Key, out var next)) { updated.Add(lines[i]); continue; }
            if (seen.Add(option.Key))
            {
                updated.AddRange(next.Where(value => value.Length > 0).Select(value => $"  {option.Key} {value}"));
                if (InlineComment(lines[i]) is { Length: > 0 } comment) updated.Add("  " + comment.TrimStart());
            }
            else if (InlineComment(lines[i]) is { Length: > 0 } comment) updated.Add("  " + comment.TrimStart());
        }
        updated.InsertRange(0, replacements.Where(entry => !seen.Contains(entry.Key)).SelectMany(entry => entry.Value.Where(value => value.Length > 0).Select(value => $"  {entry.Key} {value}")));
        var result = new List<string>(lines);
        result.RemoveRange(block.Start + 1, block.End - block.Start - 1); result.InsertRange(block.Start + 1, updated);
        return string.Join(newline, result) + (finalNewline ? newline : "");
    }
}
