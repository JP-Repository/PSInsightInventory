function Get-PSIDnsSchema {
    [ordered]@{
        dcs=@('Selected domain controllers',@('Name','Server','Domain','Site','OS','Inventory','Zones observed'))
        role=@('DNS role',@('Name','Server','DNS role present','Service state'))
        client=@('Client resolvers',@('Name','Server','Adapter','DNS search order','Preferred DNS','Alternate DNS','Additional DNS'))
        forwarders=@('Server forwarders',@('Name','Server','Forwarder','Order','Timeout seconds','Use root hints'))
        recursion=@('Recursion',@('Name','Server','Enabled','Additional timeout','Retry interval','Timeout','Secure response'))
        scavenging=@('Server scavenging',@('Name','Server','Enabled','Interval','Default no-refresh interval','Default refresh interval','Last scavenge time'))
        rootHints=@('Root hints',@('Name','Server','Name server','Addresses'))
        zones=@('Zones',@('Name','Server','Zone','Type','AD integrated','Directory partition','Dynamic updates','Reverse lookup','Paused','Shutdown','Zone file'))
        conditional=@('Conditional forwarders',@('Name','Server','Zone','Master servers','AD integrated','Directory partition','Timeout seconds','Use recursion'))
        aging=@('Zone aging',@('Name','Server','Zone','Aging enabled','No-refresh interval','Refresh interval','Scavenge servers','Available for scavenging'))
        delegations=@('Delegations',@('Name','Server','Zone','Child zone','Name servers','IP addresses'))
        nameServers=@('Zone NS records',@('Name','Server','Zone','Owner','Name server','TTL','Timestamp'))
        nsAddresses=@('Stored NS addresses',@('Name','Server','Zone','Name server','Address zone','Owner','Record type','Address','TTL'))
        scopes=@('Zone scopes',@('Name','Server','Zone','Scope','File name'))
        zoneQueries=@('Per-zone collection',@('Name','Server','Zone','Operation','Status','Duration ms','Error ID','Message','Collected at'))
        collection=@('Category collection',@('Name','Server','Section','Outcome','Method','Collected at','Message','Check ID','Status','Duration ms','Record count','Error ID','Started at'))
    }
}
function ConvertTo-PSIDnsModel {
    $schema=Get-PSIDnsSchema;$data=[ordered]@{};$coverage=[ordered]@{}
    foreach($k in $schema.Keys){
        $rows=New-Object collections.ArrayList
        foreach($source in $script:DCInvData[$k].ToArray()){
            $record=[ordered]@{};foreach($col in $schema[$k][1]){$record[$col]=Get-DCInvValue $source $col}
            $record.Server=$source.Name
            $record.Name=if($k -eq 'dcs'){$source.Name}elseif($k -eq 'collection'){$source.Name+' / '+$source.'Check ID'}elseif($null -ne (Get-DCInvValue $source 'Zone')){$source.Name+' / '+$source.Zone}else{$source.Name}
            [void]$rows.Add([pscustomobject]$record)
        }
        $data[$k]=@($rows.ToArray())
        $coverage[$k]=if($k -in @('dcs','collection')){$true}else{@($script:DCInvData.collection.ToArray()|Where-Object{$_.'Check ID' -eq $k -and $_.Status -notin @('Succeeded','NotApplicable')}).Count -eq 0}
    }
    [pscustomobject]@{Schema=$schema;Data=$data;Coverage=$coverage;Raw=[ordered]@{}}
}
