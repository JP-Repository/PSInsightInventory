function Get-PSInsightInventory {
<#
.SYNOPSIS
Lists the inventories currently available in PSInsightInventory, with usage examples.
.DESCRIPTION
Returns catalog metadata only. Does not query AD, contact servers or generate files.
.EXAMPLE
Get-PSInsightInventory | Format-List *
.EXAMPLE
Get-Command -Module PSInsightInventory
.EXAMPLE
Get-Help Invoke-ADInfrastructureInventory -Examples
#>
    [CmdletBinding()]
    param()
    [pscustomobject][ordered]@{
        Name='ADInfrastructure'
        Module='PSInsightInventory'
        Version='1.0.0'
        Command='Invoke-ADInfrastructureInventory'
        Description='Domain-scoped DC infrastructure inventory with 17 report sections.'
        Scope='One explicit domain; optional exact DC subset.'
        ReportSections=17
        SampleCommand='Invoke-ADInfrastructureInventory -SampleData -Open'
        LiveCommand='Invoke-ADInfrastructureInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADInfrastructureInventory -Examples'
    }
    [pscustomobject][ordered]@{
        Name='ADSitesAndServices';Module='PSInsightInventory';Version='1.0.0'
        Command='Invoke-ADSitesAndServicesInventory'
        Description='Forest-wide Sites & Services configuration inventory through one DC.'
        Scope='Forest-wide Configuration partition; Domain selects the connection.'
        ReportSections=12
        SampleCommand='Invoke-ADSitesAndServicesInventory -Demo -Open'
        LiveCommand='Invoke-ADSitesAndServicesInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADSitesAndServicesInventory -Examples'
    }

    [pscustomobject][ordered]@{
        Name='ADForest';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADForestInventory'
        Description='Forest and member-domain metadata, functional levels, FSMO references and default policy inventory.'
        Scope='Forest-wide, including independent member-domain reads.';ReportSections=13
        SampleCommand='Invoke-ADForestInventory -Demo -Open'
        LiveCommand='Invoke-ADForestInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADForestInventory -Examples'
    }

    [pscustomobject][ordered]@{
        Name='ADTrusts';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADTrustInventory'
        Description='Local-forest trust observations, relative directions and separate reported trust settings.'
        Scope='Trust objects in local forest member domains; no partner-side reads.';ReportSections=7
        SampleCommand='Invoke-ADTrustInventory -Demo -Open'
        LiveCommand='Invoke-ADTrustInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADTrustInventory -Examples'
    }

    [pscustomobject][ordered]@{
        Name='ADDns';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADDnsInventory'
        Description='DNS configuration on selected domain DCs with per-zone collection evidence.'
        Scope='One domain; optional exact DC subset; Primary zones for configuration; hosted zone NS records.';ReportSections=17
        SampleCommand='Invoke-ADDnsInventory -Demo -Open'
        LiveCommand='Invoke-ADDnsInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADDnsInventory -Examples'
    }
    [pscustomobject][ordered]@{
        Name='ADGroupPolicy';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADGroupPolicyInventory'
        Description='GPO configuration, link and reported permission relationships without assessment scoring.'
        Scope='One domain; forest sites for selected-domain links.';ReportSections=11
        SampleCommand='Invoke-ADGroupPolicyInventory -Demo -Open'
        LiveCommand='Invoke-ADGroupPolicyInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADGroupPolicyInventory -Examples'
    }
    [pscustomobject][ordered]@{
        Name='ADOrganizationalUnit';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADOrganizationalUnitInventory'
        Description='OU hierarchy, direct/descendant object counts, GPO references and reported delegation ACEs.'
        Scope='Organizational units in one explicit domain.';ReportSections=8
        SampleCommand='Invoke-ADOrganizationalUnitInventory -Demo -Open'
        LiveCommand='Invoke-ADOrganizationalUnitInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADOrganizationalUnitInventory -Examples'
    }
    [pscustomobject][ordered]@{
        Name='ADComputer';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADComputerInventory'
        Description='Directory computer inventory with OS breakdowns, location, SPNs and reported delegation attributes.'
        Scope='Computer objects in one explicit domain; no endpoint collection.';ReportSections=7
        SampleCommand='Invoke-ADComputerInventory -Demo -Open'
        LiveCommand='Invoke-ADComputerInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADComputerInventory -Examples'
    }
    [pscustomobject][ordered]@{
        Name='ADGroup';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADGroupInventory'
        Description='Group properties, direct linked members, nested/parent links and member-type resolution evidence.'
        Scope='Groups in one domain; external member references retained without dereferencing.';ReportSections=7
        SampleCommand='Invoke-ADGroupInventory -Demo -Open'
        LiveCommand='Invoke-ADGroupInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADGroupInventory -Examples'
    }
    [pscustomobject][ordered]@{
        Name='ADUser';Module='PSInsightInventory';Version='1.0.0';Command='Invoke-ADUserInventory'
        Description='User properties, account flags, reported group links, primary group references and organizational summaries.'
        Scope='User objects in one explicit domain; no external lookups or assessment.';ReportSections=10
        SampleCommand='Invoke-ADUserInventory -Demo -Open'
        LiveCommand='Invoke-ADUserInventory -Domain ad.example.test -Open'
        HelpCommand='Get-Help Invoke-ADUserInventory -Examples'
    }
}
