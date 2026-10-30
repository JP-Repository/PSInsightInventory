#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName='Live')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^(?=.{1,253}$)[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$')][string]$Domain,
    [Parameter(ParameterSetName='Live')][pscredential]$Credential,
    [Parameter(ParameterSetName='Live')][ValidateRange(10,600)][int]$TimeoutSeconds=120,
    [Parameter(Mandatory=$true,ParameterSetName='Sample')][switch]$SampleData,
    [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',
    [switch]$Open
)
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
foreach($file in @('Helpers.ps1','Collector.ps1','Model.ps1','Export.ps1')){. (Join-Path $PSScriptRoot $file)}
$moduleRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$started=[datetimeoffset]::Now;$runId=[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $OutputPath ('PSInsightInventory_Sites_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$runId)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$logPath=Join-Path $logs ('SitesInventory_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
$required=@('sites','subnets','links','bridges','servers','settings','transports','ntds')
$context=$null;$envelopes=New-Object collections.ArrayList;$seen=@{};$job=$null
try{
    Write-PSISitesLog $logPath $runId 'Run' 'Start' 'Started' $Domain ('Forest-wide inventory; SampleData='+[bool]$SampleData)
    if($SampleData){
        $fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/SitesAndServices.sample.json'))|ConvertFrom-Json
        $context=$fixture.context
        foreach($key in $required){[void]$envelopes.Add([pscustomobject]@{Key=$key;Status='Succeeded';Records=@($fixture.raw.$key);Method='Synthetic fixture / Configuration partition';CollectedAt=$fixture.collectedAt;DurationMs=0;ErrorId=$null;ErrorMessage=$null})}
    }else{
        if($env:OS -ne 'Windows_NT'){throw 'Live Sites inventory requires Windows and the RSAT ActiveDirectory module.'}
        if($Domain -notmatch '\.'){throw 'Specify a DNS domain name. It selects the connection domain, not a domain-only report scope.'}
        if(-not (Get-Module -ListAvailable ActiveDirectory)){throw 'RSAT ActiveDirectory module is required on the collection host.'}
        if(-not (Get-Command Test-PSIInventoryQuiet -ErrorAction SilentlyContinue) -or -not (Test-PSIInventoryQuiet)){Write-Information "Reading forest-wide Sites configuration using $Domain..." -InformationAction Continue}
        $collected=Invoke-PSISitesCollection -Domain $Domain -Credential $Credential -TimeoutSeconds $TimeoutSeconds
        $context=$collected.Context
        foreach($entry in $collected.Envelopes){[void]$envelopes.Add($entry)}
    }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
    $model=ConvertTo-PSISitesModel $context $envelopes.ToArray()
    foreach($entry in $model.Data.collection){Write-PSISitesLog $logPath $runId 'Collection' $entry.Name $entry.Status $context.Server $entry.Message ([long]$entry.'Duration ms') ([string]$entry.'Error ID')}
    $now=[datetimeoffset]::Now
    $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADSitesAndServices';title='Sites & Services Inventory';run=$runId;dataSource=if($SampleData){'Sample'}else{'Live'};scope='Forest-wide Configuration partition';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$started.ToString('o');generated=$now.ToString('o');generatedDisplay=$now.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;notice=if($SampleData){'SAMPLE DATA. Fictional forest. No directory or server was contacted.'}else{'Read-only configuration snapshot from one DC. Domain selects the connection; Sites configuration is forest-wide.'};limitations=@('Directory objects and settings, not server availability or replication health.','Successful queries cannot prove ACL-filtered object/attribute visibility. Null values can mean not set or not returned.','Stored schedules use UTC; they are not effective replication schedules. Transport options and combined paths can affect behavior.','DC objects are observed NTDS Settings objects beneath server objects, not a live DC census.','No WinRM, remote registry, service probes or infrastructure changes are used by this command.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
    $paths=Export-PSISitesReport $model $meta $moduleRoot $reports
    Write-PSISitesLog $logPath $runId 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
    $completed=@($model.Data.collection | Where-Object{$_.Status -eq 'Succeeded'}).Count
    if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning "Report saved, but could not open automatically: $($_.Exception.Message)"}}
    [pscustomobject][ordered]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADSitesAndServices';Scope='Forest-wide';Forest=$context.Forest;ConnectionDomain=$context.Domain;SourceDC=$context.Server;DataSource=$meta.dataSource;QueriesCollected=$completed;QueriesUnavailable=8-$completed;Sites=if($model.Coverage.sites){$model.Data.sites.Count}else{$null};SiteLinks=if($model.Coverage.links){$model.Data.links.Count}else{$null};HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$logPath;OutputFolder=$folder}
}catch{
    Write-PSISitesLog $logPath $runId 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId
    throw
}finally{if($null -ne $job){if($job.State -in @('Running','NotStarted','Blocked')){Stop-Job $job -ErrorAction SilentlyContinue};Remove-Job $job -Force -ErrorAction SilentlyContinue}}
