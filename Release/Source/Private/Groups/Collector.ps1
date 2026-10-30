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
 $cache=@{}
 foreach($g in $catalog){
  if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage='Reading group membership';Target=$g.Name}}
  $watch=[diagnostics.stopwatch]::StartNew();$rows=New-Object collections.ArrayList;$lookups=New-Object collections.ArrayList;$status='Succeeded';$errorId='';$message='Direct member attribute references captured; primary-group membership is excluded.'
  try{
   $members=@(Get-PSIGroupMemberDNs $server $g.DN)
   foreach($memberDN in $members){
    if(-not $cache.ContainsKey($memberDN)){
     $resolved=[pscustomobject]@{DN=$memberDN;Name=$null;Id=$null;Sid=$null;Type='Unknown';Resolution='NotAttempted';Message='Reference outside selected naming context; not dereferenced.'}
     if($groupByDN.ContainsKey($memberDN)){$known=$groupByDN[$memberDN];$resolved.Name=$known.Name;$resolved.Id=$known.Id;$resolved.Sid=$known.Sid;$resolved.Type='group';$resolved.Resolution='Succeeded';$resolved.Message='Resolved from selected-domain group catalog.'}
     elseif((Get-PSIGroupDomainDN $memberDN) -ieq $domainDN){
      try{$o=Get-ADObject -Identity $memberDN -Properties objectSid -Server $server -ErrorAction Stop
       if([string]$o.DistinguishedName -ine $memberDN){throw 'Member lookup returned a different DN.'}
       $resolved.Name=$o.Name;$resolved.Id=([guid]$o.ObjectGUID).ToString();$resolved.Sid=if($null -ne (Get-PSIGroupValue $o 'objectSid')){[string]$o.objectSid}else{$null};$resolved.Type=[string]$o.ObjectClass;$resolved.Resolution='Succeeded';$resolved.Message='Resolved through pinned selected-domain DC.'
      }catch{$resolved.Resolution='Failed';$resolved.Message=$_.Exception.Message}
     }
     $cache[$memberDN]=$resolved
    }
    $resolved=$cache[$memberDN];[void]$rows.Add($resolved);[void]$lookups.Add([pscustomobject]@{Target=$memberDN;Status=$resolved.Resolution;Message=$resolved.Message})
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
