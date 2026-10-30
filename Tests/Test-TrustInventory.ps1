#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) ('TrustInventoryTests_'+[guid]::NewGuid().ToString('N').Substring(0,8))))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$null=New-Item -ItemType Directory -Path $OutputPath -Force
$checks=New-Object collections.ArrayList
function Assert-Trust([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Trust (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Catalog and four inventory commands are exported'
Assert-Trust (@(Get-PSInsightInventory).Count -eq 10) 'Catalog includes Trust Inventory'
Assert-Trust (@((Get-Help Invoke-ADTrustInventory -Examples).examples.example).Count -eq 3) 'Trust command provides examples'
$result=Invoke-ADTrustInventory -Demo -OutputPath $OutputPath
$p=Get-Content -LiteralPath $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Trust ($result.DomainsCollected -eq 2 -and $result.ObservedTrustObjects -eq 5) 'Demo collects two local domains and five TDO observations'
Assert-Trust ($p.data.partners.Count -eq 5 -and $p.data.trusts.Count -eq 5) 'Partner summaries remain distinct from local TDO observations'
Assert-Trust ($p.data.directions[1].Direction -eq 'Outbound' -and $p.data.directions[1].Meaning -like 'Observed domain trusts*') 'Outbound meaning uses the observed-domain perspective'
Assert-Trust ($p.data.directions[2].Direction -eq 'Inbound' -and $p.data.directions[2].Meaning -like 'Partner trusts*') 'Inbound meaning uses the observed-domain perspective'
Assert-Trust ($p.data.directions[4].Direction -eq 'Disabled (0)') 'Zero direction flags remain explicit'
Assert-Trust ($p.data.settings[1].'SIDFilteringForestAware reported' -eq $true -and $p.data.settings[1].'SIDFilteringQuarantined reported' -eq $false) 'SID-filtering properties remain separate'
Assert-Trust ($null -eq $p.data.settings[4].'Selective authentication reported') 'Missing reported booleans remain unknown'
Assert-Trust ($p.data.trusts[0].'Protocol type reported' -eq 'Uplevel') 'Native protocol type is retained without a case-colliding raw property'
foreach($k in $p.sections.PSObject.Properties.Name){Assert-Trust (@(Import-Csv -LiteralPath (Join-Path $result.CsvFolder ($k+'.csv'))).Count -eq @($p.data.$k).Count) ('CSV/JSON agreement: '+$k)}
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path (Join-Path $root 'Private/Sites') $f)}
. (Join-Path (Join-Path $root 'Private/Forest') 'Collector.ps1')
foreach($f in @('Collector.ps1','Model.ps1')){. (Join-Path (Join-Path $root 'Private/Trusts') $f)}
function Fixture {Get-Content -LiteralPath (Join-Path $root 'Assets/Trusts.sample.json') -Raw|ConvertFrom-Json}
$fixture=Fixture;$fixture.envelopes[0].Status='Failed';$fixture.envelopes[0].ErrorMessage='Synthetic denied domain'
$partial=ConvertTo-PSITrustModel $fixture.context $fixture.envelopes
Assert-Trust ($partial.Data.domains.Count -eq 2 -and $null -eq $partial.Data.domains[0].'Observed TDO records') 'Failed domain retains identity with unknown count'
Assert-Trust ($partial.Data.trusts.Count -eq 2 -and -not $partial.Coverage.trusts) 'Partial trust data survives without a completeness claim'
$fixture=Fixture;$fixture.envelopes[0].Records=@();$empty=ConvertTo-PSITrustModel $fixture.context $fixture.envelopes
Assert-Trust ($empty.Data.domains[0].'Observed TDO records' -eq 0 -and $empty.Coverage.trusts) 'Successful zero-row trust query is valid empty inventory'
$fixture=Fixture;$fixture.envelopes[0].Records[0].trustDirection='7';$fixture.envelopes[0].Records[0].trustAttributes=$null
$unknown=ConvertTo-PSITrustModel $fixture.context $fixture.envelopes
Assert-Trust ($unknown.Data.trusts[0].Direction -eq 'Unknown (7)' -and $null -eq $unknown.Data.trusts[0].'Non-transitive flag') 'Unknown direction and absent raw flags are not guessed'
$bad=$false;try{$null=ConvertTo-PSITrustModel $fixture.context @($fixture.envelopes[0])}catch{$bad=$true};Assert-Trust $bad 'Missing query outcome is rejected'
$bad=$false;try{$null=ConvertTo-PSITrustModel $fixture.context (@($fixture.envelopes)+@($fixture.envelopes[0]))}catch{$bad=$true};Assert-Trust $bad 'Duplicate query outcome is rejected'
$fixture=Fixture;$hostile='=1+1 </script> <tag> "quoted"';$fixture.envelopes[0].Records[0].trustPartner=$hostile
$model=ConvertTo-PSITrustModel $fixture.context $fixture.envelopes
$folder=Join-Path $OutputPath 'Hostile';$null=New-Item -ItemType Directory -Path $folder -Force
$paths=Export-PSISitesReport $model $p.meta $root $folder 'Trusts.html' 'Trust-Inventory'
$csv=Import-Csv -LiteralPath (Join-Path $paths.CsvFolder 'trusts.csv')
Assert-Trust ($csv[0].Partner -eq ("'"+$hostile)) 'CSV protects formula-leading partner strings'
Assert-Trust ((ConvertTo-PSISafeJson $model) -notmatch '</script>') 'Embedded JSON protects closing-script payloads'

# Mock the actual collector: verify pinning, safe properties, no partner-side requests and scope guard.
$fixture=Fixture
function Mock-Collector([switch]$DenyChild,[switch]$WrongDN){
    function Import-Module {param($Name,$ErrorAction)}
    function Get-ADRootDSE {param($Server,$Credential,$ErrorAction)
        if($Server -notin @('example.test','corp.example.test','dc01.example.test','dc01.corp.example.test')){throw 'A remote partner was contacted'}
        [pscustomobject]@{dnsHostName=if($Server -in @('example.test','dc01.example.test')){'dc01.example.test'}else{'dc01.corp.example.test'};configurationNamingContext='CN=Configuration,DC=example,DC=test'}
    }
    function Get-ADDomain {param($Server,$Credential,$ErrorAction)
        if($Server -notin @('dc01.example.test','dc01.corp.example.test')){throw 'Domain query not pinned'}
        $dns=if($Server -eq 'dc01.example.test'){'example.test'}else{'corp.example.test'}
        [pscustomobject]@{DNSRoot=$dns;Forest='example.test';DistinguishedName=if($dns -eq 'example.test'){'DC=example,DC=test'}else{'DC=corp,DC=example,DC=test'}}
    }
    function Get-ADForest {param($Server,$Credential,$ErrorAction) [pscustomobject]@{Name='example.test';RootDomain='example.test';Domains=@('example.test','corp.example.test')}}
    function Get-ADTrust {param($Filter,$Properties,$Server,$Credential,$ErrorAction)
        if($Filter -ne '*' -or $Properties -contains '*' -or @($Properties|Where-Object{$_ -match 'trustAuth'}).Count){throw 'Unexpected or sensitive property request'}
        if($Server -notin @('dc01.example.test','dc01.corp.example.test')){throw 'Trust read not pinned to a local-forest DC'}
        if($DenyChild -and $Server -eq 'dc01.corp.example.test'){throw 'Synthetic access denied'}
        $index=if($Server -eq 'dc01.example.test'){0}else{1}
        foreach($row in $fixture.envelopes[$index].Records){
            $copy=$row|ConvertTo-Json -Depth 8|ConvertFrom-Json
            $copy|Add-Member -NotePropertyName TrustType -NotePropertyValue $row.NativeProtocolType
            $copy|Add-Member -NotePropertyName trustAuthIncoming -NotePropertyValue 'MUST-NOT-BE-RETAINED'
            if($WrongDN){$copy.DistinguishedName='CN=wrong,CN=System,DC=partner,DC=test'}
            $copy
        }
    }
    & $script:PSITrustCollector 'corp.example.test' $null
}
$live=@(Mock-Collector)
Assert-Trust ($live.Count -eq 3 -and @($live|Where-Object{$_.Kind -eq 'Section' -and $_.Status -eq 'Succeeded'}).Count -eq 2) 'Actual collector uses pinned local-domain queries and safe properties'
Assert-Trust (($live|ConvertTo-Json -Depth 20) -notmatch 'MUST-NOT-BE-RETAINED') 'Explicit retained-property whitelist excludes unexpected secret-like properties'
$liveModel=ConvertTo-PSITrustModel $live[0] @($live|Where-Object{$_.Kind -eq 'Section'})
Assert-Trust ($liveModel.Data.trusts.Count -eq 5 -and $liveModel.Data.trusts[0].'Protocol type reported' -eq 'Uplevel') 'Native protocol survives collector/model pipeline'
$denied=@(Mock-Collector -DenyChild)
Assert-Trust (@($denied|Where-Object{$_.Kind -eq 'Section' -and $_.Status -eq 'Failed'}).Count -eq 1) 'One domain failure does not stop independent observations'
$outside=@(Mock-Collector -WrongDN)
Assert-Trust (@($outside|Where-Object{$_.Kind -eq 'Section' -and $_.Status -eq 'Failed'}).Count -eq 2) 'Out-of-domain TDOs fail the scope guard'
$worker={param($Domain,$Credential)
    [pscustomobject]@{Kind='Context';Forest='example.test';Domain='example.test';Server='mock.example.test';Domains=@('example.test','corp.example.test')}
    [pscustomobject]@{Kind='Section';Key='trust:example.test';Target='example.test';SourceDC='mock.example.test';Status='Succeeded';Records=@();Method='Offline';CollectedAt='2026-10-29T00:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=$null}
    Start-Sleep -Seconds 30
}
$timeout=Invoke-PSIForestCollection -Domain example.test -Worker $worker -QueryPlan Trusts -TimeoutSeconds 5
Assert-Trust ($timeout.Envelopes.Count -eq 2 -and @($timeout.Envelopes|Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 1) 'Trust query plan retains completed data and fills missing domain outcome on timeout'
Assert-Trust (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Trust collection removes its jobs'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputPath 'TrustTestResults.json') -Encoding UTF8
$summary
