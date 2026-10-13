using System.Text.Json;
using System.Text.RegularExpressions;

namespace Harbor.Core;

public sealed record WindowsUpdateAsset(string Name, Uri Download, long Size, bool Installer);
public sealed record WindowsUpdateRelease(string Tag, Version Version, Uri Page, WindowsUpdateAsset? Asset, Uri? Checksums)
{
    public bool IsNewerThan(Version current) => Version > new Version(current.Major, current.Minor, Math.Max(0, current.Build), Math.Max(0, current.Revision));

    public static WindowsUpdateRelease FromManifest(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var versionText = root.GetProperty("version").GetString() ?? "";
        var buildText = root.GetProperty("build").ToString();
        if (root.GetProperty("bundle_id").GetString() != "com.mark455.harbor" ||
            !Regex.IsMatch(versionText, @"^\d+\.\d+\.\d+$", RegexOptions.CultureInvariant) ||
            !int.TryParse(buildText, out var build) || build < 0 || build > 65534 || !Version.TryParse(versionText, out var version))
            throw new InvalidDataException("Invalid Harbor update manifest.");
        var tag = "v" + versionText;
        return new WindowsUpdateRelease(tag, new Version(version.Major, version.Minor, version.Build, build),
            new Uri($"https://github.com/Mark4551124015/Harbor_ssh/releases/tag/{tag}"), null,
            new Uri($"https://github.com/Mark4551124015/Harbor_ssh/releases/download/{tag}/SHA256SUMS.txt"));
    }

    public static WindowsUpdateRelease Parse(string json, string architecture, string variant)
    {
        if (architecture is not ("x64" or "ARM64") || variant is not ("self-contained" or "framework-dependent"))
            throw new ArgumentException("Unsupported Windows update target.");
        using var document = JsonDocument.Parse(json);
        var release = document.RootElement;
        if (release.GetProperty("draft").GetBoolean() || release.GetProperty("prerelease").GetBoolean())
            throw new InvalidDataException("This release is not a stable published release.");
        var tag = release.GetProperty("tag_name").GetString() ?? "";
        var match = Regex.Match(tag, @"^[vV]?(\d+)\.(\d+)\.(\d+)(?:\.(\d+)|\+(\d+))?$", RegexOptions.CultureInvariant);
        if (!match.Success) throw new InvalidDataException("Release version is invalid.");
        var version = new Version(int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value), int.Parse(match.Groups[3].Value),
            match.Groups[4].Success ? int.Parse(match.Groups[4].Value) : match.Groups[5].Success ? int.Parse(match.Groups[5].Value) : 0);
        var prefix = $"https://github.com/Mark4551124015/Harbor_ssh/releases/download/{Uri.EscapeDataString(tag)}/";
        Uri AssetUrl(JsonElement asset)
        {
            var url = asset.GetProperty("browser_download_url").GetString() ?? "";
            if (!url.StartsWith(prefix, StringComparison.Ordinal) || !Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https")
                throw new InvalidDataException("Release asset is not hosted in Harbor's GitHub release.");
            return uri;
        }
        WindowsUpdateAsset? selected = null;
        Uri? checksums = null;
        foreach (var asset in release.GetProperty("assets").EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? "";
            if (name == "SHA256SUMS.txt") { checksums = AssetUrl(asset); continue; }
            if (!Regex.IsMatch(name, $@"^Harbor-(?:[0-9.]+-)?Windows-{Regex.Escape(architecture)}-{Regex.Escape(variant)}(?:-Setup)?\.(exe|msi|zip)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) continue;
            var installer = !name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase);
            var size = asset.GetProperty("size").GetInt64();
            if (size <= 0 || size > 1024L * 1024 * 1024) throw new InvalidDataException("Release asset size is invalid.");
            var candidate = new WindowsUpdateAsset(name, AssetUrl(asset), size, installer);
            if (selected is null || (installer && !selected.Installer)) selected = candidate;
        }
        return new WindowsUpdateRelease(tag, version, new Uri($"https://github.com/Mark4551124015/Harbor_ssh/releases/tag/{Uri.EscapeDataString(tag)}"), selected, checksums);
    }

    public static string FindChecksum(string sums, string assetName)
    {
        foreach (var line in sums.Split('\n'))
        {
            var match = Regex.Match(line.TrimEnd('\r'), @"^([a-fA-F0-9]{64})\s+\*?(.+)$", RegexOptions.CultureInvariant);
            if (match.Success && match.Groups[2].Value == assetName) return match.Groups[1].Value;
        }
        throw new InvalidDataException("The release has no SHA256 checksum for this Windows package.");
    }
}
