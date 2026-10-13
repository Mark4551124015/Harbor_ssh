param(
    [ValidateSet('x64', 'ARM64')]
    [string]$Architecture = 'x64',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$Dotnet = '',
    [string]$OutputDirectory = '',
    [string]$Version = '',
    [ValidateRange(0, 65534)]
    [int]$Build = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $Dotnet) {
    $localSdk = Join-Path $repoRoot '.local-only\dotnet\dotnet.exe'
    $Dotnet = if (Test-Path -LiteralPath $localSdk) { $localSdk } else { 'dotnet' }
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PSScriptRoot ('artifacts\packages-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
# A fresh folder prevents stale runtime files leaking into the smaller package.
if (Test-Path -LiteralPath $OutputDirectory) { throw "Package output already exists: $OutputDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$rid = if ($Architecture -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$project = Join-Path $PSScriptRoot 'Harbor.Windows\Harbor.Windows.csproj'
$summary = @()
$versionArguments = @()
if ($Version) {
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must have the form major.minor.patch.' }
    $versionArguments = @("-p:Version=$Version", "-p:AssemblyVersion=$Version.$Build", "-p:FileVersion=$Version.$Build", "-p:InformationalVersion=$Version+$Build")
}
foreach ($variant in @('self-contained', 'framework-dependent')) {
    $bundleName = "Harbor-Windows-$Architecture-$variant"
    $publish = Join-Path $OutputDirectory $bundleName
    $contained = if ($variant -eq 'self-contained') { 'true' } else { 'false' }
    & $Dotnet publish $project -c $Configuration "-p:Platform=$Architecture" -r $rid --self-contained $contained "-p:PublishTrimmed=$contained" '-p:TrimMode=partial' '-p:WindowsAppSDKSelfContained=true' '-p:DebugType=None' '-p:DebugSymbols=false' @versionArguments -o $publish --nologo
    if ($LASTEXITCODE -ne 0) { throw "Publishing $variant failed ($LASTEXITCODE)." }
    $runtime = if ($contained -eq 'true') {
        'Includes the .NET runtime. No separate .NET installation is required.'
    } else {
        "Requires the .NET 10 runtime for Windows $Architecture (Microsoft.NETCore.App 10.x). The .NET 10 Desktop Runtime also includes it."
    }
    @"
Harbor for Windows $Architecture - $variant

Extract this entire ZIP into a folder, then run Harbor.Windows.exe.
Keep all application files together. This is a portable application package.

$runtime
The Windows App SDK / WinUI runtime is included in both packages.
Windows 10 version 2004 or later is required.
SSH operations require the OpenSSH Client (ssh.exe).
Your SSH configuration and Harbor preferences remain in their existing user directories.
"@ | Set-Content -LiteralPath (Join-Path $publish 'README.txt') -Encoding utf8
    $zip = Join-Path $OutputDirectory ($bundleName + '.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($publish, $zip, [IO.Compression.CompressionLevel]::SmallestSize, $false)
    $files = Get-ChildItem -LiteralPath $publish -Recurse -File
    $summary += [pscustomobject]@{
        Variant = $variant
        Architecture = $Architecture
        Archive = $zip
        ArchiveBytes = (Get-Item -LiteralPath $zip).Length
        ExtractedBytes = ($files | Measure-Object -Property Length -Sum).Sum
        SHA256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    }
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'packages.json') -Encoding utf8
$summary | Format-Table Variant, @{Name='ZIP MiB'; Expression={[Math]::Round($_.ArchiveBytes / 1MB, 2)}}, @{Name='Extracted MiB'; Expression={[Math]::Round($_.ExtractedBytes / 1MB, 2)}}
Write-Host "Packages: $OutputDirectory"
