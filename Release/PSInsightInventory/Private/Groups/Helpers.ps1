function Get-PSIGroupSchema {
 [ordered]@{
  groups=@('Groups',@('Name','Group ID','SAM account name','SID','Scope','Category','Description','Managed by','Location DN','DN','Created','Changed','Direct linked members','Membership status'))
  members=@('Direct linked members',@('Name','Group ID','Group','Member DN','Member name','Member ID','Member SID','Member type','Resolution status'))
  nested=@('Nested group links',@('Name','Parent group ID','Parent group','Child group ID','Child group','Child DN'))
  parents=@('Parent group links',@('Name','Group ID','Group','Parent group ID','Parent group','Parent DN'))
  objectQueries=@('Member resolution',@('Name','Target','Status','Message'))
  collection=@('Collection coverage',@('Name','Target','Status','Record count','Collected at','Duration ms','Error ID','Message'))
 }
}
function Get-PSIGroupQuerySchema {[ordered]@{groups=@('Groups');collection=@('Collection coverage')}}
function Get-PSIGroupValue($o,[string]$p){if($null -ne $o -and $null -ne $o.PSObject.Properties[$p]){return $o.$p};return $null}
function Get-PSIGroupParentDN([string]$DN){$escaped=$false;for($i=0;$i -lt $DN.Length;$i++){if($escaped){$escaped=$false;continue};if($DN[$i] -eq '\'){$escaped=$true;continue};if($DN[$i] -eq ','){return $DN.Substring($i+1)}};return $null}
function Get-PSIGroupDomainDN([string]$DN){$part=$DN;while($part -and $part -notmatch '^(?i)DC='){$part=Get-PSIGroupParentDN $part};return $part}
function Read-PSIGroupRange([string]$Server,[string]$DN,[int]$Start){
 $entry=$null;$search=$null
 try{
  $entry=New-Object DirectoryServices.DirectoryEntry(('LDAP://'+$Server+'/'+$DN.Replace('/','\/')))
  $search=New-Object DirectoryServices.DirectorySearcher($entry)
  $search.ReferralChasing=[DirectoryServices.ReferralChasingOption]::None;$search.SearchScope=[DirectoryServices.SearchScope]::Base;$search.Filter='(objectClass=group)'
  $null=$search.PropertiesToLoad.Add(('member;range='+$Start+'-*'))
  $result=$search.FindOne();if($null -eq $result){throw 'Group base search returned no object.'}
  $ranged=@($result.Properties.PropertyNames|Where-Object{[string]$_ -like 'member;range=*'})
  $attribute=@();if($ranged.Count){$attribute=@($ranged)}else{$attribute=@($result.Properties.PropertyNames|Where-Object{[string]$_ -eq 'member'})}
  if($attribute.Count -gt 1){throw 'Multiple member ranges returned.'}
  if(-not $attribute.Count){return [pscustomobject]@{Attribute=$null;Values=@()}}
  [pscustomobject]@{Attribute=[string]$attribute[0];Values=@($result.Properties[$attribute[0]]|ForEach-Object{[string]$_})}
 }finally{if($null -ne $search){$search.Dispose()};if($null -ne $entry){$entry.Dispose()}}
}
function Get-PSIGroupMemberDNs([string]$Server,[string]$DN){
 $start=0;$seen=@{};$values=New-Object collections.ArrayList
 do{
  $range=Read-PSIGroupRange $Server $DN $start
  if(-not $range.Attribute){if($start -ne 0){throw 'Missing continuation range.'};break}
  foreach($value in @($range.Values)){if([string]::IsNullOrEmpty($value) -or $seen.ContainsKey([string]$value)){throw 'Empty/duplicate member reference.'};$seen[[string]$value]=$true;[void]$values.Add([string]$value)}
  if($range.Attribute -ieq 'member'){if($start -ne 0){throw 'Unexpected un-ranged continuation.'};break}
  $m=[regex]::Match($range.Attribute,'^member;range=(\d+)-(\d+|\*)$','IgnoreCase')
  if(-not $m.Success -or [int]$m.Groups[1].Value -ne $start){throw 'Unexpected member range.'}
  if($m.Groups[2].Value -eq '*'){break}
  $next=[int]$m.Groups[2].Value+1
  if($next -le $start -or @($range.Values).Count -ne ($next-$start)){throw 'Non-progressing/incomplete member range.'};$start=$next
 }while($true)
 $values.ToArray()
}
function ConvertTo-PSIGroupModel($Context,[object[]]$Envelopes,[string]$MissingStatus=''){
 $schema=Get-PSIGroupSchema;$data=[ordered]@{};$coverage=[ordered]@{};$byKey=@{}
 foreach($k in $schema.Keys){$data[$k]=New-Object collections.ArrayList;$coverage[$k]=$true}
 foreach($e in $Envelopes){if($byKey.ContainsKey([string]$e.Key) -or $e.Status -notin @('Succeeded','Failed','TimedOut')){throw 'Duplicate/invalid group outcome.'};$byKey[[string]$e.Key]=$e}
 if(-not $byKey.ContainsKey('groups')){throw 'Missing group enumeration outcome.'};$enumeration=$byKey.groups;$groupByDN=@{};$groupIds=@{}
 function Add-Ledger($e,[string]$Name,[string]$Target,[int]$Count){[void]$data.collection.Add([pscustomobject]@{Name=$Name;Target=$Target;Status=$e.Status;'Record count'=$Count;'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=$e.ErrorMessage})}
 if($enumeration.Status -eq 'Succeeded'){
  foreach($g in $enumeration.Records){$id=([guid]$g.Id).ToString();if($groupIds.ContainsKey($id) -or $groupByDN.ContainsKey([string]$g.DN) -or (Get-PSIGroupDomainDN $g.DN) -ine $Context.DomainDN){throw 'Duplicate/out-of-domain group.'};$groupIds[$id]=$true;$groupByDN[[string]$g.DN]=$g
   [void]$data.groups.Add([pscustomobject]@{Name=$g.Name;'Group ID'=$id;'SAM account name'=$g.Sam;SID=$g.Sid;Scope=$g.Scope;Category=$g.Category;Description=$g.Description;'Managed by'=$g.ManagedBy;'Location DN'=Get-PSIGroupParentDN $g.DN;DN=$g.DN;Created=$g.Created;Changed=$g.Changed;'Direct linked members'=$null;'Membership status'='Unknown'})
  }
 }else{foreach($k in @('groups','members','nested','parents','objectQueries')){$coverage[$k]=$false}}
 Add-Ledger $enumeration 'Group enumeration' $Context.Domain $data.groups.Count
 foreach($g in $data.groups){$key='members:'+$g.'Group ID'
  if(-not $byKey.ContainsKey($key)){if($MissingStatus -notin @('Failed','TimedOut')){throw "Missing membership outcome: $key"};$byKey[$key]=[pscustomobject]@{Status=$MissingStatus;Records=@();Lookups=@();CollectedAt=[datetimeoffset]::Now.ToString('o');DurationMs=0;ErrorId='GroupInventory.Incomplete';ErrorMessage='Membership worker did not complete this group.'}}
  $e=$byKey[$key];$g.'Membership status'=$e.Status
  if($e.Status -eq 'Succeeded'){
   $g.'Direct linked members'=@($e.Records).Count;$seenMembers=@{}
   foreach($member in $e.Records){if($seenMembers.ContainsKey([string]$member.DN)){throw 'Duplicate member reference.'};$seenMembers[[string]$member.DN]=$true
    [void]$data.members.Add([pscustomobject]@{Name=$g.Name+' / '+$member.DN;'Group ID'=$g.'Group ID';Group=$g.Name;'Member DN'=$member.DN;'Member name'=$member.Name;'Member ID'=$member.Id;'Member SID'=$member.Sid;'Member type'=$member.Type;'Resolution status'=$member.Resolution})
    if($groupByDN.ContainsKey([string]$member.DN)){$child=$groupByDN[[string]$member.DN];[void]$data.nested.Add([pscustomobject]@{Name=$g.Name+' → '+$child.Name;'Parent group ID'=$g.'Group ID';'Parent group'=$g.Name;'Child group ID'=$child.Id;'Child group'=$child.Name;'Child DN'=$child.DN});[void]$data.parents.Add([pscustomobject]@{Name=$child.Name+' ← '+$g.Name;'Group ID'=$child.Id;Group=$child.Name;'Parent group ID'=$g.'Group ID';'Parent group'=$g.Name;'Parent DN'=$g.DN})}
   }
   foreach($lookup in @($e.Lookups)){[void]$data.objectQueries.Add([pscustomobject]@{Name=$g.Name;Target=$lookup.Target;Status=$lookup.Status;Message=$lookup.Message});if($lookup.Status -eq 'Failed'){$coverage.objectQueries=$false}}
  }else{foreach($k in @('members','nested','parents','objectQueries')){$coverage[$k]=$false}}
  Add-Ledger $e ('Direct members: '+$g.Name) $g.DN $(if($e.Status -eq 'Succeeded'){@($e.Records).Count}else{0})
 }
 foreach($key in $byKey.Keys){if($key -ne 'groups' -and ($key -notlike 'members:*' -or -not $groupIds.ContainsKey($key.Substring(8)))){throw "Unexpected group outcome: $key"}}
 $arrays=[ordered]@{};foreach($k in $schema.Keys){$arrays[$k]=@($data[$k].ToArray())}
 [pscustomobject]@{Schema=$schema;Data=$arrays;Coverage=$coverage;Raw=[ordered]@{}}
}
