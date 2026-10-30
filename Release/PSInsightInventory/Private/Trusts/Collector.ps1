# Reads local-forest TDO observations only; does not contact a trust partner.
$script:PSITrustCollector={
    param([string]$Domain,[pscredential]$Credential)
    $ErrorActionPreference='Stop';Import-Module ActiveDirectory -ErrorAction Stop
    function Parameters([string]$dc){$p=@{Server=$dc;ErrorAction='Stop'};if($null -ne $Credential){$p.Credential=$Credential};return $p}
    function ParentDN([string]$dn){$escaped=$false;for($i=0;$i -lt $dn.Length;$i++){if($escaped){$escaped=$false;continue};if($dn[$i] -eq '\'){$escaped=$true;continue};if($dn[$i] -eq ','){return $dn.Substring($i+1)}};return $null}
    function Property($o,$p){if($null -ne $o.PSObject.Properties[$p]){return $o.$p};return $null}
    $p=Parameters $Domain;$r=Get-ADRootDSE @p;$seed=[string]$r.dnsHostName
    if(-not $seed){throw 'Trust discovery did not return a source DC.'}
    $p=Parameters $seed;$r=Get-ADRootDSE @p;$initial=Get-ADDomain @p
    if([string]$initial.DNSRoot -ine $Domain){throw 'Connection domain does not match discovery.'}
    $forest=Get-ADForest @p;$names=@($forest.Domains|ForEach-Object{[string]$_}|Sort-Object -Unique)
    if(-not $names.Count -or $names -notcontains $Domain){throw 'Connection domain is not in the returned local forest membership.'}
    [pscustomobject]@{Kind='Context';Forest=[string]$forest.Name;RootDomain=[string]$forest.RootDomain;Domain=$Domain;Server=$seed;Domains=$names;ConfigurationNC=[string]$r.configurationNamingContext}
    # Never request Properties * or trust authentication secret attributes.
    $ldap=@('trustAttributes','trustDirection','trustPartner','flatName','securityIdentifier','msDS-SupportedEncryptionTypes','whenCreated','whenChanged')
    $safe=@('Name','DistinguishedName','ObjectGUID','Source','Target','Direction','IntraForest','ForestTransitive','DisallowTransivity','SelectiveAuthentication','SIDFilteringForestAware','SIDFilteringQuarantined','TGTDelegation','UsesAESKeys','UsesRC4Encryption','SID')+$ldap
    foreach($localDomain in $names){
        $clock=[diagnostics.stopwatch]::StartNew();$rows=@();$source=$null;$status='Succeeded';$id=$null;$message=$null
        try{
            if($localDomain -ieq $Domain){$source=$seed;$info=$initial}
            else{$connect=Parameters $localDomain;$rd=Get-ADRootDSE @connect;$source=[string]$rd.dnsHostName;if(-not $source){throw 'Member-domain discovery did not return a DC.'};$connect=Parameters $source;$info=Get-ADDomain @connect}
            if([string]$info.DNSRoot -ine $localDomain -or [string]$info.Forest -ine [string]$forest.Name){throw 'Member domain/forest verification failed.'}
            $connect=Parameters $source;$systemDN='CN=System,'+[string]$info.DistinguishedName
            $rows=@(Get-ADTrust -Filter * -Properties $ldap @connect | ForEach-Object{
                if((ParentDN ([string]$_.DistinguishedName)) -ine $systemDN){throw 'Get-ADTrust returned a TDO outside the verified domain System container.'}
                $record=[ordered]@{}
                foreach($name in $safe){
                    $v=Property $_ $name
                    if($null -eq $v){$record[$name]=$null}
                    elseif($v -is [bool]){$record[$name]=$v}
                    elseif($v -is [datetime]){$record[$name]=([datetimeoffset]$v).ToString('o')}
                    elseif($v -is [byte[]]){$record[$name]=[convert]::ToBase64String($v)}
                    else{$record[$name]=[string]$v}
                }
                $record['NativeProtocolType']=[string](Property $_ 'TrustType')
                [pscustomobject]$record
            })
        }catch{$status='Failed';$id=$_.FullyQualifiedErrorId;$message=$_.Exception.Message;$rows=@()}
        $clock.Stop()
        [pscustomobject]@{Kind='Section';Key='trust:'+$localDomain;Target=$localDomain;SourceDC=$source;Status=$status;Records=$rows;Method='ADWS / Get-ADTrust on verified local-forest domain';CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$clock.ElapsedMilliseconds;ErrorId=$id;ErrorMessage=$message}
    }
}
