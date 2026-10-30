@{
    RootModule='PSInsightInventory.psm1'
    ModuleVersion='1.0.0'
    GUID='09a48d6c-5610-40dc-9ea8-69239dafaa88'
    Author='Jonathan Preetham'
    Copyright='Copyright (c) Jonathan Preetham. JP project branding reused with owner authorization.'
    Description='Read-only Active Directory infrastructure inventory with an offline JP-branded HTML console, CSV, JSON and collection coverage.'
    PowerShellVersion='5.1'
    HelpInfoURI='https://github.com/JP-Repository/PSInsightInventory'
    CompatiblePSEditions=@('Desktop','Core')
    FunctionsToExport=@('Get-PSInsightInventory','Invoke-ADInfrastructureInventory','Invoke-ADSitesAndServicesInventory','Invoke-ADForestInventory','Invoke-ADTrustInventory','Invoke-ADDnsInventory','Invoke-ADGroupPolicyInventory','Invoke-ADOrganizationalUnitInventory','Invoke-ADComputerInventory','Invoke-ADGroupInventory','Invoke-ADUserInventory')
    CmdletsToExport=@()
    VariablesToExport=@()
    AliasesToExport=@()
    RequiredModules=@()
    PrivateData=@{
        PSData=@{
            Tags=@('ActiveDirectory','Inventory','DomainControllers','Reporting','Offline','WindowsPowerShell')
            ProjectUri='https://github.com/JP-Repository/PSInsightInventory'
            LicenseUri='https://opensource.org/license/mit'
            ReleaseNotes='First public release. Includes the existing ten read-only inventories, JP-branded offline HTML, JSON/CSV exports, console progress, and Quiet automation support.'
        }
    }
}
