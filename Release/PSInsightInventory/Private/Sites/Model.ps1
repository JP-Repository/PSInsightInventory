function ConvertTo-PSISitesModel($Context,[object[]]$Envelopes){
    $required=@('sites','subnets','links','bridges','servers','settings','transports','ntds')
    $raw=@{};$ok=@{};$byKey=@{};$data=[ordered]@{};$schema=Get-PSISiteSchema
    foreach($key in $schema.Keys){$data[$key]=New-Object collections.ArrayList}
    foreach($envelope in $Envelopes){
        if($envelope.Key -notin $required -or $byKey.ContainsKey($envelope.Key)){throw 'Unknown or duplicate Sites collection envelope.'}
        if($envelope.Status -notin @('Succeeded','Failed','TimedOut')){throw 'Invalid Sites collection status.'}
        $byKey[$envelope.Key]=$envelope
    }
    foreach($key in $required){
        if(-not $byKey.ContainsKey($key)){throw "Missing collection outcome: $key"}
        $e=$byKey[$key];$ok[$key]=$e.Status -eq 'Succeeded';$raw[$key]=@()
        if($ok[$key]){$raw[$key]=@($e.Records | Where-Object{$null -ne $_})}
        [void]$data.collection.Add([pscustomobject][ordered]@{Name=$key;Status=$e.Status;'Record count'=if($ok[$key]){$raw[$key].Count}else{$null};Method=$e.Method;'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=if($ok[$key]){'Query completed; zero rows is a valid result.'}else{$e.ErrorMessage}})
    }
    $siteByDN=@{};$linkByDN=@{};$transportByDN=@{};$settingBySite=@{};$ntdsByServer=@{}
    foreach($s in $raw.sites){$siteByDN[[string]$s.DistinguishedName]=$s}
    foreach($s in $raw.links){$linkByDN[[string]$s.DistinguishedName]=$s}
    foreach($s in $raw.transports){$transportByDN[[string]$s.DistinguishedName]=$s}
    foreach($s in $raw.settings){$settingBySite[(Get-PSIParentDN $s.DistinguishedName)]=$s}
    foreach($s in $raw.ntds){$ntdsByServer[(Get-PSIParentDN $s.DistinguishedName)]=$true}
    function V($o,$p){$v=Get-PSISiteValue $o $p;if($null -eq $v -or @($v).Count -eq 0){return $null};return @($v)[0]}
    function L($o,$p){@(Get-PSISiteValue $o $p | Where-Object{$null -ne $_ -and [string]$_ -ne ''})}
    function SiteName([string]$dn){if($siteByDN.ContainsKey($dn)){return [string]$siteByDN[$dn].Name};return $dn}
    function TransportName([string]$dn){if($transportByDN.ContainsKey($dn)){return [string]$transportByDN[$dn].Name};return $dn}
    function Flag($value,[int]$mask){if($null -eq $value){return $null};return ([long]$value -band $mask) -ne 0}
    function Schedule($o,$type){
        $value=V $o 'schedule';$bytes=$null
        try{if($null -ne $value){$bytes=[convert]::FromBase64String([string]$value)}}catch{
            return [pscustomobject][ordered]@{Name=$o.Name;'Owner type'=$type;'Parse status'='Unsupported or malformed';'Allowed hours UTC'=$null;Summary='Invalid stored base64 schedule.';'Hourly masks UTC'=$null;'Raw base64'=[string]$value;DN=$o.DistinguishedName}
        }
        ConvertFrom-PSISchedule $bytes $o.Name $type $o.DistinguishedName
    }
    foreach($site in $raw.sites){
        $dn=[string]$site.DistinguishedName;$setting=$settingBySite[$dn]
        $serverCount=if($ok.servers){@($raw.servers | Where-Object{(Get-PSIParentDN (Get-PSIParentDN $_.DistinguishedName)) -eq $dn}).Count}else{$null}
        $dcCount=if($ok.servers -and $ok.ntds){@($raw.servers | Where-Object{(Get-PSIParentDN (Get-PSIParentDN $_.DistinguishedName)) -eq $dn -and $ntdsByServer.ContainsKey([string]$_.DistinguishedName)}).Count}else{$null}
        [void]$data.sites.Add([pscustomobject][ordered]@{
            Name=$site.Name;'DC objects'=$dcCount;'Server objects'=$serverCount
            Subnets=if($ok.subnets){@($raw.subnets | Where-Object{(V $_ 'siteObject') -eq $dn}).Count}else{$null}
            'Site links'=if($ok.links){@($raw.links | Where-Object{@(L $_ 'siteList') -contains $dn}).Count}else{$null}
            Location=V $site 'location';Description=V $site 'description';'ISTG DN'=V $setting 'interSiteTopologyGenerator';'Site options raw'=V $setting 'options'
            DN=$dn;Created=V $site 'whenCreated';Changed=V $site 'whenChanged'
        })
    }
    foreach($subnet in $raw.subnets){
        $siteDN=[string](V $subnet 'siteObject');$assignment=if(-not $siteDN){'Unassigned / no value returned'}elseif(-not $ok.sites){'Site lookup unavailable'}elseif($siteByDN.ContainsKey($siteDN)){'Assigned'}else{'Unresolved reference'}
        [void]$data.subnets.Add([pscustomobject][ordered]@{Name=$subnet.Name;Site=if($siteDN){SiteName $siteDN}else{$null};Assignment=$assignment;Description=V $subnet 'description';Location=V $subnet 'location';'Site DN'=$siteDN;DN=$subnet.DistinguishedName})
    }
    foreach($link in $raw.links){
        $dn=[string]$link.DistinguishedName;$transport=TransportName (Get-PSIParentDN $dn);$members=@(L $link 'siteList');$options=V $link 'options';$schedule=Schedule $link 'Site link'
        [void]$data.schedules.Add($schedule)
        [void]$data.links.Add([pscustomobject][ordered]@{Name=$link.Name;Transport=$transport;Cost=V $link 'cost';'Interval minutes'=V $link 'replInterval';Sites=(@($members | ForEach-Object{SiteName $_}) -join '; ');'Member count'=$members.Count;'Options raw'=$options;'Change notification'=Flag $options 1;'Two-way sync'=Flag $options 2;'Compression disabled'=Flag $options 4;Schedule=$schedule.Summary;DN=$dn})
        foreach($member in $members){[void]$data.linkMembers.Add([pscustomobject][ordered]@{Name=$link.Name+' → '+(SiteName $member);'Site link'=$link.Name;Site=SiteName $member;'Reference state'=if(-not $ok.sites){'Lookup unavailable'}elseif($siteByDN.ContainsKey([string]$member)){'Resolved'}else{'Unresolved'};'Site DN'=[string]$member;'Link DN'=$dn})}
    }
    foreach($bridge in $raw.bridges){
        $members=@(L $bridge 'siteLinkList');$labels=@($members | ForEach-Object{if($linkByDN.ContainsKey([string]$_)){$linkByDN[[string]$_].Name}else{[string]$_}})
        [void]$data.bridges.Add([pscustomobject][ordered]@{Name=$bridge.Name;Transport=TransportName (Get-PSIParentDN $bridge.DistinguishedName);'Member links'=$labels -join '; ';'Member count'=$members.Count;Description=V $bridge 'description';DN=$bridge.DistinguishedName})
        for($i=0;$i -lt $members.Count;$i++){[void]$data.bridgeMembers.Add([pscustomobject][ordered]@{Name=$bridge.Name+' → '+$labels[$i];Bridge=$bridge.Name;'Site link'=$labels[$i];'Reference state'=if(-not $ok.links){'Lookup unavailable'}elseif($linkByDN.ContainsKey([string]$members[$i])){'Resolved'}else{'Unresolved'};'Link DN'=[string]$members[$i];'Bridge DN'=$bridge.DistinguishedName})}
    }
    foreach($server in $raw.servers){
        $siteDN=Get-PSIParentDN (Get-PSIParentDN $server.DistinguishedName)
        [void]$data.servers.Add([pscustomobject][ordered]@{Name=$server.Name;'Host name'=V $server 'dNSHostName';Site=SiteName $siteDN;'NTDS object present'=if($ok.ntds){$ntdsByServer.ContainsKey([string]$server.DistinguishedName)}else{$null};'Bridgehead transports'=(@(L $server 'bridgeheadTransportList' | ForEach-Object{TransportName $_}) -join '; ');'Server reference'=V $server 'serverReference';DN=$server.DistinguishedName})
    }
    foreach($setting in $raw.settings){
        $siteDN=Get-PSIParentDN $setting.DistinguishedName;$schedule=Schedule $setting 'NTDS site settings'
        [void]$data.schedules.Add($schedule)
        [void]$data.settings.Add([pscustomobject][ordered]@{Name=SiteName $siteDN;Site=SiteName $siteDN;'ISTG DN'=V $setting 'interSiteTopologyGenerator';'Options raw'=V $setting 'options';'Preferred GC site DN'=V $setting 'msDS-Preferred-GC-Site';Schedule=$schedule.Summary;'Site DN'=$siteDN;DN=$setting.DistinguishedName})
    }
    foreach($transport in $raw.transports){
        $options=V $transport 'options';$bridgesRequired=Flag $options 2
        [void]$data.transports.Add([pscustomobject][ordered]@{Name=$transport.Name;'Options raw'=$options;'Ignore schedules'=Flag $options 1;'Bridge all site links'=if($null -ne $bridgesRequired){-not $bridgesRequired}else{$null};'Address attribute'=V $transport 'transportAddressAttribute';DN=$transport.DistinguishedName})
    }
    $plain=[ordered]@{};foreach($key in $data.Keys){$plain[$key]=@($data[$key].ToArray())}
    [pscustomobject]@{Context=$Context;Schema=$schema;Data=$plain;Raw=$raw;Coverage=$ok}
}
