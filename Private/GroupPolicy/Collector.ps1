$script:PSIGpoCollector={
 param([string]$Domain,[string]$HelperText,[bool]$ShowProgress=$false)
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
 . ([scriptblock]::Create($HelperText))
 function V($o,$p){if($null -ne $o -and $null -ne $o.PSObject.Properties[$p]){return $o.$p};return $null}
 function DateText($v){if($null -ne $v){return ([datetimeoffset]$v).ToString('o')};return $null}
 function Emit($Key,$Status,[object[]]$Rows,$Message='',$Id='', [long]$Ms=0){[pscustomobject]@{Kind='Section';Key=$Key;Status=$Status;Records=@($Rows);CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$Ms;ErrorId=$Id;ErrorMessage=$Message}}
 Import-Module ActiveDirectory -ErrorAction Stop;Import-Module GroupPolicy -ErrorAction Stop
 $root=Get-ADRootDSE -Server $Domain -ErrorAction Stop;$server=[string]$root.dnsHostName
 if(-not $server){throw 'Discovery did not return a pinned DC.'}
 $domainInfo=Get-ADDomain -Server $server -ErrorAction Stop
 if($domainInfo.DNSRoot -ine $Domain){throw 'Discovered DC does not serve the explicitly requested domain.'}
 $domainDN=[string]$domainInfo.DistinguishedName;$configDN=[string]$root.configurationNamingContext
 [pscustomobject]@{Kind='Context';Domain=$Domain;Server=$server;DomainDN=$domainDN;ConfigurationNC=$configDN;Forest=[string]$domainInfo.Forest}
 $ledger=New-Object collections.ArrayList;$gpos=@();$gpoError=$null;$watch=[diagnostics.stopwatch]::StartNew()
 try{$gpos=@(Get-GPO -All -Domain $Domain -Server $server -ErrorAction Stop);foreach($g in $gpos){if($g.DomainName -ine $Domain){throw 'A returned GPO is outside the selected domain.'};$null=[guid]$g.Id}}catch{$gpoError=$_;$gpos=@()}
 $watch.Stop()
 if($null -ne $gpoError){Emit 'gpos' 'Failed' @() $gpoError.Exception.Message $gpoError.FullyQualifiedErrorId $watch.ElapsedMilliseconds;Emit 'versions' 'NotAttempted' @() 'GPO enumeration failed.'}
 else{
  Emit 'gpos' 'Succeeded' @($gpos|ForEach-Object{[pscustomobject]@{Name=$_.DisplayName;'GPO ID'=([guid]$_.Id).ToString();Domain=$_.DomainName;Owner=V $_ 'Owner';Status=[string]$_.GpoStatus;Created=DateText (V $_ 'CreationTime');Changed=DateText (V $_ 'ModificationTime');Description=V $_ 'Description'}}) '' '' $watch.ElapsedMilliseconds
  Emit 'versions' 'Succeeded' @($gpos|ForEach-Object{[pscustomobject]@{Name=$_.DisplayName;'GPO ID'=([guid]$_.Id).ToString();'User AD version'=V (V $_ 'User') 'DSVersion';'User SYSVOL version'=V (V $_ 'User') 'SysvolVersion';'Computer AD version'=V (V $_ 'Computer') 'DSVersion';'Computer SYSVOL version'=V (V $_ 'Computer') 'SysvolVersion'}})
 }
 # Query each container source independently; preserve successful sources if another fails.
 $containerRows=New-Object collections.ArrayList;$linkRows=New-Object collections.ArrayList;$sourceFailures=0
 foreach($source in @('Domain','OU','Site')){
  $watch=[diagnostics.stopwatch]::StartNew();$status='Succeeded';$message='Collected';$id='';$retained=0
  try{
   $objects=switch($source){
    'Domain'{Get-ADObject -Identity $domainDN -Properties gPLink,gPOptions -Server $server -ErrorAction Stop}
    'OU'{Get-ADObject -LDAPFilter '(objectClass=organizationalUnit)' -SearchBase $domainDN -SearchScope Subtree -Properties gPLink,gPOptions -Server $server -ErrorAction Stop}
    'Site'{Get-ADObject -LDAPFilter '(objectClass=site)' -SearchBase ('CN=Sites,'+$configDN) -SearchScope OneLevel -Properties gPLink,gPOptions -Server $server -ErrorAction Stop}
   }
   foreach($o in @($objects)){
    $dn=[string]$o.DistinguishedName
    if(($source -eq 'Domain' -and $dn -ine $domainDN) -or ($source -eq 'OU' -and -not $dn.EndsWith(','+$domainDN,[StringComparison]::OrdinalIgnoreCase)) -or ($source -eq 'Site' -and -not $dn.EndsWith(',CN=Sites,'+$configDN,[StringComparison]::OrdinalIgnoreCase))){throw 'Container scope guard rejected an unexpected DN.'}
    $allText=[string](V $o 'gPLink');$links=@(ConvertFrom-PSIGpoLinks $allText $o.Name $source $dn $domainDN)
    $options=V $o 'gPOptions'
    [void]$containerRows.Add([pscustomobject]@{Name=$o.Name;Type=$source;DN=$dn;'Block inheritance'=if($null -eq $options){$null}else{([int]$options -band 1) -ne 0};'Options raw'=$options;'Link entries observed'=[regex]::Matches($allText,'\[LDAP://','IgnoreCase').Count;'Selected-domain links'=$links.Count})
    foreach($link in $links){[void]$linkRows.Add($link)};$retained++
   }
  }catch{$status='Failed';$message=$_.Exception.Message;$id=$_.FullyQualifiedErrorId;$sourceFailures++}
  $watch.Stop();[void]$ledger.Add([pscustomobject]@{Name=$source+' link containers';'GPO ID'=$null;Target=$source;Operation='Link container source';Status=$status;'Record count'=$retained;'Duration ms'=$watch.ElapsedMilliseconds;'Error ID'=$id;Message=$message;'Collected at'=[datetimeoffset]::Now.ToString('o')})
 }
 foreach($entry in @(@('containers',$containerRows),@('links',$linkRows))){Emit $entry[0] $(if($sourceFailures){'Partial'}else{'Succeeded'}) $entry[1].ToArray() $(if($sourceFailures){'One or more container sources failed; successful observations retained.'}else{'Declared container sources collected.'})}
 foreach($category in @('wmiFilters','wmiReferences')){
  $watch=[diagnostics.stopwatch]::StartNew();$rows=@();$status='Succeeded';$message='Collected';$id=''
  try{
   if($category -eq 'wmiFilters'){
    $rows=@(Get-ADObject -LDAPFilter '(objectClass=msWMI-Som)' -SearchBase $domainDN -SearchScope Subtree -Properties msWMI-ID,msWMI-Name,msWMI-Author,msWMI-Parm1,msWMI-Parm2 -Server $server -ErrorAction Stop|ForEach-Object{
     if(-not $_.DistinguishedName.EndsWith(','+$domainDN,[StringComparison]::OrdinalIgnoreCase)){throw 'WMI filter scope mismatch.'}
     [pscustomobject]@{Name=V $_ 'msWMI-Name';'Filter ID'=([string](V $_ 'msWMI-ID')).Trim('{}').ToLowerInvariant();Author=V $_ 'msWMI-Author';Description=V $_ 'msWMI-Parm1';'Query definition raw'=V $_ 'msWMI-Parm2';DN=$_.DistinguishedName}
    })
   }else{
    $rows=@(Get-ADObject -LDAPFilter '(objectClass=groupPolicyContainer)' -SearchBase ('CN=Policies,CN=System,'+$domainDN) -SearchScope OneLevel -Properties displayName,gPCWQLFilter -Server $server -ErrorAction Stop|ForEach-Object{
     if(-not $_.DistinguishedName.EndsWith(',CN=Policies,CN=System,'+$domainDN,[StringComparison]::OrdinalIgnoreCase)){throw 'GPC scope mismatch.'}
     $ref=[string](V $_ 'gPCWQLFilter');$filterId=$null;$filterDomain=$null;$m=[regex]::Match($ref,'^\[(?<domain>[^;]+);\{(?<id>[0-9a-f-]{36})\};\d+\]$','IgnoreCase')
     if($m.Success){$filterId=([guid]$m.Groups['id'].Value).ToString();$filterDomain=$m.Groups['domain'].Value}
     [pscustomobject]@{Name=V $_ 'displayName';'GPO ID'=([guid]$_.Name.Trim('{}')).ToString();'Filter reference raw'=if($ref){$ref}else{$null};'Filter ID'=$filterId;'Filter domain'=$filterDomain}
    })
   }
  }catch{$status='Failed';$rows=@();$message=$_.Exception.Message;$id=$_.FullyQualifiedErrorId}
  $watch.Stop();Emit $category $status $rows $message $id $watch.ElapsedMilliseconds
 }
 foreach($category in @('permissions','settings')){
  if($null -ne $gpoError){Emit $category 'NotAttempted' @() 'GPO enumeration failed.';continue}
  $rows=New-Object collections.ArrayList;$failures=0
  foreach($g in $gpos){
   if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage=('Reading GPO '+$category);Target=$g.DisplayName}}
   $guid=([guid]$g.Id).ToString();$status='Succeeded';$message='Collected';$id='';$count=0;$watch=[diagnostics.stopwatch]::StartNew()
   try{
    $records=if($category -eq 'permissions'){
     @(Get-GPPermission -Guid $guid -All -Domain $Domain -Server $server -ErrorAction Stop|ForEach-Object{
      $t=V $_ 'Trustee';$sid=V $t 'Sid';$sidText=if($null -ne (V $sid 'Value')){[string]$sid.Value}elseif($null -ne $sid){[string]$sid}else{$null}
      [pscustomobject]@{Name=$g.DisplayName;'GPO ID'=$guid;Trustee=V $t 'Name';'Trustee domain'=V $t 'Domain';'Trustee SID'=$sidText;'Trustee type'=V $_ 'TrusteeType';Permission=[string]$_.Permission;Inherited=V $_ 'Inherited'}
     })
    }else{@(ConvertFrom-PSIGpoXml (Get-GPOReport -Guid $guid -Domain $Domain -Server $server -ReportType Xml -ErrorAction Stop) $guid $g.DisplayName)}
    foreach($row in $records){[void]$rows.Add($row)};$count=@($records).Count
   }catch{$status='Failed';$message=$_.Exception.Message;$id=$_.FullyQualifiedErrorId;$failures++}
   $watch.Stop();[void]$ledger.Add([pscustomobject]@{Name=$g.DisplayName;'GPO ID'=$guid;Target=$guid;Operation=$category;Status=$status;'Record count'=$count;'Duration ms'=$watch.ElapsedMilliseconds;'Error ID'=$id;Message=$message;'Collected at'=[datetimeoffset]::Now.ToString('o')})
  }
  Emit $category $(if($failures){'Partial'}else{'Succeeded'}) $rows.ToArray() $(if($failures){"$failures GPO queries failed; successful results retained."}else{'All enumerated GPO queries completed.'})
 }
 Emit 'objectQueries' 'Succeeded' $ledger.ToArray() 'Ledger captured; inspect each outcome.'
}
function Invoke-PSIGpoCollection([string]$Domain,[int]$TimeoutSeconds,[scriptblock]$Worker,[string]$HelperText){
 $job=$null;$context=$null;$envelopes=New-Object collections.ArrayList;$seen=@{};$failure='';$timedOut=$false;$watch=[diagnostics.stopwatch]::StartNew()
 try{
  $showActivity=$false;if(Get-Command Get-PSIInventoryDisplayState -ErrorAction SilentlyContinue){$displayState=Get-PSIInventoryDisplayState;$showActivity=($null -ne $displayState -and -not $displayState.Quiet)}
  $job=Start-Job -ScriptBlock $Worker -ArgumentList $Domain,$HelperText,$showActivity -ErrorAction Stop
  do{
   $errors=@();$batch=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable errors)
   foreach($e in $batch){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
   if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $batch -Total 9}
   if($errors.Count){$failure=($errors|ForEach-Object{$_.Exception.Message}) -join '; '}
   if($job.State -in @('Completed','Failed','Stopped')){
    $lastErrors=@();$last=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable lastErrors)
    foreach($e in $last){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
    if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $last -Total 9}
    if($lastErrors.Count){$failure=($lastErrors|ForEach-Object{$_.Exception.Message}) -join '; '}
    break
   }
   if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;Stop-Job $job -ErrorAction SilentlyContinue;continue}
   Start-Sleep -Milliseconds 200
  }while($true)
  if($null -eq $context){throw ('Domain collection did not establish scope. '+$failure)}
  if($context.Domain -ine $Domain){throw 'Returned context differs from requested domain.'}
  foreach($key in (Get-PSIGpoSchema).Keys){if($key -ne 'collection' -and -not $seen.ContainsKey($key)){[void]$envelopes.Add([pscustomobject]@{Kind='Section';Key=$key;Status=if($timedOut){'TimedOut'}else{'Failed'};Records=@();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId='GroupPolicy.Incomplete';ErrorMessage=if($timedOut){'Domain worker exceeded its overall time budget.'}elseif($failure){$failure}else{'Worker did not return this category.'}})}}
  [pscustomobject]@{Context=$context;Envelopes=$envelopes.ToArray()}
 }finally{if($null -ne $job){if($job.State -notin @('Completed','Failed','Stopped')){Stop-Job $job -ErrorAction SilentlyContinue};Remove-Job $job -Force -ErrorAction SilentlyContinue}}
}
