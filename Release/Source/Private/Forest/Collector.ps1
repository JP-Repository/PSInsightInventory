$script:PSIForestCollector={
    param([string]$Domain,[pscredential]$Credential)
    $ErrorActionPreference='Stop'
    Import-Module ActiveDirectory -ErrorAction Stop
    function Value($o,$p){if($null -ne $o -and $null -ne $o.PSObject.Properties[$p]){return $o.$p};return $null}
    function Bag($o,[string[]]$properties){
        $row=[ordered]@{}
        foreach($p in $properties){
            $v=Value $o $p
            if($null -eq $v){$row[$p]=$null}
            elseif($v -is [timespan]){$row[$p]=$v.ToString('c')}
            elseif($v -is [bool]){$row[$p]=$v}
            elseif($v -is [collections.IEnumerable] -and $v -isnot [string]){$row[$p]=@($v|ForEach-Object{[string]$_})}
            else{$row[$p]=[string]$v}
        }
        [pscustomobject]$row
    }
    function Params([string]$server){$p=@{Server=$server;ErrorAction='Stop'};if($null -ne $Credential){$p.Credential=$Credential};return $p}
    function Emit([string]$Key,[string]$TargetDomain,[string]$SourceDC,[scriptblock]$Action){
        $clock=[diagnostics.stopwatch]::StartNew();$rows=@();$status='Succeeded';$id=$null;$message=$null
        try{$rows=@(& $Action)}catch{$status='Failed';$id=$_.FullyQualifiedErrorId;$message=$_.Exception.Message}
        $clock.Stop()
        [pscustomobject]@{Kind='Section';Key=$Key;Target=$TargetDomain;SourceDC=$SourceDC;Status=$status;Records=$rows;Method='ADWS / read-only forest and domain metadata';CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$clock.ElapsedMilliseconds;ErrorId=$id;ErrorMessage=$message}
    }
    $seed=Params $Domain;$root=Get-ADRootDSE @seed;$source=[string]$root.dnsHostName
    if(-not $source){throw 'Forest discovery did not return a source DC.'}
    $seed=Params $source;$root=Get-ADRootDSE @seed;$initial=Get-ADDomain @seed
    if([string]$initial.DNSRoot -ine $Domain){throw 'The connection domain does not match discovery.'}
    $forest=Get-ADForest @seed;$names=@($forest.Domains|ForEach-Object{[string]$_}|Sort-Object -Unique)
    if(-not $names.Count -or $names -notcontains $Domain){throw 'The connection domain is not present in the returned forest domain list.'}
    $forestProperties=@('Name','RootDomain','ForestMode','Domains','UPNSuffixes','SPNSuffixes','SchemaMaster','DomainNamingMaster','GlobalCatalogs','ApplicationPartitions','Sites')
    $domainProperties=@('DNSRoot','Name','NetBIOSName','DomainSID','ObjectGUID','DistinguishedName','Forest','DomainMode','ParentDomain','ChildDomains','PDCEmulator','RIDMaster','InfrastructureMaster','ComputersContainer','UsersContainer','DomainControllersContainer','DeletedObjectsContainer','LostAndFoundContainer','SystemsContainer','AllowedDNSSuffixes','ReplicaDirectoryServers','ReadOnlyReplicaDirectoryServers','LastLogonReplicationInterval')
    $policyProperties=@('DistinguishedName','ComplexityEnabled','ReversibleEncryptionEnabled','MinPasswordLength','PasswordHistoryCount','MinPasswordAge','MaxPasswordAge','LockoutThreshold','LockoutDuration','LockoutObservationWindow')
    $rootProperties=@('dnsHostName','configurationNamingContext','schemaNamingContext','defaultNamingContext','rootDomainNamingContext','namingContexts')
    [pscustomobject]@{Kind='Context';Forest=[string]$forest.Name;RootDomain=[string]$forest.RootDomain;Domain=$Domain;Server=$source;Domains=$names;ConfigurationNC=[string]$root.configurationNamingContext;Root=(Bag $root $rootProperties)}
    Emit 'forest' $forest.Name $source {Bag $forest $forestProperties}
    Emit 'partitions' $forest.Name $source {
        Get-ADObject -SearchBase ('CN=Partitions,'+[string]$root.configurationNamingContext) -SearchScope OneLevel -LDAPFilter '(objectClass=crossRef)' -Properties nCName,dnsRoot,nETBIOSName,systemFlags,enabled,msDS-NC-Replica-Locations,msDS-NC-RO-Replica-Locations @seed | ForEach-Object{
            Bag $_ @('Name','DistinguishedName','nCName','dnsRoot','nETBIOSName','systemFlags','enabled','msDS-NC-Replica-Locations','msDS-NC-RO-Replica-Locations')
        }
    }
    foreach($name in $names){
        $target=$null;$info=$null;$targetRoot=$null;$connectionError=$null
        try{
            if($name -ieq $Domain){$target=$source;$info=$initial;$targetRoot=$root}
            else{
                $connect=Params $name;$candidate=Get-ADRootDSE @connect;$target=[string]$candidate.dnsHostName
                if(-not $target){throw 'Domain discovery did not return a source DC.'}
                $connect=Params $target;$targetRoot=Get-ADRootDSE @connect;$info=Get-ADDomain @connect
            }
            if([string]$info.DNSRoot -ine $name -or [string]$info.Forest -ine [string]$forest.Name){throw 'Discovered domain/forest does not match the forest membership reference.'}
        }catch{$connectionError=$_;$target=$null}
        if($null -ne $connectionError){
            foreach($key in @('domain:','policy:')){
                [pscustomobject]@{Kind='Section';Key=$key+$name;Target=$name;SourceDC=$null;Status='Failed';Records=@();Method='ADWS / domain discovery';CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=0;ErrorId=$connectionError.FullyQualifiedErrorId;ErrorMessage=$connectionError.Exception.Message}
            }
            continue
        }
        Emit ('domain:'+$name) $name $target {[pscustomobject]@{Domain=(Bag $info $domainProperties);Root=(Bag $targetRoot $rootProperties)}}
        Emit ('policy:'+$name) $name $target {
            $p=Params $target
            $policy=Get-ADDefaultDomainPasswordPolicy -Identity $name @p
            Bag $policy $policyProperties
        }
    }
}

