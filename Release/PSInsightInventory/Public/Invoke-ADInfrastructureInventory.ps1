function Invoke-ADInfrastructureInventory {
<#
.SYNOPSIS
Creates a read-only, domain-scoped domain-controller inventory and offline HTML console.
.DESCRIPTION
PSInsightInventory module entry point. Uses the bundled collectors and offline renderer.
Independent of PSInsightExpl and PSInsightHTML; reuses the approved JP branding.
Live mode requires Windows, the ActiveDirectory module and authorized WinRM access.
Uses Kerberos; does not enable remoting, change trust settings, or make infrastructure changes.
Sample mode does not import AD modules or contact infrastructure.
.PARAMETER Domain
One DNS domain name. Child domains are not enumerated. Required for live runs.
.PARAMETER ComputerName
Optional exact short names or FQDNs chosen from the discovered domain DCs. No wildcards.
.PARAMETER SampleData
Render the bundled fictional inventory without contacting AD or DCs.
.PARAMETER OutputPath
Parent output folder. Default C:\Temp\Reports. Each run gets a unique folder.
.PARAMETER Credential
Optional credential used for directory reads and WinRM Kerberos authentication. Never logged.
.PARAMETER ThrottleLimit
Maximum concurrent local worker jobs. Default 4.
.PARAMETER TargetTimeoutSeconds
Wall-clock budget for each DC worker, including local job startup and all its categories.
Completed category results are retained if a later category times out. Default 180 seconds.
.PARAMETER DiscoveryTimeoutSeconds
Wall-clock wait budget for domain/DC discovery. Default 60 seconds.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER OpenTimeoutSeconds
WinRM connection-open budget. This is not a per-command timeout. Default 15 seconds.
.PARAMETER SkipRemote
Collect directory categories only. Remote categories remain NotAttempted and inventory Partial.
.PARAMETER UseSSL
Use WinRM HTTPS with normal certificate validation. Does not disable certificate checks.
.PARAMETER Port
Optional WinRM port. Defaults to 5985 for HTTP or 5986 with -UseSSL when omitted.
.PARAMETER Open
Open the generated HTML using the local default application after export.
.EXAMPLE
Invoke-ADInfrastructureInventory -SampleData -OutputPath C:\Temp\Reports -Open
.EXAMPLE
Invoke-ADInfrastructureInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADInfrastructureInventory -Domain example.test -ComputerName dc01.example.test -SkipRemote
.NOTES
PSInsightInventory 1.0.0. Target: Windows PowerShell 5.1. No health verdict, email or remediation.
#>
[CmdletBinding(DefaultParameterSetName='Live')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Live')]
    [ValidatePattern('^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$')][string]$Domain,
    [Parameter(ParameterSetName='Live')][ValidateNotNullOrEmpty()][string[]]$ComputerName,
    [Parameter(Mandatory=$true,ParameterSetName='Sample')][Alias('Demo')][switch]$SampleData,
    [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',
    [Parameter(ParameterSetName='Live')][pscredential]$Credential,
    [Parameter(ParameterSetName='Live')][ValidateRange(1,16)][int]$ThrottleLimit=4,
    [Parameter(ParameterSetName='Live')][ValidateRange(15,3600)][int]$TargetTimeoutSeconds=180,
    [Parameter(ParameterSetName='Live')][ValidateRange(10,600)][int]$DiscoveryTimeoutSeconds=60,
    [Parameter(ParameterSetName='Live')][ValidateRange(3,120)][int]$OpenTimeoutSeconds=15,
    [Parameter(ParameterSetName='Live')][switch]$SkipRemote,
    [Parameter(ParameterSetName='Live')][switch]$UseSSL,
    [Parameter(ParameterSetName='Live')][ValidateRange(0,65535)][int]$Port=0,
    [switch]$Quiet,
    [switch]$Open
)

    $engineArgs=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'Quiet'){$engineArgs[$key]=$PSBoundParameters[$key]}}
    Start-PSIInventoryDisplay -Inventory 'ADInfrastructureInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/Invoke-PSIInventoryEngine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
