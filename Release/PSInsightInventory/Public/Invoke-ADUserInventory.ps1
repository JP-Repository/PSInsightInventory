function Invoke-ADUserInventory {
<#
.SYNOPSIS
Inventories user profiles, reported account flags and group references.
.DESCRIPTION
Read-only domain-scoped directory inventory. Includes organizational summaries,
approximate replicated logon timestamps, direct memberOf backlinks and separately
derived primary group SID references. No manager/group target lookups, recursive
membership, privilege analysis, inactivity assessment or remediation is performed.
.PARAMETER Domain
Explicit DNS domain; child domains are not enumerated.
.PARAMETER TimeoutSeconds
Overall collection budget including discovery; default 600 seconds.
.PARAMETER SampleData
Offline fictional fixture. Demo is an alias; no infrastructure is contacted.
.PARAMETER OutputPath
Output parent; default C:\Temp\Reports, with a unique run folder.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER Open
Open the generated HTML locally.
.EXAMPLE
Invoke-ADUserInventory -Demo -Open
.EXAMPLE
Invoke-ADUserInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADUserInventory -Domain example.test -TimeoutSeconds 1200 -OutputPath C:\Temp\Reports -Open
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
    Start-PSIInventoryDisplay -Inventory 'ADUserInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/Users/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
