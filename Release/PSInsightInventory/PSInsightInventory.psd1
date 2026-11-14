@{
    RootModule='PSInsightInventory.psm1'
    ModuleVersion='2.0.0'
    GUID='09a48d6c-5610-40dc-9ea8-69239dafaa88'
    Author='Jonathan Preetham'
    Copyright='Copyright (c) Jonathan Preetham. JP project branding reused with owner authorization.'
    Description='Read-only Active Directory inventory for domain controllers, DNS, sites, forests, trusts, Group Policy, OUs, computers, groups, and users. Includes interactive offline dashboards, CSV and JSON exports, and collection coverage.'
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
            ReleaseNotes='Version 2.0.0 introduces a shared interactive offline dashboard across the existing ten read-only inventories, with focused tables, light and dark themes, filters, record details, CSV/JSON exports, improved collection coverage, and same-day run preservation.'
        }
    }
}
