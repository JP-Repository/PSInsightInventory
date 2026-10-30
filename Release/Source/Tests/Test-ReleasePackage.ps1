#requires -Version 5.1
<# Offline release-package checks. No network, gallery, or infrastructure access. #>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path ([IO.Path]::GetTempPath()) ('PSInsightInventoryReleaseTests_' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
$null = New-Item -ItemType Directory -Path $OutputPath -Force
$checks = New-Object System.Collections.ArrayList
function Assert-Release([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    [void]$checks.Add($Name)
    Write-Host "PASS $Name"
}

$build = & (Join-Path $root 'Build-Release.ps1') -OutputPath (Join-Path $OutputPath 'Build')
Assert-Release ((Test-Path -LiteralPath $build.ModuleStage) -and (Test-Path -LiteralPath $build.GitHubZip)) 'Builder creates Gallery stage and GitHub ZIP'
Assert-Release (Test-Path -LiteralPath $build.SourceStage) 'Builder creates clean GitHub source stage'
Assert-Release (Test-Path -LiteralPath $build.ChecksumFile) 'Builder creates ZIP checksum'

$manifestPath = Join-Path $build.ModuleStage 'PSInsightInventory.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
Assert-Release ($manifest.Name -eq 'PSInsightInventory' -and $manifest.Version -eq [version]'1.0.0') 'Staged manifest identifies 1.0.0'
Assert-Release ($manifest.PowerShellVersion -eq [version]'5.1' -and $manifest.Author -eq 'Jonathan Preetham') 'Staged manifest retains target and author'
Assert-Release ([string]$manifest.PrivateData.PSData.ProjectUri -eq 'https://github.com/JP-Repository/PSInsightInventory') 'Staged manifest identifies repository'
Assert-Release ([string]$manifest.HelpInfoUri -eq 'https://github.com/JP-Repository/PSInsightInventory') 'Staged manifest identifies documentation'

Import-Module $manifestPath -Force -ErrorAction Stop
$commands = @(Get-Command -Module PSInsightInventory)
$catalog = @(Get-PSInsightInventory)
Assert-Release ($commands.Count -eq 11 -and $catalog.Count -eq 10) 'Staged module exports catalog plus ten inventories'
Assert-Release (@($catalog | Where-Object { $_.Version -ne '1.0.0' }).Count -eq 0) 'Catalog versions are reconciled'

$demoOutput = Join-Path $OutputPath 'Demos'
foreach ($command in $catalog.Command) {
    $result = & $command -Demo -Quiet -OutputPath $demoOutput
    $html = Get-Content -LiteralPath $result.HtmlReport -Raw
    $hasAbout = $html.Contains('id="psi-help-about"') -and
        $html.Contains('href="https://www.linkedin.com/in/jonathan-preetham"') -and
        $html.Contains('href="https://github.com/JP-Repository/PSInsightInventory"') -and
        $html.Contains('href="mailto:Jonathan.Preetham@outlook.com"') -and
        $html.Contains('>Project documentation</a>')
    Assert-Release $hasAbout ("HTML Help & About links: $command")
}

$forbiddenDirectories = @('Examples', 'Tests', 'Reports', 'Logs', 'TestResults', '.git')
$badDirectories = @(Get-ChildItem -LiteralPath $build.ModuleStage -Recurse -Directory | Where-Object { $forbiddenDirectories -contains $_.Name })
Assert-Release ($badDirectories.Count -eq 0) 'Package excludes generated and maintainer directories'

$forbiddenExtensions = @('.clixml', '.credential', '.env', '.jsonl', '.key', '.log', '.nupkg', '.p12', '.pem', '.pfx', '.zip')
$packagedFiles = @(Get-ChildItem -LiteralPath $build.ModuleStage -Recurse -File)
$badFiles = @($packagedFiles | Where-Object { $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() })
Assert-Release ($badFiles.Count -eq 0) 'Package excludes generated and sensitive file types'
Assert-Release (-not (Test-Path -LiteralPath (Join-Path $build.ModuleStage 'Build-Release.ps1'))) 'Package excludes maintainer build tooling'

$sourceBadFiles = @(Get-ChildItem -LiteralPath $build.SourceStage -Recurse -File | Where-Object {
    $_.Extension.ToLowerInvariant() -in @('.clixml', '.credential', '.env', '.jsonl', '.key', '.log', '.nupkg', '.p12', '.pem', '.pfx', '.zip') -or
    $_.Name -in @('Offline-TestResults.json', 'OfflineValidationResults.json', 'MockDebug.json')
})
Assert-Release ($sourceBadFiles.Count -eq 0) 'GitHub source stage excludes logs, test output, packages, and sensitive file types'

$text = ($packagedFiles | Where-Object { $_.Extension -in @('.css', '.html', '.json', '.md', '.ps1', '.psd1', '.psm1', '.txt') } | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
Assert-Release ($text -notmatch '(?i)cabot-corp|MDC-NTB|ATLANTA-NTB|/workspace/scratch|BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY') 'Package has no known internal examples, build paths, or private keys'

$actualHash = (Get-FileHash -LiteralPath $build.GitHubZip -Algorithm SHA256).Hash.ToLowerInvariant()
$recordedHash = ((Get-Content -LiteralPath $build.ChecksumFile -Raw).Trim() -split '\s+')[0]
Assert-Release ($actualHash -eq $recordedHash -and $actualHash -eq $build.Sha256) 'Published checksum matches ZIP'

$expanded = Join-Path $OutputPath 'Expanded'
Expand-Archive -LiteralPath $build.GitHubZip -DestinationPath $expanded -Force
$expandedManifest = Join-Path (Join-Path $expanded 'PSInsightInventory') 'PSInsightInventory.psd1'
$null = Test-ModuleManifest -Path $expandedManifest -ErrorAction Stop
Assert-Release (Test-Path -LiteralPath $expandedManifest) 'GitHub ZIP preserves the module folder layout'

$summary = [pscustomobject]@{
    Status = 'Passed'
    Checks = $checks.Count
    Runtime = $PSVersionTable.PSVersion.ToString()
    WindowsPowerShell51Tested = ($PSVersionTable.PSVersion.Major -eq 5)
    ModuleStage = $build.ModuleStage
    SourceStage = $build.SourceStage
    GitHubZip = $build.GitHubZip
    Sha256 = $build.Sha256
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputPath 'ReleasePackageTestResults.json') -Encoding UTF8
$summary
