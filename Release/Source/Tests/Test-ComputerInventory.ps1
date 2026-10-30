#requires -Version 5.1
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) 'ComputerInventoryTests'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$checks=New-Object collections.ArrayList
function Assert-Computer([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force
Assert-Computer (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'Nine exports'
Assert-Computer (@(Get-PSInsightInventory).Count -eq 10) 'Eight inventory entries'
Assert-Computer (@((Get-Help Invoke-ADComputerInventory -Examples).examples.example).Count -eq 3) 'Public examples'
$result=Invoke-ADComputerInventory -Demo -OutputPath $OutputPath
$p=Get-Content $result.JsonSnapshot -Raw|ConvertFrom-Json
Assert-Computer ($result.ObservedComputers -eq 10 -and $result.OsGroups -eq 9) 'Sample computers and OS groups'
Assert-Computer (($p.data.osSummary|Measure-Object 'Computers observed' -Sum).Sum -eq 10 -and ($p.data.locations|Measure-Object 'Computers observed' -Sum).Sum -eq 10) 'Summary totals reconcile with computer population'
Assert-Computer (@($p.data.computers|Where-Object{$_.'OS family' -eq 'Windows Server'}).Count -eq 5) 'Windows Server family grouped'
Assert-Computer ($p.data.computers[8].'Server release' -eq '2012 R2' -and $p.data.computers[3].'Server release' -eq '2025') 'Server releases including R2 retained'
Assert-Computer ($p.data.computers[5].Enabled -eq $false -and $p.data.computers[7].'OS family' -eq 'Unknown') 'Disabled and unknown OS retained'
Assert-Computer ($p.data.computers[0].'DC role reported' -eq 'Domain controller' -and $p.data.computers[1].'DC role reported' -eq 'Other computer') 'Directory role indicator classification'
foreach($key in $p.sections.PSObject.Properties.Name){Assert-Computer (@(Import-Csv (Join-Path $result.CsvFolder ($key+'.csv'))).Count -eq @($p.data.$key).Count) ('CSV agreement '+$key)}
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path $root ('Private/Sites/'+$f))}
foreach($f in @('Helpers.ps1','Collector.ps1')){. (Join-Path $root ('Private/Computers/'+$f))}
function Fixture {Get-Content (Join-Path $root 'Assets/Computers.sample.json') -Raw|ConvertFrom-Json}
foreach($version in @('10.0 (20348)','10.0.20348.100')){Assert-Computer ((Get-PSIComputerOs 'Windows Server 2022 Standard' $version).Build -eq '20348') ('Recognized AD version format: '+$version)}
Assert-Computer ($null -eq (Get-PSIComputerOs 'Windows 11 Enterprise' 'unrecognized').Build) 'Unknown version does not invent build'
Assert-Computer ((Get-PSIComputerOs 'Future OS' '').Family -eq 'Other / unclassified') 'Unrecognized OS remains separate'
$caseFixture=Fixture;$caseFixture.envelopes[0].Records[9].OS='windows 11 enterprise';$caseModel=ConvertTo-PSIComputerModel $caseFixture.context $caseFixture.envelopes
Assert-Computer ($caseModel.Data.osSummary.Count -eq 10) 'Exact reported OS spellings remain separate clickable groups'
$fx=Fixture;$fx.envelopes[0].Status='Failed';$m=ConvertTo-PSIComputerModel $fx.context $fx.envelopes
Assert-Computer ($m.Data.computers.Count -eq 0 -and -not $m.Coverage.osSummary -and $m.Data.collection[0].Status -eq 'Failed') 'Failure discards untrusted rows without empty-success claim'
$fx=Fixture;$fx.envelopes[0].Records=@();$m=ConvertTo-PSIComputerModel $fx.context $fx.envelopes
Assert-Computer ($m.Coverage.computers -and $m.Data.computers.Count -eq 0) 'Successful empty domain valid'
$fx=Fixture;$bad=$false;try{$null=ConvertTo-PSIComputerModel $fx.context @()}catch{$bad=$true};Assert-Computer $bad 'Missing outcome rejected'
$bad=$false;try{$null=ConvertTo-PSIComputerModel $fx.context (@($fx.envelopes)+@($fx.envelopes))}catch{$bad=$true};Assert-Computer $bad 'Duplicate outcome rejected'
$fx=Fixture;$fx.envelopes[0].Records+=@($fx.envelopes[0].Records[0]);$bad=$false;try{$null=ConvertTo-PSIComputerModel $fx.context $fx.envelopes}catch{$bad=$true};Assert-Computer $bad 'Duplicate identity rejected'
$fx=Fixture;$fx.envelopes[0].Records[0].DN='CN=Wrong,DC=other,DC=test';$bad=$false;try{$null=ConvertTo-PSIComputerModel $fx.context $fx.envelopes}catch{$bad=$true};Assert-Computer $bad 'Out-of-domain model record rejected'
$fx=Fixture;$fx.envelopes[0].Records[0].PrimaryGroup=521;$m=ConvertTo-PSIComputerModel $fx.context $fx.envelopes;Assert-Computer ($m.Data.computers[0].'DC role reported' -eq 'Domain controller') 'RODC primary group indicator retained'
Assert-Computer ((Get-PSIComputerParentDN 'CN=PC\, One,OU=Workstations,DC=example,DC=test') -eq 'OU=Workstations,DC=example,DC=test') 'Escaped DN delimiter handled'
$fx=Fixture;$payload='=1+1 </script> <tag> "quoted"';$fx.envelopes[0].Records[0].Name=$payload;$m=ConvertTo-PSIComputerModel $fx.context $fx.envelopes
$folder=Join-Path $OutputPath 'Hostile';$null=New-Item -ItemType Directory $folder -Force
$paths=Export-PSISitesReport $m $p.meta $root $folder 'Computers.html' 'Hostile'
Assert-Computer ((Import-Csv (Join-Path $paths.CsvFolder 'computers.csv'))[0].Name -eq ("'"+$payload)) 'CSV formula protection'
Assert-Computer ((ConvertTo-PSISafeJson $m) -notmatch '</script>') 'Embedded JSON closing-script protection'
$helperText=[IO.File]::ReadAllText((Join-Path $root 'Private/Computers/Helpers.ps1'))
function Mock-Computer([string]$MockMode='Normal'){
 function Import-Module {param($Name,$ErrorAction)}
 function Get-ADRootDSE {param($Server,$ErrorAction) [pscustomobject]@{dnsHostName='dc01.example.test';configurationNamingContext='CN=Configuration,DC=example,DC=test'}}
 function Get-ADDomain {param($Server,$ErrorAction) if($Server -ne 'dc01.example.test'){throw 'Not pinned'};[pscustomobject]@{DNSRoot=if($MockMode -eq 'WrongDomain'){'other.test'}else{'example.test'};DistinguishedName='DC=example,DC=test';Forest='example.test'}}
 function Get-ADComputer {param($Filter,$SearchBase,$SearchScope,$Properties,$Server,$ErrorAction)
  if($Server -ne 'dc01.example.test' -or $SearchBase -ne 'DC=example,DC=test' -or $SearchScope -ne 'Subtree' -or $Properties -contains '*' -or @($Properties|Where-Object{$_ -match 'password$|ms-Mcs|msLAPS'}).Count){throw 'Unscoped or sensitive property request'}
  if($MockMode -eq 'Empty'){return}
  foreach($n in 1..2){[pscustomobject]@{Name='PC'+$n;ObjectGUID=([guid]('00000000-0000-0000-0000-'+$n.ToString('000000000000')));DistinguishedName=if($MockMode -eq 'Outside'){'CN=PC,DC=other,DC=test'}else{'CN=PC'+$n+',CN=Computers,DC=example,DC=test'};DNSHostName='pc.example.test';OperatingSystem='Windows 11 Enterprise';OperatingSystemVersion='10.0 (22631)';Enabled=$false;lastLogonTimestamp=if($n -eq 1){[datetime]::Parse('2026-10-01T00:00:00Z').ToFileTimeUtc()}else{0};servicePrincipalName=@('HOST/pc.example.test');'msDS-AllowedToDelegateTo'=@('cifs/files.example.test');TrustedForDelegation=$false;TrustedToAuthForDelegation=$false;AccountNotDelegated=$false;userAccountControl=4096;primaryGroupID=515;'msDS-AllowedToActOnBehalfOfOtherIdentity'=[byte[]]@(1,2,3);UnexpectedSecret='DO-NOT-RETAIN'};if($MockMode -eq 'Denied'){throw 'Interrupted after partial records'}}
 }
 & $script:PSIComputerCollector 'example.test' $helperText
}
$actual=@(Mock-Computer);$m=ConvertTo-PSIComputerModel $actual[0] @($actual[1])
Assert-Computer ($actual.Count -eq 2 -and $m.Data.computers.Count -eq 2) 'Actual collector pinned domain query'
Assert-Computer ($m.Data.computers[0].'Last logon timestamp (replicated)' -like '2026-10-01*' -and $null -eq $m.Data.computers[1].'Last logon timestamp (replicated)') 'FILETIME conversion and zero stays unknown'
Assert-Computer ($m.Data.computers[0].Enabled -eq $false -and $m.Data.delegation[0].'Trusted for delegation' -eq $false) 'False flags preserved'
Assert-Computer ($m.Data.locations[0].'Location DN' -like 'CN=Computers,*') 'CN container locations preserved'
Assert-Computer ($m.Data.spns.Count -eq 2 -and $m.Data.delegation[0].'RBCD descriptor present' -eq $true) 'SPNs delegation and RBCD presence captured'
Assert-Computer (($actual|ConvertTo-Json -Depth 20) -notmatch 'DO-NOT-RETAIN|UnexpectedSecret') 'Explicit retained properties exclude unexpected data and raw RBCD descriptor'
foreach($mode in @('Denied','Outside')){$a=@(Mock-Computer $mode);Assert-Computer ($a[1].Status -eq 'Failed' -and $a[1].Records.Count -eq 0) ('Partial/outside scan discarded: '+$mode)}
$empty=@(Mock-Computer Empty);Assert-Computer ($empty[1].Status -eq 'Succeeded' -and $empty[1].Records.Count -eq 0) 'Actual empty query succeeds'
$bad=$false;try{$null=@(Mock-Computer WrongDomain)}catch{$bad=$true};Assert-Computer $bad 'Wrong domain discovery rejected'
$worker={param($Domain,$HelperText) [pscustomobject]@{Kind='Context';Domain=$Domain;Server='mock.example.test';DomainDN='DC=example,DC=test';Forest='example.test';ConfigurationNC='CN=Configuration,DC=example,DC=test'};Start-Sleep -Seconds 30}
$timeout=Invoke-PSIComputerCollection 'example.test' 5 $worker ''
Assert-Computer ($timeout.Envelopes.Count -eq 1 -and $timeout.Envelopes[0].Status -eq 'TimedOut') 'Worker timeout creates explicit query outcome'
Assert-Computer (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Worker jobs cleaned up'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$result.HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath 'ComputerTestResults.json') -Encoding UTF8
$summary
