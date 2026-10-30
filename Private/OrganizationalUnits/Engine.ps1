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
$folder=Join-Path $OutputPath ('PSInsightInventory_OrganizationalUnits_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$run)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$log=Join-Path $logs ('OrganizationalUnits_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
 Write-PSISitesLog $log $run 'Run' 'Start' 'Started' $Domain ('Organizational Unit inventory; SampleData='+[bool]$SampleData)
 if($SampleData){$fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/OrganizationalUnits.sample.json'))|ConvertFrom-Json;$context=$fixture.context;$envelopes=@($fixture.envelopes)}
 else{
  if($env:OS -ne 'Windows_NT'){throw 'Live Organizational Unit inventory requires Windows with RSAT ActiveDirectory.'}
  foreach($name in @('ActiveDirectory')){if(-not (Get-Module -ListAvailable $name)){throw "Required RSAT module missing: $name"}}
  $collected=Invoke-PSIOuCollection $Domain $TimeoutSeconds $script:PSIOuCollector ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Helpers.ps1')))
  $context=$collected.Context;$envelopes=@($collected.Envelopes)
 }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
 $model=ConvertTo-PSIOuModel $context $envelopes
 foreach($e in $model.Data.collection){Write-PSISitesLog $log $run 'Collection' $e.Name $e.Status $context.Server $e.Message ([long]$e.'Duration ms') ([string]$e.'Error ID')}
 foreach($e in $model.Data.objectQueries){Write-PSISitesLog $log $run 'ObjectCollection' $e.Operation $e.Status $e.Target $e.Message ([long]$e.'Duration ms') ([string]$e.'Error ID')}
 $now=[datetimeoffset]::Now
 $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADOrganizationalUnit';title='Organizational Unit Inventory';run=$run;dataSource=if($SampleData){'Sample'}else{'Live'};scope='Organizational units in one explicit domain';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$started.ToString('o');generated=$now.ToString('o');generatedDisplay=$now.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;expectedQueries=6;notice=if($SampleData){'SAMPLE DATA. Fictional Organizational Unit configuration; no infrastructure was contacted.'}else{'Read-only configuration snapshot from one pinned DC. No resultant-policy or endpoint processing test.'};limitations=@('One explicit domain only; no child-domain enumeration or non-OU container inventory. Hierarchy uses returned DNs and GUIDs.','Direct counts are one level below the OU. Descendant counts include all depths and exclude the OU itself; descendant totals overlap between ancestors and must not be summed across OUs.','Counts use a single domain scan with minimum object properties. Computers are not double-counted as users. Contacts, service-account classes and other object types are excluded. Object identities are not exported.','A failed or timed-out count scan produces unknown counts, not zero. Successful reads cannot prove ACL-filtered object visibility.','Direct GPO links include stored references, including cross-domain GPO references. GPO names/targets are not queried; inherited policy and resultant-set-of-policy are not computed.','Delegation shows reported allow/deny DACL ACEs with SIDs, object GUIDs and inheritance flags. No trustee/schema resolution, group expansion or effective-access assessment is performed.','GPO inheritance blocking and DACL inheritance protection are separate fields. Missing provider properties and failed DACL reads remain null.','Collection is bounded by one overall worker budget. Completed categories survive timeout; unfinished category rows may not be available. No AD/GPO/ACL changes, remediation, scores, recommendations or email occur.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
 $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'OrganizationalUnits.html' 'Organizational-Units'
 Write-PSISitesLog $log $run 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
 if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning 'Report saved; automatic opening failed.'}}
 [pscustomobject]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADOrganizationalUnit';Domain=$context.Domain;ObservedOUs=$model.Data.ous.Count;ObservedACEs=$model.Data.delegations.Count;IncompleteCategories=@($model.Data.collection|Where-Object{$_.Status -ne 'Succeeded'}).Count;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$log;OutputFolder=$folder}
}catch{Write-PSISitesLog $log $run 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId;throw}
