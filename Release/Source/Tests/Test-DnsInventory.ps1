#requires -Version 5.1
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) 'DnsInventoryTests'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$checks=New-Object collections.ArrayList
function Assert-Dns([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Dns (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Six exports'
Assert-Dns (@(Get-PSInsightInventory).Count -eq 10) 'Five catalog entries'
Assert-Dns (@((Get-Help Invoke-ADDnsInventory -Examples).examples.example).Count -eq 3) 'DNS help examples'
$result=Invoke-ADDnsInventory -Demo -OutputPath $OutputPath
$p=Get-Content $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Dns ($result.SelectedDCs -eq 3 -and $result.DNSRoleObserved -eq 2) 'Selected DCs and observed roles'
Assert-Dns ($result.PartialInventories -eq 1 -and $result.ZoneObservations -eq 6) 'Partial zone inventory visible'
Assert-Dns ($p.data.collection.Count -eq 45) 'Exactly fifteen category outcomes per DC'
Assert-Dns ($p.data.delegations.Count -eq 2 -and -not $p.coverage.delegations) 'Partial category retains successful rows without completeness claim'
Assert-Dns (@($p.data.collection|Where-Object{$_.Status -eq 'NotApplicable'}).Count -eq 12) 'Absent role distinct from query failure'
Assert-Dns (@($p.data.zoneQueries|Where-Object{$_.Status -eq 'NotAttempted'}).Count -eq 12) 'Excluded zone types have explicit ledger rows'
Assert-Dns ($p.data.client[0].'Additional DNS' -eq '192.0.2.12') 'Client resolver order retained'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-Dns (@(Import-Csv (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV agreement '+$key)}
. (Join-Path $root 'Private/Dns/RemoteCollector.ps1')
function Mock-Dns([string]$Mode='Normal'){
 function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) [pscustomobject]@{Description='Ethernet';DNSServerSearchOrder=@('192.0.2.1','192.0.2.2','192.0.2.3')}}
 function Get-Service {param($Name,$ErrorAction)
  if($Mode -eq 'Absent'){Write-Error 'No DNS service' -ErrorId NoServiceFoundForGivenName -ErrorAction Stop}
  if($Mode -eq 'Denied'){throw 'Access denied'}
  [pscustomobject]@{Status='Running'}
 }
 function Import-Module {param($Name,$ErrorAction) if($Mode -eq 'ModuleMissing'){throw 'Module missing'}}
 function Get-DnsServerForwarder {param($ErrorAction) [pscustomobject]@{IPAddress=@('192.0.2.53');Timeout=3;UseRootHint=$false}}
 function Get-DnsServerRecursion {param($ErrorAction) [pscustomobject]@{Enable=$true}}
 function Get-DnsServerScavenging {param($ErrorAction) [pscustomobject]@{ScavengingState=$false}}
 function Get-DnsServerRootHint {param($ErrorAction) [pscustomobject]@{NameServer=[pscustomobject]@{RecordData=[pscustomobject]@{NameServer='root.example.test'}};IPAddress=@([pscustomobject]@{RecordData=[pscustomobject]@{IPv4Address='192.0.2.100'}})}}
 function Get-DnsServerZone {param($ErrorAction) if($Mode -eq 'ZonesDenied'){throw 'Zone access denied'};foreach($z in $(if($Mode -eq 'ZoneKinds'){@('one.test','two.test','stub.test','partner.test')}elseif($Mode -eq 'LongestZone'){@('one.test','child.one.test','partner.test')}else{@('one.test','two.test','partner.test')})){[pscustomobject]@{ZoneName=$z;ZoneType=if($z -eq 'partner.test'){'Forwarder'}elseif($Mode -eq 'ZoneKinds' -and $z -eq 'two.test'){'Secondary'}elseif($z -eq 'stub.test'){'Stub'}else{'Primary'}}}}
 function Get-DnsServerZoneAging {param($Name,$ErrorAction) [pscustomobject]@{AgingEnabled=$true;RefreshInterval=[timespan]::FromDays(7)}}
 function Get-DnsServerZoneDelegation {param($Name,$ErrorAction) if($Name -eq 'two.test'){throw 'Synthetic denied zone'};[pscustomobject]@{ChildZoneName='branch';NameServer='ns.branch.one.test';IPAddress='192.0.2.30'}}
 function Get-Command {param($Name,$ErrorAction) if(($Mode -eq 'Unsupported' -and $Name -eq 'Get-DnsServerZoneScope') -or ($Mode -eq 'NsUnsupported' -and $Name -eq 'Get-DnsServerResourceRecord')){return};Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue}
 function Get-DnsServerResourceRecord {param($ZoneName,$Name,$RRType,[switch]$Node,$ErrorAction)
  if($RRType -eq 'NS'){
   if($Name -or $Node){throw 'NS selection should enumerate NS owners without an apex-only filter'}
   if($Mode -eq 'NsDenied' -and $ZoneName -eq 'two.test'){throw 'Synthetic denied NS zone'}
   if($Mode -eq 'NoNs'){return}
   foreach($owner in @('@','branch')){[pscustomobject]@{HostName=$owner;RecordData=[pscustomobject]@{NameServer=if($owner -eq '@'){if($Mode -eq 'LongestZone'){'ns.child.one.test.'}else{'ns.one.test.'}}else{'external.example.'}};TimeToLive=[timespan]::FromHours(1);Timestamp=$null}}
  }else{
   $script:MockAddressQueryCount++
   if($ZoneName -ne $(if($Mode -eq 'LongestZone'){'child.one.test'}else{'one.test'}) -or $Name -ne 'ns' -or -not $Node -or $RRType -notin @('A','AAAA')){throw 'Address query was not an exact stored node in the eligible hosted zone'}
   if($Mode -eq 'AddressDenied' -and $RRType -eq 'AAAA'){throw 'Synthetic address query denied'}
   if($RRType -eq 'A'){[pscustomobject]@{HostName='ns';RecordData=[pscustomobject]@{IPv4Address='192.0.2.10'};TimeToLive=[timespan]::FromMinutes(10)}}
  }
 }
 function Get-DnsServerZoneScope {param($ZoneName,$ErrorAction) [pscustomobject]@{ZoneScope=$ZoneName;FileName=$null}}
 & $script:PSIDnsRemote 'mock.example.test'
}
$script:MockAddressQueryCount=0
$live=@(Mock-Dns)
Assert-Dns ($live.Count -eq 14) 'Remote collector emits fourteen independent categories'
$partial=@($live|Where-Object{$_.Key -eq 'delegations'})[0]
Assert-Dns ($partial.Status -eq 'Partial' -and $partial.Records.Count -eq 1) 'Actual collector retains successful delegation when another zone fails'
$queries=@($live|Where-Object{$_.Key -eq 'zoneQueries'})[0].Records
Assert-Dns (@($queries|Where-Object{$_.Status -eq 'Failed'}).Count -eq 1 -and @($queries|Where-Object{$_.Status -eq 'NotAttempted'}).Count -eq 6) 'Actual per-zone ledger includes failures and exclusions'
Assert-Dns (@($live|Where-Object{$_.Key -eq 'rootHints'})[0].Records[0].Addresses -eq '192.0.2.100') 'Nested root-hint address flattened'
Assert-Dns (@($live|Where-Object{$_.Key -eq 'scavenging'})[0].Records[0].Enabled -eq $false) 'False preserved'
Assert-Dns ($null -eq @($live|Where-Object{$_.Key -eq 'recursion'})[0].Records[0].Timeout) 'Missing property remains null'
$absent=@(Mock-Dns Absent)
Assert-Dns (@($absent|Where-Object{$_.Status -eq 'NotApplicable'}).Count -eq 12) 'Actual absent service path'
$denied=@(Mock-Dns Denied)
Assert-Dns (@($denied|Where-Object{$_.Status -eq 'Failed'}).Count -eq 13 -and @($denied|Where-Object{$_.Status -eq 'NotApplicable'}).Count -eq 0) 'Service access denial never inferred as absence'
$missing=@(Mock-Dns ModuleMissing)
Assert-Dns (@($missing|Where-Object{$_.Status -eq 'Failed'}).Count -eq 12) 'Missing DNS module records failures'
$zoneFail=@(Mock-Dns ZonesDenied)
Assert-Dns (@($zoneFail|Where-Object{$_.Status -eq 'Failed'}).Count -eq 8 -and @($zoneFail|Where-Object{$_.Key -eq 'forwarders'})[0].Status -eq 'Succeeded') 'Zone failure preserves independent configuration'
$unsupported=@(Mock-Dns Unsupported)
Assert-Dns (@($unsupported|Where-Object{$_.Key -eq 'scopes'})[0].Status -eq 'Partial') 'Unavailable per-zone cmdlet produces partial category'
Assert-Dns (@(@($unsupported|Where-Object{$_.Key -eq 'zoneQueries'})[0].Records|Where-Object{$_.Status -eq 'Unsupported'}).Count -eq 2) 'Unsupported operations explicit per primary zone'
Assert-Dns ($p.data.nameServers.Count -eq 8 -and $p.data.nsAddresses.Count -eq 4) 'Sample NS and stored address counts'
$ns=@($live|Where-Object{$_.Key -eq 'nameServers'})[0]
Assert-Dns ($ns.Status -eq 'Succeeded' -and $ns.Records.Count -eq 4 -and $ns.Records[1].Owner -eq 'branch') 'Actual NS collection includes apex and child owners'
Assert-Dns ($ns.Records[0].TTL -eq '01:00:00' -and $null -eq $ns.Records[0].Timestamp) 'NS TTL and nullable timestamp preserved'
$addresses=@($live|Where-Object{$_.Key -eq 'nsAddresses'})[0]
Assert-Dns ($addresses.Status -eq 'Succeeded' -and $addresses.Records.Count -eq 2 -and $addresses.Records[0].Address -eq '192.0.2.10') 'Stored addresses keep source-zone relationship'
Assert-Dns (@($queries|Where-Object{$_.Operation -eq 'NS address selection' -and $_.Status -eq 'NotAttempted'}).Count -eq 2) 'External NS targets are excluded from address reads'
$nsDenied=@(Mock-Dns NsDenied)
Assert-Dns (@($nsDenied|Where-Object{$_.Key -eq 'nameServers'})[0].Status -eq 'Partial' -and @($nsDenied|Where-Object{$_.Key -eq 'nameServers'})[0].Records.Count -eq 2) 'One NS zone denial retains another zone'
Assert-Dns (@($nsDenied|Where-Object{$_.Key -eq 'nsAddresses'})[0].Status -eq 'Partial') 'Unknown NS inputs prevent complete address coverage claim'
$addressDenied=@(Mock-Dns AddressDenied)
Assert-Dns (@($addressDenied|Where-Object{$_.Key -eq 'nsAddresses'})[0].Status -eq 'Partial' -and @($addressDenied|Where-Object{$_.Key -eq 'nsAddresses'})[0].Records.Count -eq 2) 'AAAA denial preserves successful A rows'
$noNs=@(Mock-Dns NoNs)
Assert-Dns (@($noNs|Where-Object{$_.Key -eq 'nameServers'})[0].Status -eq 'Succeeded' -and @($noNs|Where-Object{$_.Key -eq 'nameServers'})[0].Records.Count -eq 0) 'Successful empty NS query stays valid empty result'
$nsUnsupported=@(Mock-Dns NsUnsupported)
Assert-Dns (@($nsUnsupported|Where-Object{$_.Key -eq 'nameServers'})[0].Status -eq 'Partial' -and @($nsUnsupported|Where-Object{$_.Key -eq 'nsAddresses'})[0].Status -eq 'Partial') 'Missing NS cmdlet is partial, not absent DNS role'
$kinds=@(Mock-Dns ZoneKinds)
Assert-Dns (@($kinds|Where-Object{$_.Key -eq 'nameServers'})[0].Records.Count -eq 6 -and @($kinds|Where-Object{$_.Key -eq 'scopes'})[0].Records.Count -eq 1) 'NS covers Primary Secondary Stub while configuration reads remain Primary only'
$script:MockAddressQueryCount=0;$longest=@(Mock-Dns LongestZone)
Assert-Dns (@(@($longest|Where-Object{$_.Key -eq 'nsAddresses'})[0].Records|Where-Object{$_.'Address zone' -ne 'child.one.test'}).Count -eq 0) 'Stored address selection chooses longest eligible hosted zone'
Assert-Dns ($script:MockAddressQueryCount -eq 2) 'Repeated NS targets reuse exact A and AAAA node reads'
foreach($file in @('Common.ps1','Schema.ps1')){. (Join-Path $root ('Private/Dns/'+$file))}
$script:DCInvSections=Get-PSIDnsSchema;$script:DCInvData=[ordered]@{};$script:DCInvSeen=@{}
foreach($k in $script:DCInvSections.Keys){$script:DCInvData[$k]=New-Object collections.ArrayList}
$script:DCInvLogPath=Join-Path $OutputPath 'WorkerTest.jsonl';$script:DCInvRunId='offline'
$worker={param($Controller,$Credential,$Settings,$RemoteText)
 [pscustomobject]@{Kind='Section';Target=$Controller.HostName;Key='client';Status='Succeeded';Records=@();Method='Offline';StartedAt='2026-10-29T00:00:00Z';CollectedAt='2026-10-29T00:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=$null}
 Start-Sleep -Seconds 30
}
$settings=[pscustomobject]@{ThrottleLimit=1;TargetTimeoutSeconds=5}
Invoke-DCInvWorkers @([pscustomobject]@{HostName='mock.example.test'}) $worker '' $settings $null
Assert-Dns ($script:DCInvData.collection.Count -eq 14 -and @($script:DCInvData.collection|Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 13) 'DNS scheduler retains completed category and fills missing outcomes on timeout'
Assert-Dns (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'DNS scheduler cleans up its jobs'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath 'DnsTestResults.json') -Encoding UTF8
$summary
