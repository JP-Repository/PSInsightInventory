$script:PSIGroupCollector={
 param([string]$Domain,[string]$HelperText,[bool]$ShowProgress=$false)
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2.0;. ([scriptblock]::Create($HelperText))
 function DateText($v){if($null -ne $v){return ([datetimeoffset]$v).ToString('o')};return $null}
 Import-Module ActiveDirectory -ErrorAction Stop
 $root=Get-ADRootDSE -Server $Domain -ErrorAction Stop;$server=[string]$root.dnsHostName
 if(-not $server){throw 'No pinned DC returned.'}
 $domainInfo=Get-ADDomain -Server $server -ErrorAction Stop
 if($domainInfo.DNSRoot -ine $Domain){throw 'Discovered DC is outside the requested domain.'}
 $domainDN=[string]$domainInfo.DistinguishedName
 [pscustomobject]@{Kind='Context';Domain=$Domain;Server=$server;DomainDN=$domainDN;Forest=[string]$domainInfo.Forest;ConfigurationNC=[string]$root.configurationNamingContext}
 $watch=[diagnostics.stopwatch]::StartNew();$catalog=New-Object collections.ArrayList;$errorRecord=$null;$groupByDN=@{};$ids=@{}
 try{
  Get-ADGroup -Filter * -SearchBase $domainDN -SearchScope Subtree -Properties description,managedBy,whenCreated,whenChanged -Server $server -ErrorAction Stop|ForEach-Object{
   $id=([guid]$_.ObjectGUID).ToString();$dn=[string]$_.DistinguishedName
   if((Get-PSIGroupDomainDN $dn) -ine $domainDN -or $ids.ContainsKey($id) -or $groupByDN.ContainsKey($dn)){throw 'Duplicate/out-of-domain group.'}
   $row=[pscustomobject]@{Id=$id;Name=$_.Name;DN=$dn;Sam=Get-PSIGroupValue $_ 'SamAccountName';Sid=[string]$_.SID;Scope=[string]$_.GroupScope;Category=[string]$_.GroupCategory;Description=Get-PSIGroupValue $_ 'description';ManagedBy=Get-PSIGroupValue $_ 'managedBy';Created=DateText (Get-PSIGroupValue $_ 'whenCreated');Changed=DateText (Get-PSIGroupValue $_ 'whenChanged')}
   [void]$catalog.Add($row);$groupByDN[$dn]=$row;$ids[$id]=$true
  }
 }catch{$errorRecord=$_;$catalog.Clear()}
 $watch.Stop()
 [pscustomobject]@{Kind='Section';Key='groups';Status=if($null -ne $errorRecord){'Failed'}else{'Succeeded'};Records=$catalog.ToArray();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId=if($null -ne $errorRecord){$errorRecord.FullyQualifiedErrorId}else{''};ErrorMessage=if($null -ne $errorRecord){$errorRecord.Exception.Message}else{'Selected-domain group metadata collected.'}}
 if($null -ne $errorRecord){return}
 if(-not $catalog.Count){return}
 if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage='Reading initial LDAP member ranges';Target=$server}}
 $ranges=@{}
 $rangeError=$null
 try{$ranges=Get-PSIGroupFirstRanges $server $domainDN}catch{$rangeError=$_.Exception.Message}
 # Resolve the selected-domain object catalog once. The previous implementation
 # performed one Get-ADObject call per unique member and exhausted its overall
 # budget in large domains.
 $cache=@{}
 foreach($g in $catalog){$cache[$g.DN]=[pscustomobject]@{DN=$g.DN;Name=$g.Name;Id=$g.Id;Sid=$g.Sid;Type='group';Resolution='Succeeded';Message='Resolved from selected-domain group catalog.'}}
 if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage='Indexing directory member identities';Target=$server}}
 $catalogComplete=$false;$catalogError=$null
 try{
  Get-ADObject -LDAPFilter '(|(objectClass=user)(objectClass=group)(objectClass=foreignSecurityPrincipal))' -SearchBase $domainDN -SearchScope Subtree -Properties objectSid -Server $server -ErrorAction Stop|ForEach-Object{
   $dn=[string]$_.DistinguishedName
   if($dn -and (Get-PSIGroupDomainDN $dn) -ieq $domainDN -and -not $cache.ContainsKey($dn)){$cache[$dn]=[pscustomobject]@{DN=$dn;Name=$_.Name;Id=([guid]$_.ObjectGUID).ToString();Sid=if($null -ne (Get-PSIGroupValue $_ 'objectSid')){[string]$_.objectSid}else{$null};Type=[string]$_.ObjectClass;Resolution='Succeeded';Message='Resolved from one pinned selected-domain catalog scan.'}}
  }
  $catalogComplete=$true
 }catch{$catalogError=$_.Exception.Message}
 foreach($g in $catalog){
  if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage='Reading group membership';Target=$g.Name}}
  $watch=[diagnostics.stopwatch]::StartNew();$rows=New-Object collections.ArrayList;$lookups=New-Object collections.ArrayList;$status='Succeeded';$errorId='';$message='Direct member attribute references captured; primary-group membership is excluded.'
  try{
   $members=@(Get-PSIGroupMemberDNs $server $g.DN $ranges[$g.DN])
   if($rangeError){$message+=' Used a per-group range read because the bulk LDAP query was unavailable.'}
   foreach($memberDN in $members){
    if(-not $cache.ContainsKey($memberDN)){
     $resolved=[pscustomobject]@{DN=$memberDN;Name=$null;Id=$null;Sid=$null;Type='Unknown';Resolution='NotAttempted';Message='Reference outside selected naming context; not dereferenced.'}
     if((Get-PSIGroupDomainDN $memberDN) -ieq $domainDN){
      $resolved.Resolution='Failed'
      $resolved.Message=if($catalogComplete){'Local reference absent from the returned identity catalog.'}else{'Identity catalog incomplete: '+$catalogError}
     }
     $cache[$memberDN]=$resolved
    }
    $resolved=$cache[$memberDN];[void]$rows.Add($resolved)
    if($resolved.Resolution -ne 'Succeeded'){[void]$lookups.Add([pscustomobject]@{Target=$memberDN;Status=$resolved.Resolution;Message=$resolved.Message})}
   }
  }catch{$status='Failed';$rows.Clear();$lookups.Clear();$message=$_.Exception.Message;$errorId=$_.FullyQualifiedErrorId}
  $watch.Stop()
  [pscustomobject]@{Kind='Section';Key='members:'+$g.Id;Status=$status;Records=$rows.ToArray();Lookups=$lookups.ToArray();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId=$errorId;ErrorMessage=$message}
 }
}

