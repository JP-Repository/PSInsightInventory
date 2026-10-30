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
$folder=Join-Path $OutputPath ('PSInsightInventory_Computers_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$run)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$log=Join-Path $logs ('Computers_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
 Write-PSISitesLog $log $run 'Run' 'Start' 'Started' $Domain ('Computer inventory; SampleData='+[bool]$SampleData)
 if($SampleData){$fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/Computers.sample.json'))|ConvertFrom-Json;$context=$fixture.context;$envelopes=@($fixture.envelopes)}
 else{
  if($env:OS -ne 'Windows_NT'){throw 'Live Computer inventory requires Windows with RSAT ActiveDirectory.'}
  foreach($name in @('ActiveDirectory')){if(-not (Get-Module -ListAvailable $name)){throw "Required RSAT module missing: $name"}}
  $collected=Invoke-PSIComputerCollection $Domain $TimeoutSeconds $script:PSIComputerCollector ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Helpers.ps1')))
  $context=$collected.Context;$envelopes=@($collected.Envelopes)
 }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
 $model=ConvertTo-PSIComputerModel $context $envelopes
 foreach($e in $model.Data.collection){Write-PSISitesLog $log $run 'Collection' $e.Name $e.Status $context.Server $e.Message ([long]$e.'Duration ms') ([string]$e.'Error ID')}
 $now=[datetimeoffset]::Now
 $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADComputer';title='Computer Inventory';run=$run;dataSource=if($SampleData){'Sample'}else{'Live'};scope='Computer objects in one explicit domain';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$started.ToString('o');generated=$now.ToString('o');generatedDisplay=$now.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;expectedQueries=1;notice=if($SampleData){'SAMPLE DATA. Fictional Computer configuration; no infrastructure was contacted.'}else{'Read-only configuration snapshot from one pinned DC. No resultant-policy or endpoint processing test.'};limitations=@('One explicit domain; computer objects only. Child domains and endpoints are not enumerated or contacted.','OS, version/build, service pack and timestamps are reported directory attributes and may be missing or outdated. No installed KB, exact patch level, uptime or online status is collected.','OS family and server release are labels derived conservatively from the reported OS name. Unknown/unclassified values remain separate; build numbers are parsed only from recognizable reported version formats.','Last logon timestamp is replicated and approximate. It does not identify the signed-in user, exact last logon or a stale-device finding. Zero/missing values remain null.','DC role uses returned userAccountControl and primaryGroupID indicators. This is reported directory configuration, not an availability probe.','Locations are immediate parent DNs, including CN containers. Counts are returned computer objects rather than a complete device population. ACL-filtered objects may not be visible.','SPNs and delegation flags/targets are reported configuration. RBCD descriptor presence is recorded without exporting its binary content or claiming effective permissions; missing descriptors remain unknown.','No device-health verdict, stale-device recommendation, endpoint connection, remediation, change, credential export or email occurs.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
 $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'Computers.html' 'Computers'
 Write-PSISitesLog $log $run 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
 if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning 'Report saved; automatic opening failed.'}}
 [pscustomobject]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADComputer';Domain=$context.Domain;ObservedComputers=$model.Data.computers.Count;OsGroups=$model.Data.osSummary.Count;CollectionStatus=$model.Data.collection[0].Status;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$log;OutputFolder=$folder}
}catch{Write-PSISitesLog $log $run 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId;throw}
