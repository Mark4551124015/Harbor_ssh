param(
    [Parameter(Mandatory = $true)]
    [string]$PackageDirectory,
    [string]$Compiler = '',
    [string]$OutputDirectory = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
if (-not $Compiler) {
    $localCompiler = Join-Path $repoRoot '.local-only\toolchain\inno\compiler\ISCC.exe'
    $Compiler = if (Test-Path -LiteralPath $localCompiler) { $localCompiler } else { 'ISCC.exe' }
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PackageDirectory 'installers' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$manifest = Get-Content -LiteralPath (Join-Path $PackageDirectory 'packages.json') -Raw | ConvertFrom-Json
$stagingRoot = Join-Path $repoRoot ('.local-only\installer-staging-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
$installerManifest = @()
try {
    foreach ($package in $manifest) {
        $variant = $package.Variant
        if ($variant -notin @('self-contained', 'framework-dependent') -or $package.Architecture -ne 'x64') { throw 'Unsupported installer package.' }
        $archive = Join-Path $PackageDirectory ([IO.Path]::GetFileName($package.Archive))
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.SHA256) { throw "Package hash mismatch: $archive" }
        $source = Join-Path $stagingRoot $variant
        [IO.Compression.ZipFile]::ExtractToDirectory($archive, $source)
        $version = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $source 'Harbor.Windows.dll')).Version.ToString(3)
        & $Compiler "/DSourceDir=$source" "/DInstallerOutput=$OutputDirectory" "/DVariant=$variant" "/DAppVersion=$version" (Join-Path $PSScriptRoot 'Harbor.iss')
        if ($LASTEXITCODE -ne 0) { throw "Installer compile failed: $variant" }
        $installer = Join-Path $OutputDirectory "Harbor-Windows-x64-$variant-Setup.exe"
        $installerManifest += [pscustomobject]@{Variant=$variant; Version=$version; Architecture='x64'; Installer=$installer; Bytes=(Get-Item -LiteralPath $installer).Length; SHA256=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash}
    }
    $installerManifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'installers.json') -Encoding utf8
    $installerManifest | Format-Table Variant, Version, @{Name='Installer MiB'; Expression={[Math]::Round($_.Bytes/1MB,2)}}
}
finally {
    $resolvedStaging = [IO.Path]::GetFullPath($stagingRoot)
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.local-only')) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedStaging.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedStaging -Recurse -Force }
}
