# Console output uses host/progress streams only; it never enters returned datasets.
function Get-PSIConsoleValue($Object,[string]$Name){if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]){return $Object.$Name};return $null}
function Get-PSIInventoryDisplayState {Get-Variable -Name PSIConsole -ValueOnly -ErrorAction SilentlyContinue}
function Test-PSIInventoryQuiet {$state=Get-PSIInventoryDisplayState;return ($null -ne $state -and $state.Quiet)}
function Start-PSIInventoryDisplay([string]$Inventory,[string]$Domain,[string]$OutputPath,[bool]$Sample,[bool]$Quiet){
 $Inventory=switch($Inventory){'ADInfrastructureInventory'{'AD Infrastructure Inventory'}'ADSitesAndServicesInventory'{'AD Sites and Services Inventory'}'ADForestInventory'{'AD Forest and Domain Inventory'}'ADTrustInventory'{'AD Trust Inventory'}'ADDnsInventory'{'AD DNS Configuration Inventory'}'ADGroupPolicyInventory'{'AD Group Policy Inventory'}'ADOrganizationalUnitInventory'{'AD Organizational Unit Inventory'}'ADComputerInventory'{'AD Computer Inventory'}'ADGroupInventory'{'AD Group Inventory'}'ADUserInventory'{'AD User Inventory'}default{$Inventory}}
 $script:PSIConsole=[pscustomobject]@{
  Inventory=$Inventory;Quiet=$Quiet;Sample=$Sample;Clock=[diagnostics.stopwatch]::StartNew()
  Seen=@{};Names=@{};Completed=0;Total=-1;Failures=0;Records=0
  ControllersProcessed=0;ControllerTotal=-1;Target='';LastPaint=-1.0;LastLine=-20.0;LastLineStage='';Stage='Starting'
 }
 if($Quiet){return}
 try{
  $manifest=Import-PowerShellDataFile (Join-Path $script:PSIInventoryModuleRoot 'PSInsightInventory.psd1')
  Write-Host '';Write-Host ('-'*68) -ForegroundColor DarkGray
  Write-Host ('PSInsightInventory  |  v'+$manifest.ModuleVersion) -ForegroundColor Cyan
  Write-Host 'Active Directory Inventory'
  Write-Host ('Author:     '+$manifest.Author)
  Write-Host 'License: MIT'
  Write-Host ('-'*68) -ForegroundColor DarkGray
  Write-Host ('Inventory : '+$Inventory);Write-Host ('Domain    : '+$(if($Sample){'Fictional sample (no infrastructure access)'}else{$Domain}))
  Write-Host ('Output    : '+$OutputPath);Write-Host ('Mode      : '+$(if($Sample){'SAMPLE'}else{'LIVE - read only'}));Write-Host ''
 }catch{}
 Update-PSIInventoryDisplay -Stage 'Starting collection' -Force
}
function Update-PSIInventoryDisplay(
 [string]$Stage='', [int]$Total=-1, [string]$Target='', [switch]$Force,
 [int]$ControllerTotal=-1, [int]$ControllersProcessed=-1
){
 $state=Get-PSIInventoryDisplayState;if($null -eq $state -or $state.Quiet){return}
 $d=$state
 if($Stage){$d.Stage=$Stage}
 if($Total -ge 0){$d.Total=$Total}
 if($Target){$d.Target=$Target}
 if($ControllerTotal -ge 0){$d.ControllerTotal=$ControllerTotal}
 if($ControllersProcessed -ge 0){$d.ControllersProcessed=$ControllersProcessed}
 $stageChanged=$d.Stage -ne $d.LastLineStage
 $seconds=$d.Clock.Elapsed.TotalSeconds;if(-not $Force -and -not $stageChanged -and ($seconds-$d.LastPaint) -lt 0.4){return};$d.LastPaint=$seconds
 $elapsed=$d.Clock.Elapsed.ToString('hh\:mm\:ss');$spinner=@('|','/','-','\')[[int]($seconds*2)%4]
 $totalUnits=$d.Total
 $processedUnits=$d.Completed
 $unitLabel='query outcomes recorded'
 if($d.ControllerTotal -gt 0){
  $totalUnits=$d.ControllerTotal
  $processedUnits=$d.ControllersProcessed
  $unitLabel='controllers processed'
 }
 $percent=-1
 $countText='Working (total not known yet)'
 if($totalUnits -gt 0){
  $percent=[int][math]::Min(100,[math]::Floor(100*$processedUnits/$totalUnits))
  $countText='{0} of {1} {2}' -f $processedUnits,$totalUnits,$unitLabel
 }
 $status='{0} {1} | {2} | Elapsed {3}' -f $spinner,$d.Stage,$countText,$elapsed
 $detail='Rows observed: '+$d.Records+' | Incomplete outcomes: '+$d.Failures
 $targetText=''
 if($d.Target){$targetText=' | Target: '+$d.Target}
 try{
  Write-Progress -Id 8511 -Activity ('PSInsightInventory - '+$d.Inventory) -Status ($status+$targetText) -CurrentOperation $detail -PercentComplete $percent
 }catch{}
 try{
  # Periodic plain text remains useful in hosts that hide native progress.
  if($Force -or $stageChanged -or ($seconds-$d.LastLine) -ge 15){
   Write-Host ('['+$elapsed+'] '+$d.Stage+' | '+$countText+$targetText) -ForegroundColor DarkCyan
   $d.LastLine=$seconds
   $d.LastLineStage=$d.Stage
  }
 }catch{}
}
function Receive-PSIInventoryDisplay([object[]]$Items,[int]$Total=-1){
 $state=Get-PSIInventoryDisplayState;if($null -eq $state -or $state.Quiet){return}
 $d=$state;if($Total -ge 0){$d.Total=$Total}
 foreach($item in $Items){
  $kind=[string](Get-PSIConsoleValue $item 'Kind');$key=[string](Get-PSIConsoleValue $item 'Key');$status=[string](Get-PSIConsoleValue $item 'Status')
  if($kind -eq 'Progress'){$d.Stage=[string](Get-PSIConsoleValue $item 'Stage');$d.Target=[string](Get-PSIConsoleValue $item 'Target');continue}
  if($kind -eq 'Context'){$target=[string](Get-PSIConsoleValue $item 'Server');if($target){$d.Target=$target};continue}
  if(-not $key -or -not $status){continue}
  $target=[string](Get-PSIConsoleValue $item 'Target');$identity=$target+'|'+$key
  if($d.Seen.ContainsKey($identity)){continue};$d.Seen[$identity]=$true;$d.Completed++
  if($status -in @('Failed','TimedOut','Partial','NotAttempted')){$d.Failures++}
  $records=@((Get-PSIConsoleValue $item 'Records')|Where-Object{$null -ne $_});$d.Records+=$records.Count
  if($key -eq 'groups'){$d.Total=1+$records.Count;foreach($r in $records){$id=[string](Get-PSIConsoleValue $r 'Id');if($id){$d.Names[$id]=[string](Get-PSIConsoleValue $r 'Name')}}}
  if($key -like 'members:*'){$id=$key.Substring(8);$d.Target=if($d.Names.ContainsKey($id)){$d.Names[$id]}else{$key}}
  elseif($target){$d.Target=$target}else{$d.Target=$key}
 }
 if($d.Stage -eq 'Starting collection'){$d.Stage='Collecting configuration'}
 Update-PSIInventoryDisplay
}
function Complete-PSIInventoryCollectionDisplay([object[]]$Collection){
 $state=Get-PSIInventoryDisplayState;if($null -eq $state -or $state.Quiet){return}
 $state.Completed=@($Collection).Count;$state.Total=@($Collection).Count
 $state.Failures=@($Collection|Where-Object{[string](Get-PSIConsoleValue $_ 'Status') -notin @('Succeeded','NotApplicable')}).Count
}
function Stop-PSIInventoryDisplay($Result,[switch]$Failed){
 $state=Get-PSIInventoryDisplayState;if($null -eq $state){return};$d=$state
 try{
  if(-not $d.Quiet){
   Write-Progress -Id 8511 -Activity 'PSInsightInventory' -Completed
   Write-Host '';Write-Host $(if($Failed){'COLLECTION STOPPED'}else{'REPORT SAVED'}) -ForegroundColor $(if($Failed -or $d.Failures){'Yellow'}else{'Green'})
   Write-Host ('Elapsed: '+$d.Clock.Elapsed.ToString('hh\:mm\:ss'))
   if(-not $Failed){
    $controllers=Get-PSIConsoleValue $Result 'DomainControllers'
    $partial=Get-PSIConsoleValue $Result 'PartialInventory'
    if($null -eq $controllers){
     $controllers=Get-PSIConsoleValue $Result 'SelectedDCs'
     $partial=Get-PSIConsoleValue $Result 'PartialInventories'
    }
    if($null -ne $controllers -and $null -ne $partial){
     Write-Host ('Controllers processed: '+$controllers)
     Write-Host ('Collection complete:   '+($controllers-$partial)) -ForegroundColor Green
     Write-Host ('Collection partial:    '+$partial) -ForegroundColor $(if($partial){'Yellow'}else{'Gray'})
    }else{
     Write-Host ('Query outcomes observed: '+$d.Completed+' | Incomplete outcomes: '+$d.Failures) -ForegroundColor $(if($d.Failures){'Yellow'}else{'Gray'})
    }
    if($d.Sample){Write-Host 'Sample data only - no infrastructure was contacted.' -ForegroundColor Yellow}
    $path=Get-PSIConsoleValue $Result 'HtmlReport';if($path){Write-Host ('Report: '+$path)}
   }else{Write-Host 'Review the error and run log for details.' -ForegroundColor Yellow}
   Write-Host ('-'*68) -ForegroundColor DarkGray
  }
 }catch{}finally{$script:PSIConsole=$null}
}
$script:PSIConsole=$null
