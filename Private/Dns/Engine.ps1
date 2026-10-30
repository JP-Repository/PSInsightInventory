#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName='Live')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^(?=.{1,253}$)[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$')][string]$Domain,
    [Parameter(ParameterSetName='Live')][string[]]$ComputerName,
    [Parameter(ParameterSetName='Live')][pscredential]$Credential,
    [Parameter(ParameterSetName='Live')][ValidateRange(1,16)][int]$ThrottleLimit=4,
    [Parameter(ParameterSetName='Live')][ValidateRange(15,3600)][int]$TargetTimeoutSeconds=180,
    [Parameter(ParameterSetName='Live')][ValidateRange(10,600)][int]$DiscoveryTimeoutSeconds=60,
    [Parameter(ParameterSetName='Live')][ValidateRange(3,120)][int]$OpenTimeoutSeconds=15,
    [Parameter(ParameterSetName='Live')][switch]$UseSSL,
    [Parameter(ParameterSetName='Live')][ValidateRange(0,65535)][int]$Port=0,
    [Parameter(Mandatory=$true,ParameterSetName='Sample')][switch]$SampleData,
    [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',
    [switch]$Open
)
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
foreach($f in @('Common.ps1','Schema.ps1','RemoteCollector.ps1')){. (Join-Path $PSScriptRoot $f)}
$moduleRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach($f in @('Helpers.ps1','Export.ps1')){. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Sites') $f)}
$started=[datetimeoffset]::Now;$script:DCInvRunId=[guid]::NewGuid().ToString('N').Substring(0,8)
$folder=Join-Path $OutputPath ('PSInsightInventory_Dns_'+$started.ToString('yyyyMMdd_HHmmss_fff')+'_'+$script:DCInvRunId)
$reports=Join-Path $folder 'Reports';$logs=Join-Path $folder 'Logs';$null=New-Item -ItemType Directory -Path $reports,$logs -Force
$script:DCInvLogPath=Join-Path $logs ('DnsInventory_'+$started.ToString('yyyyMMdd_HHmmss')+'.jsonl')
$script:DCInvSections=Get-PSIDnsSchema;$script:DCInvData=[ordered]@{};$script:DCInvSeen=@{}
foreach($k in $script:DCInvSections.Keys){$script:DCInvData[$k]=New-Object collections.ArrayList}
try{
    Write-DCInvLog 'Information' 'Run' $Domain 'Start' 'Started' ('DNS inventory; domain DC scope; SampleData='+[bool]$SampleData)
    if($SampleData){
        $fixture=[IO.File]::ReadAllText((Join-Path $moduleRoot 'Assets/Dns.sample.json'))|ConvertFrom-Json
        $scope=$fixture.domain
        foreach($e in $fixture.envelopes){Add-DCInvSection $e}
    }else{
        if($env:OS -ne 'Windows_NT'){throw 'Live DNS inventory requires Windows, RSAT ActiveDirectory and authorized WinRM access.'}
        if($Domain -notmatch '\.'){throw 'Specify one DNS domain name.'}
        if(-not (Get-Module -ListAvailable ActiveDirectory)){throw 'RSAT ActiveDirectory module is required.'}
        $found=@(Invoke-DCInvDiscovery $Domain $Credential $DiscoveryTimeoutSeconds)
        $targets=@(Select-DCInvTargets $found $Domain @($ComputerName|Where-Object{$_}));$scope=$Domain
        foreach($dc in $targets){Add-DCInvSection ([pscustomobject]@{Target=$dc.HostName;Key='dcs';Status='Succeeded';Records=@([pscustomobject]@{Name=$dc.HostName;Domain=$dc.Domain;Site=$dc.Site;OS=$dc.OperatingSystem;Inventory='Pending';'Zones observed'=$null});Method='ADWS / explicit domain DC discovery';StartedAt=$started.ToString('o');CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=0;ErrorId=$null;ErrorMessage=$null})}
        $settings=[pscustomobject]@{ThrottleLimit=$ThrottleLimit;TargetTimeoutSeconds=$TargetTimeoutSeconds;OpenTimeoutSeconds=$OpenTimeoutSeconds;UseSSL=[bool]$UseSSL;Port=$Port}
        Invoke-DCInvWorkers $targets $script:PSIDnsWorker $script:PSIDnsRemote.ToString() $settings $Credential
    }
    foreach($dc in $script:DCInvData.dcs){
        $ledger=@($script:DCInvData.collection.ToArray()|Where-Object{$_.Name -eq $dc.Name})
        if($ledger.Count -ne 15){throw "DNS coverage contract failed for $($dc.Name); expected 15 category outcomes."}
        $dc.Inventory=if(@($ledger|Where-Object{$_.Status -notin @('Succeeded','NotApplicable')}).Count){'Partial'}else{'Complete'}
        $zoneOutcome=@($ledger|Where-Object{$_.'Check ID' -eq 'zones'})[0]
        $dc.'Zones observed'=if($zoneOutcome.Status -eq 'Succeeded'){@($script:DCInvData.zones.ToArray()|Where-Object{$_.Name -eq $dc.Name}).Count}elseif($zoneOutcome.Status -eq 'NotApplicable'){$null}else{$null}
    }
 if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Preparing report data' -Force}
    $model=ConvertTo-PSIDnsModel;$end=[datetimeoffset]::Now
    $meta=[ordered]@{moduleName='PSInsightInventory';version='1.0.0';inventoryId='ADDns';title='DNS Configuration Inventory';run=$script:DCInvRunId;dataSource=if($SampleData){'Sample'}else{'Live'};scope='Selected domain controllers in one explicit domain';forest='Not queried (domain-scoped inventory)';connectionDomain=$scope;sourceDC='Multiple selected DCs';configurationNC='Not queried';started=$started.ToString('o');generated=$end.ToString('o');generatedDisplay=$end.ToString('dd MMM yyyy, HH:mm:ss zzz');expectedQueries=$model.Data.dcs.Count*15;selectedDCs=$model.Data.dcs.Count;notice=if($SampleData){'SAMPLE DATA. Fictional DC DNS configuration; no infrastructure was contacted.'}else{'Read-only DNS configuration on selected DCs in one domain. This is not a DNS health or resolution test.'};limitations=@('The target list contains only DCs discovered in the explicitly supplied domain; non-DC DNS servers and child domains are not auto-enumerated.','Client adapter resolvers, server forwarders and conditional forwarders are separate datasets.','Zone observations repeat per server. Zone names across DCs are not merged into a claimed unique/consistent configuration.','Per-zone aging, delegation and scope reads are limited to Primary zones in the default virtualization instance; excluded types are listed as NotAttempted. Delegation reads use the default zone scope.','One failed/unsupported zone query leaves other successful rows intact; category status becomes Partial. See Per-zone collection for details.','An absent DNS role is NotApplicable; access denial, missing modules and failed queries are not treated as absence.','NS records are read from Primary, Secondary and Stub zones in the default zone scope/virtualization instance. NS address reads use only exact A/AAAA nodes in the most-specific matching hosted Primary/Secondary zone; external targets are not resolved. See per-query outcomes.',
'No full resource-record dump, resolver probe, scavenging pass, DNS update, cache flush, service change or email is performed. Inventory completeness is not health.');configuration=@{ThrottleLimit=$ThrottleLimit;TargetTimeoutSeconds=$TargetTimeoutSeconds;OpenTimeoutSeconds=$OpenTimeoutSeconds;UseSSL=[bool]$UseSSL;Port=$Port}}
    if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Complete-PSIInventoryCollectionDisplay -Collection $model.Data.collection;Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
    $paths=Export-PSISitesReport $model $meta $moduleRoot $reports 'Dns.html' 'Dns-Configuration'
    Write-DCInvLog 'Information' 'Export' $scope 'Report' 'Succeeded' $paths.HtmlReport
    if($Open){try{Invoke-Item -LiteralPath $paths.HtmlReport}catch{Write-Warning "Report saved, but could not open automatically: $($_.Exception.Message)"}}
    [pscustomobject][ordered]@{ModuleName='PSInsightInventory';ModuleVersion='1.0.0';InventoryId='ADDns';Domain=$scope;SelectedDCs=$model.Data.dcs.Count;DNSRoleObserved=@($model.Data.role|Where-Object{$_.'DNS role present' -eq $true}).Count;PartialInventories=@($model.Data.dcs|Where-Object{$_.Inventory -eq 'Partial'}).Count;ZoneObservations=$model.Data.zones.Count;DataSource=$meta.dataSource;HtmlReport=$paths.HtmlReport;JsonSnapshot=$paths.JsonSnapshot;CsvFolder=$paths.CsvFolder;LogFile=$script:DCInvLogPath;OutputFolder=$folder}
}catch{Write-DCInvLog 'Error' 'Run' $Domain 'Complete' 'Failed' $_.Exception.Message 0 $_.FullyQualifiedErrorId $_.Exception.Message;throw}
