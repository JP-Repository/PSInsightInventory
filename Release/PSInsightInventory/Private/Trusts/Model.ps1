function Get-PSITrustSchema {
    [ordered]@{
        domains=@('Observed domains',@('Name','Source DC','Query status','Observed TDO records','Collected at'))
        trusts=@('Trust observations',@('Name','Observed domain','Partner','Direction','Relationship flags','Protocol type reported','Selective authentication reported','Forest transitive reported','Within forest reported','Non-transitive flag','DN','Source DC','GUID','Provider source'))
        directions=@('Direction descriptions',@('Name','Observed domain','Partner','Direction','Raw direction','Meaning','DN'))
        settings=@('Trust settings',@('Name','Observed domain','Partner','Selective authentication reported','SIDFilteringForestAware reported','SIDFilteringQuarantined reported','TGT delegation reported','Uses AES keys reported','Uses RC4 encryption reported','Trust attributes raw','Supported encryption types raw','Treat as external flag','Quarantined domain flag','Cross-organization flag','Partner SID reported','Flat name','Created','Changed','DN'))
        partners=@('Observed partners',@('Name','Observed TDO records','Observed local domains','Observed directions'))
        collection=@('Collection ledger',@('Name','Target','Source DC','Status','Record count','Method','Collected at','Duration ms','Error ID','Message'))
    }
}
function ConvertTo-PSITrustModel($Context,[object[]]$Envelopes){
    $schema=Get-PSITrustSchema;$data=[ordered]@{};foreach($k in $schema.Keys){$data[$k]=New-Object collections.ArrayList}
    $required=@($Context.Domains|ForEach-Object{'trust:'+$_});$queries=@{};$raw=@{};$partners=@{};$collected=0
    foreach($e in $Envelopes){
        if($e.Key -notin $required -or $queries.ContainsKey($e.Key)){throw 'Unknown or duplicate trust outcome.'}
        if($e.Status -notin @('Succeeded','Failed','TimedOut')){throw 'Invalid trust collection status.'}
        $queries[$e.Key]=$e;$raw[$e.Key]=@();if($e.Status -eq 'Succeeded'){$raw[$e.Key]=@($e.Records|Where-Object{$null -ne $_})}
    }
    function V($o,$p){Get-PSISiteValue $o $p}
    function Flag($value,[long]$mask){if($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)){return $null};[long]$number=0;if(-not [long]::TryParse([string]$value,[ref]$number)){return $null};return ($number -band $mask) -ne 0}
    foreach($domainName in @($Context.Domains)){
        $key='trust:'+$domainName;if(-not $queries.ContainsKey($key)){throw "Missing trust outcome: $key"};$e=$queries[$key]
        if($e.Status -eq 'Succeeded'){$collected++}
        [void]$data.domains.Add([pscustomobject][ordered]@{Name=$domainName;'Source DC'=$e.SourceDC;'Query status'=$e.Status;'Observed TDO records'=if($e.Status -eq 'Succeeded'){$raw[$key].Count}else{$null};'Collected at'=$e.CollectedAt})
        [void]$data.collection.Add([pscustomobject][ordered]@{Name=$key;Target=$domainName;'Source DC'=$e.SourceDC;Status=$e.Status;'Record count'=if($e.Status -eq 'Succeeded'){$raw[$key].Count}else{$null};Method=$e.Method;'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=if($e.Status -eq 'Succeeded'){'Local domain TDO read completed; zero rows is a valid empty result.'}else{$e.ErrorMessage}})
        foreach($r in $raw[$key]){
            $partner=V $r 'trustPartner';if(-not $partner){$partner=V $r 'Target'}
            $label=$domainName+' / '+$(if($partner){[string]$partner}else{'Partner not returned'})
            $directionRaw=V $r 'trustDirection';$direction='Unknown';$meaning='Direction was not returned or could not be interpreted.'
            if($null -ne $directionRaw){
                switch([string]$directionRaw){
                    '0'{$direction='Disabled (0)';$meaning='No trust-direction bits are set on this observed object.'}
                    '1'{$direction='Inbound';$meaning='Partner trusts the observed domain (configured direction only).'}
                    '2'{$direction='Outbound';$meaning='Observed domain trusts the partner (configured direction only).'}
                    '3'{$direction='Bidirectional';$meaning='Both directions are configured on this observed object.'}
                    default{$direction='Unknown ('+[string]$directionRaw+')'}
                }
            }else{
                switch([string](V $r 'Direction')){
                    'Inbound'{$direction='Inbound';$meaning='Partner trusts the observed domain (provider-reported direction).'}
                    'Outbound'{$direction='Outbound';$meaning='Observed domain trusts the partner (provider-reported direction).'}
                    'Bidirectional'{$direction='Bidirectional';$meaning='Both directions are reported on this observed object.'}
                }
            }
            $attrs=V $r 'trustAttributes';$within=V $r 'IntraForest';$forest=V $r 'ForestTransitive'
            $relationship=if($within -eq $true){'Within-forest flag reported'}elseif($forest -eq $true){'Forest-transitive flag reported'}elseif($null -ne $attrs){'See raw attributes and protocol type'}else{'Not returned'}
            [void]$data.trusts.Add([pscustomobject][ordered]@{Name=$label;'Observed domain'=$domainName;Partner=$partner;Direction=$direction;'Relationship flags'=$relationship;'Protocol type reported'=V $r 'NativeProtocolType';'Selective authentication reported'=V $r 'SelectiveAuthentication';'Forest transitive reported'=$forest;'Within forest reported'=$within;'Non-transitive flag'=Flag $attrs 1;DN=V $r 'DistinguishedName';'Source DC'=$e.SourceDC;GUID=V $r 'ObjectGUID';'Provider source'=V $r 'Source'})
            [void]$data.directions.Add([pscustomobject][ordered]@{Name=$label;'Observed domain'=$domainName;Partner=$partner;Direction=$direction;'Raw direction'=$directionRaw;Meaning=$meaning;DN=V $r 'DistinguishedName'})
            [void]$data.settings.Add([pscustomobject][ordered]@{Name=$label;'Observed domain'=$domainName;Partner=$partner;'Selective authentication reported'=V $r 'SelectiveAuthentication';'SIDFilteringForestAware reported'=V $r 'SIDFilteringForestAware';'SIDFilteringQuarantined reported'=V $r 'SIDFilteringQuarantined';'TGT delegation reported'=V $r 'TGTDelegation';'Uses AES keys reported'=V $r 'UsesAESKeys';'Uses RC4 encryption reported'=V $r 'UsesRC4Encryption';'Trust attributes raw'=$attrs;'Supported encryption types raw'=V $r 'msDS-SupportedEncryptionTypes';'Treat as external flag'=Flag $attrs 64;'Quarantined domain flag'=Flag $attrs 4;'Cross-organization flag'=Flag $attrs 16;'Partner SID reported'=V $r 'SID';'Flat name'=V $r 'flatName';Created=V $r 'whenCreated';Changed=V $r 'whenChanged';DN=V $r 'DistinguishedName'})
            if($partner){$pkey=([string]$partner).ToLowerInvariant();if(-not $partners.ContainsKey($pkey)){$partners[$pkey]=New-Object collections.ArrayList};[void]$partners[$pkey].Add([pscustomobject]@{Partner=$partner;Domain=$domainName;Direction=$direction})}
        }
    }
    foreach($key in @($partners.Keys|Sort-Object)){$rows=@($partners[$key].ToArray());[void]$data.partners.Add([pscustomobject][ordered]@{Name=$rows[0].Partner;'Observed TDO records'=$rows.Count;'Observed local domains'=(@($rows.Domain|Sort-Object -Unique) -join '; ');'Observed directions'=(@($rows.Direction|Sort-Object -Unique) -join '; ')})}
    $complete=$collected -eq @($Context.Domains).Count;$coverage=[ordered]@{domains=$true;trusts=$complete;directions=$complete;settings=$complete;partners=$complete;collection=$true}
    $plain=[ordered]@{};foreach($k in $data.Keys){$plain[$k]=@($data[$k].ToArray())}
    [pscustomobject]@{Schema=$schema;Data=$plain;Raw=$raw;Coverage=$coverage;DomainsCollected=$collected}
}
