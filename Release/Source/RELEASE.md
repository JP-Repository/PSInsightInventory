# Release procedure

This procedure is intentionally split into local validation, GitHub publication, and PowerShell Gallery publication. Do not push or publish until the local results have been reviewed and explicitly approved.

## 1. Build and validate locally

From the project root:

```powershell
$build = .\Build-Release.ps1
Test-ModuleManifest -Path "$($build.ModuleStage)\PSInsightInventory.psd1"
.\Tests\Test-ReleasePackage.ps1
```

Run every offline suite listed in `VALIDATION.md`. Native Windows PowerShell 5.1 and live AD checks must be reported separately and must not be inferred from PowerShell 7 demo tests.

Review the staged source and module contents:

```powershell
Get-ChildItem -LiteralPath $build.SourceStage -Recurse -Force
Get-ChildItem -LiteralPath $build.ModuleStage -Recurse -Force
Get-Content -LiteralPath $build.ChecksumFile
```

The module stage must not contain `Examples`, `Tests`, `Reports`, `Logs`, test output, ZIP/NUPKG files, credentials, certificates, or tokens.

## 2. Publish source to GitHub

The repository already has a `main` branch with an initial README and the same MIT license. Preserve that commit history by working from a clean clone after approval:

```powershell
$repository = 'https://github.com/JP-Repository/PSInsightInventory.git'
$clone = Join-Path ([IO.Path]::GetTempPath()) 'PSInsightInventory-publish'
git clone $repository $clone
Get-ChildItem -LiteralPath $build.SourceStage -Force |
    Copy-Item -Destination $clone -Recurse -Force
git -C $clone status --short
git -C $clone diff --check
git -C $clone add --all
git -C $clone diff --cached --stat
git -C $clone diff --cached --check
git -C $clone commit -m 'Release PSInsightInventory 1.0.0'
git -C $clone push origin main
```

Do not proceed if the staged diff contains generated output, credentials, tokens, unexpected environment names, or unrelated files.

Create and push the release tag only after the main-branch push succeeds:

```powershell
git -C $clone tag -a v1.0.0 -m 'PSInsightInventory 1.0.0'
git -C $clone push origin v1.0.0
```

Create the GitHub release and attach the clean module ZIP and checksum:

```powershell
gh release create v1.0.0 `
    $build.GitHubZip `
    $build.ChecksumFile `
    --repo JP-Repository/PSInsightInventory `
    --title 'PSInsightInventory 1.0.0' `
    --notes-file (Join-Path $build.SourceStage 'RELEASE-NOTES.md')
```

Verify the release page, asset names, checksum, source archive, README links, and tag before publishing to PowerShell Gallery.

## 3. Publish to PowerShell Gallery

First confirm that 1.0.0 is not already published:

```powershell
Find-Module -Name PSInsightInventory -Repository PSGallery -AllVersions
```

Use the allowlisted module stage, not the repository root. Read the API key securely so it is not stored in source, a script, command history, or a committed file:

```powershell
$secureKey = Read-Host 'PowerShell Gallery API key' -AsSecureString
$keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try {
    $galleryKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    Publish-Module `
        -Path $build.ModuleStage `
        -Repository PSGallery `
        -NuGetApiKey $galleryKey `
        -Verbose
}
finally {
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
    Remove-Variable galleryKey, secureKey, keyPointer -ErrorAction SilentlyContinue
}
```

Never place the API key in the manifest, repository, build output, environment file, transcript, issue, release notes, or CI configuration committed to the repository.

Verify the published package in a fresh temporary module path:

```powershell
Find-Module -Name PSInsightInventory -RequiredVersion 1.0.0 -Repository PSGallery
$verifyPath = Join-Path ([IO.Path]::GetTempPath()) 'PSInsightInventory-gallery-verify'
Save-Module -Name PSInsightInventory -RequiredVersion 1.0.0 -Repository PSGallery -Path $verifyPath
Test-ModuleManifest -Path (Join-Path $verifyPath 'PSInsightInventory\1.0.0\PSInsightInventory.psd1')
```

Record the GitHub release URL and Gallery package URL after both are live. Do not claim native Windows PowerShell 5.1 or live AD validation unless those checks were actually performed.
