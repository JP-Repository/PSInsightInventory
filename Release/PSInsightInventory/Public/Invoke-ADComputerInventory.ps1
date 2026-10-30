function Invoke-ADComputerInventory {
<#
.SYNOPSIS
Inventories directory computers with OS breakdowns and related attributes.
.DESCRIPTION
Read-only one-domain inventory through a pinned DC using RSAT ActiveDirectory.
Includes AD-reported OS/build, enabled state, role indicators, location, timestamps,
SPNs and delegation attributes. Does not contact endpoints or assess stale devices.
.PARAMETER Domain
Explicit DNS domain; child domains are not enumerated.
.PARAMETER TimeoutSeconds
Overall worker budget including discovery; default 600 seconds.
.PARAMETER SampleData
Fictional offline fixture. Demo is an alias; no infrastructure is contacted.
.PARAMETER OutputPath
Output parent; default C:\Temp\Reports, with a unique run folder.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER Open
Open the generated HTML locally.
.EXAMPLE
Invoke-ADComputerInventory -Demo -Open
.EXAMPLE
Invoke-ADComputerInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADComputerInventory -Domain example.test -TimeoutSeconds 900 -OutputPath C:\Temp\Reports -Open
#>
 [CmdletBinding(DefaultParameterSetName='Live')]
 param(
  [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$')][string]$Domain,
  [Parameter(ParameterSetName='Live')][ValidateRange(10,3600)][int]$TimeoutSeconds=600,
  [Parameter(Mandatory=$true,ParameterSetName='Sample')][Alias('Demo')][switch]$SampleData,
  [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',[switch]$Quiet,
    [switch]$Open
 )

    $engineArgs=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'Quiet'){$engineArgs[$key]=$PSBoundParameters[$key]}}
    Start-PSIInventoryDisplay -Inventory 'ADComputerInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/Computers/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
