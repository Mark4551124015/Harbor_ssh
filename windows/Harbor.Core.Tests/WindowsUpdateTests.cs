using System.Text.Json;
using Xunit;

namespace Harbor.Core.Tests;

public sealed class WindowsUpdateTests
{
    [Fact]
    public void Manifest_compares_build_revision_and_validates_product()
    {
        const string manifest = "{\"version\":\"1.0.6\",\"build\":\"8\",\"bundle_id\":\"com.mark455.harbor\"}";
        var release = WindowsUpdateRelease.FromManifest(manifest);
        Assert.True(release.IsNewerThan(new Version(1, 0, 5, 7)));
        Assert.True(release.IsNewerThan(new Version(1, 0, 6, 7)));
        Assert.False(release.IsNewerThan(new Version(1, 0, 6, 8)));
        Assert.Throws<InvalidDataException>(() => WindowsUpdateRelease.FromManifest(manifest.Replace("com.mark455.harbor", "other.product")));
    }
    private static string Release(params string[] names) => JsonSerializer.Serialize(new
    {
        tag_name = "v1.0.6", draft = false, prerelease = false,
        assets = names.Select(name => new { name, size = 100, browser_download_url = "https://github.com/Mark4551124015/Harbor_ssh/releases/download/v1.0.6/" + name })
    });

    [Fact]
    public void New_patch_is_newer_than_four_part_installed_version()
    {
        var release = WindowsUpdateRelease.Parse(Release(), "x64", "self-contained");
        Assert.True(release.IsNewerThan(new Version(1, 0, 5, 7)));
        Assert.False(release.IsNewerThan(new Version(1, 0, 6, 8)));
        Assert.False(release.IsNewerThan(new Version(1, 0, 6)));
    }

    [Fact]
    public void Selects_own_platform_architecture_and_runtime_with_installer_preferred()
    {
        var release = WindowsUpdateRelease.Parse(Release("Harbor-1.0.6-macos-universal.zip", "Harbor-Windows-ARM64-self-contained.zip", "Harbor-Windows-x64-framework-dependent-Setup.exe", "Harbor-Windows-x64-self-contained.zip", "Harbor-Windows-x64-self-contained-Setup.exe"), "x64", "self-contained");
        Assert.Equal("Harbor-Windows-x64-self-contained-Setup.exe", release.Asset!.Name);
        Assert.True(release.Asset.Installer);
    }

    [Fact]
    public void Zip_only_release_is_not_presented_as_an_installer()
    {
        var release = WindowsUpdateRelease.Parse(Release("Harbor-Windows-x64-framework-dependent.zip"), "x64", "framework-dependent");
        Assert.NotNull(release.Asset);
        Assert.False(release.Asset.Installer);
        Assert.Null(WindowsUpdateRelease.Parse(Release("Harbor-1.0.6-macos-universal.zip"), "x64", "framework-dependent").Asset);
    }

    [Fact]
    public void Checksum_requires_exact_asset_name()
    {
        var hash = new string('a', 64);
        Assert.Equal(hash, WindowsUpdateRelease.FindChecksum(hash + "  Harbor-Windows-x64-self-contained.zip\n", "Harbor-Windows-x64-self-contained.zip"));
        Assert.Throws<InvalidDataException>(() => WindowsUpdateRelease.FindChecksum(hash + "  macos.zip", "windows.zip"));
    }

    [Fact]
    public void Rejects_assets_from_another_repository()
    {
        var json = Release("Harbor-Windows-x64-self-contained.zip").Replace("Mark4551124015/Harbor_ssh/releases/download", "other/repo/releases/download");
        Assert.Throws<InvalidDataException>(() => WindowsUpdateRelease.Parse(json, "x64", "self-contained"));
    }
}
