$script:PSIUserCollector={
 param([string]$Domain,[string]$HelperText,[bool]$ShowProgress=$false)
 $ErrorActionPreference='Stop';Set-StrictMode -Version 2.0;. ([scriptblock]::Create($HelperText))
 function DateText($v){if($null -ne $v){return ([datetimeoffset]$v).ToString('o')};return $null}
 Import-Module ActiveDirectory -ErrorAction Stop
 $root=Get-ADRootDSE -Server $Domain -ErrorAction Stop;$server=[string]$root.dnsHostName;if(-not $server){throw 'No pinned DC returned.'}
 $domainInfo=Get-ADDomain -Server $server -ErrorAction Stop;if($domainInfo.DNSRoot -ine $Domain){throw 'Discovered DC is outside requested domain.'};$domainDN=[string]$domainInfo.DistinguishedName
 [pscustomobject]@{Kind='Context';Domain=$Domain;Server=$server;DomainDN=$domainDN;Forest=[string]$domainInfo.Forest;ConfigurationNC=[string]$root.configurationNamingContext}
 $watch=[diagnostics.stopwatch]::StartNew();$rows=New-Object collections.ArrayList;$status='Succeeded';$message='Reported user attributes captured; memberOf excludes primary group and is not effective access.';$errorId=''
 try{
  if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage='Reading directory users';Target=$Domain}}
  $properties=@('userPrincipalName','mail','department','title','company','manager','whenCreated','whenChanged','PasswordLastSet','AccountExpirationDate','lastLogonTimestamp','memberOf','primaryGroupID','PasswordNeverExpires','PasswordNotRequired','CannotChangePassword','SmartcardLogonRequired','AccountNotDelegated','TrustedForDelegation','TrustedToAuthForDelegation')
  Get-ADUser -Filter * -SearchBase $domainDN -SearchScope Subtree -Properties $properties -Server $server -ErrorAction Stop|ForEach-Object{
   if((Get-PSIUserDomainDN $_.DistinguishedName) -ine $domainDN){throw 'User outside selected naming context.'}
   $stamp=Get-PSIUserValue $_ 'lastLogonTimestamp';$logon=$null;if($null -ne $stamp -and [long]$stamp -gt 0){$logon=[datetime]::FromFileTimeUtc([long]$stamp).ToString('o')}
   [void]$rows.Add([pscustomobject]@{Id=([guid]$_.ObjectGUID).ToString();Name=$_.Name;DN=$_.DistinguishedName;Sam=Get-PSIUserValue $_ 'SamAccountName';Sid=[string]$_.SID;Upn=Get-PSIUserValue $_ 'UserPrincipalName';Email=Get-PSIUserValue $_ 'mail';Enabled=Get-PSIUserValue $_ 'Enabled';Department=Get-PSIUserValue $_ 'department';Title=Get-PSIUserValue $_ 'title';Company=Get-PSIUserValue $_ 'company';Manager=Get-PSIUserValue $_ 'manager';Created=DateText (Get-PSIUserValue $_ 'whenCreated');Changed=DateText (Get-PSIUserValue $_ 'whenChanged');PasswordLastSet=DateText (Get-PSIUserValue $_ 'PasswordLastSet');Expires=DateText (Get-PSIUserValue $_ 'AccountExpirationDate');LastLogonTimestamp=$logon;MemberOf=@(Get-PSIUserValue $_ 'memberOf');PrimaryGroup=Get-PSIUserValue $_ 'primaryGroupID';PasswordNeverExpires=Get-PSIUserValue $_ 'PasswordNeverExpires';PasswordNotRequired=Get-PSIUserValue $_ 'PasswordNotRequired';CannotChangePassword=Get-PSIUserValue $_ 'CannotChangePassword';SmartcardRequired=Get-PSIUserValue $_ 'SmartcardLogonRequired';AccountNotDelegated=Get-PSIUserValue $_ 'AccountNotDelegated';TrustedForDelegation=Get-PSIUserValue $_ 'TrustedForDelegation';TrustedToAuthForDelegation=Get-PSIUserValue $_ 'TrustedToAuthForDelegation'})
  }
 }catch{$status='Failed';$rows.Clear();$message=$_.Exception.Message;$errorId=$_.FullyQualifiedErrorId}
 $watch.Stop();[pscustomobject]@{Kind='Section';Key='users';Status=$status;Records=$rows.ToArray();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId=$errorId;ErrorMessage=$message}
}

function Invoke-PSIUserCollection([string]$Domain,[int]$TimeoutSeconds,[scriptblock]$Worker,[string]$HelperText){
 $job=$null;$context=$null;$envelopes=New-Object collections.ArrayList;$seen=@{};$failure='';$timedOut=$false;$watch=[diagnostics.stopwatch]::StartNew()
 try{
  $showActivity=$false;if(Get-Command Get-PSIInventoryDisplayState -ErrorAction SilentlyContinue){$displayState=Get-PSIInventoryDisplayState;$showActivity=($null -ne $displayState -and -not $displayState.Quiet)}
  $job=Start-Job -ScriptBlock $Worker -ArgumentList $Domain,$HelperText,$showActivity -ErrorAction Stop
  do{
   $errors=@();$batch=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable errors)
   foreach($e in $batch){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
   if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $batch -Total 1}
   if($errors.Count){$failure=($errors|ForEach-Object{$_.Exception.Message}) -join '; '}
   if($job.State -in @('Completed','Failed','Stopped')){
    $lastErrors=@();$last=@(Receive-Job $job -ErrorAction SilentlyContinue -ErrorVariable lastErrors)
    foreach($e in $last){if($e.Kind -eq 'Progress'){continue};if($e.Kind -eq 'Context'){if($null -ne $context){throw 'Duplicate context.'};$context=$e}elseif($e.Kind -eq 'Section'){if($seen.ContainsKey([string]$e.Key)){throw 'Duplicate category.'};$seen[[string]$e.Key]=$true;[void]$envelopes.Add($e)}else{throw 'Unexpected collection output.'}}
    if(Get-Command Receive-PSIInventoryDisplay -ErrorAction SilentlyContinue){Receive-PSIInventoryDisplay -Items $last -Total 1}
    if($lastErrors.Count){$failure=($lastErrors|ForEach-Object{$_.Exception.Message}) -join '; '}
    break
   }
   if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;Stop-Job $job -ErrorAction SilentlyContinue;continue}
   Start-Sleep -Milliseconds 200
  }while($true)
  if($null -eq $context){throw ('Domain collection did not establish scope. '+$failure)}
  if($context.Domain -ine $Domain){throw 'Returned context differs from requested domain.'}
  foreach($key in (Get-PSIUserQuerySchema).Keys){if($key -ne 'collection' -and -not $seen.ContainsKey($key)){[void]$envelopes.Add([pscustomobject]@{Kind='Section';Key=$key;Status=if($timedOut){'TimedOut'}else{'Failed'};Records=@();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=$watch.ElapsedMilliseconds;ErrorId='Users.Incomplete';ErrorMessage=if($timedOut){'Domain worker exceeded its overall time budget.'}elseif($failure){$failure}else{'Worker did not return this category.'}})}}
  [pscustomobject]@{Context=$context;Envelopes=$envelopes.ToArray()}
 }finally{if($null -ne $job){if($job.State -notin @('Completed','Failed','Stopped')){Stop-Job $job -ErrorAction SilentlyContinue};Remove-Job $job -Force -ErrorAction SilentlyContinue}}
}
