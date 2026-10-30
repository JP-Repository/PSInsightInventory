#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName='Live')]
param(
 [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$')][string]$Domain,
 [Parameter(ParameterSetName='Live')][ValidateRange(10,3600)][int]$TimeoutSeconds=600,
 [Parameter(Mandatory=$true,ParameterSetName='Sample')][switch]$SampleData,
 [string]$OutputPath='C:\Temp\Reports',[switch]$Open
)
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
$moduleRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Sites') $f)}
foreach($f in @('Helpers.ps1','Collector.ps1')){. (Join-Path $PSScriptRoot $f)}
$started=[datetimeoffset]::Now;$run=[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $OutputPath ('PSInsightInventory_Users_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$run)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$log=Join-Path $logs ('Users_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
 Write-PSISitesLog $log $run 'Run' 'Start' 'Started' $Domain ('User inventory; SampleData='+[bool]$SampleData)
 if($SampleData){$fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/Users.sample.json'))|ConvertFrom-Json;$context=$fixture.context;$envelopes=@($fixture.envelopes)}
 else{
  if($env:OS -ne 'Windows_NT'){throw 'Live User inventory requires Windows with RSAT ActiveDirectory.'}
  foreach($name in @('ActiveDirectory')){if(-not (Get-Module -ListAvailable $name)){throw "Required RSAT module missing: $name"}}
  $collected=Invoke-PSIUserCollection $Domain $TimeoutSeconds $script:PSIUserCollector ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Helpers.ps1')))
  $context=$collected.Context;$envelopes=@($collected.Envelopes)
 }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
 $model=ConvertTo-PSIUserModel $context $envelopes
 foreach($e in $model.Data.collection){Write-PSISitesLog $log $run 'Collection' $e.Name $e.Status $context.Server $e.Message ([long]$e.'Duration ms') ([string]$e.'Error ID')}
 $now=[datetimeoffset]::Now
 $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADUser';title='User Inventory';run=$run;dataSource=if($SampleData){'Sample'}else{'Live'};scope='User objects in one explicit domain';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$started.ToString('o');generated=$now.ToString('o');generatedDisplay=$now.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;expectedQueries=1;notice=if($SampleData){'SAMPLE DATA. Fictional User configuration; no infrastructure was contacted.'}else{'Read-only configuration snapshot from one pinned DC. No resultant-policy or endpoint processing test.'};limitations=@('One explicit domain; user objects only. No child-domain enumeration, manager/group target lookups or endpoint connections.','Names, profile fields, flags and timestamps are reported directory values and can be missing or outdated. Empty and unknown summary values remain distinguishable.','Last logon timestamp is replicated and approximate, not exact last sign-in or a stale-account finding. Zero/missing timestamps remain null. Account expiration is separate from password expiration.','Group links use memberOf values returned by Get-ADUser. They exclude primary group and recursive membership; no claim of complete forest-wide membership, independent backlink range validation or effective access is made.','Primary group SID is derived from a valid account-domain SID and primaryGroupID. It is a reference, not a resolved or verified group object.','Manager and group DNs are retained without dereferencing external targets. managed profile attributes do not prove organizational ownership or employment status.','Summaries reconcile to observed user objects and use exact returned values. ACL-filtered objects/attributes may not be visible; successful reads do not prove complete visibility.','No inactivity threshold, privilege analysis, recommendation, password/secret export, modification, remediation or email occurs.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
 $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'Users.html' 'Users'
 Write-PSISitesLog $log $run 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
 if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning 'Report saved; automatic opening failed.'}}
 [pscustomobject]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADUser';Domain=$context.Domain;ObservedUsers=$model.Data.users.Count;ObservedGroupLinks=$model.Data.memberships.Count;CollectionStatus=$model.Data.collection[0].Status;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$log;OutputFolder=$folder}
}catch{Write-PSISitesLog $log $run 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId;throw}
