function Invoke-ADOrganizationalUnitInventory {
<#
.SYNOPSIS
Inventories OU hierarchy, object counts, GPO references and delegation ACEs.
.DESCRIPTION
Read-only domain-scoped inventory using RSAT ActiveDirectory and pinned LDAP
DACL reads with the current Windows identity. Counts are computed from one bulk
scan. No object identities, effective permissions or recommendations are exported.
.PARAMETER Domain
Explicit DNS domain; child domains are not enumerated.
.PARAMETER TimeoutSeconds
Overall worker budget including discovery; default 600 seconds.
.PARAMETER SampleData
Offline fictional data. Demo is an alias; no infrastructure is contacted.
.PARAMETER OutputPath
Output parent; default C:\Temp\Reports, with a unique run folder.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER Open
Open the generated HTML locally.
.EXAMPLE
Invoke-ADOrganizationalUnitInventory -Demo -Open
.EXAMPLE
Invoke-ADOrganizationalUnitInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADOrganizationalUnitInventory -Domain example.test -TimeoutSeconds 900 -OutputPath C:\Temp\Reports -Open
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
    Start-PSIInventoryDisplay -Inventory 'ADOrganizationalUnitInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/OrganizationalUnits/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
