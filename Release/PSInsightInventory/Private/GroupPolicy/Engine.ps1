#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName='Live')]
param(
 [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$')][string]$Domain,
 [Parameter(ParameterSetName='Live')][ValidateRange(10,3600)][int]$TimeoutSeconds=300,
 [Parameter(Mandatory=$true,ParameterSetName='Sample')][switch]$SampleData,
 [string]$OutputPath='C:\Temp\Reports',[switch]$Open
)
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
$moduleRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Sites') $f)}
foreach($f in @('Helpers.ps1','Collector.ps1')){. (Join-Path $PSScriptRoot $f)}
$started=[datetimeoffset]::Now;$run=[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $OutputPath ('PSInsightInventory_GroupPolicy_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$run)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$log=Join-Path $logs ('GroupPolicy_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
 Write-PSISitesLog $log $run 'Run' 'Start' 'Started' $Domain ('Group Policy inventory; SampleData='+[bool]$SampleData)
 if($SampleData){$fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/GroupPolicy.sample.json'))|ConvertFrom-Json;$context=$fixture.context;$envelopes=@($fixture.envelopes)}
 else{
  if($env:OS -ne 'Windows_NT'){throw 'Live Group Policy inventory requires Windows with RSAT ActiveDirectory and GroupPolicy.'}
  foreach($name in @('ActiveDirectory','GroupPolicy')){if(-not (Get-Module -ListAvailable $name)){throw "Required RSAT module missing: $name"}}
  $collected=Invoke-PSIGpoCollection $Domain $TimeoutSeconds $script:PSIGpoCollector ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Helpers.ps1')))
  $context=$collected.Context;$envelopes=@($collected.Envelopes)
 }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
 $model=ConvertTo-PSIGpoModel $context $envelopes
 foreach($e in $model.Data.collection){Write-PSISitesLog $log $run 'Collection' $e.Name $e.Status $context.Server $e.Message ([long]$e.'Duration ms') ([string]$e.'Error ID')}
 foreach($e in $model.Data.objectQueries){Write-PSISitesLog $log $run 'ObjectCollection' $e.Operation $e.Status $e.Target $e.Message ([long]$e.'Duration ms') ([string]$e.'Error ID')}
 $now=[datetimeoffset]::Now
 $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADGroupPolicy';title='Group Policy Inventory';run=$run;dataSource=if($SampleData){'Sample'}else{'Live'};scope='GPOs in one domain; links in that domain and forest sites';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$started.ToString('o');generated=$now.ToString('o');generatedDisplay=$now.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;expectedQueries=9;notice=if($SampleData){'SAMPLE DATA. Fictional Group Policy configuration; no infrastructure was contacted.'}else{'Read-only configuration snapshot from one pinned DC. No resultant-policy or endpoint processing test.'};limitations=@('GPO metadata is limited to the explicit domain. Link containers include that domain, its OUs and all forest sites; only links referencing the selected domain are retained. Cross-domain links on other domains and OUs are outside scope.','Reported permissions come from Get-GPPermission. GpoApply entries describe reported permission levels, not effective access, full ACE semantics, nested membership or actual policy applicability.','Settings structure lists extension names, top-level setting types and node counts. Individual setting values, scripts, arbitrary preference values and raw XML are not exported. Counts are XML structure counts, not distinct configured policies.','WMI definitions and references are stored configuration. Filters are not executed, and external-domain filter targets are not queried.','AD/SYSVOL versions are returned by Get-GPO against the selected DC, not compared across DCs. No replication or mismatch assessment is made.','Collection may be partial. Successful GPO/source records survive independent failures; inspect Object collection. A successful ledger category only means the ledger itself was captured.','No unlinked-GPO cleanup inference, severity, scoring, recommendations, backup, policy update, gpupdate, remediation or email is performed. Successful reads cannot prove ACL-filtered visibility.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
 $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'GroupPolicy.html' 'Group-Policy'
 Write-PSISitesLog $log $run 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
 if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning 'Report saved; automatic opening failed.'}}
 [pscustomobject]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADGroupPolicy';Domain=$context.Domain;ObservedGPOs=$model.Data.gpos.Count;ObservedLinks=$model.Data.links.Count;IncompleteCategories=@($model.Data.collection|Where-Object{$_.Status -ne 'Succeeded'}).Count;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$log;OutputFolder=$folder}
}catch{Write-PSISitesLog $log $run 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId;throw}
