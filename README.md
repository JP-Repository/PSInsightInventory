# PSInsightInventory 1.0.0

PSInsightInventory is a read-only Active Directory inventory module for Windows PowerShell 5.1. It provides ten inventories, offline JP-branded HTML reports, JSON snapshots, CSV datasets, and JSONL collection logs. It does not assess health, recommend remediation, or change directory, DNS, Group Policy, or endpoint configuration.

The module preserves the existing console banner, progress display, and `-Quiet` automation option. Reports are self-contained and retain the established HTML layout and JP branding.

## Prerequisites

| Use | Requirements |
|---|---|
| Demo mode | Windows PowerShell 5.1 or PowerShell 7; no AD modules, credentials, network, or server access |
| Directory inventories | Windows PowerShell 5.1 on Windows, RSAT `ActiveDirectory`, DNS/domain connectivity, and permission to read the selected scope |
| Group Policy inventory | Directory prerequisites plus the RSAT `GroupPolicy` module |
| DC infrastructure and DNS inventories | Directory prerequisites plus authorized WinRM access to selected DCs; the target uses its local providers and, for DNS categories, its `DnsServer` module |
| Full HTML experience | A current Edge or Chrome browser; static tables remain readable without JavaScript |

Importing the module and running `Get-PSInsightInventory` do not load the ActiveDirectory module or contact infrastructure. Live commands load capabilities only when they need them.

## Installation

### PowerShell Gallery

After 1.0.0 is published:

```powershell
Install-Module -Name PSInsightInventory -Scope CurrentUser
Import-Module PSInsightInventory
```

### GitHub release ZIP

