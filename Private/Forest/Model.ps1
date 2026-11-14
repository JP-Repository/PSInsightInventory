function Get-PSIForestSchema {
    [ordered]@{
        forest=@('Forest',@('Name','Root domain','Functional level','Domain references','Site count','Application partition count','Schema master','Domain naming master','Application partitions','Sites'))
        domains=@('Domains',@('Name','Query status','Source DC','NetBIOS name','Functional level','Parent domain','Children','SID','GUID','DN','Last logon replication interval'))
        hierarchy=@('Domain hierarchy',@('Name','Forest root','Parent domain','Children','Query status','DN','Relationship source'))
        levels=@('Functional levels',@('Name','Scope','Functional level','Query status'))
        fsmo=@('FSMO owners',@('Name','Scope','Domain / forest','Role','Owner','Query status'))
        suffixes=@('Configured suffixes',@('Name','Type','Forest'))
        partitions=@('Partition references',@('Name','Naming context','DNS root','NetBIOS name','Enabled','System flags raw','Writable replica DNs','Read-only replica DNs','DN'))
        contexts=@('Hosted naming contexts',@('Name','Source DC','Connection domain','Observation scope'))
        containers=@('Default containers',@('Name','Domain','Container property','DN'))
        servers=@('Unique directory servers',@('Name','Domain','Directory roles','Reference sources','Reference count'))
        policies=@('Default domain password policies',@('Name','Query status','Source DC','Minimum length','Password history','Complexity','Reversible encryption','Minimum age','Maximum age','Lockout threshold','Lockout duration','Lockout observation window','DN'))
        collection=@('Collection ledger',@('Name','Target','Source DC','Status','Record count','Method','Collected at','Duration ms','Error ID','Message'))
    }
}
function ConvertTo-PSIForestModel($Context,[object[]]$Envelopes){
    $schema=Get-PSIForestSchema;$data=[ordered]@{};foreach($key in $schema.Keys){$data[$key]=New-Object collections.ArrayList}
    $required=@('forest','partitions');foreach($n in @($Context.Domains)){$required+=@(('domain:'+$n),('policy:'+$n))}
    $queries=@{};$raw=@{}
    foreach($e in $Envelopes){
        if($e.Key -notin $required -or $queries.ContainsKey($e.Key)){throw 'Unknown or duplicate forest outcome.'}
        if($e.Status -notin @('Succeeded','Failed','TimedOut')){throw 'Invalid forest collection status.'}
        $queries[$e.Key]=$e;$raw[$e.Key]=@();if($e.Status -eq 'Succeeded'){$raw[$e.Key]=@($e.Records|Where-Object{$null -ne $_})}
        [void]$data.collection.Add([pscustomobject][ordered]@{Name=$e.Key;Target=$e.Target;'Source DC'=$e.SourceDC;Status=$e.Status;'Record count'=if($e.Status -eq 'Succeeded'){$raw[$e.Key].Count}else{$null};Method=$e.Method;'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=if($e.Status -eq 'Succeeded'){'Read completed; returned values are configuration inventory.'}else{$e.ErrorMessage}})
    }
    foreach($key in $required){if(-not $queries.ContainsKey($key)){throw "Missing forest outcome: $key"}}
    function V($o,$p){Get-PSISiteValue $o $p}
    function Join-V($o,$p){(@(Get-PSISiteValue $o $p | Where-Object{$null -ne $_})|ForEach-Object{[string]$_}) -join '; '}
    $f=if($raw.forest.Count){$raw.forest[0]}else{$null}
    [void]$data.forest.Add([pscustomobject][ordered]@{Name=$Context.Forest;'Root domain'=V $f 'RootDomain';'Functional level'=V $f 'ForestMode';'Domain references'=@($Context.Domains).Count;'Site count'=if($null -ne $f){@(V $f 'Sites'|Where-Object{$_}).Count}else{$null};'Application partition count'=if($null -ne $f){@(V $f 'ApplicationPartitions'|Where-Object{$_}).Count}else{$null};'Schema master'=V $f 'SchemaMaster';'Domain naming master'=V $f 'DomainNamingMaster';'Application partitions'=Join-V $f 'ApplicationPartitions';Sites=Join-V $f 'Sites'})
    [void]$data.levels.Add([pscustomobject]@{Name=$Context.Forest;Scope='Forest';'Functional level'=V $f 'ForestMode';'Query status'=$queries.forest.Status})
    foreach($role in @('SchemaMaster','DomainNamingMaster')){[void]$data.fsmo.Add([pscustomobject][ordered]@{Name=$Context.Forest+' / '+$role;Scope='Forest';'Domain / forest'=$Context.Forest;Role=$role;Owner=V $f $role;'Query status'=$queries.forest.Status})}
    foreach($kind in @('UPNSuffixes','SPNSuffixes')){foreach($suffix in @(V $f $kind|Where-Object{$_})){[void]$data.suffixes.Add([pscustomobject][ordered]@{Name=[string]$suffix;Type=if($kind -eq 'UPNSuffixes'){'Configured UPN suffix'}else{'Configured SPN suffix'};Forest=$Context.Forest})}}
    foreach($server in @(V $f 'GlobalCatalogs'|Where-Object{$_})){[void]$data.servers.Add([pscustomobject][ordered]@{Name=[string]$server;'Domain / forest'=$Context.Forest;'Source property'='Get-ADForest.GlobalCatalogs'})}
    $rootSeen=@{}
    function Add-Contexts($root,$domain){
        $hostName=[string](V $root 'dnsHostName')
        foreach($nc in @(V $root 'namingContexts'|Where-Object{$_})){
            $id=$hostName+'|'+$nc
            if(-not $rootSeen.ContainsKey($id)){[void]$data.contexts.Add([pscustomobject][ordered]@{Name=[string]$nc;'Source DC'=$hostName;'Connection domain'=$domain;'Observation scope'='Naming contexts hosted by this observed DC only'});$rootSeen[$id]=$true}
        }
    }
    Add-Contexts $Context.Root $Context.Domain
    $domainSuccess=0;$policySuccess=0
    foreach($name in @($Context.Domains)){
        $q=$queries['domain:'+$name];$rows=$raw['domain:'+$name];$d=$null
        if($q.Status -eq 'Succeeded'){
            if($rows.Count -ne 1){throw 'A successful domain query must return exactly one domain record.'}
            $domainSuccess++;$d=$rows[0].Domain;Add-Contexts $rows[0].Root $name
        }
        [void]$data.domains.Add([pscustomobject][ordered]@{Name=$name;'Query status'=$q.Status;'Source DC'=$q.SourceDC;'NetBIOS name'=V $d 'NetBIOSName';'Functional level'=V $d 'DomainMode';'Parent domain'=V $d 'ParentDomain';Children=Join-V $d 'ChildDomains';SID=V $d 'DomainSID';GUID=V $d 'ObjectGUID';DN=V $d 'DistinguishedName';'Last logon replication interval'=V $d 'LastLogonReplicationInterval'})
        [void]$data.hierarchy.Add([pscustomobject][ordered]@{Name=$name;'Forest root'=([string]$Context.RootDomain -ieq $name);'Parent domain'=V $d 'ParentDomain';Children=Join-V $d 'ChildDomains';'Query status'=$q.Status;DN=V $d 'DistinguishedName'})
        [void]$data.levels.Add([pscustomobject][ordered]@{Name=$name;Scope='Domain';'Functional level'=V $d 'DomainMode';'Query status'=$q.Status})
        foreach($role in @('PDCEmulator','RIDMaster','InfrastructureMaster')){[void]$data.fsmo.Add([pscustomobject][ordered]@{Name=$name+' / '+$role;Scope='Domain';'Domain / forest'=$name;Role=$role;Owner=V $d $role;'Query status'=$q.Status})}
        if($null -ne $d){
            foreach($property in @('ComputersContainer','UsersContainer','DomainControllersContainer','DeletedObjectsContainer','LostAndFoundContainer','SystemsContainer')){[void]$data.containers.Add([pscustomobject][ordered]@{Name=$name+' / '+$property;Domain=$name;'Container property'=$property;DN=V $d $property})}
            foreach($property in @('ReplicaDirectoryServers','ReadOnlyReplicaDirectoryServers')){foreach($server in @(V $d $property|Where-Object{$_})){[void]$data.servers.Add([pscustomobject][ordered]@{Name=[string]$server;'Domain / forest'=$name;'Source property'='Get-ADDomain.'+$property})}}
        }
        $pq=$queries['policy:'+$name];$pr=$raw['policy:'+$name];$policy=$null
        if($pq.Status -eq 'Succeeded'){if($pr.Count -ne 1){throw 'A successful default policy query must return one record.'};$policy=$pr[0];$policySuccess++}
        [void]$data.policies.Add([pscustomobject][ordered]@{Name=$name;'Query status'=$pq.Status;'Source DC'=$pq.SourceDC;'Minimum length'=V $policy 'MinPasswordLength';'Password history'=V $policy 'PasswordHistoryCount';Complexity=V $policy 'ComplexityEnabled';'Reversible encryption'=V $policy 'ReversibleEncryptionEnabled';'Minimum age'=V $policy 'MinPasswordAge';'Maximum age'=V $policy 'MaxPasswordAge';'Lockout threshold'=V $policy 'LockoutThreshold';'Lockout duration'=V $policy 'LockoutDuration';'Lockout observation window'=V $policy 'LockoutObservationWindow';DN=V $policy 'DistinguishedName'})
    }
    foreach($p in $raw.partitions){[void]$data.partitions.Add([pscustomobject][ordered]@{Name=V $p 'Name';'Naming context'=V $p 'nCName';'DNS root'=V $p 'dnsRoot';'NetBIOS name'=V $p 'nETBIOSName';Enabled=V $p 'enabled';'System flags raw'=V $p 'systemFlags';'Writable replica DNs'=Join-V $p 'msDS-NC-Replica-Locations';'Read-only replica DNs'=Join-V $p 'msDS-NC-RO-Replica-Locations';DN=V $p 'DistinguishedName'})}

    # Resolve explicit directory relationships only. Forest membership does
    # not make a domain a child of the forest root, and DNS names can differ.
    $domainByCrossRef=@{};$crossRefByDomain=@{}
    foreach($record in $raw.partitions){
        $dns=[string](V $record 'dnsRoot');$ref=[string](V $record 'DistinguishedName')
        $nc=[string](V $record 'nCName')
        if($dns -in @($Context.Domains) -and $ref -and $nc -ieq (($dns.Split('.')|ForEach-Object{'DC='+$_}) -join ',')){
            $domainByCrossRef[$ref]=$dns;$crossRefByDomain[$dns]=$record
        }
    }
    $parentByName=@{}
    $relationshipSource=@{}
    foreach($row in $data.domains){
        $name=[string]$row.Name
        if($name -ieq $Context.RootDomain){continue}
        $parent=[string]$row.'Parent domain'
        if($parent -and $parent -ine $name){
            $parentByName[$name]=$parent;$relationshipSource[$name]='Get-ADDomain.ParentDomain'
            continue
        }
        $ref=[string](V $crossRefByDomain[$name] 'trustParent')
        if($ref -and $domainByCrossRef.ContainsKey($ref) -and $domainByCrossRef[$ref] -ine $name){
            $parentByName[$name]=$domainByCrossRef[$ref];$relationshipSource[$name]='Configuration crossRef trustParent'
        }
    }
    foreach($row in $data.domains){
        foreach($child in @($row.Children -split '; '|Where-Object{$_ -and $_ -in $Context.Domains})){
            if($child -ieq $Context.RootDomain -or $child -ieq $row.Name -or $parentByName.ContainsKey($child)){continue}
            $parentByName[$child]=$row.Name;$relationshipSource[$child]='Get-ADDomain.ChildDomains'
        }
    }
    foreach($row in @($data.domains.ToArray())+@($data.hierarchy.ToArray())){
        $name=[string]$row.Name
        $row.'Parent domain'=$parentByName[$name]
        $row.Children=(@($parentByName.Keys|Where-Object{$parentByName[$_] -ieq $name}|Sort-Object) -join '; ')
        if($null -ne $row.PSObject.Properties['Forest root']){
            $source=if($name -ieq $Context.RootDomain){'Forest root'}elseif($relationshipSource.ContainsKey($name)){$relationshipSource[$name]}else{'Parent not reported'}
            $row | Add-Member -NotePropertyName 'Relationship source' -NotePropertyValue $source
        }
    }

    # Collapse GC, writable and RODC references into one row per unique server.
    $serverMap=@{}
    foreach($row in @($data.servers)){
        $id=([string]$row.Name).ToLowerInvariant()
        if(-not $serverMap.ContainsKey($id)){$serverMap[$id]=[ordered]@{Name=[string]$row.Name;Domains=New-Object collections.ArrayList;Roles=New-Object collections.ArrayList;Sources=New-Object collections.ArrayList;Count=0}}
        $item=$serverMap[$id];$item.Count++
        $source=[string]$row.'Source property';if(-not $item.Sources.Contains($source)){[void]$item.Sources.Add($source)}
        if($source -notlike '*.GlobalCatalogs' -and $row.'Domain / forest' -and -not $item.Domains.Contains([string]$row.'Domain / forest')){[void]$item.Domains.Add([string]$row.'Domain / forest')}
        $role=if($source -like '*.GlobalCatalogs'){'Global Catalog'}elseif($source -like '*.ReadOnlyReplicaDirectoryServers'){'RODC'}else{'Writable DC'}
        if(-not $item.Roles.Contains($role)){[void]$item.Roles.Add($role)}
    }
    $data.servers.Clear()
    foreach($item in @($serverMap.Values|Sort-Object Name)){[void]$data.servers.Add([pscustomobject][ordered]@{Name=$item.Name;Domain=if($item.Domains.Count){$item.Domains -join '; '}else{$null};'Directory roles'=($item.Roles -join '; ');'Reference sources'=($item.Sources -join '; ');'Reference count'=$item.Count})}
    $all=$domainSuccess -eq @($Context.Domains).Count;$coverage=[ordered]@{forest=($queries.forest.Status -eq 'Succeeded');domains=$true;hierarchy=$true;levels=$true;fsmo=$true;suffixes=($queries.forest.Status -eq 'Succeeded');partitions=($queries.partitions.Status -eq 'Succeeded');contexts=$all;containers=$all;servers=$all;policies=$true;collection=$true}
    $plain=[ordered]@{};foreach($key in $data.Keys){$plain[$key]=@($data[$key].ToArray())}
    [pscustomobject]@{Schema=$schema;Data=$plain;Raw=$raw;Coverage=$coverage;DomainDetailsCollected=$domainSuccess;PoliciesCollected=$policySuccess}
}
