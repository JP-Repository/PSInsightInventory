#requires -Version 5.1
Set-StrictMode -Version 2.0
$script:PSIInventoryModuleRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'Private/Console.ps1')
foreach($file in @('Get-PSInsightInventory.ps1','Invoke-ADInfrastructureInventory.ps1','Invoke-ADSitesAndServicesInventory.ps1','Invoke-ADForestInventory.ps1','Invoke-ADTrustInventory.ps1','Invoke-ADDnsInventory.ps1','Invoke-ADGroupPolicyInventory.ps1','Invoke-ADOrganizationalUnitInventory.ps1','Invoke-ADComputerInventory.ps1','Invoke-ADGroupInventory.ps1','Invoke-ADUserInventory.ps1')){
    . (Join-Path (Join-Path $PSScriptRoot 'Public') $file)
}
Export-ModuleMember -Function Get-PSInsightInventory,Invoke-ADInfrastructureInventory,Invoke-ADSitesAndServicesInventory,Invoke-ADForestInventory,Invoke-ADTrustInventory,Invoke-ADDnsInventory,Invoke-ADGroupPolicyInventory,Invoke-ADOrganizationalUnitInventory,Invoke-ADComputerInventory,Invoke-ADGroupInventory,Invoke-ADUserInventory
