#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) ('SitesInventoryTests_'+[guid]::NewGuid().ToString('N').Substring(0,8))))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$null=New-Item -ItemType Directory -Path $OutputPath -Force
$checks=New-Object collections.ArrayList
function Assert-Sites([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Sites (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Module exports four intended commands'
Assert-Sites (@(Get-PSInsightInventory).Count -eq 10) 'Catalog includes all inventory types'
Assert-Sites (@((Get-Help Invoke-ADSitesAndServicesInventory -Examples).examples.example).Count -eq 3) 'Sites command supplies help examples'
function Invoke-IsolatedSample {
    function Start-Job {throw 'Sample invoked a worker'}
    function Import-Module {throw 'Sample imported a module'}
    function Invoke-Command {throw 'Sample invoked WinRM'}
    function Get-ADObject {throw 'Sample queried AD'}
    Invoke-ADSitesAndServicesInventory -Demo -OutputPath $OutputPath
}
$result=Invoke-IsolatedSample
$p=Get-Content -LiteralPath $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Sites ($result.Scope -eq 'Forest-wide' -and $p.meta.connectionDomain -eq 'corp.example.test' -and $p.meta.forest -eq 'example.test') 'Connection domain and forest-wide scope remain explicit'
Assert-Sites ($result.QueriesCollected -eq 8 -and $result.QueriesUnavailable -eq 0) 'Sample does not call infrastructure and collects eight fixture categories'
Assert-Sites ($p.data.sites.Count -eq 4 -and @($p.data.sites | Where-Object{$_.'DC objects' -eq 0}).Count -eq 1) 'Sites with no DC objects are retained'
Assert-Sites ($p.data.subnets.Count -eq 5) 'All subnet rows are retained'
Assert-Sites (@($p.data.subnets | Where-Object{$_.Assignment -like 'Unassigned*'}).Count -eq 1) 'Absent subnet assignment is explicit'
Assert-Sites (@($p.data.subnets | Where-Object{$_.Assignment -eq 'Unresolved reference'}).Count -eq 1) 'Unresolved site references retain their DN'
Assert-Sites ($p.data.links.Count -eq 3 -and $p.data.linkMembers.Count -eq 6) 'Site-link inventory preserves every membership'
Assert-Sites ($p.data.bridges.Count -eq 1 -and $p.data.bridgeMembers.Count -eq 2) 'Bridge inventory preserves every member link'
Assert-Sites ($p.data.servers.Count -eq 3 -and $p.data.settings.Count -eq 4) 'Directory servers and per-site settings are separate'
Assert-Sites ($p.data.transports[0].'Bridge all site links' -eq $true -and $p.data.transports[1].'Bridge all site links' -eq $false) 'Transport bridges-required bit is inverted for bridge-all display'
Assert-Sites ($p.data.links[0].'Change notification' -eq $true -and $p.data.links[0].'Two-way sync' -eq $false) 'Known link options are decoded without changing raw values'
Assert-Sites ($p.data.schedules.Count -eq 7) 'Link and NTDS site-setting schedules are both retained'
Assert-Sites ($p.data.schedules[0].'Allowed hours UTC' -eq 168 -and $p.data.schedules[2].'Allowed hours UTC' -eq 84) 'Stored schedule masks yield correct weekly permitted-hour totals'
Assert-Sites ($p.data.schedules[1].'Parse status' -eq 'Not set or not returned' -and $null -eq $p.data.schedules[1].'Allowed hours UTC') 'Missing schedule remains unknown rather than always available'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-Sites (@(Import-Csv -LiteralPath (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV agrees with JSON: '+$key)}
$html=Get-Content -LiteralPath $result.HtmlReport -Raw
Assert-Sites ($html.Contains('>JP</span>') -and $html.Contains('PSInsightInventory')) 'JP branding is embedded'
Assert-Sites (-not $html.Contains('/*DATA*/') -and -not $html.Contains('/*JP_BRAND_CSS*/')) 'Report placeholders resolve'
Assert-Sites (-not [regex]::IsMatch($html,'<(?:script|img)\b[^>]*\bsrc=|<link\b[^>]*\bhref=','IgnoreCase')) 'Sites report uses no external assets'
foreach($file in @('Helpers.ps1','Collector.ps1','Model.ps1','Export.ps1')){. (Join-Path (Join-Path $root 'Private/Sites') $file)}
$fixture=Get-Content -LiteralPath (Join-Path $root 'Assets/SitesAndServices.sample.json') -Raw|ConvertFrom-Json
function New-Envelopes {
    foreach($key in @('sites','subnets','links','bridges','servers','settings','transports','ntds')){[pscustomobject]@{Key=$key;Status='Succeeded';Records=@($fixture.raw.$key);Method='Mock';CollectedAt='2026-10-29T10:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=$null}}
}
$envelopes=@(New-Envelopes);($envelopes|Where-Object{$_.Key -eq 'ntds'}).Status='Failed'
$partial=ConvertTo-PSISitesModel $fixture.context $envelopes
Assert-Sites (@($partial.Data.sites | Where-Object{$null -ne $_.'DC objects'}).Count -eq 0) 'Failed NTDS query leaves DC counts unknown, not zero'
Assert-Sites ($partial.Data.servers.Count -eq 3 -and $null -eq $partial.Data.servers[0].'NTDS object present') 'Other successful data survives a failed NTDS query'
$envelopes=@(New-Envelopes);($envelopes|Where-Object{$_.Key -eq 'sites'}).Status='Failed'
$partial=ConvertTo-PSISitesModel $fixture.context $envelopes
Assert-Sites ($partial.Data.sites.Count -eq 0 -and $partial.Data.subnets.Count -eq 5 -and $partial.Data.subnets[0].Assignment -eq 'Site lookup unavailable') 'Failed site lookup preserves subnet references without false resolution'
$envelopes=@(New-Envelopes);($envelopes|Where-Object{$_.Key -eq 'bridges'}).Records=@()
$empty=ConvertTo-PSISitesModel $fixture.context $envelopes
Assert-Sites ($empty.Data.bridges.Count -eq 0 -and $empty.Coverage.bridges) 'Successful empty bridge query remains collected'
$duplicateRejected=$false;try{$null=ConvertTo-PSISitesModel $fixture.context (@(New-Envelopes)+@((New-Envelopes)[0]))}catch{$duplicateRejected=$true}
Assert-Sites $duplicateRejected 'Duplicate query envelopes are rejected'
$missingRejected=$false;try{$null=ConvertTo-PSISitesModel $fixture.context @((New-Envelopes)|Where-Object{$_.Key -ne 'sites'})}catch{$missingRejected=$true}
Assert-Sites $missingRejected 'Missing query outcomes are rejected'
Assert-Sites ((Get-PSIParentDN 'CN=North\, Hub,CN=Sites,CN=Configuration,DC=example,DC=test') -eq 'CN=Sites,CN=Configuration,DC=example,DC=test') 'Escaped commas in DNs do not break parent association'
Assert-Sites ((Get-PSIParentDN 'CN=Tail\\,CN=Sites,DC=example,DC=test') -eq 'CN=Sites,DC=example,DC=test') 'Escaped trailing backslash before separator is handled'
$bad=ConvertFrom-PSISchedule ([byte[]]@(1,2,3)) 'Bad' 'Site link' 'CN=Bad'
Assert-Sites ($bad.'Parse status' -eq 'Unsupported or malformed' -and $bad.'Raw base64' -eq 'AQID') 'Malformed schedule bytes remain exportable without a fabricated schedule'
$bytes=[convert]::FromBase64String($fixture.raw.links[0].schedule);$bytes[20]=255
$bad=ConvertFrom-PSISchedule $bytes 'Bad' 'Site link' 'CN=Bad'
Assert-Sites ($bad.'Parse status' -eq 'Unsupported or malformed') 'Reserved schedule bits are not interpreted as valid availability'
$hostile='=1+1 <tag> </script> "quoted" '+[char]0x03a9
$envelopes=@(New-Envelopes);$envelopes[0].Records[0].description=@($hostile)
$hostileModel=ConvertTo-PSISitesModel $fixture.context $envelopes
$hostileMeta=$p.meta;$hostileFolder=Join-Path $OutputPath 'HostileExport';$null=New-Item -ItemType Directory -Path $hostileFolder
$paths=Export-PSISitesReport $hostileModel $hostileMeta $root $hostileFolder
$safe=Import-Csv -LiteralPath (Join-Path $paths.CsvFolder 'sites.csv')
Assert-Sites ($safe[0].Description -eq ("'"+$hostile)) 'CSV protects formula-leading strings'
$raw=Get-Content -LiteralPath $paths.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Sites ($raw.data.sites[0].Description -eq $hostile) 'JSON retains original evidence'
Assert-Sites ((ConvertTo-PSISafeJson @{Text=$hostile}) -notmatch '</script>') 'Embedded JSON protects script-closing payloads'
$emptyFolder=Join-Path $OutputPath 'EmptyExport';$null=New-Item -ItemType Directory -Path $emptyFolder
$paths=Export-PSISitesReport $empty $p.meta $root $emptyFolder
Assert-Sites ((Get-Content -LiteralPath (Join-Path $paths.CsvFolder 'bridges.csv') -Raw).StartsWith('"Name","Transport"')) 'Zero-row exports retain headers'

# Mock the actual directory worker; verify all eight configuration queries pin to one DC.
function Invoke-MockedCollector([switch]$FailBridges){
    function Import-Module {param($Name,$ErrorAction)}
    function Get-ADRootDSE {param($Server,$Credential,$ErrorAction) [pscustomobject]@{dnsHostName='pinned.example.test';configurationNamingContext='CN=Configuration,DC=example,DC=test'}}
    function Get-ADDomain {param($Server,$Credential,$ErrorAction) if($Server -ne 'pinned.example.test'){throw 'Domain query not pinned'};[pscustomobject]@{DNSRoot='corp.example.test'}}
    function Get-ADForest {param($Server,$Credential,$ErrorAction) [pscustomobject]@{Name='example.test'}}
    function Get-ADObject {param($SearchBase,$SearchScope,$LDAPFilter,$Properties,$Server,$Credential,$ErrorAction)
        if($Server -ne 'pinned.example.test' -or $SearchBase -ne 'CN=Sites,CN=Configuration,DC=example,DC=test' -or $SearchScope -ne 'Subtree'){throw 'Unexpected query pin/scope'}
        $mapping=@{'(objectClass=site)'='sites';'(objectClass=subnet)'='subnets';'(objectClass=siteLink)'='links';'(objectClass=siteLinkBridge)'='bridges';'(objectClass=server)'='servers';'(objectClass=nTDSSiteSettings)'='settings';'(objectClass=interSiteTransport)'='transports';'(objectClass=nTDSDSA)'='ntds'}
        $key=$mapping[$LDAPFilter];if($FailBridges -and $key -eq 'bridges'){throw 'Synthetic bridge access denied'}
        foreach($row in $fixture.raw.$key){
            $copy=$row|ConvertTo-Json -Depth 8|ConvertFrom-Json
            if($null -ne $copy.PSObject.Properties['schedule'] -and $null -ne $copy.schedule){$copy.schedule=[convert]::FromBase64String($copy.schedule)}
            $copy
        }
    }
    & $script:PSISitesCollector 'corp.example.test' $null
}
$workerResults=@(Invoke-MockedCollector)
Assert-Sites ($workerResults.Count -eq 9 -and $workerResults[0].Kind -eq 'Context') 'Mock collector returns verified forest context and eight independent outcomes'
Assert-Sites (@($workerResults|Where-Object{$_.Kind -eq 'Section' -and $_.Status -eq 'Succeeded'}).Count -eq 8) 'All mocked live queries use the pinned DC and Sites base'
$denied=@(Invoke-MockedCollector -FailBridges)
Assert-Sites (@($denied|Where-Object{$_.Kind -eq 'Section' -and $_.Status -eq 'Failed'}).Count -eq 1 -and @($denied|Where-Object{$_.Kind -eq 'Section'}).Count -eq 8) 'A directory access denial does not stop independent queries'
$converted=ConvertTo-PSISitesModel $workerResults[0] @($workerResults|Where-Object{$_.Kind -eq 'Section'})
Assert-Sites ($converted.Data.schedules[0].'Allowed hours UTC' -eq 168) 'Binary schedules survive the collector property-bag pipeline'
$fakeWorker={param($Domain,$Credential)
    [pscustomobject]@{Kind='Context';Forest='example.test';Domain='corp.example.test';Server='mock.example.test';ConfigurationNC='CN=Configuration,DC=example,DC=test'}
    [pscustomobject]@{Kind='Section';Key='sites';Status='Succeeded';Records=@();Method='Mock timeout';CollectedAt='2026-10-29T10:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=$null}
    Start-Sleep -Seconds 30
}
$timeout=Invoke-PSISitesCollection -Domain 'corp.example.test' -Worker $fakeWorker -TimeoutSeconds 5
Assert-Sites ($timeout.Envelopes.Count -eq 8 -and @($timeout.Envelopes|Where-Object{$_.Status -eq 'Succeeded'}).Count -eq 1) 'Completed stream result survives collector timeout'
Assert-Sites (@($timeout.Envelopes|Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 7) 'Only missing queries become timed out'
Assert-Sites (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Sites collector removes its jobs'
$noContextRejected=$false
try{$null=Invoke-PSISitesCollection -Domain 'corp.example.test' -Worker {throw 'Synthetic context failure'} -TimeoutSeconds 5}catch{$noContextRejected=$true}
Assert-Sites $noContextRejected 'Missing forest context stops report generation'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputPath 'SitesTestResults.json') -Encoding UTF8
$summary
