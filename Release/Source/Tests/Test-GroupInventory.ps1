#requires -Version 5.1
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) 'GroupInventoryTests'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$checks=New-Object collections.ArrayList
function Assert-Group([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Group (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Ten exports'
Assert-Group (@(Get-PSInsightInventory).Count -eq 10) 'Nine inventories'
Assert-Group (@((Get-Help Invoke-ADGroupInventory -Examples).examples.example).Count -eq 3) 'Public help examples'
$result=Invoke-ADGroupInventory -Demo -OutputPath $OutputPath;$p=Get-Content $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Group ($result.ObservedGroups -eq 4 -and $result.ObservedMemberLinks -eq 5) 'Sample group and direct-link counts'
Assert-Group ($p.data.groups[2].'Direct linked members' -eq 0 -and $null -eq $p.data.groups[3].'Direct linked members') 'Empty group zero distinguished from denied unknown'
Assert-Group ($p.data.nested.Count -eq 1 -and $p.data.parents[0].'Group ID' -eq $p.data.groups[1].'Group ID') 'Nested and parent edges agree'
Assert-Group (@($p.data.members|Where-Object{$_.'Member type' -eq 'foreignSecurityPrincipal'}).Count -eq 1) 'Local FSP type retained'
Assert-Group ($p.data.collection.Count -eq 5 -and -not $p.coverage.members) 'Metadata and per-group coverage separate'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-Group (@(Import-Csv (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV agreement '+$key)}
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path $root ('Private/Sites/'+$f))}
foreach($f in @('Helpers.ps1','Collector.ps1')){. (Join-Path $root ('Private/Groups/'+$f))}
function Fixture {Get-Content (Join-Path $root 'Assets/Groups.sample.json') -Raw|ConvertFrom-Json}
$fx=Fixture;$bad=$false;try{$null=ConvertTo-PSIGroupModel $fx.context @($fx.envelopes[0])}catch{$bad=$true};Assert-Group $bad 'Missing membership outcome rejected in strict sample contract'
$m=ConvertTo-PSIGroupModel $fx.context @($fx.envelopes[0],$fx.envelopes[1]) 'TimedOut'
Assert-Group ($m.Data.members.Count -eq 3 -and @($m.Data.collection|Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 3) 'Missing timed-out groups preserve completed lists'
$bad=$false;try{$null=ConvertTo-PSIGroupModel $fx.context (@($fx.envelopes)+@($fx.envelopes[0]))}catch{$bad=$true};Assert-Group $bad 'Duplicate query outcome rejected'
$fx=Fixture;$fx.envelopes[0].Records[0].DN='CN=Wrong,DC=child,DC=example,DC=test';$bad=$false;try{$null=ConvertTo-PSIGroupModel $fx.context $fx.envelopes}catch{$bad=$true};Assert-Group $bad 'Child naming context rejected despite parent suffix'
Assert-Group ((Get-PSIGroupDomainDN 'CN=Name\, One,OU=Groups,DC=example,DC=test') -eq 'DC=example,DC=test') 'Escaped DN and domain extraction'
$fx=Fixture;$payload='=1+1 </script> <tag> "quoted"';$fx.envelopes[0].Records[0].Name=$payload;$m=ConvertTo-PSIGroupModel $fx.context $fx.envelopes
$folder=Join-Path $OutputPath 'Hostile';$null=New-Item -ItemType Directory $folder -Force;$paths=Export-PSISitesReport $m $p.meta $root $folder 'Groups.html' 'Hostile'
Assert-Group ((Import-Csv (Join-Path $paths.CsvFolder 'groups.csv'))[0].Name -eq ("'"+$payload)) 'CSV formula protection'
Assert-Group ((ConvertTo-PSISafeJson $m) -notmatch '</script>') 'Embedded JSON script protection'
function Test-Ranges([string]$Mode='Normal'){
 function Read-PSIGroupRange {param($Server,$DN,$Start)
  if($Mode -eq 'Empty'){return [pscustomobject]@{Attribute=$null;Values=@()}}
  if($Start -eq 0){return [pscustomobject]@{Attribute='member;range=0-1499';Values=@(1..1500|ForEach-Object{'CN=User'+$_+',DC=example,DC=test'})}}
  if($Mode -eq 'Missing'){return [pscustomobject]@{Attribute=$null;Values=@()}}
  if($Mode -eq 'WrongStart'){return [pscustomobject]@{Attribute='member;range=0-*';Values=@('CN=Other,DC=example,DC=test')}}
  if($Mode -eq 'Duplicate'){return [pscustomobject]@{Attribute='member;range=1500-*';Values=@('CN=User1,DC=example,DC=test')}}
  [pscustomobject]@{Attribute='member;range=1500-*';Values=@('CN=User1501,DC=example,DC=test')}
 }
 @(Get-PSIGroupMemberDNs 'mock' 'CN=Group,DC=example,DC=test')
}
Assert-Group (@(Test-Ranges).Count -eq 1501) 'Range retrieval crosses 1500-member block'
Assert-Group (@(Test-Ranges Empty).Count -eq 0) 'Initial empty member attribute remains valid empty'
foreach($mode in @('Missing','WrongStart','Duplicate')){$bad=$false;try{$null=Test-Ranges $mode}catch{$bad=$true};Assert-Group $bad ('Invalid range rejected: '+$mode)}
$fixtureGroups=(Fixture).envelopes[0].Records;$helperText=[IO.File]::ReadAllText((Join-Path $root 'Private/Groups/Helpers.ps1'))
$mockRange=@'
function Read-PSIGroupRange([string]$Server,[string]$DN,[int]$Start){
 if($Server -ne 'dc01.example.test'){throw 'Not pinned'}
 if($DN -eq $fixtureGroups[3].DN){throw 'Denied list'}
 $values=if($DN -eq $fixtureGroups[0].DN){@($fixtureGroups[1].DN,'CN=User,OU=Users,DC=example,DC=test','CN=PC,OU=Computers,DC=example,DC=test','CN=S-1-5-11,CN=ForeignSecurityPrincipals,DC=example,DC=test','CN=Partner,DC=child,DC=example,DC=test')}elseif($DN -eq $fixtureGroups[1].DN){@('CN=User,OU=Users,DC=example,DC=test')}else{@()}
 [pscustomobject]@{Attribute='member;range=0-*';Values=$values}
}
'@
function Mock-Group([string]$Mode='Normal'){
 function Import-Module {param($Name,$ErrorAction)}
 function Get-ADRootDSE {param($Server,$ErrorAction) [pscustomobject]@{dnsHostName='dc01.example.test';configurationNamingContext='CN=Configuration,DC=example,DC=test'}}
 function Get-ADDomain {param($Server,$ErrorAction) [pscustomobject]@{DNSRoot=if($Mode -eq 'WrongDomain'){'other.test'}else{'example.test'};DistinguishedName='DC=example,DC=test';Forest='example.test'}}
 function Get-ADGroup {param($Filter,$SearchBase,$SearchScope,$Properties,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $SearchBase -ne 'DC=example,DC=test' -or $SearchScope -ne 'Subtree' -or $Properties -contains '*'){throw 'Unscoped query'}
  if($Mode -eq 'Empty'){return}
  foreach($g in $fixtureGroups){[pscustomobject]@{Name=$g.Name;ObjectGUID=$g.Id;DistinguishedName=$g.DN;SID=$g.Sid;GroupScope=$g.Scope;GroupCategory=$g.Category;SamAccountName=$g.Sam;description=$g.Description;managedBy=$null};if($Mode -eq 'MetadataDenied'){throw 'Metadata interrupted'}}
 }
 function Get-ADObject {param($Identity,$Properties,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $Identity -like '*DC=child,*' -or @($Properties).Count -ne 1 -or @($Properties)[0] -ne 'objectSid'){throw 'Unscoped member request'}
  $script:MemberLookups++
  if($Mode -eq 'ResolutionDenied' -and $Identity -like 'CN=User,*'){throw 'Lookup denied'}
  [pscustomobject]@{Name=($Identity.Split(',')[0]);DistinguishedName=$Identity;ObjectGUID=[guid]::NewGuid();objectSid='S-1-5-11';ObjectClass=if($Identity -like 'CN=PC,*'){'computer'}elseif($Identity -like '*ForeignSecurityPrincipals*'){'foreignSecurityPrincipal'}else{'user'};UnexpectedSecret='DO-NOT-RETAIN'}
 }
 & $script:PSIGroupCollector 'example.test' ($helperText+"`n"+$mockRange)
}
$script:MemberLookups=0;$actual=@(Mock-Group);$m=ConvertTo-PSIGroupModel $actual[0] @($actual|Where-Object{$_.Kind -eq 'Section'})
Assert-Group ($m.Data.groups.Count -eq 4 -and $m.Data.members.Count -eq 6) 'Actual collector per-group complete/denied lists'
Assert-Group ($script:MemberLookups -eq 3) 'Member resolution cache reused and external reference not queried'
Assert-Group (@($m.Data.members|Where-Object{$_.'Resolution status' -eq 'NotAttempted'}).Count -eq 1 -and @($m.Data.members|Where-Object{$_.'Member type' -eq 'foreignSecurityPrincipal'}).Count -eq 1) 'External reference and local FSP distinguished'
Assert-Group ($m.Data.groups[2].'Direct linked members' -eq 0 -and $null -eq $m.Data.groups[3].'Direct linked members') 'Actual empty/denied count distinction'
Assert-Group (($actual|ConvertTo-Json -Depth 20) -notmatch 'DO-NOT-RETAIN') 'Explicit retained member fields'
$denied=@(Mock-Group ResolutionDenied);$m=ConvertTo-PSIGroupModel $denied[0] @($denied|Where-Object{$_.Kind -eq 'Section'})
Assert-Group ($m.Data.groups[0].'Direct linked members' -eq 5 -and -not $m.Coverage.objectQueries) 'Failed type lookup preserves raw links and valid link count'
$denied=@(Mock-Group MetadataDenied);$m=ConvertTo-PSIGroupModel $denied[0] @($denied|Where-Object{$_.Kind -eq 'Section'});Assert-Group ($m.Data.groups.Count -eq 0 -and -not $m.Coverage.members) 'Failed metadata discards partial catalog'
$empty=@(Mock-Group Empty);$m=ConvertTo-PSIGroupModel $empty[0] @($empty|Where-Object{$_.Kind -eq 'Section'});Assert-Group ($m.Data.groups.Count -eq 0 -and $m.Coverage.groups) 'Successful empty domain'
$bad=$false;try{$null=@(Mock-Group WrongDomain)}catch{$bad=$true};Assert-Group $bad 'Wrong domain stopped'
$worker={param($Domain,$HelperText) [pscustomobject]@{Kind='Context';Domain=$Domain;Server='mock';DomainDN='DC=example,DC=test';Forest='example.test';ConfigurationNC='CN=Configuration,DC=example,DC=test'};[pscustomobject]@{Kind='Section';Key='groups';Status='Succeeded';Records=@();CollectedAt='2026-10-30T00:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=''};Start-Sleep -Seconds 30}
$timed=Invoke-PSIGroupCollection 'example.test' 5 $worker '';Assert-Group ($timed.TimedOut -and $timed.Envelopes.Count -eq 1) 'Timeout retains metadata and signals incomplete members'
Assert-Group (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Worker cleanup'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath 'GroupTestResults.json') -Encoding UTF8
$summary
