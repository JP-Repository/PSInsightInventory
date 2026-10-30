function Invoke-ADTrustInventory {
<#
.SYNOPSIS
Inventories trust objects observed in local forest member domains.
.DESCRIPTION
Reads local-forest trusted-domain objects through a verified DC in each returned domain.
Captures relative direction, reported protocol/transitivity, selective authentication,
separate SID-filtering properties, raw flags and encryption/delegation configuration.
Does not contact trust partners, validate trusts, reset secure channels or change directory data.
.PARAMETER Domain
DNS connection domain. All returned local forest member domains are queried.
.PARAMETER Credential
Optional authorized directory-read credential; not used to contact external trust partners.
.PARAMETER TimeoutSeconds
Overall worker budget, including discovery and member-domain reads. Default 180 seconds.
Completed results survive later timeouts. Cancellation/cleanup can add time.
.PARAMETER SampleData
Use fictional fixtures without network access. Demo is an alias.
.PARAMETER OutputPath
Parent folder for a unique Reports/Logs run directory. Default C:\Temp\Reports.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER Open
Open the saved HTML locally.
.EXAMPLE
Invoke-ADTrustInventory -Demo -Open
.EXAMPLE
Invoke-ADTrustInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADTrustInventory -Domain example.test -Credential (Get-Credential) -TimeoutSeconds 300 -Open
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
    Start-PSIInventoryDisplay -Inventory 'ADTrustInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/Trusts/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
