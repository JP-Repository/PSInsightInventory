#requires -Version 5.1
param([string]$OutputPath=(Join-Path ([IO.Path]::GetTempPath()) 'InventoryConsoleTests'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot;$null=New-Item -ItemType Directory $OutputPath -Force;$checks=New-Object collections.ArrayList
function Assert-Display([bool]$Value,[string]$Name){if(-not $Value){throw "FAILED: $Name"};[void]$checks.Add($Name);Write-Host "PASS $Name"}
Import-Module (Join-Path $root 'PSInsightInventory.psd1') -Force;$module=Get-Module PSInsightInventory
Assert-Display (@(Get-Command -Module PSInsightInventory).Count -eq 11) 'No console helpers exported'
foreach($command in (Get-PSInsightInventory).Command){Assert-Display ((Get-Command $command).Parameters.ContainsKey('Quiet')) ('Quiet available: '+$command)}
$quietInfo=@();$quiet=@(Invoke-ADUserInventory -Demo -Quiet -OutputPath $OutputPath -InformationVariable quietInfo)
Assert-Display ($quiet.Count -eq 1 -and $quiet[0].ObservedUsers -eq 5) 'Quiet returns the original structured result only'
Assert-Display (@($quietInfo).Count -eq 0) 'Quiet suppresses host information output'
$normalInfo=@();$normal=@(Invoke-ADUserInventory -Demo -OutputPath $OutputPath -InformationVariable normalInfo)
$text=($normalInfo|ForEach-Object{[string]$_.MessageData}) -join "`n"
Assert-Display ($normal.Count -eq 1 -and $normal[0].ObservedUsers -eq $quiet[0].ObservedUsers) 'Banner does not contaminate success stream'
Assert-Display ($text -match 'PSInsightInventory' -and $text -match 'License: MIT' -and $text -match 'Jonathan Preetham') 'Banner identifies module author and MIT license'
Assert-Display ($text -notmatch 'github\.com|linkedin\.com|outlook\.com|mailto:') 'Repository, support, documentation and author links stay out of console banner'
Assert-Display ($text -match 'REPORT SAVED' -and $text -match 'Sample data only') 'Completion explicitly identifies sample output'
$state=& $module {
 Start-PSIInventoryDisplay 'Test' 'example.test' 'C:\Temp\Reports' $false $false
 $context=[pscustomobject]@{Kind='Context';Server='dc01.example.test'}
 $catalog=[pscustomobject]@{Kind='Section';Key='groups';Status='Succeeded';Records=@([pscustomobject]@{Id='a';Name='Group A'},[pscustomobject]@{Id='b';Name='Group B'})}
 Receive-PSIInventoryDisplay @($context,$catalog)
 Receive-PSIInventoryDisplay @($catalog)
 $progress=[pscustomobject]@{Kind='Progress';Stage='Reading group membership';Target='Group A'}
 Receive-PSIInventoryDisplay @($progress)
 $d=Get-PSIInventoryDisplayState
 $result=[pscustomobject]@{Completed=$d.Completed;Total=$d.Total;Rows=$d.Records;Stage=$d.Stage;Target=$d.Target}
 Complete-PSIInventoryCollectionDisplay @([pscustomobject]@{Status='Succeeded'},[pscustomobject]@{Status='TimedOut'},[pscustomobject]@{Status='NotAttempted'})
 $result|Add-Member -NotePropertyName FinalIncomplete -NotePropertyValue $d.Failures
 Stop-PSIInventoryDisplay -Failed
 $result
}
Assert-Display ($state.Completed -eq 1 -and $state.Total -eq 3 -and $state.Rows -eq 2) 'Repeated batches are deduplicated with real group denominator'
Assert-Display ($state.Stage -eq 'Reading group membership' -and $state.Target -eq 'Group A') 'Worker activity updates current stage/target without becoming an outcome'
Assert-Display ($state.FinalIncomplete -eq 2) 'Final ledger includes missing and timed-out outcomes'
Assert-Display (& $module {$null -eq (Get-PSIInventoryDisplayState)}) 'Display state cleared after failure/completion'
Assert-Display ((Get-Content (Join-Path $root 'LICENSE') -Raw) -match 'MIT License' -and (Get-Content (Join-Path $root 'LICENSE') -Raw) -match 'Jonathan Preetham') 'MIT label backed by packaged license'
# Exercise parent polling integration and verify progress messages do not enter data.
$pipeline=& $module {
 Start-PSIInventoryDisplay 'Group polling test' 'example.test' 'C:\Temp\Reports' $false $false
 try{
  . (Join-Path $script:PSIInventoryModuleRoot 'Private/Groups/Helpers.ps1')
  . (Join-Path $script:PSIInventoryModuleRoot 'Private/Groups/Collector.ps1')
  $worker={param($Domain,$HelperText,$ShowProgress)
   [pscustomobject]@{Kind='Context';Domain=$Domain;Server='mock.example.test';DomainDN='DC=example,DC=test'}
   if($ShowProgress){[pscustomobject]@{Kind='Progress';Stage='Reading group membership';Target='Group A'}}
   [pscustomobject]@{Kind='Section';Key='groups';Status='Succeeded';Records=@();CollectedAt='2026-10-30T00:00:00Z';DurationMs=1;ErrorId=$null;ErrorMessage=''}
  }
  Invoke-PSIGroupCollection 'example.test' 15 $worker ''
 }finally{Stop-PSIInventoryDisplay -Failed}
}
Assert-Display ($pipeline.Envelopes.Count -eq 1 -and $pipeline.Envelopes[0].Kind -eq 'Section') 'Polling consumes activity messages without exporting them'
Assert-Display (@(Get-Job|Where-Object{$_.State -eq 'Running'}).Count -eq 0) 'Activity worker jobs are cleaned up'
$summary=[pscustomobject]@{Status='Passed';Checks=$checks.Count;Runtime=$PSVersionTable.PSVersion.ToString();SampleReport=$normal[0].HtmlReport;WindowsPowerShell51Tested=($PSVersionTable.PSVersion.Major -eq 5)}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath 'ConsoleTestResults.json') -Encoding UTF8
$summary