Download [PSInsightInventory-1.0.0.zip](https://github.com/JP-Repository/PSInsightInventory/releases/download/v1.0.0/PSInsightInventory-1.0.0.zip), verify its published SHA-256 checksum, and extract it so the folder structure is:

```text
PSInsightInventory
  PSInsightInventory.psd1
  PSInsightInventory.psm1
  Assets
  Private
  Public
  Templates
```

Then import the manifest:

```powershell
Import-Module C:\Tools\PSInsightInventory\PSInsightInventory.psd1 -Force
```

Follow your organization's policy for downloaded and unsigned PowerShell code. The module does not alter execution policy or install dependencies.

## Available commands

| Command | Scope and output |
|---|---|
| `Get-PSInsightInventory` | Lists the ten available inventories without collecting data |
| `Invoke-ADInfrastructureInventory` | DC infrastructure in one explicit domain; optional exact DC subset; directory and authorized WinRM reads |
| `Invoke-ADSitesAndServicesInventory` | Forest-wide Sites & Services configuration through a DC selected from the supplied domain |
| `Invoke-ADForestInventory` | Forest and member-domain metadata, partitions, FSMO references, and default domain policies |
| `Invoke-ADTrustInventory` | Trust objects observed in local-forest member domains; no trust-partner contact or validation |
| `Invoke-ADDnsInventory` | DNS configuration on selected DCs in one explicit domain; includes per-zone collection evidence |
| `Invoke-ADGroupPolicyInventory` | GPO metadata, links, reported permissions, WMI references, versions, and settings structure |
| `Invoke-ADOrganizationalUnitInventory` | OU hierarchy, counts, direct GPO references, inheritance, and reported delegation ACEs |
| `Invoke-ADComputerInventory` | Directory computer objects, reported OS data, SPNs, location, and delegation attributes; no endpoint connection |
| `Invoke-ADGroupInventory` | Group properties, direct linked members, local nesting/parents, and member-type lookup evidence |
| `Invoke-ADUserInventory` | User properties, flags, reported group backlinks, primary-group references, and organizational summaries |

Discover parameters and command-specific examples locally:

```powershell
Get-Command -Module PSInsightInventory
Get-PSInsightInventory | Format-Table Name, Command, Scope
Get-Help Invoke-ADInfrastructureInventory -Full
Get-Help Invoke-ADUserInventory -Examples
```

Detailed scope notes are included in the inventory-specific Markdown files shipped with the module.

## Demo mode

Every inventory command accepts `-Demo`, an alias for `-SampleData`. Demo mode uses bundled fictional fixtures and does not load AD/DNS providers or contact any server.

```powershell
Invoke-ADInfrastructureInventory -Demo -Open
Invoke-ADSitesAndServicesInventory -Demo -Open
Invoke-ADForestInventory -Demo -Open
Invoke-ADTrustInventory -Demo -Open
Invoke-ADDnsInventory -Demo -Open
Invoke-ADGroupPolicyInventory -Demo -Open
Invoke-ADOrganizationalUnitInventory -Demo -Open
Invoke-ADComputerInventory -Demo -Open
Invoke-ADGroupInventory -Demo -Open
Invoke-ADUserInventory -Demo -Open
```

Samples are explicitly labeled in the console and generated report.

## Live examples

Use a domain and account approved for inventory collection:

```powershell
# Domain-scoped directory inventory
Invoke-ADUserInventory -Domain ad.example.test -Open

# Exact DC subset for infrastructure collection
Invoke-ADInfrastructureInventory `
    -Domain ad.example.test `
    -ComputerName dc01.example.test `
    -OutputPath C:\Temp\Reports `
    -Open

# Directory-only DC categories when WinRM is unavailable
Invoke-ADInfrastructureInventory -Domain ad.example.test -SkipRemote -Open

# Use an authorized alternate credential without logging or storing it
$inventoryCredential = Get-Credential
Invoke-ADForestInventory -Domain ad.example.test -Credential $inventoryCredential -Open

# Automation: retain the result object and suppress banner/progress decoration
$result = Invoke-ADGroupInventory -Domain ad.example.test -Quiet
```

`-Quiet` suppresses host/progress decoration only. It does not suppress warnings or errors, and it does not change the returned result object.

## Output files

The default output parent is `C:\Temp\Reports`. Each invocation creates a unique run folder and preserves earlier runs:

```text
PSInsightInventory_<inventory>_<timestamp>_<RunId>
  Reports
    <inventory>.html
    <inventory>.json
    CSV
      <dataset>.csv
  Logs
    <inventory>_<timestamp>.jsonl
```

The result object contains the exact HTML, JSON, CSV, log, and output-folder paths. `-Open` opens the saved local HTML report; it does not repeat collection.

HTML embeds its data, scripts, and JP branding for offline use. JSON preserves normalized evidence. CSV protects formula-leading text before spreadsheet use. JSONL records collection phase, target, outcome, duration, and error context; credential objects and publishing tokens are never written.

## Permissions and network access

Use least privilege approved for the chosen inventory. Ordinary directory reads commonly cover directory-only commands, but ACL filtering can hide objects or attributes without producing an error. DC infrastructure and DNS categories can additionally require rights to use the target PowerShell endpoint and read local system, registry, certificate, share, and DNS provider data.

Expected live paths can include AD Web Services (TCP 9389), DNS/Kerberos traffic, and WinRM TCP 5985 or 5986. The module does not enable remoting, change TrustedHosts, enable Basic/CredSSP authentication, bypass certificate validation, or fall back to DCOM.

## Collection limitations

- Inventory is a point-in-time observation, not a health, security, compliance, or effective-access assessment.
- Successful reads cannot prove that ACL-filtered objects or attributes do not exist.
- Failed, timed-out, unsupported, excluded, and not-applicable categories remain distinct; unknown values are not converted to zero.
- Most object inventories are scoped to one explicit domain. Forest, Sites & Services, and trust commands document their wider scope explicitly.
- Trust collection does not contact partner forests or validate/reset trusts.
- Computer inventory reads directory attributes only and does not connect to computer endpoints.
- Group counts exclude primary-group membership and do not compute recursive/effective membership.
- User group links use returned `memberOf` backlinks and exclude primary and recursive membership.
- Group Policy inventory does not calculate resultant policy, execute WMI filters, export arbitrary setting values, or modify policy.
- DNS inventory records configuration and stored records; it is not a resolution or service-health test.
- No command sends email, stores credentials, changes infrastructure, or performs remediation.

See the per-inventory documentation for exact datasets and additional limitations.

## Troubleshooting

**The module will not import**

Run `Test-ModuleManifest .\PSInsightInventory.psd1`, confirm the complete folder was extracted, and check that Windows PowerShell is version 5.1 or later.

**`ActiveDirectory` or `GroupPolicy` is unavailable**

Install the relevant RSAT feature on the collector. Demo mode remains available without RSAT.

**A live command cannot find or verify the domain**

Check DNS resolution, domain connectivity, AD Web Services, and the exact `-Domain` value. Scope mismatches intentionally stop collection.

**WinRM categories fail**

Confirm the approved endpoint, authentication path, firewall, account permissions, and `-UseSSL`/`-Port` settings. Use `-SkipRemote` only when an explicitly partial directory-only DC report is acceptable.

**The report is partial**

Open the Collection section and JSONL log. A partial report can contain trustworthy successful categories while keeping failed or timed-out categories explicit.

**The report does not open automatically**

Use the `HtmlReport` path returned by the command. Failure of `-Open` does not discard the saved report.

## Validation status

The release validation record is in `VALIDATION.md`. Offline fixture/mocked-provider checks, live AD checks, and native Windows PowerShell 5.1 checks are reported separately. Offline success must not be treated as live-environment or host-compatibility validation.

## License and author

Copyright (c) 2026 [Jonathan Preetham](https://www.linkedin.com/in/jonathan-preetham). Released under the MIT License; see `LICENSE`.

- Repository and documentation: [PSInsightInventory on GitHub](https://github.com/JP-Repository/PSInsightInventory)
- Support: [Jonathan.Preetham@outlook.com](mailto:Jonathan.Preetham@outlook.com)
