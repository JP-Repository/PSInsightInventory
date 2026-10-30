#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) ('ForestInventoryTests_'+[guid]::NewGuid().ToString('N').Substring(0,8))))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$null=New-Item -ItemType Directory -Path $OutputPath -Force
$checks=New-Object collections.ArrayList
function Assert-Forest([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Forest (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Module exports catalog and three inventory commands'
Assert-Forest (@(Get-PSInsightInventory).Count -eq 10) 'Catalog includes all inventory types'
Assert-Forest (@((Get-Help Invoke-ADForestInventory -Examples).examples.example).Count -eq 3) 'Forest command provides examples'
$result=Invoke-ADForestInventory -Demo -OutputPath $OutputPath
$p=Get-Content -LiteralPath $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Forest ($result.ModuleVersion -eq '1.0.0' -and $result.DomainReferences -eq 2 -and $result.DomainDetailsCollected -eq 2) 'Sample forest/domain counts agree'
Assert-Forest ($result.QueriesCollected -eq 6 -and $p.meta.expectedQueries -eq 6) 'Query denominator is two forest queries plus two per domain'
Assert-Forest ($p.meta.connectionDomain -eq 'corp.example.test' -and $p.meta.forest -eq 'example.test') 'Connection domain and forest scope remain distinct'
Assert-Forest ($p.data.fsmo.Count -eq 8) 'Forest and domain FSMO assignments are separate'
Assert-Forest ($p.data.levels.Count -eq 3 -and $p.data.hierarchy[1].'Parent domain' -eq 'example.test') 'Functional levels and hierarchy are captured'
Assert-Forest ($p.data.suffixes.Count -eq 2) 'Additional UPN and SPN lists are retained'
Assert-Forest ($p.data.contexts.Count -eq 6 -and $p.data.partitions.Count -eq 5) 'Hosted contexts and forest partition references remain separate'
Assert-Forest ($p.data.containers.Count -eq 12 -and $p.data.policies.Count -eq 2) 'Default containers and default domain policies are retained'
Assert-Forest ($p.data.policies[0].'Maximum age' -eq '42.00:00:00' -and $p.data.policies[0].'Reversible encryption' -eq $false) 'Policy duration and false values are preserved'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-Forest (@(Import-Csv -LiteralPath (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV/JSON agreement: '+$key)}
$html=Get-Content -LiteralPath $result.HtmlReport -Raw
Assert-Forest ($html.Contains('>JP</span>') -and $html.Contains('Forest &amp; Domain Inventory')) 'JP branding and static forest title are embedded'
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path (Join-Path $root 'Private/Sites') $f)}
foreach($f in @('Collector.ps1','Model.ps1')){. (Join-Path (Join-Path $root 'Private/Forest') $f)}
function Fixture {Get-Content -LiteralPath (Join-Path $root 'Assets/Forest.sample.json') -Raw|ConvertFrom-Json}
$fixture=Fixture;$fixture.envelopes[2].Status='Failed';$fixture.envelopes[2].ErrorMessage='Synthetic domain access denial'
$partial=ConvertTo-PSIForestModel $fixture.context $fixture.envelopes
Assert-Forest ($partial.Data.domains.Count -eq 2 -and $partial.DomainDetailsCollected -eq 1) 'Failed domain remains visible from forest membership reference'
Assert-Forest ($null -eq $partial.Data.domains[0].'Functional level' -and $null -eq $partial.Data.fsmo[2].Owner) 'Failed domain values remain unknown, not invented'
Assert-Forest ($partial.Data.domains[0].'Query status' -eq 'Failed') 'Failed domain retains collection status'
$fixture=Fixture;$fixture.envelopes[3].Status='Failed';$fixture.envelopes[3].ErrorMessage='Synthetic policy denial'
$partial=ConvertTo-PSIForestModel $fixture.context $fixture.envelopes
Assert-Forest ($partial.PoliciesCollected -eq 1 -and $null -eq $partial.Data.policies[0].'Minimum length') 'Policy failure does not become a zero-length policy'
Assert-Forest ($partial.DomainDetailsCollected -eq 2) 'Policy failure does not discard domain identity'
$fixture=Fixture;$fixture.envelopes[1].Records=@();$empty=ConvertTo-PSIForestModel $fixture.context $fixture.envelopes
Assert-Forest ($empty.Data.partitions.Count -eq 0 -and $empty.Coverage.partitions) 'Successful empty partition query remains collected'
$bad=$false;try{$null=ConvertTo-PSIForestModel $fixture.context @($fixture.envelopes[0..4])}catch{$bad=$true};Assert-Forest $bad 'Missing query outcome is rejected'
$bad=$false;try{$null=ConvertTo-PSIForestModel $fixture.context (@($fixture.envelopes)+@($fixture.envelopes[0]))}catch{$bad=$true};Assert-Forest $bad 'Duplicate query outcome is rejected'
$fixture=Fixture;$hostile='=1+1 </script> <tag> "quoted"';$fixture.envelopes[0].Records[0].UPNSuffixes=@($hostile)
$model=ConvertTo-PSIForestModel $fixture.context $fixture.envelopes
$export=Join-Path $OutputPath 'Hostile';$null=New-Item -ItemType Directory -Path $export -Force
$paths=Export-PSISitesReport $model $p.meta $root $export 'Forest.html' 'Forest-And-Domains'
$csv=Import-Csv -LiteralPath (Join-Path $paths.CsvFolder 'suffixes.csv')
Assert-Forest ($csv[0].Name -eq ("'"+$hostile)) 'CSV protects formula-leading suffix strings'
Assert-Forest ((ConvertTo-PSISafeJson $model) -notmatch '</script>') 'Embedded JSON protects closing-script payloads'

# Exercise actual AD collector with mocks, including independent policy failure and cross-domain pinning.
$fixture=Fixture
function Mock-Collector([switch]$DenyPolicy){
    function Import-Module {param($Name,$ErrorAction)}
    function Get-ADRootDSE {param($Server,$Credential,$ErrorAction)
        $n=if($Server -in @('example.test','dc01.example.test')){'example.test'}else{'corp.example.test'}
        $row=($fixture.envelopes|Where-Object{$_.Key -eq ('domain:'+$n)}).Records[0].Root
        $row
    }
    function Get-ADDomain {param($Server,$Credential,$ErrorAction)
        if($Server -notin @('dc01.example.test','dc01.corp.example.test')){throw 'Domain read was not pinned to a DC'}
        $n=if($Server -eq 'dc01.example.test'){'example.test'}else{'corp.example.test'}
        ($fixture.envelopes|Where-Object{$_.Key -eq ('domain:'+$n)}).Records[0].Domain
    }
    function Get-ADForest {param($Server,$Credential,$ErrorAction) $fixture.envelopes[0].Records[0]}
    function Get-ADObject {param($SearchBase,$SearchScope,$LDAPFilter,$Properties,$Server,$Credential,$ErrorAction)
        if($Server -ne 'dc01.corp.example.test' -or $SearchScope -ne 'OneLevel' -or $LDAPFilter -ne '(objectClass=crossRef)'){throw 'Partition query pin/scope mismatch'}
        $fixture.envelopes[1].Records
    }
    function Get-ADDefaultDomainPasswordPolicy {param($Identity,$Server,$Credential,$ErrorAction)
        if($Server -notin @('dc01.example.test','dc01.corp.example.test')){throw 'Policy read was not pinned'}
        if($DenyPolicy -and $Identity -eq 'corp.example.test'){throw 'Synthetic policy access denied'}
        ($fixture.envelopes|Where-Object{$_.Key -eq ('policy:'+$Identity)}).Records[0]
    }
    & $script:PSIForestCollector 'corp.example.test' $null
}
$live=@(Mock-Collector)
Assert-Forest ($live.Count -eq 7 -and $live[0].Kind -eq 'Context') 'Mock live collector returns context plus dynamic query outcomes'
$live|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutputPath 'MockDebug.json') -Encoding UTF8
Assert-Forest (@($live|Where-Object{$_.Kind -eq 'Section' -and $_.Status -eq 'Succeeded'}).Count -eq 6) 'Pinned forest and member-domain mock queries succeed'
$mockModel=ConvertTo-PSIForestModel $live[0] @($live|Where-Object{$_.Kind -eq 'Section'})
Assert-Forest ($mockModel.DomainDetailsCollected -eq 2 -and $mockModel.Data.fsmo.Count -eq 8) 'Live property bags use the same model pipeline'
$denied=@(Mock-Collector -DenyPolicy)
Assert-Forest (@($denied|Where-Object{$_.Kind -eq 'Section' -and $_.Status -eq 'Failed'}).Count -eq 1) 'One policy denial remains independent'
$worker={param($Domain,$Credential)
    [pscustomobject]@{Kind='Context';Forest='example.test';RootDomain='example.test';Domain='example.test';Server='mock.example.test';Domains=@('example.test','corp.example.test');ConfigurationNC='CN=Configuration,DC=example,DC=test';Root=$null}
    [pscustomobject]@{Kind='Section';Key='partitions';Target='example.test';SourceDC='mock.example.test';Status='Succeeded';Records=@();Method='Offline timeout';CollectedAt='2026-10-29T00:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=$null}
    Start-Sleep -Seconds 30
}
$timeout=Invoke-PSIForestCollection -Domain example.test -Worker $worker -TimeoutSeconds 5
Assert-Forest ($timeout.Envelopes.Count -eq 6 -and @($timeout.Envelopes|Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 5) 'Timeout keeps completed results and dynamically fills missing outcomes'
Assert-Forest (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Forest collector cleans up local jobs'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputPath 'ForestTestResults.json') -Encoding UTF8
$summary
