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
foreach($file in @('Helpers.ps1','Export.ps1')){. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Sites') $file)}
foreach($file in @('Collector.ps1','Model.ps1')){. (Join-Path $PSScriptRoot $file)}
$now=[datetimeoffset]::Now;$runId=[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $OutputPath ('PSInsightInventory_Forest_'+$now.ToString('yyyyMMdd_HHmmss_fff')+'_'+$runId)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$log=Join-Path $logs ('ForestInventory_'+$now.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
    Write-PSISitesLog $log $runId 'Run' 'Start' 'Started' $Domain ('Forest/domain inventory; SampleData='+[bool]$SampleData)
    if($SampleData){$fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/Forest.sample.json'))|ConvertFrom-Json;$context=$fixture.context;$envelopes=@($fixture.envelopes)}
    else{
        if($env:OS -ne 'Windows_NT'){throw 'Live forest inventory requires Windows and RSAT ActiveDirectory.'}
        if($Domain -notmatch '\.'){throw 'Specify a DNS connection domain. The inventory scope is the entire forest.'}
        if(-not (Get-Module -ListAvailable ActiveDirectory)){throw 'RSAT ActiveDirectory module is required.'}
        if(-not (Get-Command Test-PSIInventoryQuiet -ErrorAction SilentlyContinue) -or -not (Test-PSIInventoryQuiet)){Write-Information "Reading forest metadata and member domains using $Domain..." -InformationAction Continue}
        $collected=Invoke-PSIForestCollection -Domain $Domain -Credential $Credential -TimeoutSeconds $TimeoutSeconds
        $context=$collected.Context;$envelopes=$collected.Envelopes
    }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
    $model=ConvertTo-PSIForestModel $context $envelopes
    foreach($entry in $model.Data.collection){Write-PSISitesLog $log $runId 'Collection' $entry.Name $entry.Status $entry.Target $entry.Message ([long]$entry.'Duration ms') ([string]$entry.'Error ID')}
    $end=[datetimeoffset]::Now;$expected=2+2*@($context.Domains).Count
    $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADForest';title='Forest & Domain Inventory';run=$runId;dataSource=if($SampleData){'Sample'}else{'Live'};scope='Forest-wide metadata and member domains';forest=$context.Forest;connectionDomain=$context.Domain;sourceDC=$context.Server;configurationNC=$context.ConfigurationNC;started=$now.ToString('o');generated=$end.ToString('o');generatedDisplay=$end.ToString('dd MMM yyyy, HH:mm:ss zzz');timeZone=[timezoneinfo]::Local.Id;expectedQueries=$expected;domainCount=@($context.Domains).Count;domainDetailsCollected=$model.DomainDetailsCollected;policiesCollected=$model.PoliciesCollected;notice=if($SampleData){'SAMPLE DATA. Fictional forest. No infrastructure was contacted.'}else{'Read-only forest and domain inventory. The supplied domain is the starting point; all returned forest member domains are queried.'};limitations=@('Functional levels and role owners are configuration values, not compatibility or health assessments.','Forest membership references remain visible even when a member-domain query fails; unavailable values remain unknown.','Hosted naming contexts are observed on the selected DCs; partition references are read separately from Configuration.','Only configured additional UPN/SPN suffix lists are shown; they are not a census of suffixes used by accounts.','Default domain password policies are inventory only. Fine-grained policies and user-effective password policies are not evaluated.','Successful reads cannot prove ACL-filtered attribute/object visibility. Server references do not prove endpoint availability.','No WinRM, object changes, trust enumeration, password/hash retrieval or email is performed.');timeoutSeconds=if($SampleData){$null}else{$TimeoutSeconds}}
 if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($envelopes);Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
    $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'Forest.html' 'Forest-And-Domains'
    $success=@($model.Data.collection|Where-Object{$_.Status -eq 'Succeeded'}).Count
    Write-PSISitesLog $log $runId 'Export' 'Report' 'Succeeded' $context.Server $paths.HtmlReport
    if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning "Report saved, but could not open automatically: $($_.Exception.Message)"}}
    [pscustomobject][ordered]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADForest';Scope='Forest-wide';Forest=$context.Forest;DomainReferences=@($context.Domains).Count;DomainDetailsCollected=$model.DomainDetailsCollected;PoliciesCollected=$model.PoliciesCollected;QueriesCollected=$success;QueriesUnavailable=$expected-$success;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$log;OutputFolder=$folder}
}catch{Write-PSISitesLog $log $runId 'Run' 'Complete' 'Failed' $Domain $_.Exception.Message 0 $_.FullyQualifiedErrorId;throw}
