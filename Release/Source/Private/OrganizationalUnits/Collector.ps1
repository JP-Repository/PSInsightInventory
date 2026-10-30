$script:PSIOuCollector={
 param([string]$Domain,[string]$HelperText,[bool]$ShowProgress=$false)
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
 . ([scriptblock]::Create($HelperText))
 function V($o,$p){if($null -ne $o -and $null -ne $o.PSObject.Properties[$p]){return $o.$p};return $null}
 function Emit($Key,$Status,[object[]]$Rows,$Message='',$Id='', [long]$Ms=0){[pscustomobject]@{Kind='Section';Key=$Key;Status=$Status;Records=@($Rows);CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$Ms;ErrorId=$Id;ErrorMessage=$Message}}
 Import-Module ActiveDirectory -ErrorAction Stop
 $root=Get-ADRootDSE -Server $Domain -ErrorAction Stop;$server=[string]$root.dnsHostName
 if(-not $server){throw 'Discovery did not return a pinned DC.'}
 $domainInfo=Get-ADDomain -Server $server -ErrorAction Stop
 if($domainInfo.DNSRoot -ine $Domain){throw 'Discovered DC is outside the requested domain.'}
 $domainDN=[string]$domainInfo.DistinguishedName
 [pscustomobject]@{Kind='Context';Domain=$Domain;Server=$server;DomainDN=$domainDN;Forest=[string]$domainInfo.Forest;ConfigurationNC=[string]$root.configurationNamingContext}
 $watch=[diagnostics.stopwatch]::StartNew();$ous=@();$errorRecord=$null
 try{
  $ous=@(Get-ADOrganizationalUnit -Filter * -SearchBase $domainDN -SearchScope Subtree -Properties canonicalName,description,managedBy,ProtectedFromAccidentalDeletion,whenCreated,whenChanged,gPLink,gPOptions -Server $server -ErrorAction Stop)
  $ids=@{};$dns=@{}
  foreach($ou in $ous){$oid=([guid]$ou.ObjectGUID).ToString();$odn=[string]$ou.DistinguishedName;if(-not $odn.EndsWith(','+$domainDN,[StringComparison]::OrdinalIgnoreCase)){throw 'OU scope mismatch.'};if($ids.ContainsKey($oid) -or $dns.ContainsKey($odn)){throw 'Duplicate OU identity.'};$ids[$oid]=$true;$dns[$odn]=$true}
 }catch{$errorRecord=$_;$ous=@()}
 $watch.Stop()
 if($null -ne $errorRecord){Emit 'ous' 'Failed' @() $errorRecord.Exception.Message $errorRecord.FullyQualifiedErrorId $watch.ElapsedMilliseconds;foreach($key in @('counts','links','inheritance','delegations','objectQueries')){Emit $key 'NotAttempted' @() 'OU enumeration failed.'};return}
 Emit 'ous' 'Succeeded' @($ous|ForEach-Object{[pscustomobject]@{Name=$_.Name;'OU ID'=([guid]$_.ObjectGUID).ToString();DN=$_.DistinguishedName;'Parent DN'=Get-PSIOuParentDN $_.DistinguishedName;'Canonical path'=V $_ 'canonicalName';Description=V $_ 'description';'Managed by'=V $_ 'managedBy';'Protected from accidental deletion'=V $_ 'ProtectedFromAccidentalDeletion';Created=if($null -ne (V $_ 'whenCreated')){([datetimeoffset]$_.whenCreated).ToString('o')}else{$null};Changed=if($null -ne (V $_ 'whenChanged')){([datetimeoffset]$_.whenChanged).ToString('o')}else{$null}}}) '' '' $watch.ElapsedMilliseconds
 $ledger=New-Object collections.ArrayList;$countMap=@{}
 foreach($ou in $ous){$row=[ordered]@{Name=$ou.Name;'OU ID'=([guid]$ou.ObjectGUID).ToString();DN=$ou.DistinguishedName;'Count status'='Collected'};foreach($kind in @('users','computers','groups','OUs')){foreach($mode in @('Direct','Descendant')){$row[$mode+' '+$kind]=0}};$countMap[[string]$ou.DistinguishedName]=[pscustomobject]$row}
 $watch=[diagnostics.stopwatch]::StartNew();$countError=$null
 try{
  if($ous.Count){
   Get-ADObject -LDAPFilter '(|(objectCategory=person)(objectClass=computer)(objectClass=group)(objectClass=organizationalUnit))' -SearchBase $domainDN -SearchScope Subtree -Server $server -ErrorAction Stop|ForEach-Object{
    $odn=[string]$_.DistinguishedName;if(-not $odn.EndsWith(','+$domainDN,[StringComparison]::OrdinalIgnoreCase)){throw 'Count scan returned an out-of-domain object.'}
    $kind=switch([string]$_.ObjectClass){'user'{'users'}'computer'{'computers'}'group'{'groups'}'organizationalUnit'{'OUs'}default{$null}}
    if($null -ne $kind){
     $parent=Get-PSIOuParentDN $odn;$direct=$parent
     while($parent -and $parent -ine $domainDN){if($countMap.ContainsKey($parent)){$countMap[$parent].('Descendant '+$kind)++;if($parent -ieq $direct){$countMap[$parent].('Direct '+$kind)++}};$parent=Get-PSIOuParentDN $parent}
    }
   }
  }
 }catch{$countError=$_}
 $watch.Stop()
 if($null -ne $countError){Emit 'counts' 'Failed' @() $countError.Exception.Message $countError.FullyQualifiedErrorId $watch.ElapsedMilliseconds}
 else{Emit 'counts' 'Succeeded' @($ous|ForEach-Object{$countMap[[string]$_.DistinguishedName]}) 'Direct is one level; descendant includes all depths, excluding the OU itself.' '' $watch.ElapsedMilliseconds}
 $linkRows=New-Object collections.ArrayList;$inheritRows=New-Object collections.ArrayList;$aceRows=New-Object collections.ArrayList;$linkFailures=0;$aclFailures=0
 foreach($ou in $ous){
  if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage='Reading OU links and DACL';Target=$ou.Name}}
  $oid=([guid]$ou.ObjectGUID).ToString();$odn=[string]$ou.DistinguishedName
  $gpOptions=V $ou 'gPOptions';$inherit=[pscustomobject]@{Name=$ou.Name;'OU ID'=$oid;DN=$odn;'Block GPO inheritance'=if($null -eq $gpOptions){$null}else{([int]$gpOptions -band 1) -ne 0};'GPO options raw'=$gpOptions;'DACL inheritance protected'=$null}
  foreach($operation in @('GPO links','DACL')){
   $watch=[diagnostics.stopwatch]::StartNew();$status='Succeeded';$message='Collected';$errorId='';$recordCount=0
   try{
    if($operation -eq 'GPO links'){
     $raw=[string](V $ou 'gPLink');$tokens=[regex]::Matches($raw,'\[LDAP://(?<dn>[^\]]+);(?<options>\d+)\]','IgnoreCase')
     if(($tokens|ForEach-Object{$_.Value}) -join '' -ine $raw){throw 'Malformed gpLink; no complete link list was inferred.'}
     $localRows=New-Object collections.ArrayList
     for($i=0;$i -lt $tokens.Count;$i++){
      $gpc=$tokens[$i].Groups['dn'].Value;$options=[int]$tokens[$i].Groups['options'].Value;$match=[regex]::Match($gpc,'(?i)^CN=\{(?<id>[0-9a-f-]{36})\},CN=Policies,CN=System,.+$')
      if(-not $match.Success){throw 'Unrecognized GPO DN reference.'}
      [void]$localRows.Add([pscustomobject]@{Name=$ou.Name;'OU ID'=$oid;'OU DN'=$odn;'GPO ID'=([guid]$match.Groups['id'].Value).ToString();'GPO DN'=$gpc;'Link order'=$tokens.Count-$i;Enabled=($options -band 1) -eq 0;Enforced=($options -band 2) -ne 0;'Options raw'=$options})
     }
     foreach($record in $localRows){[void]$linkRows.Add($record)};$recordCount=$localRows.Count
    }else{
     $acl=Get-PSIOuAcl $server $odn;$localRows=New-Object collections.ArrayList
     foreach($rule in @($acl.Rules)){
      [void]$localRows.Add([pscustomobject]@{Name=$ou.Name;'OU ID'=$oid;'OU DN'=$odn;'Trustee SID'=[string]$rule.IdentityReference;'Access type'=[string]$rule.AccessControlType;'AD rights'=[string]$rule.ActiveDirectoryRights;'Object type GUID'=[string]$rule.ObjectType;'Inherited object type GUID'=[string]$rule.InheritedObjectType;'Inheritance type'=[string]$rule.InheritanceType;Inherited=[bool]$rule.IsInherited;'Inheritance flags'=[string]$rule.InheritanceFlags;'Propagation flags'=[string]$rule.PropagationFlags})
     }
     foreach($record in $localRows){[void]$aceRows.Add($record)};$recordCount=$localRows.Count;$inherit.'DACL inheritance protected'=$acl.Protected
    }
   }catch{$status='Failed';$message=$_.Exception.Message;$errorId=$_.FullyQualifiedErrorId;if($operation -eq 'GPO links'){$linkFailures++}else{$aclFailures++}}
   $watch.Stop();[void]$ledger.Add([pscustomobject]@{Name=$ou.Name;'OU ID'=$oid;Target=$odn;Operation=$operation;Status=$status;'Record count'=$recordCount;'Duration ms'=$watch.ElapsedMilliseconds;'Error ID'=$errorId;Message=$message;'Collected at'=[datetimeoffset]::Now.ToString('o')})
  }
  [void]$inheritRows.Add($inherit)
 }
 Emit 'links' $(if($linkFailures){'Partial'}else{'Succeeded'}) $linkRows.ToArray() 'Per-OU results are recorded in OU collection.'
 Emit 'inheritance' $(if($aclFailures){'Partial'}else{'Succeeded'}) $inheritRows.ToArray() 'GPO block inheritance and DACL protection are separate settings; unavailable DACL flags remain null.'
 Emit 'delegations' $(if($aclFailures){'Partial'}else{'Succeeded'}) $aceRows.ToArray() 'Reported DACL ACEs; not an effective-access calculation.'
 Emit 'objectQueries' 'Succeeded' $ledger.ToArray() 'Outcome ledger captured; inspect each row.'
}

