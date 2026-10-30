#requires -Version 5.1
<#
.SYNOPSIS
Creates allowlisted PSInsightInventory release artifacts.
.DESCRIPTION
Builds a clean module folder suitable for Publish-Module and a GitHub release ZIP.
Tests, examples, generated reports/logs, validation output, source-control metadata,
and secret-bearing file types are excluded by construction.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'Release')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$manifestPath = Join-Path $PSScriptRoot 'PSInsightInventory.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
if ($manifest.Name -ne 'PSInsightInventory' -or $manifest.Version -ne [version]'1.0.0') {
    throw 'Release build requires the PSInsightInventory 1.0.0 manifest.'
}

$moduleStage = Join-Path $OutputPath 'PSInsightInventory'
$sourceStage = Join-Path $OutputPath 'Source'
$zipPath = Join-Path $OutputPath 'PSInsightInventory-1.0.0.zip'
$checksumPath = $zipPath + '.sha256'

foreach ($stage in @($moduleStage, $sourceStage)) {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
foreach ($path in @($zipPath, $checksumPath)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
$null = New-Item -ItemType Directory -Path $moduleStage -Force
$null = New-Item -ItemType Directory -Path $sourceStage -Force

$files = @(
    'PSInsightInventory.psd1',
    'PSInsightInventory.psm1',
    'LICENSE',
    'README.md',
    'CHANGELOG.md',
    'RELEASE-NOTES.md',
    'VALIDATION.md',
    'BRANDING.md',
    'CONSOLE-DISPLAY.md',
    'COMPUTER-INVENTORY.md',
    'DNS-INVENTORY.md',
    'FOREST-INVENTORY.md',
    'GROUP-INVENTORY.md',
    'GROUP-POLICY-INVENTORY.md',
    'ORGANIZATIONAL-UNIT-INVENTORY.md',
    'SITES-AND-SERVICES.md',
    'TRUST-INVENTORY.md',
    'USER-INVENTORY.md'
)
$directories = @('Assets', 'Private', 'Public', 'Templates')

foreach ($relativePath in $files) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination (Join-Path $moduleStage $relativePath)
}
foreach ($relativePath in $directories) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination $moduleStage -Recurse
}

$sourceFiles = @(
    '.gitignore', 'Build-Release.ps1', 'PSInsightInventory.psd1', 'PSInsightInventory.psm1',
    'LICENSE', 'README.md', 'CHANGELOG.md', 'RELEASE-NOTES.md', 'RELEASE.md', 'VALIDATION.md',
    'BRANDING.md', 'CONSOLE-DISPLAY.md', 'COMPUTER-INVENTORY.md', 'DNS-INVENTORY.md',
    'FOREST-INVENTORY.md', 'GROUP-INVENTORY.md', 'GROUP-POLICY-INVENTORY.md',
    'ORGANIZATIONAL-UNIT-INVENTORY.md', 'SITES-AND-SERVICES.md', 'TRUST-INVENTORY.md',
    'USER-INVENTORY.md'
)
foreach ($relativePath in $sourceFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination (Join-Path $sourceStage $relativePath)
}
foreach ($relativePath in @('Assets', 'Examples', 'Private', 'Public', 'Templates', 'Tests')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination $sourceStage -Recurse
}

$forbiddenExtensions = @('.clixml', '.credential', '.env', '.key', '.log', '.nupkg', '.p12', '.pem', '.pfx', '.zip')
$forbiddenNames = @('Reports', 'Logs', 'TestResults', '.git', '.github', 'Tests', 'Examples')
$packagedFiles = @(Get-ChildItem -LiteralPath $moduleStage -Recurse -File)
$badFiles = @($packagedFiles | Where-Object { $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() })
$badDirectories = @(Get-ChildItem -LiteralPath $moduleStage -Recurse -Directory | Where-Object { $forbiddenNames -contains $_.Name })
if ($badFiles.Count -or $badDirectories.Count) {
    throw 'The staged package contains a forbidden generated or sensitive path.'
}

$null = Test-ModuleManifest -Path (Join-Path $moduleStage 'PSInsightInventory.psd1') -ErrorAction Stop
Compress-Archive -Path $moduleStage -DestinationPath $zipPath -CompressionLevel Optimal
$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
($hash.Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zipPath)) |
    Set-Content -LiteralPath $checksumPath -Encoding Ascii

[pscustomobject][ordered]@{
    SourceStage = $sourceStage
    ModuleStage = $moduleStage
    GitHubZip = $zipPath
    Sha256 = $hash.Hash.ToLowerInvariant()
    ChecksumFile = $checksumPath
    FileCount = $packagedFiles.Count
}
