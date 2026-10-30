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
$folder=Join-Path $OutputPath ('PSInsightInventory_Groups_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$run)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$log=Join-Path $logs ('Groups_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
 Write-PSISitesLog $log $run 'Run' 'Start' 'Started' $Domain ('Group inventory; SampleData='+[bool]$SampleData)
 if($SampleData){$fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/Groups.sample.json'))|ConvertFrom-Json;$context=$fixture.context;$envelopes=@($fixture.envelopes)}
 else{
  if($env:OS -ne 'Windows_NT'){throw 'Live Group inventory requires Windows with RSAT ActiveDirectory.'}
  foreach($name in @('ActiveDirectory')){if(-not (Get-Module -ListAvailable $name)){throw "Required RSAT module missing: $name"}}
  $collected=Invoke-PSIGroupCollection $Domain $TimeoutSeconds $script:PSIGroupCollector ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Helpers.ps1')))
  $context=$collected.Context;$envelopes=@($collected.Envelopes)
 }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
 $model=if($SampleData){ConvertTo-PSIGroupModel $context $envelopes}else{ConvertTo-PSIGroupModel $context $envelopes $(if($collected.TimedOut){'TimedOut'}else{'Failed'})}
 foreach($e in $model.Data.collection){Write-PSISitesLog $log $run 'Collection' $e.Name $e.Status $context.Server $e.Message ([long]$e.'Duration ms') ([string]$e.'Error ID')}
 foreach($lookup in @($model.Data.objectQueries|Where-Object{$_.Status -eq 'Failed'})){Write-PSISitesLog $log $run 'MemberResolution' $lookup.Name $lookup.Status $lookup.Target $lookup.Message}
 $now=[datetimeoffset]::Now
 $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADGroup';title='Group Inventory';run=$run;dataSource=if($SampleData){'Sample'}else{'Live'};scope='Group objects in one explicit domain';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$started.ToString('o');generated=$now.ToString('o');generatedDisplay=$now.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;expectedQueries=1+$model.Data.groups.Count;notice=if($SampleData){'SAMPLE DATA. Fictional Group configuration; no infrastructure was contacted.'}else{'Read-only configuration snapshot from one pinned DC. No resultant-policy or endpoint processing test.'};limitations=@('One explicit domain only; local group metadata and direct member attribute links. External/child-domain references are retained but not dereferenced.','Direct linked-member counts exclude primaryGroupID membership. Counts are not effective membership, recursive expansion, access-token membership or unique people.','Ranged LDAP member reads retain complete per-group lists. A failed/incomplete range discards that group list; its count remains unknown rather than zero. Completed groups survive timeout.','Nested and parent links are derived only between groups in the selected-domain catalog using successful member lists. No recursive expansion or cycle traversal occurs; parent coverage can be incomplete.','Member types are reported object classes from pinned local lookups or the group catalog. Failed and excluded lookups retain raw DNs and unknown type. Local foreignSecurityPrincipal objects are not resolved to external accounts.','managedBy is a directory reference, not proof of business ownership or delegated rights. Successful reads cannot prove ACL-filtered visibility.','One bounded worker reads metadata then each group list, reusing member lookups. Large directories may need a higher timeout. No endpoint/partner queries, changes, privilege scores, recommendations or email occur.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
 $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'Groups.html' 'Groups'
 Write-PSISitesLog $log $run 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
 if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning 'Report saved; automatic opening failed.'}}
 [pscustomobject]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADGroup';Domain=$context.Domain;ObservedGroups=$model.Data.groups.Count;ObservedMemberLinks=$model.Data.members.Count;IncompleteQueries=@($model.Data.collection|Where-Object{$_.Status -ne 'Succeeded'}).Count;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$log;OutputFolder=$folder}
}catch{Write-PSISitesLog $log $run 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId;throw}
