#requires -Version 5.1
<#
.SYNOPSIS
Creates a read-only, domain-scoped domain-controller inventory and offline HTML console.
.DESCRIPTION
Private PSInsightInventory execution engine. Invoked through the module public command.
Live mode requires Windows, the ActiveDirectory module and authorized WinRM access.
Uses Kerberos; does not enable remoting, change trust settings, or make infrastructure changes.
Sample mode does not import AD modules or contact infrastructure.
.PARAMETER Domain
One DNS domain name. Child domains are not enumerated. Required for live runs.
.PARAMETER ComputerName
Optional exact short names or FQDNs chosen from the discovered domain DCs. No wildcards.
.PARAMETER SampleData
Render the embedded fictional inventory without contacting AD or DCs.
.PARAMETER OutputPath
Parent output folder. Default C:\Temp\Reports. Each run gets a unique folder.
.PARAMETER Credential
Optional credential used for directory reads and WinRM Kerberos authentication. Never logged.
.PARAMETER ThrottleLimit
Maximum concurrent local worker jobs. Default 4.
.PARAMETER TargetTimeoutSeconds
Wall-clock budget for each DC worker, including local job startup and all its categories.
Completed category results are retained if a later category times out. Default 180 seconds.
.PARAMETER DiscoveryTimeoutSeconds
Wall-clock wait budget for domain/DC discovery. Default 60 seconds.
.PARAMETER OpenTimeoutSeconds
WinRM connection-open budget. This is not a per-command timeout. Default 15 seconds.
.PARAMETER SkipRemote
Collect directory categories only. Remote categories remain NotAttempted and inventory Partial.
.PARAMETER UseSSL
Use WinRM HTTPS with normal certificate validation. Does not disable certificate checks.
.PARAMETER Port
Optional WinRM port. Defaults to 5985 for HTTP or 5986 with -UseSSL when omitted.
.PARAMETER Open
Open the generated HTML using the local default application after export.
.EXAMPLE
Invoke-ADInfrastructureInventory -SampleData -OutputPath C:\Temp\Reports -Open
.EXAMPLE
Invoke-ADInfrastructureInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADInfrastructureInventory -Domain example.test -ComputerName dc01.example.test -SkipRemote
.NOTES
Version 1.0.0. Target: Windows PowerShell 5.1. No health verdict, email or remediation.
#>
[CmdletBinding(DefaultParameterSetName='Live')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Live')]
    [ValidatePattern('^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$')][string]$Domain,
    [Parameter(ParameterSetName='Live')][ValidateNotNullOrEmpty()][string[]]$ComputerName,
    [Parameter(Mandatory=$true,ParameterSetName='Sample')][switch]$SampleData,
    [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',
    [Parameter(ParameterSetName='Live')][pscredential]$Credential,
    [Parameter(ParameterSetName='Live')][ValidateRange(1,16)][int]$ThrottleLimit=4,
    [Parameter(ParameterSetName='Live')][ValidateRange(15,3600)][int]$TargetTimeoutSeconds=180,
    [Parameter(ParameterSetName='Live')][ValidateRange(10,600)][int]$DiscoveryTimeoutSeconds=60,
    [Parameter(ParameterSetName='Live')][ValidateRange(3,120)][int]$OpenTimeoutSeconds=15,
    [Parameter(ParameterSetName='Live')][switch]$SkipRemote,
    [Parameter(ParameterSetName='Live')][switch]$UseSSL,
    [Parameter(ParameterSetName='Live')][ValidateRange(0,65535)][int]$Port=0,
    [switch]$Open
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:DCInvVersion='1.0.0'
$script:DCInvModuleRoot=Split-Path -Parent $PSScriptRoot
$script:DCInvRunId=[guid]::NewGuid().ToString('N').Substring(0,8)
$script:DCInvStarted=[datetimeoffset]::Now
$script:DCInvData=[ordered]@{}
$script:DCInvSeen=@{}
$script:DCInvSections=[ordered]@{
    dcs=@('Domain controllers',@('Name','Domain','Site','IPv4','OS','GC','Type','Inventory','OS version','IPv6'))
    system=@('System',@('Name','Manufacturer','Model','CPU','Memory GB','OS build','Last boot','OS caption','OS version','Uptime days'))
    disks=@('Disks',@('Name','Drive','Label','Capacity GB','Free GB','File system'))
    paths=@('AD paths',@('Name','Database','Log directory','SYSVOL'))
    network=@('Network',@('Name','Adapter','IPv4','IPv6','Subnet masks / prefixes','Gateway','Preferred DNS','Alternate DNS','Additional DNS','DNS search order','Interface index','MAC address','DHCP'))
    forwarders=@('DNS forwarders',@('Name','Forwarder','Order','Timeout seconds','Use root hints','Service state'))
    zones=@('DNS zones',@('Name','Zone','Type','AD integrated','Directory partition','Dynamic updates','Reverse lookup','Zone file'))
    conditional=@('Conditional forwarders',@('Name','DNS namespace','Master servers','AD integrated','Directory partition','Timeout seconds','Use recursion'))
    subnets=@('Subnets',@('Name','Subnet','Mapped site','Description','Location','Site DN'))
    partners=@('Replication partners',@('Name','Source partner','Naming context','Transport','Direction','Last success','Last attempt','Last result','Consecutive failures'))
    connections=@('Connections',@('Name','Connection','Source server','Destination site','Generated by','Enabled','Transport','Connection DN'))
    time=@('Time configuration',@('Name','Source','Type','NTP server setting','Announce flags'))
    roles=@('Directory roles',@('Name','Role','Scope'))
    certificates=@('Certificates',@('Name','Subject','Issuer','Template','Not after','Not before','Store','Thumbprint','Has private key','EKU'))
    shares=@('Shares',@('Name','Share','Path','Description','Type'))
    collection=@('Collection ledger',@('Name','Section','Outcome','Method','Collected at','Message','Check ID','Status','Duration ms','Record count','Error ID','Started at'))
}
foreach($key in $script:DCInvSections.Keys){$script:DCInvData[$key]=New-Object System.Collections.ArrayList}

function Get-DCInvValue($Object,[string]$Property){
    if($null -eq $Object){return $null}
    if($Object -is [System.Collections.IDictionary]){if($Object.Contains($Property)){return $Object[$Property]}else{return $null}}
    if($null -ne $Object.PSObject.Properties[$Property]){return $Object.$Property}
    return $null
}
function ConvertTo-DCInvFlat($Value){
    if($null -eq $Value){return $null}
    if($Value -is [datetime] -or $Value -is [datetimeoffset]){return ([datetimeoffset]$Value).ToString('o')}
    if($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]){return $Value}
    if($Value -is [System.Collections.IEnumerable]){return (@($Value | ForEach-Object{[string]$_}) -join '; ')}
    return [string]$Value
}
function Write-DCInvLog([string]$Level,[string]$Phase,[string]$Target,[string]$Operation,[string]$Outcome,[string]$Message,[long]$DurationMs=0,[string]$ErrorId='', [string]$ErrorMessage=''){
    [pscustomobject][ordered]@{
        Timestamp=[datetimeoffset]::Now.ToString('o');Level=$Level;RunId=$script:DCInvRunId;Phase=$Phase
        Target=$Target;Operation=$Operation;Outcome=$Outcome;DurationMs=$DurationMs;Message=$Message;ErrorId=$ErrorId;ErrorMessage=$ErrorMessage
    } | ConvertTo-Json -Compress -Depth 5 | Add-Content -LiteralPath $script:DCInvLogPath -Encoding UTF8
}
function Add-DCInvSection($Envelope){
    if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items @($Envelope)}
    $key=[string]$Envelope.Key;$target=[string]$Envelope.Target
    if(-not $script:DCInvSections.Contains($key) -or $key -eq 'collection'){throw "Unknown category envelope: $key"}
    $identity=$target+'|'+$key
    if($script:DCInvSeen.ContainsKey($identity)){throw "Duplicate category envelope: $identity"}
    $allowed=@('Succeeded','Failed','TimedOut','NotAttempted','NotApplicable')
    if([string]$Envelope.Status -notin $allowed){throw "Invalid collection status for $identity"}
    $rows=@($Envelope.Records | Where-Object{$null -ne $_})
    # Failed/timeout categories have no trusted records; completed categories are separate envelopes.
    if([string]$Envelope.Status -notin @('Succeeded','NotApplicable')){$rows=@()}
    foreach($row in $rows){
        $record=[ordered]@{}
        foreach($column in $script:DCInvSections[$key][1]){$record[$column]=ConvertTo-DCInvFlat (Get-DCInvValue $row $column)}
        $record.Name=$target
        [void]$script:DCInvData[$key].Add([pscustomobject]$record)
    }
    $outcome=switch([string]$Envelope.Status){'Succeeded'{'Collected'}'NotApplicable'{'Not applicable'}'NotAttempted'{'Not attempted'}'TimedOut'{'Timed out'}default{'Failed'}}
    $message=[string](Get-DCInvValue $Envelope 'ErrorMessage')
    if($Envelope.Status -eq 'Succeeded'){$message='Collection succeeded; zero records is a valid empty result.'}
    $ledger=[pscustomobject][ordered]@{
        Name=$target;Section=$script:DCInvSections[$key][0];Outcome=$outcome;Method=$Envelope.Method
        'Collected at'=$Envelope.CollectedAt;Message=$message;'Check ID'=$key;Status=$Envelope.Status
        'Duration ms'=$Envelope.DurationMs;'Record count'=$rows.Count;'Error ID'=Get-DCInvValue $Envelope 'ErrorId'
        'Started at'=Get-DCInvValue $Envelope 'StartedAt'
    }
    [void]$script:DCInvData.collection.Add($ledger);$script:DCInvSeen[$identity]=$true
    $level=if($Envelope.Status -in @('Succeeded','NotApplicable')){'Information'}else{'Warning'}
    Write-DCInvLog $level 'Collection' $target $key $Envelope.Status $message $Envelope.DurationMs ([string](Get-DCInvValue $Envelope 'ErrorId')) ([string](Get-DCInvValue $Envelope 'ErrorMessage'))
}
function Select-DCInvTargets([object[]]$Discovered,[string]$SelectedDomain,[string[]]$Names){
    $domainTargets=@($Discovered | Where-Object{[string]$_.Domain -ieq $SelectedDomain} | Sort-Object HostName -Unique)
    if($domainTargets.Count -ne $Discovered.Count){throw 'Discovery returned a DC outside the requested domain. Collection stopped.'}
    if(-not $domainTargets.Count){throw "No domain controllers discovered in $SelectedDomain"}
    if(@($Names | Where-Object{$_}).Count -eq 0){return $domainTargets}
    $selected=New-Object System.Collections.ArrayList
    foreach($name in $Names){
        if($name -match '[*?\[\]]'){throw 'ComputerName accepts exact short names or FQDNs, not wildcard patterns.'}
        $matches=@($domainTargets | Where-Object{[string]$_.Name -ieq $name -or [string]$_.HostName -ieq $name})
        if($matches.Count -ne 1){throw "ComputerName '$name' is not a unique DC discovered in $SelectedDomain"}
        if(@($selected | Where-Object{$_.HostName -ieq $matches[0].HostName}).Count -eq 0){[void]$selected.Add($matches[0])}
    }
    $selected.ToArray()
}
function Invoke-DCInvDiscovery([string]$RequestedDomain,[pscredential]$DiscoveryCredential,[int]$TimeoutSeconds){
    $job=$null
    try{
        $job=Start-Job -ScriptBlock {
            param($RequestedDomain,$DiscoveryCredential)
            $ErrorActionPreference='Stop'
            Import-Module ActiveDirectory -ErrorAction Stop
            $params=@{Server=$RequestedDomain;ErrorAction='Stop'}
            if($null -ne $DiscoveryCredential){$params.Credential=$DiscoveryCredential}
            $domainInfo=Get-ADDomain @params
            if($domainInfo.DNSRoot -ine $RequestedDomain){throw 'Requested domain does not match discovered DNS domain.'}
            Get-ADDomainController -Filter * @params | ForEach-Object{
                [pscustomobject]@{
                    Name=$_.Name;HostName=$_.HostName;Domain=$_.Domain;Site=$_.Site;IPv4Address=$_.IPv4Address;IPv6Address=$_.IPv6Address
                    OperatingSystem=$_.OperatingSystem;OperatingSystemVersion=$_.OperatingSystemVersion;IsGlobalCatalog=$_.IsGlobalCatalog
                    IsReadOnly=$_.IsReadOnly;NTDSSettingsObjectDN=$_.NTDSSettingsObjectDN;OperationMasterRoles=@($_.OperationMasterRoles | ForEach-Object{[string]$_})
                }
            }
        } -ArgumentList $RequestedDomain,$DiscoveryCredential -ErrorAction Stop
        $discoveryClock=[diagnostics.stopwatch]::StartNew();$finished=$null
        while($discoveryClock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Stage 'Discovering domain controllers'}
            if($job.State -in @('Completed','Failed','Stopped')){$finished=$job;break}
            Start-Sleep -Milliseconds 200
        }
        if($null -eq $finished){throw "Domain discovery exceeded $TimeoutSeconds seconds. No DC collection started."}
        $results=@(Receive-Job -Job $job -ErrorAction Stop)
        if($job.State -ne 'Completed'){throw "Domain discovery ended with state $($job.State)"}
        return $results
    }
    finally{if($null -ne $job){if($job.State -in @('Running','NotStarted','Blocked')){Stop-Job -Job $job -ErrorAction SilentlyContinue};Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}}
}