function Invoke-PSIGroupCollection([string]$Domain,[int]$TimeoutSeconds,[scriptblock]$Worker,[string]$HelperText){
 $job=$null;$context=$null;$envelopes=New-Object collections.ArrayList;$seen=@{};$failure='';$timedOut=$false;$watch=[diagnostics.stopwatch]::StartNew()
 try{
  $showActivity=$false;if(Get-Command Get-PSIInventoryDisplayState -ErrorAction SilentlyContinue){$displayState=Get-PSIInventoryDisplayState;$showActivity=($null -ne $displayState -and -not $displayState.Quiet)}
  $job=Start-Job -ScriptBlock $Worker -ArgumentList $Domain,$HelperText,$showActivity -ErrorAction Stop
  do{
   $errors=@();$batch=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable errors)
   foreach($e in $batch){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
   if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $batch -Total -1}
   if($errors.Count){$failure=($errors|ForEach-Object{$_.Exception.Message}) -join '; '}
   if($job.State -in @('Completed','Failed','Stopped')){
    $lastErrors=@();$last=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable lastErrors)
    foreach($e in $last){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
    if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $last -Total -1}
    if($lastErrors.Count){$failure=($lastErrors|ForEach-Object{$_.Exception.Message}) -join '; '}
    break
   }
   if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;Stop-Job $job -ErrorAction SilentlyContinue;continue}
   Start-Sleep -Milliseconds 200
  }while($true)
  if($null -eq $context){throw ('Domain collection did not establish scope. '+$failure)}
  if($context.Domain -ine $Domain){throw 'Returned context differs from requested domain.'}
  foreach($key in (Get-PSIGroupQuerySchema).Keys){if($key -ne 'collection' -and -not $seen.ContainsKey($key)){[void]$envelopes.Add([pscustomobject]@{Kind='Section';Key=$key;Status=if($timedOut){'TimedOut'}else{'Failed'};Records=@();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId='Groups.Incomplete';ErrorMessage=if($timedOut){'Domain worker exceeded its overall time budget.'}elseif($failure){$failure}else{'Worker did not return this category.'}})}}
  [pscustomobject]@{Context=$context;Envelopes=$envelopes.ToArray();TimedOut=$timedOut}
 }finally{if($null -ne $job){if($job.State -notin @('Completed','Failed','Stopped')){Stop-Job $job -ErrorAction SilentlyContinue};Remove-Job $job -Force -ErrorAction SilentlyContinue}}
}
