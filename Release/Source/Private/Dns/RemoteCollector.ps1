$script:PSIDnsRemote={
    param([string]$TargetName)
    $ErrorActionPreference='Stop'
    function V($o,$p){if($null -ne $o -and $null -ne $o.PSObject.Properties[$p]){return $o.$p};return $null}
    function Flat($v){if($null -eq $v){return $null};if($v -is [datetime]){return ([datetimeoffset]$v).ToString('o')};if($v -is [timespan]){return $v.ToString('c')};if($v -is [bool] -or $v -is [ValueType] -or $v -is [string]){return $v};return (@($v)|ForEach-Object{[string]$_}) -join '; '}
    function Emit([string]$Key,[string]$Status,[object[]]$Records,[string]$Message='',[string]$ErrorId='', [long]$DurationMs=0){
        [pscustomobject]@{Kind='Section';Target=$TargetName;Key=$Key;Status=$Status;Records=@($Records);Method='WinRM / local DNS configuration providers';StartedAt=[datetimeoffset]::Now.ToString('o');CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$DurationMs;ErrorId=$ErrorId;ErrorMessage=$Message}
    }
    function Read-Category([string]$Key,[scriptblock]$Action){
        $watch=[diagnostics.stopwatch]::StartNew();$rows=@();$status='Succeeded';$message='';$id=''
        try{$rows=@(& $Action)}catch{$status='Failed';$message=$_.Exception.Message;$id=$_.FullyQualifiedErrorId}
        $watch.Stop();Emit $Key $status $rows $message $id $watch.ElapsedMilliseconds
    }
    Read-Category 'client' {
        Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction Stop|ForEach-Object{
            $dns=@($_.DNSServerSearchOrder|Where-Object{$_})
            [pscustomobject]@{Name=$TargetName;Adapter=$_.Description;'DNS search order'=Flat $dns;'Preferred DNS'=if($dns.Count){$dns[0]}else{$null};'Alternate DNS'=if($dns.Count -gt 1){$dns[1]}else{$null};'Additional DNS'=if($dns.Count -gt 2){Flat $dns[2..($dns.Count-1)]}else{$null}}
        }
    }
    $other=@('forwarders','recursion','scavenging','rootHints','zones','conditional','aging','delegations','scopes','nameServers','nsAddresses','zoneQueries')
    $svc=$null;$absent=$false;$errorRecord=$null
    try{$svc=Get-Service -Name DNS -ErrorAction Stop}catch{if($_.FullyQualifiedErrorId -like 'NoServiceFoundForGivenName*'){$absent=$true}else{$errorRecord=$_}}
    if($null -ne $errorRecord){Emit 'role' 'Failed' @() $errorRecord.Exception.Message $errorRecord.FullyQualifiedErrorId;foreach($k in $other){Emit $k 'Failed' @() 'DNS role detection failed; no absence was inferred.' $errorRecord.FullyQualifiedErrorId};return}
    Emit 'role' 'Succeeded' @([pscustomobject]@{Name=$TargetName;'DNS role present'=(-not $absent);'Service state'=if($null -ne $svc){[string]$svc.Status}else{'Not installed'}})
    if($absent){foreach($k in $other){Emit $k 'NotApplicable' @() 'DNS Server service is not installed.'};return}
    try{Import-Module DnsServer -ErrorAction Stop}catch{foreach($k in $other){Emit $k 'Failed' @() $_.Exception.Message $_.FullyQualifiedErrorId};return}
    Read-Category 'forwarders' {
        $c=Get-DnsServerForwarder -ErrorAction Stop;$addresses=@($c.IPAddress|Where-Object{$null -ne $_});$i=0
        if(-not $addresses.Count){$addresses=@('(none configured)')}
        foreach($a in $addresses){$i++;[pscustomobject]@{Name=$TargetName;Forwarder=[string]$a;Order=$i;'Timeout seconds'=V $c 'Timeout';'Use root hints'=V $c 'UseRootHint'}}
    }
    Read-Category 'recursion' {$c=Get-DnsServerRecursion -ErrorAction Stop;[pscustomobject]@{Name=$TargetName;Enabled=V $c 'Enable';'Additional timeout'=Flat (V $c 'AdditionalTimeout');'Retry interval'=Flat (V $c 'RetryInterval');Timeout=Flat (V $c 'Timeout');'Secure response'=V $c 'SecureResponse'}}
    Read-Category 'scavenging' {$c=Get-DnsServerScavenging -ErrorAction Stop;[pscustomobject]@{Name=$TargetName;Enabled=V $c 'ScavengingState';Interval=Flat (V $c 'ScavengingInterval');'Default no-refresh interval'=Flat (V $c 'NoRefreshInterval');'Default refresh interval'=Flat (V $c 'RefreshInterval');'Last scavenge time'=Flat (V $c 'LastScavengeTime')}}
    Read-Category 'rootHints' {
        Get-DnsServerRootHint -ErrorAction Stop|ForEach-Object{
            $ns=V (V $_ 'NameServer') 'RecordData';$addresses=New-Object collections.ArrayList
            foreach($a in @(V $_ 'IPAddress')){$rd=V $a 'RecordData';foreach($p in @('IPv4Address','IPv6Address')){$v=V $rd $p;if($null -ne $v){[void]$addresses.Add([string]$v)}}}
            [pscustomobject]@{Name=$TargetName;'Name server'=V $ns 'NameServer';Addresses=$addresses.ToArray() -join '; '}
        }
    }
    $zones=@();$zoneFailure=$null
    try{$zones=@(Get-DnsServerZone -ErrorAction Stop)}catch{$zoneFailure=$_}
    if($null -ne $zoneFailure){foreach($k in @('zones','conditional','aging','delegations','scopes','nameServers','nsAddresses','zoneQueries')){Emit $k 'Failed' @() $zoneFailure.Exception.Message $zoneFailure.FullyQualifiedErrorId};return}
    $zoneRows=@($zones|ForEach-Object{[pscustomobject]@{Name=$TargetName;Zone=$_.ZoneName;Type=[string]$_.ZoneType;'AD integrated'=V $_ 'IsDsIntegrated';'Directory partition'=V $_ 'DirectoryPartitionName';'Dynamic updates'=Flat (V $_ 'DynamicUpdate');'Reverse lookup'=V $_ 'IsReverseLookupZone';Paused=V $_ 'IsPaused';Shutdown=V $_ 'IsShutdown';'Zone file'=V $_ 'ZoneFile'}})
    Emit 'zones' 'Succeeded' $zoneRows
    Emit 'conditional' 'Succeeded' @($zones|Where-Object{[string]$_.ZoneType -eq 'Forwarder'}|ForEach-Object{[pscustomobject]@{Name=$TargetName;Zone=$_.ZoneName;'Master servers'=Flat (V $_ 'MasterServers');'AD integrated'=V $_ 'IsDsIntegrated';'Directory partition'=V $_ 'DirectoryPartitionName';'Timeout seconds'=V $_ 'ForwarderTimeout';'Use recursion'=V $_ 'UseRecursion'}})
    $zoneLedger=New-Object collections.ArrayList;$nsRows=New-Object collections.ArrayList
    foreach($operation in @(@{Key='aging';Command='Get-DnsServerZoneAging'},@{Key='delegations';Command='Get-DnsServerZoneDelegation'},@{Key='scopes';Command='Get-DnsServerZoneScope'},@{Key='nameServers';Command='Get-DnsServerResourceRecord'})){
        $rows=New-Object collections.ArrayList;$failures=0;$attempted=0
        foreach($zone in $zones){
            $status='Succeeded';$message='Query completed.';$errorId=$null;$watch=[diagnostics.stopwatch]::StartNew()
            if(($operation.Key -eq 'nameServers' -and [string]$zone.ZoneType -notin @('Primary','Secondary','Stub')) -or ($operation.Key -ne 'nameServers' -and [string]$zone.ZoneType -ne 'Primary')){$status='NotAttempted';$message='Excluded by declared selection: NS reads select Primary/Secondary/Stub zones; other per-zone configuration reads select Primary zones.'}
            else{
                $attempted++
                try{
                    if(-not (Get-Command -Name $operation.Command -ErrorAction SilentlyContinue)){$status='Unsupported';throw 'DNS cmdlet is unavailable on this target.'}
                    $argsForQuery=@{ErrorAction='Stop'}
                    if($operation.Key -eq 'nameServers'){$argsForQuery.ZoneName=$zone.ZoneName;$argsForQuery.RRType='NS'}elseif($operation.Key -eq 'scopes'){$argsForQuery.ZoneName=$zone.ZoneName}else{$argsForQuery.Name=$zone.ZoneName}
                    $items=@(& $operation.Command @argsForQuery)
                    foreach($item in $items){
                        $record= switch($operation.Key){
                            'aging'{[pscustomobject]@{Name=$TargetName;Zone=$zone.ZoneName;'Aging enabled'=V $item 'AgingEnabled';'No-refresh interval'=Flat (V $item 'NoRefreshInterval');'Refresh interval'=Flat (V $item 'RefreshInterval');'Scavenge servers'=Flat (V $item 'ScavengeServers');'Available for scavenging'=Flat (V $item 'AvailForScavengeTime')}}
                            'delegations'{[pscustomobject]@{Name=$TargetName;Zone=$zone.ZoneName;'Child zone'=V $item 'ChildZoneName';'Name servers'=Flat (V $item 'NameServer');'IP addresses'=Flat (V $item 'IPAddress')}}
                            'nameServers'{[pscustomobject]@{Name=$TargetName;Zone=$zone.ZoneName;Owner=V $item 'HostName';'Name server'=V (V $item 'RecordData') 'NameServer';TTL=Flat (V $item 'TimeToLive');Timestamp=Flat (V $item 'Timestamp')}}
                            'scopes'{[pscustomobject]@{Name=$TargetName;Zone=$zone.ZoneName;Scope=V $item 'ZoneScope';'File name'=V $item 'FileName'}}
                        }
                        [void]$rows.Add($record);if($operation.Key -eq 'nameServers'){[void]$nsRows.Add($record)}
                    }
                }catch{if($status -ne 'Unsupported'){$status='Failed'};$message=$_.Exception.Message;$errorId=$_.FullyQualifiedErrorId;$failures++}
            }
            $watch.Stop();[void]$zoneLedger.Add([pscustomobject]@{Name=$TargetName;Zone=$zone.ZoneName;Operation=$operation.Key;Status=$status;'Duration ms'=$watch.ElapsedMilliseconds;'Error ID'=$errorId;Message=$message;'Collected at'=[datetimeoffset]::Now.ToString('o')})
        }
        Emit $operation.Key $(if($failures){'Partial'}else{'Succeeded'}) $rows.ToArray() $(if($failures){"$failures of $attempted selected zone queries failed or were unsupported; successful rows retained."}else{'Selected zone queries completed; see zoneQueries for excluded types.'})
    }
    # Read stored address nodes only; never ask a resolver or an advertised NS endpoint.
    $addressRows=New-Object collections.ArrayList;$addressFailures=0;$addressCache=@{}
    foreach($ns in $nsRows){
        $target=([string]$ns.'Name server').TrimEnd('.')
        $matching=@($zones|Where-Object{[string]$_.ZoneType -in @('Primary','Secondary') -and ($target -ieq $_.ZoneName.TrimEnd('.') -or $target.EndsWith('.'+$_.ZoneName.TrimEnd('.'),[StringComparison]::OrdinalIgnoreCase))}|Sort-Object @{Expression={$_.ZoneName.Length};Descending=$true})
        if(-not $target -or -not $matching.Count){
            [void]$zoneLedger.Add([pscustomobject]@{Name=$TargetName;Zone=$ns.Zone;Operation='NS address selection';Status='NotAttempted';'Duration ms'=0;'Error ID'=$null;Message=('No eligible hosted address zone selected for NS target: '+$target);'Collected at'=[datetimeoffset]::Now.ToString('o')});continue
        }
        $addressZone=$matching[0].ZoneName;$normalized=$addressZone.TrimEnd('.')
        $owner=if($target -ieq $normalized){'@'}else{$target.Substring(0,$target.Length-$normalized.Length-1)}
        foreach($type in @('A','AAAA')){
            $cacheKey=$addressZone+'|'+$owner+'|'+$type
            if(-not $addressCache.ContainsKey($cacheKey)){
                $watch=[diagnostics.stopwatch]::StartNew();$records=@();$status='Succeeded';$message='Stored node query completed; zero returned rows is valid.';$id=$null
                try{
                    $records=@(Get-DnsServerResourceRecord -ZoneName $addressZone -Name $owner -RRType $type -Node -ErrorAction Stop|ForEach-Object{
                        [pscustomobject]@{Owner=V $_ 'HostName';Address=Flat (V (V $_ 'RecordData') $(if($type -eq 'A'){'IPv4Address'}else{'IPv6Address'}));TTL=Flat (V $_ 'TimeToLive')}
                    })
                }catch{$status='Failed';$records=@();$message=$_.Exception.Message;$id=$_.FullyQualifiedErrorId;$addressFailures++}
                $watch.Stop();$addressCache[$cacheKey]=[pscustomobject]@{Records=$records;Status=$status;Message=$message;Id=$id;Duration=$watch.ElapsedMilliseconds}
            }
            $cached=$addressCache[$cacheKey]
            foreach($record in $cached.Records){[void]$addressRows.Add([pscustomobject]@{Name=$TargetName;Zone=$ns.Zone;'Name server'=$ns.'Name server';'Address zone'=$addressZone;Owner=$record.Owner;'Record type'=$type;Address=$record.Address;TTL=$record.TTL})}
            [void]$zoneLedger.Add([pscustomobject]@{Name=$TargetName;Zone=$ns.Zone;Operation=('NS address '+$type);Status=$cached.Status;'Duration ms'=$cached.Duration;'Error ID'=$cached.Id;Message=($target+' via stored '+$addressZone+'/'+$owner+': '+$cached.Message);'Collected at'=[datetimeoffset]::Now.ToString('o')})
        }
    }
    $nsFailed=@($zoneLedger|Where-Object{$_.Operation -eq 'nameServers' -and $_.Status -in @('Failed','Unsupported')}).Count
    Emit 'nsAddresses' $(if($addressFailures -or $nsFailed){'Partial'}else{'Succeeded'}) $addressRows.ToArray() 'Stored node reads only for successfully observed NS targets with an eligible hosted address zone. Exclusions and read failures are recorded separately; no address resolution or health conclusion.'
    Emit 'zoneQueries' 'Succeeded' $zoneLedger.ToArray() 'Per-zone query ledger captured; inspect each row for outcomes.'
}

$script:PSIDnsWorker={
    param($Controller,$Credential,$Settings,[string]$RemoteText)
    $ErrorActionPreference='Stop'
    $p=@{ComputerName=$Controller.HostName;ScriptBlock=[scriptblock]::Create($RemoteText);ArgumentList=@([string]$Controller.HostName);Authentication='Kerberos';ErrorAction='Stop';SessionOption=New-PSSessionOption -OpenTimeout ($Settings.OpenTimeoutSeconds*1000) -OperationTimeout 60000 -CancelTimeout 5000}
    if($null -ne $Credential){$p.Credential=$Credential};if($Settings.UseSSL){$p.UseSSL=$true};if($Settings.Port -gt 0){$p.Port=$Settings.Port}
    Invoke-Command @p
}