function Invoke-DCInvWorkers([object[]]$Controllers,[scriptblock]$Worker,[string]$RemoteText,$Settings,[pscredential]$WorkerCredential){
    if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay -Total ($Controllers.Count*@($script:DCInvSections.Keys|Where-Object{$_ -ne 'collection'}).Count)}
    $pending=New-Object 'System.Collections.Generic.Queue[object]'
    foreach($controller in $Controllers){$pending.Enqueue($controller)}
    $active=New-Object System.Collections.ArrayList;$finishedCount=0
    $required=@($script:DCInvSections.Keys | Where-Object{$_ -ne 'collection' -and $_ -ne 'dcs'})
    try{
        while($pending.Count -gt 0 -or $active.Count -gt 0){
            while($pending.Count -gt 0 -and $active.Count -lt $Settings.ThrottleLimit){
                $dc=$pending.Dequeue();$target=[string]$dc.HostName
                Write-DCInvLog 'Information' 'Collection' $target 'Worker' 'Started' 'Starting read-only target worker.'
                $job=Start-Job -ScriptBlock $Worker -ArgumentList $dc,$WorkerCredential,$Settings,$RemoteText -ErrorAction Stop
                [void]$active.Add([pscustomobject]@{Job=$job;Controller=$dc;Clock=[diagnostics.stopwatch]::StartNew();ErrorMessage=''})
            }
            foreach($item in @($active.ToArray())){
                $receiveErrors=@()
                $envelopes=@(Receive-Job -Job $item.Job -ErrorAction SilentlyContinue -ErrorVariable receiveErrors)
                foreach($envelope in $envelopes){
                    if([string](Get-DCInvValue $envelope 'Kind') -eq 'Section'){Add-DCInvSection $envelope}
                    else{throw "Unexpected worker output from $($item.Controller.HostName). Expected category envelope."}
                }
                if($receiveErrors.Count){$item.ErrorMessage=($receiveErrors | ForEach-Object{$_.Exception.Message}) -join '; '}
                $timedOut=$item.Clock.Elapsed.TotalSeconds -ge $Settings.TargetTimeoutSeconds
                $terminal=$item.Job.State -in @('Completed','Failed','Stopped')
                if($timedOut -or $terminal){
                    if($timedOut -and -not $terminal){Stop-Job -Job $item.Job -ErrorAction SilentlyContinue}
                    # Drain any envelopes produced between the earlier receive and completion/cancellation.
                    $lastErrors=@();$last=@(Receive-Job -Job $item.Job -ErrorAction SilentlyContinue -ErrorVariable lastErrors)
                    foreach($envelope in $last){if([string](Get-DCInvValue $envelope 'Kind') -eq 'Section'){Add-DCInvSection $envelope}}
                    if($lastErrors.Count){$item.ErrorMessage=($lastErrors | ForEach-Object{$_.Exception.Message}) -join '; '}
                    foreach($key in $required){
                        if(-not $script:DCInvSeen.ContainsKey($item.Controller.HostName+'|'+$key)){
                            $status=if($timedOut -and -not $terminal){'TimedOut'}else{'Failed'}
                            $message=if($status -eq 'TimedOut'){"Target worker exceeded $($Settings.TargetTimeoutSeconds) seconds; this category did not complete."}elseif($item.ErrorMessage){$item.ErrorMessage}else{'Worker did not return this category.'}
                            Add-DCInvSection ([pscustomobject]@{Target=$item.Controller.HostName;Key=$key;Status=$status;Method='Worker / incomplete category';StartedAt=$null;CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=[long]$item.Clock.ElapsedMilliseconds;Records=@();ErrorId='DCInventory.WorkerIncomplete';ErrorMessage=$message})
                        }
                    }
                    Remove-Job -Job $item.Job -Force -ErrorAction SilentlyContinue
                    [void]$active.Remove($item);$finishedCount++
                    if(-not (Get-Command Test-PSIInventoryQuiet -ErrorAction SilentlyContinue) -or -not (Test-PSIInventoryQuiet)){Write-Information "[$finishedCount/$($Controllers.Count)] Inventory collection finished: $($item.Controller.HostName)" -InformationAction Continue}
                }
            }
            if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay}else{Write-Progress -Activity 'Read-only DC inventory' -Status "$finishedCount of $($Controllers.Count) controllers finished; $($active.Count) active" -PercentComplete (100*$finishedCount/$Controllers.Count)}
            if($active.Count -gt 0){Start-Sleep -Milliseconds 200}
        }
    }
    finally{
        foreach($item in @($active.ToArray())){Stop-Job -Job $item.Job -ErrorAction SilentlyContinue;Remove-Job -Job $item.Job -Force -ErrorAction SilentlyContinue}
            if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Update-PSIInventoryDisplay}else{Write-Progress -Activity 'Read-only DC inventory' -Completed}
    }
}

