function Invoke-ADForestInventory {
<#
.SYNOPSIS
Creates a read-only forest and member-domain inventory report.
.DESCRIPTION
Uses a supplied connection domain to discover the forest, then queries the returned member domains.
Includes forest/domain identity, functional levels, hierarchy, configured UPN/SPN suffixes,
FSMO references, partition references, hosted naming contexts, default containers, directory-server
references and default domain password policy values. Does not evaluate health or effective policy.
.PARAMETER Domain
DNS connection domain. All returned forest member domains are included in inventory scope.
.PARAMETER Credential
Optional authorized directory-read credential used for forest and member-domain queries.
.PARAMETER TimeoutSeconds
Overall worker budget including discovery and all domains. Default 180 seconds. Completed results
survive a later timeout; cancellation/cleanup can add time. Failed domains remain in the inventory.
.PARAMETER SampleData
Use fictional fixtures without network access. Demo is an alias.
.PARAMETER OutputPath
Parent for a unique Reports/Logs run directory. Default C:\Temp\Reports.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER Open
Open the saved HTML locally.
.EXAMPLE
Invoke-ADForestInventory -Demo -Open
.EXAMPLE
Invoke-ADForestInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADForestInventory -Domain example.test -Credential (Get-Credential) -TimeoutSeconds 300 -Open
#>
    [CmdletBinding(DefaultParameterSetName='Live')]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^(?=.{1,253}$)[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$')][string]$Domain,
        [Parameter(ParameterSetName='Live')][pscredential]$Credential,
        [Parameter(ParameterSetName='Live')][ValidateRange(10,1800)][int]$TimeoutSeconds=180,
        [Parameter(Mandatory=$true,ParameterSetName='Sample')][Alias('Demo')][switch]$SampleData,
        [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',
        [switch]$Quiet,
    [switch]$Open
    )

    $engineArgs=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'Quiet'){$engineArgs[$key]=$PSBoundParameters[$key]}}
    Start-PSIInventoryDisplay -Inventory 'ADForestInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/Forest/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
