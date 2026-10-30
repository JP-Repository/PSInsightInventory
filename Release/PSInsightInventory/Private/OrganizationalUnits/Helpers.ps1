function Get-PSIOuSchema {
 [ordered]@{
  ous=@('Organizational units',@('Name','OU ID','DN','Parent DN','Canonical path','Description','Managed by','Protected from accidental deletion','Created','Changed'))
  counts=@('Object counts',@('Name','OU ID','DN','Direct users','Descendant users','Direct computers','Descendant computers','Direct groups','Descendant groups','Direct OUs','Descendant OUs','Count status'))
  links=@('Direct GPO links',@('Name','OU ID','OU DN','GPO ID','GPO DN','Link order','Enabled','Enforced','Options raw'))
  inheritance=@('Inheritance configuration',@('Name','OU ID','DN','Block GPO inheritance','GPO options raw','DACL inheritance protected'))
  delegations=@('Delegation ACEs',@('Name','OU ID','OU DN','Trustee SID','Access type','AD rights','Object type GUID','Inherited object type GUID','Inheritance type','Inherited','Inheritance flags','Propagation flags'))
  objectQueries=@('OU collection',@('Name','OU ID','Target','Operation','Status','Record count','Duration ms','Error ID','Message','Collected at'))
  collection=@('Category collection',@('Name','Status','Record count','Method','Collected at','Duration ms','Error ID','Message'))
 }
}
function Get-PSIOuParentDN([string]$DN){
 $escaped=$false
 for($i=0;$i -lt $DN.Length;$i++){if($escaped){$escaped=$false;continue};if($DN[$i] -eq '\'){$escaped=$true;continue};if($DN[$i] -eq ','){return $DN.Substring($i+1)}}
 return $null
}
function Get-PSIOuAcl([string]$Server,[string]$DN){
 $entry=$null
 try{
  $entry=New-Object DirectoryServices.DirectoryEntry(('LDAP://'+$Server+'/'+$DN.Replace('/','\/')))
  $entry.Options.SecurityMasks=[DirectoryServices.SecurityMasks]::Dacl
  $entry.RefreshCache(@('nTSecurityDescriptor'))
  $security=$entry.ObjectSecurity
  if($null -eq $security){throw 'DACL was not returned.'}
  [pscustomobject]@{Protected=$security.AreAccessRulesProtected;Rules=@($security.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))}
 }finally{if($null -ne $entry){$entry.Dispose()}}
}
function ConvertTo-PSIOuModel($Context,[object[]]$Envelopes){
 $schema=Get-PSIOuSchema;$data=[ordered]@{};$coverage=[ordered]@{};$seen=@{}
 foreach($k in $schema.Keys){$data[$k]=@()}
 foreach($e in $Envelopes){
  $k=[string]$e.Key
  if(-not $schema.Contains($k) -or $k -eq 'collection' -or $seen.ContainsKey($k)){throw "Unknown/duplicate OU category: $k"}
  if($e.Status -notin @('Succeeded','Partial','Failed','TimedOut','NotAttempted')){throw "Invalid OU status: $k"}
  $seen[$k]=$true;$coverage[$k]=$e.Status -eq 'Succeeded'
  if($e.Status -in @('Succeeded','Partial')){$data[$k]=@($e.Records|Where-Object{$null -ne $_}|ForEach-Object{$row=[ordered]@{};foreach($c in $schema[$k][1]){$row[$c]=Get-PSISiteValue $_ $c};[pscustomobject]$row})}
  $data.collection+=[pscustomobject]@{Name=$schema[$k][0];Status=$e.Status;'Record count'=$data[$k].Count;Method='Pinned DC / ADWS and LDAP DACL reads';'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=$e.ErrorMessage}
 }
 foreach($k in $schema.Keys){if($k -ne 'collection' -and -not $seen.ContainsKey($k)){throw "Missing OU category: $k"}}
 # An unfinished count category still retains OU identity with unknown counts.
 if(-not $coverage.counts -and $data.counts.Count -eq 0){$data.counts=@($data.ous|ForEach-Object{$row=[ordered]@{};foreach($c in $schema.counts[1]){$row[$c]=$null};$row.Name=$_.Name;$row.'OU ID'=$_.'OU ID';$row.DN=$_.DN;$row.'Count status'='Unavailable';[pscustomobject]$row})}
 $coverage.collection=$true
 [pscustomobject]@{Schema=$schema;Data=$data;Coverage=$coverage;Raw=[ordered]@{}}
}
