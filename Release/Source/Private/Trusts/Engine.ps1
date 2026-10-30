#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName='Live')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^(?=.{1,253}$)[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$')][string]$Domain,
    [Parameter(ParameterSetName='Live')][pscredential]$Credential,
    [Parameter(ParameterSetName='Live')][ValidateRange(10,1800)][int]$TimeoutSeconds=180,
    [Parameter(Mandatory=$true,ParameterSetName='Sample')][switch]$SampleData,
    [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',
    [switch]$Open
)
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
$moduleRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Sites') $f)}
. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Forest') 'Collector.ps1')
foreach($f in @('Collector.ps1','Model.ps1')){. (Join-Path $PSScriptRoot $f)}
$started=[datetimeoffset]::Now;$runId=[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $OutputPath ('PSInsightInventory_Trusts_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$runId)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$log=Join-Path $logs ('TrustInventory_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
    Write-PSISitesLog $log $runId 'Run' 'Start' 'Started' $Domain ('Trust inventory; local forest observations; SampleData='+[bool]$SampleData)
    if($SampleData){$fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/Trusts.sample.json'))|ConvertFrom-Json;$context=$fixture.context;$envelopes=@($fixture.envelopes)}
    else{
        if($env:OS -ne 'Windows_NT'){throw 'Live trust inventory requires Windows and RSAT ActiveDirectory.'}
        if($Domain -notmatch '\.'){throw 'Specify a DNS connection domain.'}
        if(-not (Get-Module -ListAvailable ActiveDirectory)){throw 'RSAT ActiveDirectory module is required.'}
        if(-not (Get-Command Test-PSIInventoryQuiet -ErrorAction SilentlyContinue) -or -not (Test-PSIInventoryQuiet)){Write-Information "Reading local-forest trust objects using $Domain..." -InformationAction Continue}
        $collected=Invoke-PSIForestCollection -Domain $Domain -Credential $Credential -TimeoutSeconds $TimeoutSeconds -Worker $script:PSITrustCollector -QueryPlan Trusts
        $context=$collected.Context;$envelopes=$collected.Envelopes
    }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
    $model=ConvertTo-PSITrustModel $context $envelopes
    foreach($entry in $model.Data.collection){Write-PSISitesLog $log $runId 'Collection' $entry.Name $entry.Status $entry.Target $entry.Message ([long]$entry.'Duration ms') ([string]$entry.'Error ID')}
    $now=[datetimeoffset]::Now;$expected=@($context.Domains).Count
    $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADTrusts';title='Trust Inventory';run=$runId;dataSource=if($SampleData){'Sample'}else{'Live'};scope='Trust objects observed in local forest member domains';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$started.ToString('o');generated=$now.ToString('o');generatedDisplay=$now.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;expectedQueries=$expected;domainCount=$expected;domainsCollected=$model.DomainsCollected;notice=if($SampleData){'SAMPLE DATA. Fictional trust configuration; no infrastructure was contacted.'}else{'Local-forest TDO observations only. Remote trust partners are not contacted.'};limitations=@('Direction is relative to the observed local domain; it describes configured trust direction, not a verified authentication path.','Each TDO observation is retained. Reciprocal objects are not merged or treated as proof that both ends agree.','SIDFilteringForestAware and SIDFilteringQuarantined are reported separately; neither alone is labeled overall SID filtering enabled or disabled.','Selective authentication and encryption/delegation values are reported configuration, not proof of effective access or negotiated algorithms.','Only local forest member domains are queried. Partner-side configuration, trust validation, connectivity and secure-channel checks are outside this inventory.','Successful reads cannot prove ACL-filtered object or attribute visibility. Failed queries leave counts unknown; a successful zero-row query remains empty.','Explicit safe properties are retained; trust authentication secret attributes are not requested or exported. No changes or email are performed.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
    $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'Trusts.html' 'Trust-Inventory'
    Write-PSISitesLog $log $runId 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
    if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning "Report saved, but could not open automatically: $($_.Exception.Message)"}}
    [pscustomobject][ordered]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADTrusts';Scope='Local forest domain observations';Forest=$context.Forest;DomainsCollected=$model.DomainsCollected;DomainsReferenced=$expected;ObservedTrustObjects=$model.Data.trusts.Count;ObservedPartners=$model.Data.partners.Count;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$log;OutputFolder=$folder}
}catch{Write-PSISitesLog $log $runId 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId;throw}
