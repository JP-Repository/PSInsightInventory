function Invoke-ADDnsInventory {
<#
.SYNOPSIS
Inventories DNS configuration on DCs in one explicitly supplied domain.
.DESCRIPTION
Read-only local DNS/CIM queries over authorized WinRM, using bounded workers.
Includes DNS role, client resolvers, forwarders, recursion, scavenging, root hints,
zones, conditional forwarders and primary-zone aging, delegations and scopes.
Zone NS records and exact stored A/AAAA nodes for eligible hosted NS targets are
included without resolver probes; external address targets are not queried.
Per-zone failures are retained separately and do not discard successful zone results.
.PARAMETER Domain
Explicit DNS domain. Child domains and non-DC DNS servers are not enumerated.
.PARAMETER ComputerName
Optional exact DC names/FQDNs selected from domain discovery.
.PARAMETER Credential
Optional authorized AD/WinRM credential.
.PARAMETER SampleData
Fictional fixtures without infrastructure access. Demo is an alias.
.PARAMETER OutputPath
Output parent; default C:\Temp\Reports.
.PARAMETER ThrottleLimit
Maximum concurrent DC workers; default 4.
.PARAMETER TargetTimeoutSeconds
Overall per-DC budget including worker startup and all queries; default 180 seconds.
.PARAMETER DiscoveryTimeoutSeconds
Domain discovery budget; default 60 seconds.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER OpenTimeoutSeconds
WinRM connection-open budget; default 15 seconds.
.PARAMETER UseSSL
Use an existing WinRM HTTPS endpoint with normal certificate validation.
.PARAMETER Port
Optional approved WinRM port; zero uses the default for the chosen transport.
.PARAMETER Open
Open the saved report locally.
.EXAMPLE
Invoke-ADDnsInventory -Demo -Open
.EXAMPLE
Invoke-ADDnsInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADDnsInventory -Domain ad.example.test -ComputerName dc01.example.test -Open
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
    [Parameter(ParameterSetName='Live')][switch]$UseSSL,
    [Parameter(ParameterSetName='Live')][ValidateRange(0,65535)][int]$Port=0,
    [switch]$Quiet,
    [switch]$Open
)

    $engineArgs=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'Quiet'){$engineArgs[$key]=$PSBoundParameters[$key]}}
    Start-PSIInventoryDisplay -Inventory 'ADDnsInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/Dns/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
