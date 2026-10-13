param(
    [ValidateSet('Build', 'Test', 'Run', 'Publish', 'Smoke')]
    [string]$Task = 'Build',
    [ValidateSet('x64', 'ARM64')]
    [string]$Architecture = 'x64',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$Dotnet = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $Dotnet) {
    $localSdk = Join-Path $repoRoot '.local-only\dotnet\dotnet.exe'
    $Dotnet = if (Test-Path -LiteralPath $localSdk) { $localSdk } else { 'dotnet' }
}
$project = Join-Path $PSScriptRoot 'Harbor.Windows\Harbor.Windows.csproj'
$tests = Join-Path $PSScriptRoot 'Harbor.Core.Tests\Harbor.Core.Tests.csproj'
$rid = if ($Architecture -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }

function Invoke-Dotnet([string[]]$Arguments) {
    & $Dotnet @Arguments
    if ($LASTEXITCODE -ne 0) { throw "dotnet exited with code $LASTEXITCODE." }
}

if ($Task -eq 'Test') {
    Invoke-Dotnet @('test', $tests, '-c', $Configuration, '--nologo')
    return
}
if ($Task -eq 'Publish') {
    $output = Join-Path $PSScriptRoot "artifacts\$rid"
    Invoke-Dotnet @('publish', $project, '-c', $Configuration, "-p:Platform=$Architecture", '-r', $rid, '--self-contained', 'true', '-p:PublishTrimmed=true', '-p:TrimMode=partial', '-p:DebugType=None', '-p:DebugSymbols=false', '-o', $output, '--nologo')
    Write-Host "Published Harbor to $output. Keep the entire folder together."
    return
}
Invoke-Dotnet @('build', $project, '-c', $Configuration, "-p:Platform=$Architecture", '--nologo')
$executable = Join-Path $PSScriptRoot "Harbor.Windows\bin\$Architecture\$Configuration\net10.0-windows10.0.26100.0\$rid\Harbor.Windows.exe"
if ($Task -eq 'Run') {
    & $executable
    return
}
if ($Task -eq 'Smoke') {
    $reportFolder = Join-Path $PSScriptRoot 'artifacts'
    New-Item -ItemType Directory -Force $reportFolder | Out-Null
    $report = Join-Path $reportFolder "ui-smoke-$rid-$([guid]::NewGuid().ToString('N')).txt"
    # Use fictional data in a temporary workspace, then close automatically.
    $process = Start-Process -FilePath $executable -ArgumentList @('--smoke-test', ('"' + $report + '"')) -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        throw 'Windows UI smoke test timed out.'
    }
    if (-not (Test-Path -LiteralPath $report)) { throw "Windows app exited without a smoke report (exit $($process.ExitCode))." }
    $result = Get-Content -LiteralPath $report -Raw
    Write-Host $result
    if ($result -notmatch 'PASS Windows UI smoke test') { throw 'Windows UI smoke test failed.' }
}
