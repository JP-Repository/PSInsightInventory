function Get-PSISiteValue($Object,[string]$Property){
    if($null -eq $Object){return $null}
    if($Object -is [collections.IDictionary]){if($Object.Contains($Property)){return $Object[$Property]};return $null}
    if($null -ne $Object.PSObject.Properties[$Property]){return $Object.$Property}
    return $null
}
function Get-PSIParentDN([string]$DN){
    $escaped=$false
    for($i=0;$i -lt $DN.Length;$i++){
        if($escaped){$escaped=$false;continue}
        if($DN[$i] -eq '\'){$escaped=$true;continue}
        if($DN[$i] -eq ','){return $DN.Substring($i+1)}
    }
    return $null
}
function Get-PSISiteSchema {
    [ordered]@{
        sites=@('Sites',@('Name','DC objects','Server objects','Subnets','Site links','Location','Description','ISTG DN','Site options raw','DN','Created','Changed'))
        subnets=@('Subnets',@('Name','Site','Assignment','Description','Location','Site DN','DN'))
        links=@('Site links',@('Name','Transport','Cost','Interval minutes','Sites','Member count','Options raw','Change notification','Two-way sync','Compression disabled','Schedule','DN'))
        linkMembers=@('Site link membership',@('Name','Site link','Site','Reference state','Site DN','Link DN'))
        bridges=@('Site link bridges',@('Name','Transport','Member links','Member count','Description','DN'))
        bridgeMembers=@('Bridge membership',@('Name','Bridge','Site link','Reference state','Link DN','Bridge DN'))
        servers=@('Directory servers',@('Name','Host name','Site','NTDS object present','Bridgehead transports','Server reference','DN'))
        settings=@('Site configuration',@('Name','Site','ISTG DN','Options raw','Preferred GC site DN','Schedule','Site DN','DN'))
        transports=@('Transports',@('Name','Options raw','Ignore schedules','Bridge all site links','Address attribute','DN'))
        schedules=@('Stored schedules',@('Name','Owner type','Parse status','Allowed hours UTC','Summary','Hourly masks UTC','Raw base64','DN'))
        collection=@('Collection ledger',@('Name','Status','Record count','Method','Collected at','Duration ms','Error ID','Message'))
    }
}
function ConvertFrom-PSISchedule($Value,[string]$Name,[string]$OwnerType,[string]$DN){
    $raw=$null;$masks=$null;$hours=$null;$status='Not set or not returned';$summary='No stored schedule returned; no availability inferred.'
    try{
        if($null -ne $Value -and @($Value).Count -gt 0){
            [byte[]]$bytes=$Value;$raw=[convert]::ToBase64String($bytes)
            if($bytes.Length -lt 20){throw 'Schedule header is truncated.'}
            $size=[bitconverter]::ToUInt32($bytes,0);$count=[bitconverter]::ToUInt32($bytes,8)
            $type=[bitconverter]::ToUInt32($bytes,12);$offset=[bitconverter]::ToUInt32($bytes,16)
            if($size -ne $bytes.Length -or $count -ne 1 -or $type -ne 0 -or $offset -lt 20 -or ([long]$offset+168) -gt $bytes.Length){throw 'Unsupported schedule header or offset.'}
            $maskValues=@($bytes[$offset..($offset+167)])
            if(@($maskValues | Where-Object{($_ -band 240) -ne 0}).Count){throw 'Reserved schedule bits are nonzero.'}
            $quarters=0
            foreach($mask in $maskValues){foreach($bit in @(1,2,4,8)){if(($mask -band $bit) -ne 0){$quarters++}}}
            $masks=($maskValues | ForEach-Object{$_.ToString('X1')}) -join ''
            $hours=$quarters/4.0;$status='Parsed';$summary="$hours / 168 permitted hours per stored UTC week."
        }
    }catch{$status='Unsupported or malformed';$summary=$_.Exception.Message}
    [pscustomobject][ordered]@{Name=$Name;'Owner type'=$OwnerType;'Parse status'=$status;'Allowed hours UTC'=$hours;Summary=$summary;'Hourly masks UTC'=$masks;'Raw base64'=$raw;DN=$DN}
}
function ConvertTo-PSISafeJson($Value){
    ($Value | ConvertTo-Json -Depth 30).Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
}