function Invoke-PSIOuCollection([string]$Domain,[int]$TimeoutSeconds,[scriptblock]$Worker,[string]$HelperText){
 $job=$null;$context=$null;$envelopes=New-Object collections.ArrayList;$seen=@{};$failure='';$timedOut=$false;$watch=[diagnostics.stopwatch]::StartNew()
 try{
  $showActivity=$false;if(Get-Command Get-PSIInventoryDisplayState -ErrorAction SilentlyContinue){$displayState=Get-PSIInventoryDisplayState;$showActivity=($null -ne $displayState -and -not $displayState.Quiet)}
  $job=Start-Job -ScriptBlock $Worker -ArgumentList $Domain,$HelperText,$showActivity -ErrorAction Stop
  do{
   $errors=@();$batch=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable errors)
   foreach($e in $batch){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
   if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $batch -Total 6}
   if($errors.Count){$failure=($errors|ForEach-Object{$_.Exception.Message}) -join '; '}
   if($job.State -in @('Completed','Failed','Stopped')){
    $lastErrors=@();$last=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable lastErrors)
    foreach($e in $last){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
    if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $last -Total 6}
    if($lastErrors.Count){$failure=($lastErrors|ForEach-Object{$_.Exception.Message}) -join '; '}
    break
   }
   if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;Stop-Job $job -ErrorAction SilentlyContinue;continue}
   Start-Sleep -Milliseconds 200
  }while($true)
  if($null -eq $context){throw ('Domain collection did not establish scope. '+$failure)}
  if($context.Domain -ine $Domain){throw 'Returned context differs from requested domain.'}
  foreach($key in (Get-PSIOuSchema).Keys){if($key -ne 'collection' -and -not $seen.ContainsKey($key)){[void]$envelopes.Add([pscustomobject]@{Kind='Section';Key=$key;Status=if($timedOut){'TimedOut'}else{'Failed'};Records=@();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId='OrganizationalUnits.Incomplete';ErrorMessage=if($timedOut){'Domain worker exceeded its overall time budget.'}elseif($failure){$failure}else{'Worker did not return this category.'}})}}
  [pscustomobject]@{Context=$context;Envelopes=$envelopes.ToArray()}
 }finally{if($null -ne $job){if($job.State -notin @('Completed','Failed','Stopped')){Stop-Job $job -ErrorAction SilentlyContinue};Remove-Job $job -Force -ErrorAction SilentlyContinue}}
}
