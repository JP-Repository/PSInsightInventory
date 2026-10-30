#requires -Version 5.1
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) 'GroupPolicyInventoryTests'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$checks=New-Object collections.ArrayList
function Assert-Gpo([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Gpo (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Seven exports'
Assert-Gpo (@(Get-PSInsightInventory).Count -eq 10) 'Six inventory catalog entries'
Assert-Gpo (@((Get-Help Invoke-ADGroupPolicyInventory -Examples).examples.example).Count -eq 3) 'Three public examples'
$result=Invoke-ADGroupPolicyInventory -Demo -OutputPath $OutputPath
$p=Get-Content $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Gpo ($result.ObservedGPOs -eq 3 -and $result.ObservedLinks -eq 3) 'Demo GPO and link counts'
Assert-Gpo ($result.IncompleteCategories -eq 1 -and $p.data.settings.Count -eq 2 -and -not $p.coverage.settings) 'Partial settings preserve successful GPO data'
Assert-Gpo ($p.data.collection.Count -eq 9 -and $p.data.objectQueries.Count -eq 9) 'Category and object outcomes separate'
Assert-Gpo ($p.data.wmiReferences[1].'Filter ID' -eq $p.data.wmiFilters[0].'Filter ID') 'WMI relation IDs retained'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-Gpo (@(Import-Csv (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV agreement '+$key)}
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path $root ('Private/Sites/'+$f))}
foreach($f in @('Helpers.ps1','Collector.ps1')){. (Join-Path $root ('Private/GroupPolicy/'+$f))}
function Fixture {Get-Content (Join-Path $root 'Assets/GroupPolicy.sample.json') -Raw|ConvertFrom-Json}
$fx=Fixture;$fx.envelopes[0].Status='Failed';$m=ConvertTo-PSIGpoModel $fx.context $fx.envelopes
Assert-Gpo ($m.Data.gpos.Count -eq 0 -and -not $m.Coverage.gpos -and $m.Data.links.Count -eq 3) 'Failed source drops untrusted rows while independent data survives'
$fx=Fixture;$fx.envelopes[0].Records=@();$m=ConvertTo-PSIGpoModel $fx.context $fx.envelopes
Assert-Gpo ($m.Coverage.gpos -and $m.Data.gpos.Count -eq 0) 'Successful empty GPO collection valid'
$fx=Fixture;$bad=$false;try{$null=ConvertTo-PSIGpoModel $fx.context @($fx.envelopes[0])}catch{$bad=$true};Assert-Gpo $bad 'Missing category rejected'
$bad=$false;try{$null=ConvertTo-PSIGpoModel $fx.context (@($fx.envelopes)+@($fx.envelopes[0]))}catch{$bad=$true};Assert-Gpo $bad 'Duplicate category rejected'
$fixtureId='11111111-1111-1111-1111-111111111111';$fixtureId2='22222222-2222-2222-2222-222222222222';$fixtureDN='DC=example,DC=test'
$text='[LDAP://CN={'+$fixtureId+'},CN=Policies,CN=System,'+$fixtureDN+';0][LDAP://CN={'+$fixtureId2+'},CN=Policies,CN=System,'+$fixtureDN+';3]'
$links=@(ConvertFrom-PSIGpoLinks $text 'Workstations' 'OU' ('OU=Workstations,'+$fixtureDN) $fixtureDN)
Assert-Gpo ($links.Count -eq 2 -and $links[0].'Link order' -eq 2 -and $links[1].'Link order' -eq 1) 'Stored link order keeps all entries in denominator'
Assert-Gpo ($links[0].Enabled -eq $true -and $links[1].Enabled -eq $false -and $links[1].Enforced -eq $true) 'Disabled and enforced bits retained separately'
$outText=$text.Replace('CN={'+$fixtureId2+'},CN=Policies,CN=System,'+$fixtureDN,'CN={'+$fixtureId2+'},CN=Policies,CN=System,DC=other,DC=test')
Assert-Gpo (@(ConvertFrom-PSIGpoLinks $outText 'C' 'Site' 'CN=C' $fixtureDN).Count -eq 1) 'Other-domain GPO links excluded'
$bad=$false;try{$null=ConvertFrom-PSIGpoLinks ($text+'BROKEN') 'C' 'OU' 'OU=C' $fixtureDN}catch{$bad=$true};Assert-Gpo $bad 'Malformed links do not silently establish complete collection'
$xml='<GPO xmlns="urn:test"><Identifier><Identifier>{'+$fixtureId+'}</Identifier></Identifier><Computer><ExtensionData><Name>Registry</Name><Extension><Policy><Value>DO-NOT-EXPORT-SECRET</Value></Policy><Policy/></Extension></ExtensionData></Computer></GPO>'
$x=@(ConvertFrom-PSIGpoXml $xml $fixtureId 'Example')
Assert-Gpo ($x.Count -eq 1 -and $x[0].'Top-level setting nodes' -eq 2 -and $x[0].'Setting types' -eq 'Policy') 'Namespace-independent settings structure'
Assert-Gpo (($x|ConvertTo-Json) -notmatch 'DO-NOT-EXPORT-SECRET') 'Arbitrary setting values omitted'
$bad=$false;try{$null=ConvertFrom-PSIGpoXml $xml $fixtureId2 'Wrong'}catch{$bad=$true};Assert-Gpo $bad 'Wrong XML GPO identity rejected'
$bad=$false;try{$null=ConvertFrom-PSIGpoXml ('<!DOCTYPE GPO [<!ENTITY x SYSTEM "file:///etc/passwd">]>'+$xml) $fixtureId 'Wrong'}catch{$bad=$true};Assert-Gpo $bad 'External XML entities prohibited'
$fx=Fixture;$hostile='=1+1 </script> <tag> "quoted"';$fx.envelopes[0].Records[0].Name=$hostile;$m=ConvertTo-PSIGpoModel $fx.context $fx.envelopes
$folder=Join-Path $OutputPath 'Hostile';$null=New-Item -ItemType Directory $folder -Force
$paths=Export-PSISitesReport $m $p.meta $root $folder 'GroupPolicy.html' 'Hostile'
Assert-Gpo ((Import-Csv (Join-Path $paths.CsvFolder 'gpos.csv'))[0].Name -eq ("'"+$hostile)) 'Formula-leading CSV values protected'
Assert-Gpo ((ConvertTo-PSISafeJson $m) -notmatch '</script>') 'Script-closing payload encoded'
$helperText=[IO.File]::ReadAllText((Join-Path $root 'Private/GroupPolicy/Helpers.ps1'))
function Mock-Gpo([string]$Mode='Normal'){
 function Import-Module {param($Name,$ErrorAction)}
 function Get-ADRootDSE {param($Server,$ErrorAction) [pscustomobject]@{dnsHostName='dc01.example.test';configurationNamingContext='CN=Configuration,'+$fixtureDN}}
 function Get-ADDomain {param($Server,$ErrorAction) if($Server -ne 'dc01.example.test'){throw 'Domain query not pinned'};[pscustomobject]@{DNSRoot=if($Mode -eq 'WrongDomain'){'other.test'}else{'example.test'};DistinguishedName=$fixtureDN;Forest='example.test'}}
 function Get-GPO {param([switch]$All,$Domain,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $Domain -ne 'example.test'){throw 'GPO read not scoped/pinned'}
  if($Mode -eq 'GpoDenied'){throw 'GPO enumeration denied'}
  foreach($i in @($fixtureId,$fixtureId2)){[pscustomobject]@{Id=$i;DisplayName='GPO '+$i;DomainName='example.test';GpoStatus='AllSettingsEnabled';User=[pscustomobject]@{DSVersion=1;SysvolVersion=1};Computer=[pscustomobject]@{DSVersion=2;SysvolVersion=2}}}
 }
 function Get-ADObject {param($Identity,$LDAPFilter,$SearchBase,$SearchScope,$Properties,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $Properties -contains '*'){throw 'Unpinned or wildcard AD query'}
  if($Mode -eq 'SiteDenied' -and $LDAPFilter -eq '(objectClass=site)'){throw 'Sites denied'}
  if($Identity){[pscustomobject]@{Name='example.test';DistinguishedName=$fixtureDN;gPLink=$text;gPOptions=0}}
  elseif($LDAPFilter -eq '(objectClass=organizationalUnit)'){[pscustomobject]@{Name='Workstations';DistinguishedName='OU=Workstations,'+$fixtureDN;gPLink=$text;gPOptions=1}}
  elseif($LDAPFilter -eq '(objectClass=site)'){[pscustomobject]@{Name='HQ';DistinguishedName='CN=HQ,CN=Sites,CN=Configuration,'+$fixtureDN;gPLink=$text;gPOptions=$null}}
  elseif($LDAPFilter -eq '(objectClass=groupPolicyContainer)'){[pscustomobject]@{Name='{'+$fixtureId+'}';DistinguishedName='CN={'+$fixtureId+'},CN=Policies,CN=System,'+$fixtureDN;displayName='Policy';gPCWQLFilter='[example.test;{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa};0]'}}
 }
 function Get-GPPermission {param($Guid,[switch]$All,$Domain,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $Domain -ne 'example.test'){throw 'Permission read not pinned'}
  if($Guid -eq $fixtureId2){throw 'Synthetic per-GPO permission denied'}
  [pscustomobject]@{Trustee=[pscustomobject]@{Name='Authenticated Users';Domain='NT AUTHORITY';Sid=[pscustomobject]@{Value='S-1-5-11'}};TrusteeType='WellKnownGroup';Permission='GpoApply';Inherited=$false}
 }
 function Get-GPOReport {param($Guid,$Domain,$Server,$ReportType,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $Domain -ne 'example.test' -or $ReportType -ne 'Xml'){throw 'Report read not pinned'}
  if($Guid -eq $fixtureId2){throw 'Synthetic per-GPO XML denied'};$xml
 }
 & $script:PSIGpoCollector 'example.test' $helperText
}
$actual=@(Mock-Gpo);$sections=@($actual|Where-Object{$_.Kind -eq 'Section'})
Assert-Gpo ($actual.Count -eq 10 -and $sections.Count -eq 9) 'Actual collector context plus nine categories'
$actualModel=ConvertTo-PSIGpoModel $actual[0] $sections
Assert-Gpo ($actualModel.Data.gpos.Count -eq 2 -and $actualModel.Data.links.Count -eq 6) 'Actual collector pinned GPO and three-container-source observations'
Assert-Gpo ($actualModel.Data.permissions.Count -eq 1 -and -not $actualModel.Coverage.permissions) 'Permission denial retains another GPO'
Assert-Gpo ($actualModel.Data.settings.Count -eq 1 -and -not $actualModel.Coverage.settings) 'XML denial retains another GPO'
Assert-Gpo ($actualModel.Data.permissions[0].'Trustee SID' -eq 'S-1-5-11' -and $actualModel.Data.permissions[0].Inherited -eq $false) 'Nested SID and false inherited flag preserved'
Assert-Gpo ($actualModel.Data.wmiReferences[0].'Filter ID' -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') 'Actual raw WMI reference parsed'
$siteDenied=@(Mock-Gpo SiteDenied);$model=ConvertTo-PSIGpoModel $siteDenied[0] @($siteDenied|Where-Object{$_.Kind -eq 'Section'})
Assert-Gpo ($model.Data.links.Count -eq 4 -and -not $model.Coverage.links) 'Denied site source retains domain and OU links'
$gpoDenied=@(Mock-Gpo GpoDenied);$model=ConvertTo-PSIGpoModel $gpoDenied[0] @($gpoDenied|Where-Object{$_.Kind -eq 'Section'})
Assert-Gpo ($model.Data.gpos.Count -eq 0 -and $model.Data.links.Count -eq 6 -and @($model.Data.collection|Where-Object{$_.Status -eq 'NotAttempted'}).Count -eq 3) 'GPO enumeration failure retains independent directory inventory'
$bad=$false;try{$null=@(Mock-Gpo WrongDomain)}catch{$bad=$true};Assert-Gpo $bad 'Wrong domain discovery stops collection'
$worker={param($Domain,$HelperText)
 [pscustomobject]@{Kind='Context';Domain=$Domain;Server='mock.example.test';DomainDN='DC=example,DC=test';Forest='example.test';ConfigurationNC='CN=Configuration,DC=example,DC=test'}
 [pscustomobject]@{Kind='Section';Key='gpos';Status='Succeeded';Records=@();CollectedAt='2026-10-29T00:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=''}
 Start-Sleep -Seconds 30
}
$timeout=Invoke-PSIGpoCollection 'example.test' 5 $worker ''
Assert-Gpo ($timeout.Envelopes.Count -eq 9 -and @($timeout.Envelopes|Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 8) 'Timeout keeps completed category and fills missing outcomes'
Assert-Gpo (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'GPO collection removes its jobs'
$completeWorker={param($Domain,$HelperText)
 $fixture=$HelperText|ConvertFrom-Json
 $context=$fixture.context;$context|Add-Member -NotePropertyName Kind -NotePropertyValue 'Context';$context
 foreach($entry in $fixture.envelopes){$entry}
}
$complete=Invoke-PSIGpoCollection 'example.test' 10 $completeWorker ([IO.File]::ReadAllText((Join-Path $root 'Assets/GroupPolicy.sample.json')))
Assert-Gpo ($complete.Envelopes.Count -eq 9 -and @($complete.Envelopes|Where-Object{$_.Status -eq 'Failed'}).Count -eq 0) 'Completed worker drains its entire result stream'
$invalidWorker={param($Domain,$HelperText) [pscustomobject]@{Kind='Context';Domain='other.test';Server='other.test'}}
$bad=$false;try{$null=Invoke-PSIGpoCollection 'example.test' 10 $invalidWorker ''}catch{$bad=$true};Assert-Gpo $bad 'Worker context mismatch rejected and job removed'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath 'GroupPolicyTestResults.json') -Encoding UTF8
$summary
