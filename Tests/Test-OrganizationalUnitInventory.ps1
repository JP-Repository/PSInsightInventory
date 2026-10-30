#requires -Version 5.1
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) 'OuInventoryTests'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$checks=New-Object collections.ArrayList
function Assert-Ou([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Ou (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Eight exports'
Assert-Ou (@(Get-PSInsightInventory).Count -eq 10) 'Seven inventory catalog entries'
Assert-Ou (@((Get-Help Invoke-ADOrganizationalUnitInventory -Examples).examples.example).Count -eq 3) 'Three public examples'
$result=Invoke-ADOrganizationalUnitInventory -Demo -OutputPath $OutputPath
$p=Get-Content $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Ou ($result.ObservedOUs -eq 3 -and $result.ObservedACEs -eq 4) 'Demo OU and ACE counts'
Assert-Ou ($p.data.collection.Count -eq 6 -and $p.data.objectQueries.Count -eq 6) 'Category and per-OU collection separate'
Assert-Ou ($result.IncompleteCategories -eq 2 -and $null -eq $p.data.inheritance[1].'DACL inheritance protected') 'Denied DACL leaves unknown flag and partial coverage'
Assert-Ou ($p.data.ous[1].'Parent DN' -eq $p.data.ous[0].DN) 'Sample hierarchy relation'
Assert-Ou ($p.data.counts[2].'Direct users' -eq 0) 'Successful empty OU preserves zero'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-Ou (@(Import-Csv (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV agreement '+$key)}
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path $root ('Private/Sites/'+$f))}
foreach($f in @('Helpers.ps1','Collector.ps1')){. (Join-Path $root ('Private/OrganizationalUnits/'+$f))}
function Fixture {Get-Content (Join-Path $root 'Assets/OrganizationalUnits.sample.json') -Raw|ConvertFrom-Json}
$fx=Fixture;$fx.envelopes[1].Status='Failed';$m=ConvertTo-PSIOuModel $fx.context $fx.envelopes
Assert-Ou ($m.Data.counts.Count -eq 3 -and $null -eq $m.Data.counts[0].'Direct users' -and $m.Data.counts[0].'Count status' -eq 'Unavailable') 'Failed count query retains identities with null counts'
$bad=$false;try{$null=ConvertTo-PSIOuModel $fx.context @($fx.envelopes[0])}catch{$bad=$true};Assert-Ou $bad 'Missing category rejected'
$bad=$false;try{$null=ConvertTo-PSIOuModel $fx.context (@($fx.envelopes)+@($fx.envelopes[0]))}catch{$bad=$true};Assert-Ou $bad 'Duplicate category rejected'
Assert-Ou ((Get-PSIOuParentDN 'OU=Sales\, East,OU=Corporate,DC=example,DC=test') -eq 'OU=Corporate,DC=example,DC=test') 'Escaped comma in OU DN preserved'
Assert-Ou ((Get-PSIOuParentDN 'OU=Backslash\\,DC=example,DC=test') -eq 'DC=example,DC=test') 'Escaped backslash does not hide delimiter'
$fx=Fixture;$hostile='=1+1 </script> <tag> "quoted"';$fx.envelopes[0].Records[0].Name=$hostile;$m=ConvertTo-PSIOuModel $fx.context $fx.envelopes
$folder=Join-Path $OutputPath 'Hostile';$null=New-Item -ItemType Directory $folder -Force
$paths=Export-PSISitesReport $m $p.meta $root $folder 'OrganizationalUnits.html' 'Hostile'
Assert-Ou ((Import-Csv (Join-Path $paths.CsvFolder 'ous.csv'))[0].Name -eq ("'"+$hostile)) 'CSV formula-leading values protected'
Assert-Ou ((ConvertTo-PSISafeJson $m) -notmatch '</script>') 'Script-closing payload encoded'
$fixtureRows=(Fixture).envelopes[0].Records;$fixtureDomainDN='DC=example,DC=test'
$helperText=[IO.File]::ReadAllText((Join-Path $root 'Private/OrganizationalUnits/Helpers.ps1'))
$mockAcl=@'
function Get-PSIOuAcl([string]$Server,[string]$DN){
 if($Server -ne 'dc01.example.test'){throw 'ACL not pinned'}
 if($MockMode -eq 'AclDenied' -and $DN -like 'OU=Workstations,*'){throw 'Synthetic denied DACL'}
 [pscustomobject]@{Protected=$false;Rules=@([pscustomobject]@{IdentityReference='S-1-5-11';AccessControlType='Allow';ActiveDirectoryRights='ReadProperty';ObjectType=[guid]::Empty;InheritedObjectType=[guid]::Empty;InheritanceType='All';IsInherited=$true;InheritanceFlags='ContainerInherit';PropagationFlags='None'})}
}
'@
function Mock-Ou([string]$MockMode='Normal'){
 function Import-Module {param($Name,$ErrorAction)}
 function Get-ADRootDSE {param($Server,$ErrorAction) [pscustomobject]@{dnsHostName='dc01.example.test';configurationNamingContext='CN=Configuration,'+$fixtureDomainDN}}
 function Get-ADDomain {param($Server,$ErrorAction) if($Server -ne 'dc01.example.test'){throw 'Not pinned'};[pscustomobject]@{DNSRoot=if($MockMode -eq 'WrongDomain'){'other.test'}else{'example.test'};DistinguishedName=$fixtureDomainDN;Forest='example.test'}}
 function Get-ADOrganizationalUnit {param($Filter,$SearchBase,$SearchScope,$Properties,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $SearchBase -ne $fixtureDomainDN -or $SearchScope -ne 'Subtree' -or $Properties -contains '*'){throw 'Unscoped OU query'}
  if($MockMode -eq 'OuDenied'){throw 'Enumeration denied'};if($MockMode -eq 'Empty'){return}
  foreach($r in $fixtureRows){[pscustomobject]@{Name=$r.Name;ObjectGUID=$r.'OU ID';DistinguishedName=if($MockMode -eq 'OutsideOu'){'OU=Wrong,DC=other,DC=test'}else{$r.DN};canonicalName=$r.'Canonical path';description=$r.Description;managedBy=$null;ProtectedFromAccidentalDeletion=$r.'Protected from accidental deletion';gPLink=if($r.Name -eq 'Corporate'){'[LDAP://CN={aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa},CN=Policies,CN=System,DC=other,DC=test;3]'}elseif($MockMode -eq 'BadLink' -and $r.Name -eq 'Workstations'){'BROKEN'}else{''};gPOptions=0}}
 }
 function Get-ADObject {param($LDAPFilter,$SearchBase,$SearchScope,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $SearchBase -ne $fixtureDomainDN -or $SearchScope -ne 'Subtree'){throw 'Unscoped object scan'}
  if($MockMode -eq 'Empty'){throw 'Empty OU selection should not run object scan'}
  $rows=@(@('CN=User1,OU=Corporate,','user'),@('CN=User2,CN=Container,OU=Corporate,','user'),@('CN=User3,OU=Workstations,OU=Corporate,','user'),@('CN=PC1,OU=Workstations,OU=Corporate,','computer'),@('CN=PC2,OU=Workstations,OU=Corporate,','computer'),@('CN=Group1,OU=Workstations,OU=Corporate,','group'),@('OU=Workstations,OU=Corporate,','organizationalUnit'),@('CN=Contact,OU=Corporate,','contact'))
  foreach($pair in $rows){[pscustomobject]@{DistinguishedName=$pair[0]+$fixtureDomainDN;ObjectClass=$pair[1]};if($MockMode -eq 'CountDenied'){throw 'Scan interrupted after partial output'}}
  if($MockMode -eq 'OutsideCount'){[pscustomobject]@{DistinguishedName='CN=Wrong,DC=other,DC=test';ObjectClass='user'}}
 }
 & $script:PSIOuCollector 'example.test' ($helperText+"`n"+$mockAcl)
}
$actual=@(Mock-Ou);$model=ConvertTo-PSIOuModel $actual[0] @($actual|Where-Object{$_.Kind -eq 'Section'})
Assert-Ou ($actual.Count -eq 7 -and $model.Data.ous.Count -eq 3) 'Actual collector context plus six categories'
Assert-Ou ($model.Data.counts[0].'Direct users' -eq 1 -and $model.Data.counts[0].'Descendant users' -eq 3) 'Direct versus descendant counts include intermediate containers'
Assert-Ou ($model.Data.counts[0].'Direct computers' -eq 0 -and $model.Data.counts[0].'Descendant computers' -eq 2 -and $model.Data.counts[1].'Direct users' -eq 1) 'Computers not double-counted as users'
Assert-Ou ($model.Data.counts[0].'Direct OUs' -eq 1 -and $model.Data.counts[0].'Descendant OUs' -eq 1 -and $model.Data.counts[1].'Descendant OUs' -eq 0) 'Child OU counts exclude the OU itself'
Assert-Ou ($model.Data.counts[2].'Descendant users' -eq 0 -and $model.Coverage.counts) 'Successful empty OU remains counted'
Assert-Ou ($model.Data.links[0].Enabled -eq $false -and $model.Data.links[0].Enforced -eq $true -and $model.Data.links[0].'GPO DN' -like '*DC=other,DC=test') 'Cross-domain GPO references retained with raw flags'
Assert-Ou ($model.Data.delegations.Count -eq 3 -and $model.Data.delegations[0].Inherited -eq $true -and $model.Data.inheritance[0].'DACL inheritance protected' -eq $false) 'Reported ACE and false DACL protection preserved'
$denied=@(Mock-Ou AclDenied);$m=ConvertTo-PSIOuModel $denied[0] @($denied|Where-Object{$_.Kind -eq 'Section'})
Assert-Ou ($m.Data.delegations.Count -eq 2 -and -not $m.Coverage.delegations -and $m.Data.counts.Count -eq 3 -and $null -eq $m.Data.inheritance[1].'DACL inheritance protected') 'One denied DACL preserves other ACEs, counts and unknown flag'
foreach($mode in @('CountDenied','OutsideCount')){$denied=@(Mock-Ou $mode);$m=ConvertTo-PSIOuModel $denied[0] @($denied|Where-Object{$_.Kind -eq 'Section'});Assert-Ou (-not $m.Coverage.counts -and $null -eq $m.Data.counts[0].'Direct users') ('Interrupted/out-of-domain count scan never becomes partial zero: '+$mode)}
$badLink=@(Mock-Ou BadLink);$m=ConvertTo-PSIOuModel $badLink[0] @($badLink|Where-Object{$_.Kind -eq 'Section'})
Assert-Ou (-not $m.Coverage.links -and $m.Data.links.Count -eq 1 -and $m.Coverage.delegations) 'Bad OU link keeps other links and independent DACLs'
foreach($mode in @('OuDenied','OutsideOu')){$denied=@(Mock-Ou $mode);$m=ConvertTo-PSIOuModel $denied[0] @($denied|Where-Object{$_.Kind -eq 'Section'});Assert-Ou ($m.Data.ous.Count -eq 0 -and @($m.Data.collection|Where-Object{$_.Status -eq 'NotAttempted'}).Count -eq 5) ('Enumeration failure/scope guard prevents dependent reads: '+$mode)}
$empty=@(Mock-Ou Empty);$m=ConvertTo-PSIOuModel $empty[0] @($empty|Where-Object{$_.Kind -eq 'Section'});Assert-Ou ($m.Data.ous.Count -eq 0 -and @($m.Data.collection|Where-Object{$_.Status -ne 'Succeeded'}).Count -eq 0) 'Empty OU domain produces valid empty inventory without scan'
$bad=$false;try{$null=@(Mock-Ou WrongDomain)}catch{$bad=$true};Assert-Ou $bad 'Wrong domain discovery rejected'
$worker={param($Domain,$HelperText)
 [pscustomobject]@{Kind='Context';Domain=$Domain;Server='mock.example.test';DomainDN='DC=example,DC=test';Forest='example.test';ConfigurationNC='CN=Configuration,DC=example,DC=test'}
 [pscustomobject]@{Kind='Section';Key='ous';Status='Succeeded';Records=@();CollectedAt='2026-10-30T00:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=''}
 Start-Sleep -Seconds 30
}
$timeout=Invoke-PSIOuCollection 'example.test' 5 $worker ''
Assert-Ou ($timeout.Envelopes.Count -eq 6 -and @($timeout.Envelopes|Where-Object{$_.Status -eq 'TimedOut'}).Count -eq 5) 'Timeout retains completed category and fills missing outcomes'
Assert-Ou (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'OU worker removes its jobs'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath 'OuTestResults.json') -Encoding UTF8
$summary
