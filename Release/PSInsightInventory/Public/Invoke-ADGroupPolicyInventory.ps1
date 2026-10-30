function Invoke-ADGroupPolicyInventory {
<#
.SYNOPSIS
Inventories Group Policy configuration and relationships in one domain.
.DESCRIPTION
Read-only inventory using RSAT ActiveDirectory and GroupPolicy with the current
Windows identity. Uses one pinned DC and one bounded background worker. Includes
GPO properties, versions, links, reported permissions, WMI definitions/references,
settings structure and collection evidence. Does not assess effective application.
.PARAMETER Domain
Explicit DNS domain. Other domains are not enumerated for GPOs or OU links.
.PARAMETER TimeoutSeconds
Overall collection budget, including startup and discovery. Default 300 seconds.
.PARAMETER SampleData
Generate fictional offline data. Demo is an alias; no infrastructure is contacted.
.PARAMETER OutputPath
Output parent. Default C:\Temp\Reports. Creates a unique run folder.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER Open
Open the generated HTML locally.
.EXAMPLE
Invoke-ADGroupPolicyInventory -Demo -Open
.EXAMPLE
Invoke-ADGroupPolicyInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADGroupPolicyInventory -Domain example.test -TimeoutSeconds 600 -OutputPath C:\Temp\Reports -Open
#>
 [CmdletBinding(DefaultParameterSetName='Live')]
 param(
  [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$')][string]$Domain,
  [Parameter(ParameterSetName='Live')][ValidateRange(10,3600)][int]$TimeoutSeconds=300,
  [Parameter(Mandatory=$true,ParameterSetName='Sample')][Alias('Demo')][switch]$SampleData,
  [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',[switch]$Quiet,
    [switch]$Open
 )

    $engineArgs=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'Quiet'){$engineArgs[$key]=$PSBoundParameters[$key]}}
    Start-PSIInventoryDisplay -Inventory 'ADGroupPolicyInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/GroupPolicy/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
