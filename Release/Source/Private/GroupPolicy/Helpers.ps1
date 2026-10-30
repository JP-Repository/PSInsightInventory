function Get-PSIGpoSchema {
 [ordered]@{
  gpos=@('Group Policy Objects',@('Name','GPO ID','Domain','Owner','Status','Created','Changed','Description'))
  versions=@('Configuration versions',@('Name','GPO ID','User AD version','User SYSVOL version','Computer AD version','Computer SYSVOL version'))
  containers=@('Link containers',@('Name','Type','DN','Block inheritance','Options raw','Link entries observed','Selected-domain links'))
  links=@('GPO links',@('Name','GPO ID','Container','Container type','Container DN','GPO DN','Link order','Enabled','Enforced','Options raw'))
  permissions=@('Reported GPO permissions',@('Name','GPO ID','Trustee','Trustee domain','Trustee SID','Trustee type','Permission','Inherited'))
  wmiFilters=@('Domain WMI filters',@('Name','Filter ID','Author','Description','Query definition raw','DN'))
  wmiReferences=@('GPO WMI references',@('Name','GPO ID','Filter reference raw','Filter ID','Filter domain'))
  settings=@('Settings structure',@('Name','GPO ID','Side','Extension','Setting types','Top-level setting nodes'))
  objectQueries=@('Object collection',@('Name','GPO ID','Target','Operation','Status','Record count','Duration ms','Error ID','Message','Collected at'))
  collection=@('Category collection',@('Name','Status','Record count','Method','Collected at','Duration ms','Error ID','Message'))
 }
}
function ConvertFrom-PSIGpoLinks([string]$Value,[string]$Container,[string]$Type,[string]$DN,[string]$DomainDN){
 if([string]::IsNullOrEmpty($Value)){return}
 $tokens=[regex]::Matches($Value,'\[LDAP://(?<dn>[^\]]+);(?<options>\d+)\]','IgnoreCase')
 if(($tokens|ForEach-Object{$_.Value}) -join '' -ine $Value){throw 'Malformed gpLink value; link order cannot be determined.'}
 for($i=0;$i -lt $tokens.Count;$i++){
  $gpc=$tokens[$i].Groups['dn'].Value;$bits=[int]$tokens[$i].Groups['options'].Value
  $idMatch=[regex]::Match($gpc,('(?i)^CN=\{(?<id>[0-9a-f-]{36})\},CN=Policies,CN=System,'+[regex]::Escape($DomainDN)+'$'))
  if(-not $idMatch.Success){continue}
  $id=([guid]$idMatch.Groups['id'].Value).ToString()
  [pscustomobject]@{Name=$Container+' / '+$id;'GPO ID'=$id;Container=$Container;'Container type'=$Type;'Container DN'=$DN;'GPO DN'=$gpc;'Link order'=$tokens.Count-$i;Enabled=($bits -band 1) -eq 0;Enforced=($bits -band 2) -ne 0;'Options raw'=$bits}
 }
}
function ConvertFrom-PSIGpoXml([string]$Xml,[string]$Id,[string]$Name){
 $settings=New-Object xml.XmlReaderSettings;$settings.DtdProcessing=[xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
 $stringReader=New-Object IO.StringReader($Xml);$reader=$null
 try{
  $reader=[xml.XmlReader]::Create($stringReader,$settings);$doc=New-Object xml.XmlDocument;$doc.XmlResolver=$null;$doc.Load($reader)
  $root=$doc.DocumentElement
  if($root.LocalName -ne 'GPO'){throw 'Expected a GPO XML report.'}
  $identifier=$root.SelectSingleNode("*[local-name()='Identifier']/*[local-name()='Identifier']")
  if($null -eq $identifier -or ([guid]$identifier.InnerText).ToString() -ne ([guid]$Id).ToString()){throw 'Report GUID does not match the requested GPO.'}
  foreach($side in @('User','Computer')){
   foreach($ext in $root.SelectNodes("*[local-name()='$side']/*[local-name()='ExtensionData']")){
    $label=$ext.SelectSingleNode("*[local-name()='Name']");$extension=$ext.SelectSingleNode("*[local-name()='Extension']")
    $nodes=@();if($null -ne $extension){$nodes=@($extension.ChildNodes|Where-Object{$_.NodeType -eq [xml.XmlNodeType]::Element})}
    [pscustomobject]@{Name=$Name;'GPO ID'=$Id;Side=$side;Extension=if($null -ne $label){$label.InnerText}else{$null};'Setting types'=(@($nodes|ForEach-Object{$_.LocalName}|Sort-Object -Unique) -join '; ');'Top-level setting nodes'=$nodes.Count}
   }
  }
 }finally{if($null -ne $reader){$reader.Dispose()};$stringReader.Dispose()}
}
function ConvertTo-PSIGpoModel($Context,[object[]]$Envelopes){
 $schema=Get-PSIGpoSchema;$data=[ordered]@{};$coverage=[ordered]@{}
 foreach($k in $schema.Keys){$data[$k]=@()}
 $seen=@{}
 foreach($e in $Envelopes){
  $k=[string]$e.Key
  if(-not $schema.Contains($k) -or $k -eq 'collection' -or $seen.ContainsKey($k)){throw "Unknown/duplicate GPO category: $k"}
  if($e.Status -notin @('Succeeded','Partial','Failed','TimedOut','NotAttempted')){throw "Invalid status for $k"}
  $seen[$k]=$true;$coverage[$k]=$e.Status -eq 'Succeeded'
  if($e.Status -in @('Succeeded','Partial')){
   $data[$k]=@($e.Records|Where-Object{$null -ne $_}|ForEach-Object{$row=[ordered]@{};foreach($c in $schema[$k][1]){$row[$c]=Get-PSISiteValue $_ $c};[pscustomobject]$row})
  }
  $data.collection+= [pscustomobject]@{Name=$schema[$k][0];Status=$e.Status;'Record count'=$data[$k].Count;Method='Pinned DC / AD and GroupPolicy';'Collected at'=$e.CollectedAt;'Duration ms'=$e.DurationMs;'Error ID'=$e.ErrorId;Message=$e.ErrorMessage}
 }
 foreach($k in $schema.Keys){if($k -ne 'collection' -and -not $seen.ContainsKey($k)){throw "Missing GPO category: $k"}}
 $coverage.collection=$true
 [pscustomobject]@{Schema=$schema;Data=$data;Coverage=$coverage;Raw=[ordered]@{}}
}