function Invoke-PSIForestCollection {
    [CmdletBinding()]
    param([string]$Domain,[pscredential]$Credential,[ValidateRange(1,1800)][int]$TimeoutSeconds=180,[scriptblock]$Worker=$script:PSIForestCollector,[ValidateSet('Forest','Trusts')][string]$QueryPlan='Forest')
    $context=$null;$required=@();$seen=@{};$results=New-Object collections.ArrayList;$job=$null;$errorText=''
    function Read-Result($item){
        if($item.Kind -eq 'Context'){
            if($null -ne $scriptContext.Value){throw 'Duplicate forest context.'}
            $scriptContext.Value=$item
            $keys=@();if($QueryPlan -eq 'Trusts'){$keys=@($item.Domains|ForEach-Object{'trust:'+$_})}else{$keys=@('forest','partitions');foreach($domainName in @($item.Domains)){$keys+=@(('domain:'+$domainName),('policy:'+$domainName))}}
            $scriptRequired.Value=$keys
        }elseif($item.Kind -eq 'Section'){
            if($null -eq $scriptContext.Value -or $item.Key -notin $scriptRequired.Value -or $seen.ContainsKey($item.Key)){throw 'Unknown, premature or duplicate forest query outcome.'}
            [void]$results.Add($item);$seen[$item.Key]=$true
        }else{throw 'Unexpected forest worker output.'}
    }
    # Explicit references keep the nested reader scoped to this invocation.
    $scriptContext=[ref]$context;$scriptRequired=[ref]$required
    try{
        $job=Start-Job -ScriptBlock $Worker -ArgumentList $Domain,$Credential -ErrorAction Stop
        $clock=[diagnostics.stopwatch]::StartNew();$timedOut=$false
        while($true){
            $errors=@();$items=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable errors)
            if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $items;Update-PSIInventoryDisplay -Total $required.Count}
        if($errors.Count){$errorText=($errors|ForEach-Object{$_.Exception.Message}) -join '; '}
            foreach($item in $items){Read-Result $item}
            if($job.State -in @('Completed','Failed','Stopped')){break}
            if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;Stop-Job $job -ErrorAction SilentlyContinue;break}
            Start-Sleep -Milliseconds 200
        }
        $errors=@();$items=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable errors)
        if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $items;Update-PSIInventoryDisplay -Total $required.Count}
        if($errors.Count){$errorText=($errors|ForEach-Object{$_.Exception.Message}) -join '; '}
        foreach($item in $items){Read-Result $item}
        if($null -eq $context){throw "Verified forest context was not returned. $errorText"}
        foreach($key in $required){if(-not $seen.ContainsKey($key)){
            [void]$results.Add([pscustomobject]@{Kind='Section';Key=$key;Target=if($key.Contains(':')){$key.Substring($key.IndexOf(':')+1)}else{$context.Forest};SourceDC=$null;Status=if($timedOut){'TimedOut'}else{'Failed'};Records=@();Method='Forest worker / incomplete query';CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$clock.ElapsedMilliseconds;ErrorId='PSInsightInventory.ForestQueryIncomplete';ErrorMessage=if($timedOut){"Overall collector budget of $TimeoutSeconds seconds expired."}elseif($errorText){$errorText}else{'Query did not return an outcome.'}})
        }}
        return [pscustomobject]@{Context=$context;Envelopes=@($results.ToArray())}
    }finally{if($null -ne $job){if($job.State -in @('Running','Blocked','NotStarted')){Stop-Job $job -ErrorAction SilentlyContinue};Remove-Job $job -Force -ErrorAction SilentlyContinue}}
}