function Export-DCInvCsv([string]$Key,[string]$Path){
    $columns=@($script:DCInvSections[$Key][1]);$rows=@($script:DCInvData[$Key].ToArray())
    if($rows.Count -gt 0){
        $rows | ForEach-Object{
            $safe=[ordered]@{}
            foreach($column in $columns){
                $value=Get-DCInvValue $_ $column
                if($value -is [string] -and $value -match '^[=+@\-\t\r\n]'){$value="'"+$value}
                $safe[$column]=$value
            }
            [pscustomobject]$safe
        } | Select-Object -Property $columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
    else{(('"'+($columns -join '","')+'"')+[environment]::NewLine) | Set-Content -LiteralPath $Path -Encoding UTF8 -NoNewline}
}
function Get-DCInvFallback($Payload){
    $builder=New-Object System.Text.StringBuilder
    [void]$builder.Append('<h1>PSInsightInventory - Domain Controller Inventory</h1><p>JP</p><p>'+[net.webutility]::HtmlEncode($Payload.meta.notice)+'</p><p>'+[net.webutility]::HtmlEncode($Payload.meta.generatedDisplay)+'</p>')
    foreach($key in $script:DCInvSections.Keys){
        [void]$builder.Append('<h2>'+[net.webutility]::HtmlEncode($script:DCInvSections[$key][0])+'</h2><div style="overflow:auto"><table><thead><tr>')
        foreach($col in $script:DCInvSections[$key][1]){[void]$builder.Append('<th>'+[net.webutility]::HtmlEncode($col)+'</th>')}
        [void]$builder.Append('</tr></thead><tbody>')
        foreach($row in $script:DCInvData[$key]){
            [void]$builder.Append('<tr>');foreach($col in $script:DCInvSections[$key][1]){[void]$builder.Append('<td>'+[net.webutility]::HtmlEncode([string](Get-DCInvValue $row $col))+'</td>')};[void]$builder.Append('</tr>')
        }
        [void]$builder.Append('</tbody></table></div>')
    }
    $builder.ToString()
}

# Each invocation executes in its own script scope. Importing the module does not collect data.
. (Join-Path $PSScriptRoot 'Collectors/RemoteCollector.ps1')
. (Join-Path $PSScriptRoot 'Collectors/TargetWorker.ps1')
function Get-DCInvTemplate {
    $templatePath=Join-Path $script:DCInvModuleRoot 'Templates/InventoryConsole.html'
    $brandPath=Join-Path $script:DCInvModuleRoot 'Assets/JP.brand.css'
    return [IO.File]::ReadAllText($templatePath).Replace('/*JP_BRAND_CSS*/',[IO.File]::ReadAllText($brandPath))
}
function Get-DCInvSample {
    $samplePath=Join-Path $script:DCInvModuleRoot 'Assets/DCInventory.sample.json'
    return ([IO.File]::ReadAllText($samplePath) | ConvertFrom-Json)
}

$runName='PSInsightInventory_'+$script:DCInvStarted.ToString('yyyyMMdd_HHmmss_fff')+'_'+$script:DCInvRunId
$runFolder=Join-Path $OutputPath $runName
$reportFolder=Join-Path $runFolder 'Reports';$logFolder=Join-Path $runFolder 'Logs';$csvFolder=Join-Path $reportFolder 'CSV'
$null=New-Item -ItemType Directory -Path $csvFolder,$logFolder -Force -ErrorAction Stop
$script:DCInvLogPath=Join-Path $logFolder ('PSInsightInventory_'+$script:DCInvStarted.ToString('yyyyMMdd_HHmmss')+'.jsonl')
try{
    Write-DCInvLog 'Information' 'Run' '' 'Start' 'Started' ('Version '+$script:DCInvVersion+'; SampleData='+[bool]$SampleData+'; Domain='+$Domain+'; Throttle='+$ThrottleLimit+'; SkipRemote='+[bool]$SkipRemote)
    $source=if($SampleData){'Sample'}else{'Live'}
    if($SampleData){
        $sample=Get-DCInvSample
        foreach($key in $script:DCInvSections.Keys){
            if($key -ne 'collection'){
                foreach($row in $sample.data.$key){
                    $record=[ordered]@{};foreach($column in $script:DCInvSections[$key][1]){$record[$column]=ConvertTo-DCInvFlat (Get-DCInvValue $row $column)}
                    [void]$script:DCInvData[$key].Add([pscustomobject]$record)
                }
            }
        }
        # Sample records use the same normalization, ledger, coverage, render and export pipeline.
        $staged=$script:DCInvData
        $script:DCInvData=[ordered]@{};foreach($key in $script:DCInvSections.Keys){$script:DCInvData[$key]=New-Object System.Collections.ArrayList}
        foreach($entry in $sample.data.collection){
            $key=[string]$entry.'Check ID'
            $rows=@($staged[$key].ToArray() | Where-Object{$_.Name -eq $entry.Name})
            Add-DCInvSection ([pscustomobject]@{Target=$entry.Name;Key=$key;Status=$entry.Status;Method='Synthetic fixture / '+$entry.Method;StartedAt=$entry.'Started at';CollectedAt=$entry.'Collected at';DurationMs=0;Records=$rows;ErrorId=$entry.'Error ID';ErrorMessage=$entry.Message})
        }
        $resolvedDomain=$sample.meta.domain;$selectedCount=$script:DCInvData.dcs.Count;$discoveredCount=$selectedCount
    }
    else{
        if($env:OS -ne 'Windows_NT'){throw 'Live inventory requires Windows. Use -SampleData for an offline sample on other platforms.'}
        if(-not (Get-Module -ListAvailable -Name ActiveDirectory)){throw 'ActiveDirectory module is required on the collection host. Install approved RSAT AD tools before running.'}
        if($Domain -notmatch '\.'){throw 'Specify the full DNS domain name with -Domain.'}
        if(-not (Get-Command Test-PSIInventoryQuiet -ErrorAction SilentlyContinue) -or -not (Test-PSIInventoryQuiet)){Write-Information "Discovering DCs in $Domain only..." -InformationAction Continue}
        $discoveryStart=[datetimeoffset]::Now;$watch=[diagnostics.stopwatch]::StartNew()
        $discovered=@(Invoke-DCInvDiscovery $Domain $Credential $DiscoveryTimeoutSeconds);$watch.Stop()
        $targets=@(Select-DCInvTargets $discovered $Domain @($ComputerName | Where-Object{$_}))
        $resolvedDomain=$Domain.ToLowerInvariant();$selectedCount=$targets.Count;$discoveredCount=$discovered.Count
        foreach($dc in $targets){
            $row=[pscustomobject][ordered]@{
                Name=$dc.HostName;Domain=$dc.Domain;Site=$dc.Site;IPv4=[string]$dc.IPv4Address;OS=$dc.OperatingSystem
                GC=if($dc.IsGlobalCatalog){'Yes'}else{'No'};Type=if($dc.IsReadOnly){'RODC'}else{'Writable'};Inventory='Pending'
                'OS version'=$dc.OperatingSystemVersion;IPv6=[string]$dc.IPv6Address
            }
            Add-DCInvSection ([pscustomobject]@{Target=$dc.HostName;Key='dcs';Status='Succeeded';Method='ADWS / explicit domain discovery';StartedAt=$discoveryStart.ToString('o');CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;Records=@($row);ErrorId=$null;ErrorMessage=$null})
        }
        $settings=[pscustomobject]@{ThrottleLimit=$ThrottleLimit;TargetTimeoutSeconds=$TargetTimeoutSeconds;OpenTimeoutSeconds=$OpenTimeoutSeconds;SkipRemote=[bool]$SkipRemote;UseSSL=[bool]$UseSSL;Port=$Port}
        Invoke-DCInvWorkers $targets $script:DCInvTargetWorker $script:DCInvRemoteCollector.ToString() $settings $Credential
    }
    $coverage=New-Object System.Collections.ArrayList
    foreach($dc in $script:DCInvData.dcs){
        $ledger=@($script:DCInvData.collection.ToArray() | Where-Object{$_.Name -eq $dc.Name})
        if($ledger.Count -ne 15){throw "Coverage contract failed for $($dc.Name): expected 15 category operations, received $($ledger.Count)."}
        $unavailable=@($ledger | Where-Object{$_.Status -notin @('Succeeded','NotApplicable')})
        $dc.Inventory=if($unavailable.Count -eq 0){'Complete'}else{'Partial'}
        [void]$coverage.Add([pscustomobject]@{Target=$dc.Name;Operations=$ledger.Count;Succeeded=@($ledger | Where-Object{$_.Status -eq 'Succeeded'}).Count;NotApplicable=@($ledger | Where-Object{$_.Status -eq 'NotApplicable'}).Count;Unavailable=$unavailable.Count;Inventory=$dc.Inventory})
    }
    $completed=[datetimeoffset]::Now
    $data=[ordered]@{};foreach($key in $script:DCInvSections.Keys){$data[$key]=@($script:DCInvData[$key].ToArray())}
    $payload=[ordered]@{
        meta=[ordered]@{
            moduleName='PSInsightInventory';inventoryId='ADInfrastructure';title='Domain Controller Inventory';version=$script:DCInvVersion;run=$script:DCInvRunId;dataSource=$source
            started=$script:DCInvStarted.ToString('o');generated=$completed.ToString('o');generatedDisplay=$completed.ToString('dd MMM yyyy, HH:mm:ss zzz')
            timeZone=[timezoneinfo]::Local.Id;scope=$resolvedDomain;domain=$resolvedDomain;selectedDCs=$selectedCount;discoveredDCs=$discoveredCount
            source=if($SampleData){'Deterministic synthetic fixtures'}else{'ADWS domain discovery + per-DC directory reads + WinRM local providers'}
            notice=if($SampleData){'SAMPLE DATA. Fictional environment. No servers were contacted. Inventory only; no health assessment.'}else{'LIVE INVENTORY SNAPSHOT. Read-only collection. Completeness describes category coverage, not DC health.'}
            configuration=[ordered]@{Domain=$resolvedDomain;SelectedControllers=@($data.dcs | ForEach-Object{$_.Name});ThrottleLimit=$ThrottleLimit;TargetTimeoutSeconds=$TargetTimeoutSeconds;DiscoveryTimeoutSeconds=$DiscoveryTimeoutSeconds;OpenTimeoutSeconds=$OpenTimeoutSeconds;SkipRemote=[bool]$SkipRemote;UseSSL=[bool]$UseSSL;Port=if($Port -gt 0){$Port}elseif($UseSSL){5986}else{5985}}
            coverage=@($coverage.ToArray())
        }
        sections=$script:DCInvSections;data=$data
    }
    $json=$payload | ConvertTo-Json -Depth 20
    $embedded=$json.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
    $html=(Get-DCInvTemplate).Replace('/*DATA*/',$embedded).Replace('<!--FALLBACK-->',(Get-DCInvFallback $payload))
    $about=[IO.File]::ReadAllText((Join-Path $script:DCInvModuleRoot 'Assets/HelpAbout.html')).Replace('{{MODULE_VERSION}}',[net.webutility]::HtmlEncode($script:DCInvVersion))
    $html=$html.Replace('</body>',$about+'</body>')
    if($html.Contains('/*DATA*/') -or $html.Contains('<!--FALLBACK-->') -or $html.Contains('{{MODULE_VERSION}}')){throw 'Unresolved report template placeholder.'}
    if(Get-Command Update-PSIInventoryDisplay -ErrorAction SilentlyContinue){Complete-PSIInventoryCollectionDisplay -Collection $script:DCInvData.collection.ToArray();Update-PSIInventoryDisplay -Stage 'Saving reports' -Force}
    $htmlPath=Join-Path $reportFolder 'DC-Inventory.html';$jsonPath=Join-Path $reportFolder 'DC-Inventory.json'
    $utf8=New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($htmlPath,$html,$utf8);[System.IO.File]::WriteAllText($jsonPath,$json,$utf8)
    foreach($key in $script:DCInvSections.Keys){Export-DCInvCsv $key (Join-Path $csvFolder ($key+'.csv'))}
    $coveragePath=Join-Path $csvFolder 'Coverage.csv'
    $coverage.ToArray() | Export-Csv -LiteralPath $coveragePath -NoTypeInformation -Encoding UTF8
    $partial=@($script:DCInvData.dcs.ToArray() | Where-Object{$_.Inventory -eq 'Partial'}).Count
    Write-DCInvLog 'Information' 'Export' '' 'Reports' 'Succeeded' ("HTML=$htmlPath; JSON=$jsonPath; CSV=$csvFolder; complete="+($selectedCount-$partial)+"/$selectedCount")
    Write-DCInvLog 'Information' 'Run' '' 'Complete' 'Succeeded' 'Report generation completed. See category ledger for collection outcomes.'
    if($Open){
        try{Invoke-Item -LiteralPath $htmlPath -ErrorAction Stop}catch{Write-Warning "Report saved, but could not open automatically: $($_.Exception.Message)"}
    }
    [pscustomobject][ordered]@{ModuleName='PSInsightInventory';ModuleVersion=$script:DCInvVersion;InventoryId='ADInfrastructure';RunId=$script:DCInvRunId;DataSource=$source;Domain=$resolvedDomain;DomainControllers=$selectedCount;CompleteInventory=($selectedCount-$partial);PartialInventory=$partial;HtmlReport=$htmlPath;JsonSnapshot=$jsonPath;CsvFolder=$csvFolder;LogFile=$script:DCInvLogPath;OutputFolder=$runFolder}
}
catch{
    Write-DCInvLog 'Error' 'Run' '' 'Complete' 'Failed' 'Inventory run did not complete.' 0 $_.FullyQualifiedErrorId $_.Exception.Message
    throw
}
