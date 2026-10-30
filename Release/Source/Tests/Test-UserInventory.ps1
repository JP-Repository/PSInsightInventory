#requires -Version 5.1
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) 'UserInventoryTests'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$checks=New-Object collections.ArrayList
function Assert-User([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-User (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Eleven public exports'
Assert-User (@(Get-PSInsightInventory).Count -eq 10) 'Ten inventory entries'
Assert-User (@((Get-Help Invoke-ADUserInventory -Examples).examples.example).Count -eq 3) 'Three public examples'
$result=Invoke-ADUserInventory -Demo -OutputPath $OutputPath;$p=Get-Content $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-User ($result.ObservedUsers -eq 5 -and $result.ObservedGroupLinks -eq 2) 'Sample users and backlinks'
foreach($key in @('departments','companies','locations','statuses')){Assert-User (($p.data.$key|Measure-Object 'Users observed' -Sum).Sum -eq 5) ('Summary totals agree: '+$key)}
Assert-User ($p.data.departments.Count -eq 4) 'Empty and unknown departments kept separate'
Assert-User (@($p.data.statuses|Where-Object{$_.Enabled -eq $false -and $_.Name -eq 'False'}).Count -eq 1) 'False status not confused with empty string'
Assert-User ($p.data.primaryGroups[0].'Derived primary group SID' -eq 'S-1-5-21-100-200-300-513') 'Primary group SID derived separately'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-User (@(Import-Csv (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV agreement '+$key)}
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path $root ('Private/Sites/'+$f))}
foreach($f in @('Helpers.ps1','Collector.ps1')){. (Join-Path $root ('Private/Users/'+$f))}
function Fixture {Get-Content (Join-Path $root 'Assets/Users.sample.json') -Raw|ConvertFrom-Json}
$fx=Fixture;$fx.envelopes[0].Status='Failed';$m=ConvertTo-PSIUserModel $fx.context $fx.envelopes
Assert-User ($m.Data.users.Count -eq 0 -and -not $m.Coverage.departments -and $m.Data.collection[0].Status -eq 'Failed') 'Failure does not become empty success'
$fx=Fixture;$fx.envelopes[0].Records=@();$m=ConvertTo-PSIUserModel $fx.context $fx.envelopes
Assert-User ($m.Coverage.users -and $m.Data.users.Count -eq 0) 'Successful empty domain valid'
$fx=Fixture;$bad=$false;try{$null=ConvertTo-PSIUserModel $fx.context @()}catch{$bad=$true};Assert-User $bad 'Missing query rejected'
$bad=$false;try{$null=ConvertTo-PSIUserModel $fx.context (@($fx.envelopes)+@($fx.envelopes))}catch{$bad=$true};Assert-User $bad 'Duplicate query rejected'
$fx=Fixture;$fx.envelopes[0].Records+=@($fx.envelopes[0].Records[0]);$bad=$false;try{$null=ConvertTo-PSIUserModel $fx.context $fx.envelopes}catch{$bad=$true};Assert-User $bad 'Duplicate user identity rejected'
$fx=Fixture;$fx.envelopes[0].Records[0].DN='CN=Wrong,DC=child,DC=example,DC=test';$bad=$false;try{$null=ConvertTo-PSIUserModel $fx.context $fx.envelopes}catch{$bad=$true};Assert-User $bad 'Child naming context rejected'
$fx=Fixture;$fx.envelopes[0].Records[0].Sid='S-1-5-11';$m=ConvertTo-PSIUserModel $fx.context $fx.envelopes
Assert-User ($null -eq $m.Data.primaryGroups[0].'Derived primary group SID') 'Invalid account-domain SID not guessed'
Assert-User ((Get-PSIUserParentDN 'CN=Name\, One,OU=People,DC=example,DC=test') -eq 'OU=People,DC=example,DC=test') 'Escaped DN delimiter handled'
$fx=Fixture;$payload='=1+1 </script> <tag> "quoted"';$fx.envelopes[0].Records[0].Name=$payload;$m=ConvertTo-PSIUserModel $fx.context $fx.envelopes
$folder=Join-Path $OutputPath 'Hostile';$null=New-Item -ItemType Directory $folder -Force;$paths=Export-PSISitesReport $m $p.meta $root $folder 'Users.html' 'Hostile'
Assert-User ((Import-Csv (Join-Path $paths.CsvFolder 'users.csv'))[0].Name -eq ("'"+$payload)) 'CSV formula protection'
Assert-User ((ConvertTo-PSISafeJson $m) -notmatch '</script>') 'Embedded JSON closing-script protection'
$helperText=[IO.File]::ReadAllText((Join-Path $root 'Private/Users/Helpers.ps1'))
function Mock-User([string]$Mode='Normal'){
 function Import-Module {param($Name,$ErrorAction)}
 function Get-ADRootDSE {param($Server,$ErrorAction) [pscustomobject]@{dnsHostName='dc01.example.test';configurationNamingContext='CN=Configuration,DC=example,DC=test'}}
 function Get-ADDomain {param($Server,$ErrorAction) if($Server -ne 'dc01.example.test'){throw 'Not pinned'};[pscustomobject]@{DNSRoot=if($Mode -eq 'WrongDomain'){'other.test'}else{'example.test'};DistinguishedName='DC=example,DC=test';Forest='example.test'}}
 function Get-ADUser {param($Filter,$SearchBase,$SearchScope,$Properties,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $SearchBase -ne 'DC=example,DC=test' -or $SearchScope -ne 'Subtree' -or $Properties -contains '*' -or @($Properties|Where-Object{$_ -match '^(unicodePwd|userPassword|ntPwdHistory|supplementalCredentials|msDS-ManagedPassword)$'}).Count){throw 'Unscoped or secret property request'}
  if($Mode -eq 'Empty'){return}
  foreach($n in 1..2){[pscustomobject]@{Name='User'+$n;ObjectGUID=([guid]('00000000-0000-0000-0000-'+$n.ToString('000000000000')));DistinguishedName=if($Mode -eq 'Outside'){'CN=Wrong,DC=child,DC=example,DC=test'}else{'CN=User'+$n+',CN=Users,DC=example,DC=test'};SID='S-1-5-21-100-200-300-1100';SamAccountName='user'+$n;UserPrincipalName='user'+$n+'@example.test';mail='user'+$n+'@example.test';Enabled=$false;department='IT';company='Example';manager='CN=Manager,DC=child,DC=example,DC=test';PasswordNeverExpires=$false;CannotChangePassword=$false;lastLogonTimestamp=if($n -eq 1){[datetime]::Parse('2026-10-01T00:00:00Z').ToFileTimeUtc()}else{0};AccountExpirationDate=$null;PasswordLastSet=$null;primaryGroupID=513;memberOf=@('CN=External Group,DC=child,DC=example,DC=test');UnexpectedSecret='DO-NOT-RETAIN'};if($Mode -eq 'Denied'){throw 'Interrupted scan'}}
 }
 function Get-ADObject {throw 'Unexpected reference dereference'}
 & $script:PSIUserCollector 'example.test' $helperText
}
$actual=@(Mock-User);$m=ConvertTo-PSIUserModel $actual[0] @($actual[1])
Assert-User ($actual.Count -eq 2 -and $m.Data.users.Count -eq 2) 'Actual collector pinned domain query'
Assert-User ($m.Data.users[0].Enabled -eq $false -and $m.Data.flags[0].'Cannot change password' -eq $false) 'False flags preserved'
Assert-User ($m.Data.users[0].'Last logon timestamp (replicated)' -like '2026-10-01*' -and $null -eq $m.Data.users[1].'Last logon timestamp (replicated)') 'FILETIME converted and zero remains unknown'
Assert-User ($m.Data.memberships.Count -eq 2 -and $m.Data.memberships[0].'Group DN' -like '*DC=child,*' -and $m.Data.users[0].'Manager DN' -like '*DC=child,*') 'External references retained without dereferencing'
Assert-User ($m.Data.users[0].'Location DN' -like 'CN=Users,*' -and $null -eq $m.Data.users[0].'Account expires') 'CN location and missing expiry preserved'
Assert-User (($actual|ConvertTo-Json -Depth 20) -notmatch 'DO-NOT-RETAIN|UnexpectedSecret') 'Explicit retained fields exclude unexpected data'
foreach($mode in @('Denied','Outside')){$a=@(Mock-User $mode);Assert-User ($a[1].Status -eq 'Failed' -and $a[1].Records.Count -eq 0) ('Partial/outside scan discarded: '+$mode)}
$empty=@(Mock-User Empty);Assert-User ($empty[1].Status -eq 'Succeeded' -and $empty[1].Records.Count -eq 0) 'Actual empty query succeeds'
$bad=$false;try{$null=@(Mock-User WrongDomain)}catch{$bad=$true};Assert-User $bad 'Wrong domain discovery rejected'
$worker={param($Domain,$HelperText) [pscustomobject]@{Kind='Context';Domain=$Domain;Server='mock';DomainDN='DC=example,DC=test';Forest='example.test';ConfigurationNC='CN=Configuration,DC=example,DC=test'};Start-Sleep -Seconds 30}
$timed=Invoke-PSIUserCollection 'example.test' 5 $worker '';Assert-User ($timed.Envelopes.Count -eq 1 -and $timed.Envelopes[0].Status -eq 'TimedOut') 'Timeout explicit outcome'
Assert-User (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Worker cleanup'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath 'UserTestResults.json') -Encoding UTF8
$summary
