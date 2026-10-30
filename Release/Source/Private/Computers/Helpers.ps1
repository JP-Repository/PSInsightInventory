function Get-PSIComputerSchema {
 [ordered]@{
  computers=@('Computers',@('Name','Computer ID','DNS hostname','Domain','OS reported','OS family','Server release','Version reported','Build reported','Service pack reported','Enabled','DC role reported','Location DN','DN','Managed by','Created','Changed','Password last set','Last logon timestamp (replicated)','User account control raw','Primary group ID'))
  osSummary=@('OS breakdown',@('Name','OS family','OS reported','Server release','Version reported','Build reported','Computers observed'))
  locations=@('Directory locations',@('Name','Location DN','Computers observed'))
  spns=@('Reported SPNs',@('Name','Computer ID','SPN'))
  delegation=@('Delegation attributes',@('Name','Computer ID','Trusted for delegation','Trusted to authenticate for delegation','Account not delegated','Allowed target SPN','RBCD descriptor present'))
  collection=@('Collection coverage',@('Name','Status','Record count','Method','Collected at','Duration ms','Error ID','Message'))
 }
}
function Get-PSIComputerQuerySchema {[ordered]@{computers=@('Directory computers');collection=@('Collection coverage')}}
function Get-PSIComputerValue($Object,[string]$Property){if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Property]){return $Object.$Property};return $null}
function Get-PSIComputerParentDN([string]$DN){$escaped=$false;for($i=0;$i -lt $DN.Length;$i++){if($escaped){$escaped=$false;continue};if($DN[$i] -eq '\'){$escaped=$true;continue};if($DN[$i] -eq ','){return $DN.Substring($i+1)}};return $null}
function Get-PSIComputerOs([string]$OS,[string]$Version){
 $family='Unknown';$release=$null;$build=$null
 if(-not [string]::IsNullOrWhiteSpace($OS)){
  if($OS -match '(?i)\bWindows\s+Server\b'){$family='Windows Server';$m=[regex]::Match($OS,'(?i)\bWindows\s+Server\s+(2000|2003|2008|2012|2016|2019|2022|2025)(?:\s+(R2))?\b');if($m.Success){$release=$m.Groups[1].Value;if($m.Groups[2].Success){$release+=' R2'}}}
  elseif($OS -match '(?i)\bWindows\s+(?:XP|Vista|7|8(?:\.1)?|10|11|Embedded)\b'){$family='Windows client'}else{$family='Other / unclassified'}
 }
 if($Version -match '^\d+\.\d+\s+\((\d+)\)$'){$build=$Matches[1]}elseif($Version -match '^\d+\.\d+\.(\d+)(?:\.\d+)?$'){$build=$Matches[1]}
 [pscustomobject]@{Family=$family;Release=$release;Build=$build}
}
function ConvertTo-PSIComputerModel($Context,[object[]]$Envelopes){
 if($Envelopes.Count -ne 1 -or $Envelopes[0].Key -ne 'computers' -or $Envelopes[0].Status -notin @('Succeeded','Failed','TimedOut')){throw 'Expected one valid computer query outcome.'}
 $e=$Envelopes[0];$schema=Get-PSIComputerSchema;$data=[ordered]@{};$coverage=[ordered]@{}
 foreach($k in $schema.Keys){$data[$k]=New-Object collections.ArrayList;$coverage[$k]=$e.Status -eq 'Succeeded'}
 $seen=@{};$osGroups=New-Object 'System.Collections.Generic.Dictionary[string,object]' -ArgumentList ([StringComparer]::Ordinal);$locationGroups=@{}
 if($e.Status -eq 'Succeeded'){
  foreach($source in @($e.Records)){
   $id=([guid]$source.Id).ToString();$dn=[string]$source.DN
   if($seen.ContainsKey($id) -or -not $dn.EndsWith(','+$Context.DomainDN,[StringComparison]::OrdinalIgnoreCase)){throw 'Duplicate or out-of-domain computer record.'};$seen[$id]=$true
   $os=Get-PSIComputerOs $source.OS $source.Version;$location=Get-PSIComputerParentDN $dn
   $uac=Get-PSIComputerValue $source 'Uac';$primary=Get-PSIComputerValue $source 'PrimaryGroup';$dcRole='Unknown'
   if($null -ne $uac){$dcRole=if(([long]$uac -band 8192) -ne 0 -or $primary -eq 521){'Domain controller'}else{'Other computer'}}
   [void]$data.computers.Add([pscustomobject]@{Name=$source.Name;'Computer ID'=$id;'DNS hostname'=$source.Dns;Domain=$Context.Domain;'OS reported'=$source.OS;'OS family'=$os.Family;'Server release'=$os.Release;'Version reported'=$source.Version;'Build reported'=$os.Build;'Service pack reported'=$source.ServicePack;Enabled=$source.Enabled;'DC role reported'=$dcRole;'Location DN'=$location;DN=$dn;'Managed by'=$source.ManagedBy;Created=$source.Created;Changed=$source.Changed;'Password last set'=$source.PasswordLastSet;'Last logon timestamp (replicated)'=$source.LastLogonTimestamp;'User account control raw'=$uac;'Primary group ID'=$primary})
   foreach($spn in @($source.Spns|Where-Object{$_})){[void]$data.spns.Add([pscustomobject]@{Name=$source.Name;'Computer ID'=$id;SPN=[string]$spn})}
   $targets=@($source.AllowedTargets|Where-Object{$_});if(-not $targets.Count){$targets=@($null)}
   foreach($target in $targets){[void]$data.delegation.Add([pscustomobject]@{Name=$source.Name;'Computer ID'=$id;'Trusted for delegation'=$source.TrustedForDelegation;'Trusted to authenticate for delegation'=$source.TrustedToAuthForDelegation;'Account not delegated'=$source.AccountNotDelegated;'Allowed target SPN'=$target;'RBCD descriptor present'=$source.RbcdPresent})}
   $key=@($os.Family,$source.OS,$os.Release,$source.Version,$os.Build)|ConvertTo-Json -Compress
   if(-not $osGroups.ContainsKey($key)){$osGroups[$key]=[pscustomobject]@{Name=if($source.OS){$source.OS}else{'Unknown OS'};'OS family'=$os.Family;'OS reported'=$source.OS;'Server release'=$os.Release;'Version reported'=$source.Version;'Build reported'=$os.Build;'Computers observed'=0}}
   $osGroups[$key].'Computers observed'++
   if(-not $locationGroups.ContainsKey($location)){$locationGroups[$location]=[pscustomobject]@{Name=$location;'Location DN'=$location;'Computers observed'=0}};$locationGroups[$location].'Computers observed'++
  }
 }
 foreach($row in @($osGroups.Values|Sort-Object Name,'Version reported')){[void]$data.osSummary.Add($row)}
 foreach($row in @($locationGroups.Values|Sort-Object Name)){[void]$data.locations.Add($row)}
 [void]$data.collection.Add([pscustomobject]@{Name='Domain computer enumeration';Status=$e.Status;'Record count'=$data.computers.Count;Method='ADWS / pinned domain DC';'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=$e.ErrorMessage})
 $coverage.collection=$true;$arrays=[ordered]@{};foreach($k in $schema.Keys){$arrays[$k]=@($data[$k].ToArray())}
 [pscustomobject]@{Schema=$schema;Data=$arrays;Coverage=$coverage;Raw=[ordered]@{}}
}
