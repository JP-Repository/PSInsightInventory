#requires -Version 5.1
<# Module-level offline checks. Collector/provider tests are in Test-InventoryEngine.ps1. #>
[CmdletBinding()]
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) ('PSInsightInventoryTests_'+[guid]::NewGuid().ToString('N').Substring(0,8))))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$moduleRoot=Split-Path -Parent $PSScriptRoot
$manifestPath=Join-Path $moduleRoot 'PSInsightInventory.psd1'
$null=New-Item -ItemType Directory -Path $OutputPath -Force
$checks=New-Object System.Collections.ArrayList
function Assert-Module([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
foreach($file in Get-ChildItem -LiteralPath $moduleRoot -Recurse -File | Where-Object{$_.Extension -in @('.ps1','.psm1','.psd1')}){
    $parseErrors=$null
    $null=[System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$null,[ref]$parseErrors)
    Assert-Module ($parseErrors.Count -eq 0) ('Parser: '+$file.Name)
}
$manifest=Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
Assert-Module ($manifest.Name -eq 'PSInsightInventory' -and $manifest.Version -eq [version]'1.0.0') 'Manifest identifies PSInsightInventory 1.0.0'
Assert-Module ($manifest.RequiredModules.Count -eq 0) 'No PSInsightExpl, PSInsightHTML or AD dependency during import'
$adBefore=@(Get-Module -Name ActiveDirectory).Count
$preferenceBefore=$ErrorActionPreference
Import-Module $manifestPath -Force -ErrorAction Stop
Assert-Module ($ErrorActionPreference -eq $preferenceBefore) 'Module import preserves caller error preference'
Assert-Module (@(Get-Module -Name ActiveDirectory).Count -eq $adBefore) 'Import does not load ActiveDirectory'
$commands=@(Get-Command -Module PSInsightInventory | Sort-Object Name)
Assert-Module ($commands.Count -eq 11 -and $commands[0].Name -eq 'Get-PSInsightInventory' -and $commands[6].Name -eq 'Invoke-ADInfrastructureInventory') 'Only intended public commands are exported'
$catalog=@(Get-PSInsightInventory)
Assert-Module ($catalog.Count -eq 10 -and $catalog[0].ReportSections -eq 17) 'Catalog describes the available 17-section inventory'
Assert-Module ($catalog[0].SampleCommand -match '-SampleData' -and $catalog[0].LiveCommand -match '-Domain') 'Catalog includes executable examples'
$help=Get-Help Invoke-ADInfrastructureInventory -Examples
Assert-Module (@($help.examples.example).Count -ge 3) 'Public command includes comment-based help examples'
$public=Get-Command Invoke-ADInfrastructureInventory
Assert-Module ($public.Parameters.SampleData.Aliases -contains 'Demo') 'Demo alias is available for SampleData'
$one=Invoke-ADInfrastructureInventory -SampleData -OutputPath $OutputPath
$two=Invoke-ADInfrastructureInventory -Demo -OutputPath $OutputPath
Assert-Module ($one.ModuleName -eq 'PSInsightInventory' -and $one.ModuleVersion -eq '1.0.0') 'Run result identifies module/version'
Assert-Module ($one.OutputFolder -ne $two.OutputFolder) 'Public command creates independent run directories'
Assert-Module ($one.CompleteInventory -eq 10 -and $one.PartialInventory -eq 2 -and $two.DomainControllers -eq 12) 'Both sample switches run the existing collector pipeline'
$snapshot=Get-Content -LiteralPath $two.JsonSnapshot -Raw | ConvertFrom-Json
Assert-Module ($snapshot.meta.moduleName -eq 'PSInsightInventory' -and $snapshot.meta.version -eq '1.0.0') 'Snapshot identifies module/version'
Assert-Module ($snapshot.data.collection.Count -eq 180) 'Repeated module invocations do not accumulate previous run records'
Assert-Module ($snapshot.meta.dataSource -eq 'Sample') 'Sample report stays explicitly labeled'
$html=Get-Content -LiteralPath $two.HtmlReport -Raw
Assert-Module ($html.Contains('id="brandicon" aria-hidden="true">JP</span>')) 'Report embeds the original JP monogram'
Assert-Module ($html.Contains('background:#9177db') -and $html.Contains('font-weight:750;letter-spacing:-.7px')) 'Report embeds Explorer JP logo colors and typography'
Assert-Module ($html.Contains('<div>PSInsightInventory<small>DIRECTORY INVENTORY</small></div>')) 'Report displays PSInsightInventory branding'
Assert-Module (-not $html.Contains('/*JP_BRAND_CSS*/') -and -not $html.Contains('/*DATA*/') -and -not $html.Contains('<!--FALLBACK-->')) 'Brand, data and fallback placeholders are resolved'
Assert-Module (-not [regex]::IsMatch($html,'<(?:script|img)\b[^>]*\bsrc=|<link\b[^>]*\bhref=','IgnoreCase')) 'Branded report remains self-contained'
Assert-Module (@(Get-Module -Name ActiveDirectory).Count -eq $adBefore) 'Public sample command does not load ActiveDirectory'
Import-Module $manifestPath -Force
$three=Invoke-ADInfrastructureInventory -SampleData -OutputPath $OutputPath
Assert-Module ($three.DomainControllers -eq 12 -and $three.CompleteInventory -eq 10) 'Force reload preserves sample behavior'
$mixedRejected=$false
try{Invoke-ADInfrastructureInventory -SampleData -Domain 'example.test' -OutputPath $OutputPath}catch{$mixedRejected=$true}
Assert-Module $mixedRejected 'Sample and live scope cannot be combined'
$rangeRejected=$false
try{Invoke-ADInfrastructureInventory -Domain 'example.test' -ThrottleLimit 0 -OutputPath $OutputPath}catch{$rangeRejected=$true}
Assert-Module $rangeRejected 'Public validation rejects invalid concurrency before collection'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$two.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputPath 'ModuleTestResults.json') -Encoding UTF8
$summary
