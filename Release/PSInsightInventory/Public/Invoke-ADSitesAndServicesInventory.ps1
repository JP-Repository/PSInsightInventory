function Invoke-ADSitesAndServicesInventory {
<#
.SYNOPSIS
Inventories forest-wide AD Sites & Services configuration through one DC.
.DESCRIPTION
Reads the Configuration partition: sites, subnets, site links, bridges, directory servers,
NTDS Site Settings, transports and stored schedules. Domain selects the connection domain;
it does not restrict Sites configuration to one domain. No WinRM or infrastructure changes.
Outputs a JP-branded offline HTML console, CSV, JSON and structured logs.
.PARAMETER Domain
DNS domain used to discover the connection DC. The report scope is forest-wide.
.PARAMETER Credential
Optional credential authorized to read the Configuration partition.
.PARAMETER TimeoutSeconds
Overall worker budget, including connection and all eight queries. Default 120 seconds.
Completed queries survive a later timeout. Cancellation/cleanup can take additional time.
.PARAMETER SampleData
Use fictional fixtures without AD access. Demo is an alias.
.PARAMETER OutputPath
Parent folder for a unique run directory. Default C:\Temp\Reports.
.PARAMETER Quiet
Suppress the console banner, heartbeat, progress and completion display.
Warnings/errors and structured report output are retained.
.PARAMETER Open
Open the generated HTML locally after saving.
.EXAMPLE
Invoke-ADSitesAndServicesInventory -Demo -Open
.EXAMPLE
Invoke-ADSitesAndServicesInventory -Domain ad.example.test -Open
.EXAMPLE
Invoke-ADSitesAndServicesInventory -Domain example.test -Credential (Get-Credential) -TimeoutSeconds 180 -Open
#>
    [CmdletBinding(DefaultParameterSetName='Live')]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Live')][ValidatePattern('^(?=.{1,253}$)[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$')][string]$Domain,
        [Parameter(ParameterSetName='Live')][pscredential]$Credential,
        [Parameter(ParameterSetName='Live')][ValidateRange(10,600)][int]$TimeoutSeconds=120,
        [Parameter(Mandatory=$true,ParameterSetName='Sample')][Alias('Demo')][switch]$SampleData,
        [ValidateNotNullOrEmpty()][string]$OutputPath='C:\Temp\Reports',
        [switch]$Quiet,
    [switch]$Open
    )

    $engineArgs=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'Quiet'){$engineArgs[$key]=$PSBoundParameters[$key]}}
    Start-PSIInventoryDisplay -Inventory 'ADSitesAndServicesInventory' -Domain $Domain -OutputPath $OutputPath -Sample ([bool]$SampleData) -Quiet ([bool]$Quiet)
    try{
        $result=& (Join-Path $script:PSIInventoryModuleRoot 'Private/Sites/Engine.ps1') @engineArgs
        Stop-PSIInventoryDisplay -Result $result
        $result
    }catch{Stop-PSIInventoryDisplay -Failed;throw}

}
