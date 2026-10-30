function Get-PSIUserSchema {
 [ordered]@{
  users=@('Users',@('Name','User ID','SAM account name','UPN','Email','Enabled','Department','Title','Company','Manager DN','Location DN','DN','Created','Changed','Password last set','Account expires','Last logon timestamp (replicated)','Direct group links observed'))
  flags=@('Reported account flags',@('Name','User ID','Password never expires','Password not required','Cannot change password','Smartcard required','Account not delegated','Trusted for delegation','Trusted to authenticate for delegation'))
  memberships=@('Reported direct group links',@('Name','User ID','User','Group DN'))
  primaryGroups=@('Primary group references',@('Name','User ID','User SID','Primary group RID','Derived primary group SID'))
  departments=@('Departments',@('Name','Department','Users observed'))
  companies=@('Companies',@('Name','Company','Users observed'))
  locations=@('Directory locations',@('Name','Location DN','Users observed'))
  statuses=@('Enabled status',@('Name','Enabled','Users observed'))
  collection=@('Collection coverage',@('Name','Status','Record count','Method','Collected at','Duration ms','Error ID','Message'))
 }
}
function Get-PSIUserQuerySchema {[ordered]@{users=@('Directory users');collection=@('Collection coverage')}}
function Get-PSIUserValue($o,[string]$p){if($null -ne $o -and $null -ne $o.PSObject.Properties[$p]){return $o.$p};return $null}
function Get-PSIUserParentDN([string]$DN){$escaped=$false;for($i=0;$i -lt $DN.Length;$i++){if($escaped){$escaped=$false;continue};if($DN[$i] -eq '\'){$escaped=$true;continue};if($DN[$i] -eq ','){return $DN.Substring($i+1)}};return $null}
function Get-PSIUserDomainDN([string]$DN){$part=$DN;while($part -and $part -notmatch '^(?i)DC='){$part=Get-PSIUserParentDN $part};return $part}
function ConvertTo-PSIUserModel($Context,[object[]]$Envelopes){
 if($Envelopes.Count -ne 1 -or $Envelopes[0].Key -ne 'users' -or $Envelopes[0].Status -notin @('Succeeded','Failed','TimedOut')){throw 'Expected one valid user query outcome.'}
 $e=$Envelopes[0];$schema=Get-PSIUserSchema;$data=[ordered]@{};$coverage=[ordered]@{};$seen=@{};$summaries=@{}
 foreach($k in $schema.Keys){$data[$k]=New-Object collections.ArrayList;$coverage[$k]=$e.Status -eq 'Succeeded'}
 foreach($k in @('departments','companies','locations','statuses')){$summaries[$k]=New-Object 'System.Collections.Generic.Dictionary[string,object]' -ArgumentList ([StringComparer]::Ordinal)}
 if($e.Status -eq 'Succeeded'){
  foreach($source in @($e.Records)){
   $id=([guid]$source.Id).ToString();if($seen.ContainsKey($id) -or (Get-PSIUserDomainDN $source.DN) -ine $Context.DomainDN){throw 'Duplicate/out-of-domain user record.'};$seen[$id]=$true
   $location=Get-PSIUserParentDN $source.DN;$groups=@($source.MemberOf|Where-Object{$_}|Sort-Object -Unique)
   [void]$data.users.Add([pscustomobject]@{Name=$source.Name;'User ID'=$id;'SAM account name'=$source.Sam;UPN=$source.Upn;Email=$source.Email;Enabled=$source.Enabled;Department=$source.Department;Title=$source.Title;Company=$source.Company;'Manager DN'=$source.Manager;'Location DN'=$location;DN=$source.DN;Created=$source.Created;Changed=$source.Changed;'Password last set'=$source.PasswordLastSet;'Account expires'=$source.Expires;'Last logon timestamp (replicated)'=$source.LastLogonTimestamp;'Direct group links observed'=$groups.Count})
   [void]$data.flags.Add([pscustomobject]@{Name=$source.Name;'User ID'=$id;'Password never expires'=$source.PasswordNeverExpires;'Password not required'=$source.PasswordNotRequired;'Cannot change password'=$source.CannotChangePassword;'Smartcard required'=$source.SmartcardRequired;'Account not delegated'=$source.AccountNotDelegated;'Trusted for delegation'=$source.TrustedForDelegation;'Trusted to authenticate for delegation'=$source.TrustedToAuthForDelegation})
   foreach($group in $groups){[void]$data.memberships.Add([pscustomobject]@{Name=$source.Name+' / '+$group;'User ID'=$id;User=$source.Name;'Group DN'=$group})}
   $primarySid=$null
   if($null -ne $source.PrimaryGroup -and [string]$source.Sid -match '^S-1-5-21-\d+-\d+-\d+-\d+$'){$primarySid=([string]$source.Sid -replace '-\d+$','')+'-'+[string]$source.PrimaryGroup}
   [void]$data.primaryGroups.Add([pscustomobject]@{Name=$source.Name;'User ID'=$id;'User SID'=$source.Sid;'Primary group RID'=$source.PrimaryGroup;'Derived primary group SID'=$primarySid})
   foreach($dimension in @(@('departments','Department',$source.Department),@('companies','Company',$source.Company),@('locations','Location DN',$location),@('statuses','Enabled',$source.Enabled))){
    $k=$dimension[0];$field=$dimension[1];$value=$dimension[2];$key=ConvertTo-Json -InputObject $value -Compress
    if(-not $summaries[$k].ContainsKey($key)){$row=[ordered]@{Name=if($null -eq $value){'Unknown / not returned'}elseif($value -is [string] -and $value.Length -eq 0){'Empty reported value'}else{[string]$value}};$row[$field]=$value;$row['Users observed']=0;$summaries[$k][$key]=[pscustomobject]$row}
    $summaries[$k][$key].'Users observed'++
   }
  }
 }
 foreach($k in $summaries.Keys){foreach($row in @($summaries[$k].Values|Sort-Object Name)){[void]$data[$k].Add($row)}}
 [void]$data.collection.Add([pscustomobject]@{Name='Domain user enumeration';Status=$e.Status;'Record count'=$data.users.Count;Method='ADWS / pinned domain DC';'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=$e.ErrorMessage});$coverage.collection=$true
 $arrays=[ordered]@{};foreach($k in $schema.Keys){$arrays[$k]=@($data[$k].ToArray())};[pscustomobject]@{Schema=$schema;Data=$arrays;Coverage=$coverage;Raw=[ordered]@{}}
}
