# This worker is invoked in a bounded local job. Every directory query is pinned to one DC.
$script:PSISitesCollector={
    param([string]$Domain,[pscredential]$Credential)
    $ErrorActionPreference='Stop'
    Import-Module ActiveDirectory -ErrorAction Stop
    $ad=@{Server=$Domain;ErrorAction='Stop'};if($null -ne $Credential){$ad.Credential=$Credential}
    $root=Get-ADRootDSE @ad
    $server=[string]$root.dnsHostName
    if([string]::IsNullOrWhiteSpace($server)){throw 'Discovery did not return a DC DNS host name.'}
    $ad.Server=$server
    $root=Get-ADRootDSE @ad
    $domainInfo=Get-ADDomain @ad
    if([string]$domainInfo.DNSRoot -ine $Domain){throw 'The supplied connection domain does not match the discovered domain.'}
    $forest=Get-ADForest @ad
    $config=[string]$root.configurationNamingContext
    if([string]::IsNullOrWhiteSpace($config)){throw 'Configuration naming context is unavailable.'}
    $base='CN=Sites,'+$config
    [pscustomobject]@{Kind='Context';Forest=[string]$forest.Name;Domain=[string]$domainInfo.DNSRoot;Server=$server;ConfigurationNC=$config;CollectedAt=[datetimeoffset]::Now.ToString('o')}
    $queries=@(
        @{Key='sites';Filter='(objectClass=site)';Properties=@('description','location','whenCreated','whenChanged')},
        @{Key='subnets';Filter='(objectClass=subnet)';Properties=@('siteObject','description','location')},
        @{Key='links';Filter='(objectClass=siteLink)';Properties=@('cost','replInterval','siteList','options','schedule','description')},
        @{Key='bridges';Filter='(objectClass=siteLinkBridge)';Properties=@('siteLinkList','description')},
        @{Key='servers';Filter='(objectClass=server)';Properties=@('dNSHostName','serverReference','bridgeheadTransportList')},
        @{Key='settings';Filter='(objectClass=nTDSSiteSettings)';Properties=@('interSiteTopologyGenerator','options','msDS-Preferred-GC-Site','schedule')},
        @{Key='transports';Filter='(objectClass=interSiteTransport)';Properties=@('options','transportAddressAttribute')},
        @{Key='ntds';Filter='(objectClass=nTDSDSA)';Properties=@('objectGUID')}
    )
    foreach($query in $queries){
        $watch=[diagnostics.stopwatch]::StartNew();$records=@();$status='Succeeded';$id=$null;$message=$null
        try{
            $records=@(Get-ADObject -SearchBase $base -SearchScope Subtree -LDAPFilter $query.Filter -Properties $query.Properties @ad | ForEach-Object{
                # Plain property bags avoid losing optional LDAP attributes during job deserialization.
                $row=[ordered]@{Name=[string]$_.Name;DistinguishedName=[string]$_.DistinguishedName}
                foreach($property in $query.Properties){
                    $v=$_.PSObject.Properties[$property]
                    if($null -eq $v){$row[$property]=$null}
                    elseif($property -eq 'schedule'){$row[$property]=if($null -ne $v.Value -and @($v.Value).Count){[convert]::ToBase64String([byte[]]$v.Value)}else{$null}}
                    elseif($v.Value -is [datetime]){$row[$property]=([datetimeoffset]$v.Value).ToString('o')}
                    else{$row[$property]=@($v.Value | ForEach-Object{if($null -ne $_){[string]$_}})}
                }
                [pscustomobject]$row
            })
        }catch{$status='Failed';$id=$_.FullyQualifiedErrorId;$message=$_.Exception.Message}
        $watch.Stop()
        [pscustomobject]@{Kind='Section';Key=$query.Key;Status=$status;Records=$records;Method='ADWS / '+$query.Filter;CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId=$id;ErrorMessage=$message}
    }
}

function Invoke-PSISitesCollection {
    [CmdletBinding()]
    param([string]$Domain,[pscredential]$Credential,[ValidateRange(1,600)][int]$TimeoutSeconds=120,[scriptblock]$Worker=$script:PSISitesCollector)
    $required=@('sites','subnets','links','bridges','servers','settings','transports','ntds')
    $context=$null;$envelopes=New-Object collections.ArrayList;$seen=@{};$job=$null
    try{
    $job=Start-Job -ScriptBlock $Worker -ArgumentList $Domain,$Credential
    $timer=[diagnostics.stopwatch]::StartNew();$lastError='';$timedOut=$false
    while($true){
        $receiveErrors=@();$items=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable receiveErrors)
        if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $items -Total $required.Count}
    if($receiveErrors.Count){$lastError=($receiveErrors|ForEach-Object{$_.Exception.Message}) -join '; '}
        foreach($item in $items){
        if($item.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate forest context.'};$context=$item}
        elseif($item.Kind -eq 'Section'){
            if($item.Key -notin $required -or $seen.ContainsKey($item.Key)){throw 'Unknown or duplicate collector result.'}
            [void]$envelopes.Add($item);$seen[$item.Key]=$true
        }else{throw 'Unexpected collector output.'}
        }
        if($job.State -in @('Completed','Failed','Stopped')){break}
        if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;Stop-Job $job -ErrorAction SilentlyContinue;break}
        Start-Sleep -Milliseconds 200
    }
    # Drain the race between receiving the stream and worker completion/cancellation.
    $receiveErrors=@();$items=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable receiveErrors)
    if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $items -Total $required.Count}
    if($receiveErrors.Count){$lastError=($receiveErrors|ForEach-Object{$_.Exception.Message}) -join '; '}
    foreach($item in $items){
        if($item.Kind -eq 'Context' -and $null -eq $context){$context=$item}
        elseif($item.Kind -eq 'Section' -and -not $seen.ContainsKey($item.Key)){[void]$envelopes.Add($item);$seen[$item.Key]=$true}
    }
    if($null -eq $context){throw "Forest context could not be established. $lastError"}
    foreach($key in $required){if(-not $seen.ContainsKey($key)){
        [void]$envelopes.Add([pscustomobject]@{Key=$key;Status=if($timedOut){'TimedOut'}else{'Failed'};Records=@();Method='Collector / incomplete query';CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$timer.ElapsedMilliseconds;ErrorId='PSInsightInventory.SitesQueryIncomplete';ErrorMessage=if($timedOut){"Overall collector budget of $TimeoutSeconds seconds expired."}elseif($lastError){$lastError}else{'Collector did not return this query.'}})
    }}
        return [pscustomobject]@{Context=$context;Envelopes=@($envelopes.ToArray())}
    }finally{if($null -ne $job){if($job.State -in @('Running','NotStarted','Blocked')){Stop-Job $job -ErrorAction SilentlyContinue};Remove-Job $job -Force -ErrorAction SilentlyContinue}}
}
